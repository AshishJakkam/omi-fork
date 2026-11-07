import 'package:flutter_test/flutter_test.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/pages/conversations/sync_pending_work.dart';
import 'package:omi/services/wals/local_wal_sync.dart';
import 'package:omi/services/wals/wal.dart';

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

    test('never releases audio that was genuinely captured on-device', () {
      // Its phone copy may be the only one; the cloud path must not claim it.
      final born = unsent(onDeviceOnly: true, capturedOnDeviceOnly: true);

      expect(LocalWalSyncImpl.shouldRouteToProvider(born, onDevice: false), isFalse);
    });

    test('releases a recording we adopted earlier when on-device is switched off', () {
      final adopted = unsent(onDeviceOnly: true, capturedOnDeviceOnly: false);

      expect(LocalWalSyncImpl.shouldRouteToProvider(adopted, onDevice: false), isTrue);
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
}
