import 'package:flutter_test/flutter_test.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/pages/conversations/sync_pending_work.dart';
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
}
