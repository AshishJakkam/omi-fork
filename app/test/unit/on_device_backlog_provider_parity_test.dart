import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/sync_pending_work.dart';
import 'package:omi/services/wals/local_wal_sync.dart';
import 'package:omi/services/wals/wal.dart';
import 'package:omi/services/wals/wal_interfaces.dart';
import 'package:omi/utils/wal_file_manager.dart';

class _MockListener implements IWalSyncListener {
  @override
  void onWalUpdated() {}

  @override
  void onWalSynced(Wal wal, {ServerConversation? conversation}) {}
}

/// Selecting an on-device transcription provider must apply to the whole
/// library, not only to recordings captured after the setting changed.
///
/// The cloud drain classifies each Wal purely from that Wal's own
/// `onDeviceOnly` flag (`SyncPendingWork.isPendingWal`). The current provider
/// setting is never consulted, so a pre-existing backlog stays on the cloud
/// path forever: the user pays cloud minutes for audio they already asked to
/// transcribe on device, and the backlog cannot drain on a free plan.
///
/// These tests pin the current behaviour so a fix has something to flip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    tempDir = await Directory.systemTemp.createTemp('on_device_route_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return tempDir.path;
        return null;
      },
    );
    await WalFileManager.init();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Wal makeWal({required WalStatus status, bool onDeviceOnly = false}) {
    return Wal(
      timerStart: 1700000000,
      codec: BleAudioCodec.opus,
      seconds: 30,
      status: status,
      onDeviceOnly: onDeviceOnly,
    );
  }

  group('SyncPendingWork.isPendingWal classification', () {
    test('a legacy cloud-path backlog entry counts as pending cloud work', () {
      // Recorded before the user switched to on-device: onDeviceOnly is false.
      final backlogItem = makeWal(status: WalStatus.miss);

      expect(SyncPendingWork.isPendingWal(backlogItem), isTrue);
    });

    test('a recording captured under on-device never joins the cloud drain', () {
      final localOnly = makeWal(status: WalStatus.miss, onDeviceOnly: true);

      expect(SyncPendingWork.isPendingWal(localOnly), isFalse);
    });

    test('the per-recording flag alone decides, across the whole status surface', () {
      // isPendingWal takes no provider argument: the only input that can move a
      // recording between the cloud drain and the on-device path is the flag
      // stamped when it was captured. Nothing a settings toggle does can
      // reclassify audio already on the device.
      for (final status in WalStatus.values) {
        final cloudPath = makeWal(status: status);
        final onDevicePath = makeWal(status: status, onDeviceOnly: true);

        expect(
          SyncPendingWork.isPendingWal(onDevicePath),
          isFalse,
          reason: 'an on-device recording must never be queued for cloud upload (status=$status)',
        );
        expect(
          SyncPendingWork.isPendingWal(cloudPath),
          status == WalStatus.miss,
          reason: 'only a missed cloud-path recording is pending (status=$status)',
        );
      }
    });
  });

  group('LocalWalSyncImpl.shouldRouteToProvider', () {
    Wal unsent({bool onDeviceOnly = false, bool? capturedOnDeviceOnly}) {
      return Wal(
        timerStart: 1700000000,
        codec: BleAudioCodec.opus,
        seconds: 30,
        status: WalStatus.miss,
        storage: WalStorage.disk,
        filePath: 'audio_1700000000.bin',
        onDeviceOnly: onDeviceOnly,
        capturedOnDeviceOnly: capturedOnDeviceOnly,
      );
    }

    test('claims a legacy unsent recording when the provider is on-device', () {
      expect(LocalWalSyncImpl.shouldRouteToProvider(unsent(), onDevice: true), isTrue);
    });

    test('leaves an already-on-device recording alone', () {
      expect(LocalWalSyncImpl.shouldRouteToProvider(unsent(onDeviceOnly: true), onDevice: true), isFalse);
    });

    test('never releases on-device audio back to the cloud', () {
      // The phone copy may be the only one, and the cloud path would upload
      // audio the user asked to keep local. Adoption is one-way.
      final born = unsent(onDeviceOnly: true, capturedOnDeviceOnly: true);
      final adoptedEarlier = unsent(onDeviceOnly: true, capturedOnDeviceOnly: false);

      expect(LocalWalSyncImpl.shouldRouteToProvider(born, onDevice: false), isFalse);
      expect(LocalWalSyncImpl.shouldRouteToProvider(adoptedEarlier, onDevice: false), isFalse);
    });

    test('refuses audio that already reached the server', () {
      final uploaded = Wal(
        timerStart: 1700000000,
        codec: BleAudioCodec.opus,
        seconds: 30,
        status: WalStatus.uploaded,
        storage: WalStorage.disk,
        filePath: 'audio_1700000000.bin',
      );
      expect(LocalWalSyncImpl.shouldRouteToProvider(uploaded, onDevice: true), isFalse);
    });

    test('refuses audio with a server job, a transcript, or an upload in flight', () {
      final withJob = Wal(
        timerStart: 1700000000,
        codec: BleAudioCodec.opus,
        seconds: 30,
        status: WalStatus.miss,
        storage: WalStorage.disk,
        filePath: 'audio_1700000000.bin',
        jobId: 'job-1',
      );
      final transcribed = unsent()
        ..onDeviceConversation = const {'id': 'conv-1'};
      final preparing = unsent()
        ..onDevicePreparedUpload = const {'id': 'upload-1'};

      expect(LocalWalSyncImpl.shouldRouteToProvider(withJob, onDevice: true), isFalse);
      expect(LocalWalSyncImpl.shouldRouteToProvider(transcribed, onDevice: true), isFalse);
      expect(LocalWalSyncImpl.shouldRouteToProvider(preparing, onDevice: true), isFalse);
    });

    test('refuses audio that is not on disk', () {
      final inMemory = Wal(
        timerStart: 1700000000,
        codec: BleAudioCodec.opus,
        seconds: 30,
        status: WalStatus.miss,
      );
      expect(LocalWalSyncImpl.shouldRouteToProvider(inMemory, onDevice: true), isFalse);
    });
  });

  group('LocalWalSyncImpl.routeUnsentRecordingsToProvider', () {
    late LocalWalSyncImpl sync;

    setUp(() async {
      sync = LocalWalSyncImpl(_MockListener());
      sync.setDeviceInfo('devkit-1', 'Omi DevKit');
      sync.start();
      await sync.walReady;
    });

    tearDown(() async {
      await sync.stop();
    });

    Future<void> addUnsent({
      bool onDeviceOnly = false,
      bool? capturedOnDeviceOnly,
      String name = 'audio_route.bin',
    }) async {
      File('${tempDir.path}/$name').writeAsBytesSync(List.filled(64, 0xAB), flush: true);
      final wal = Wal(
        timerStart: 1700000000,
        codec: BleAudioCodec.opus,
        seconds: 1,
        status: WalStatus.miss,
        storage: WalStorage.disk,
        filePath: name,
        device: 'devkit-1',
        deviceModel: 'Omi DevKit',
        totalFrames: 10,
        onDeviceOnly: onDeviceOnly,
        capturedOnDeviceOnly: capturedOnDeviceOnly,
      );
      await sync.addExternalWal(wal, admittedGeneration: sync.sessionGeneration);
    }

    test('adopts an unsent legacy recording and persists the flip', () async {
      await addUnsent();

      final moved = await sync.routeUnsentRecordingsToProvider(onDevice: true);

      expect(moved, 1);
      final index = await WalFileManager.loadWals();
      expect(index, hasLength(1));
      expect(index.first.onDeviceOnly, isTrue, reason: 'the flip must survive a restart');
    });

    test('never releases audio that was genuinely captured on-device', () async {
      await addUnsent(onDeviceOnly: true, capturedOnDeviceOnly: true);

      final moved = await sync.routeUnsentRecordingsToProvider(onDevice: false);

      expect(moved, 0, reason: 'adoption is one-way; that phone copy may be the only one');
      final index = await WalFileManager.loadWals();
      expect(index.first.onDeviceOnly, isTrue);
    });

    test('routes the backlog only once', () async {
      await addUnsent();

      expect(await sync.routeUnsentRecordingsToProvider(onDevice: true), 1);
      expect(await sync.routeUnsentRecordingsToProvider(onDevice: true), 0,
          reason: 'already on the on-device path');
    });
  });
}
