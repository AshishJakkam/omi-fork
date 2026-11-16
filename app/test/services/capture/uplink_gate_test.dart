import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/capture/capture_controller.dart';

void main() {
  group('shouldFeedTranscriptionSocket', () {
    test('feeds a custom cloud provider even when audio is kept on the phone', () {
      // The regression that muted a working Gemini key: an exhausted Omi plan
      // turned on local-only retention, and every frame was withheld.
      expect(
        shouldFeedTranscriptionSocket(
          socketConnected: true,
          streamsToCustomCloud: true,
          keepAudioLocal: true,
          feedsOnDeviceSocket: false,
        ),
        isTrue,
      );
    });

    test('never feeds a disconnected socket', () {
      expect(
        shouldFeedTranscriptionSocket(
          socketConnected: false,
          streamsToCustomCloud: true,
          keepAudioLocal: false,
          feedsOnDeviceSocket: true,
        ),
        isFalse,
      );
    });

    test('withholds managed upload while audio is kept local', () {
      expect(
        shouldFeedTranscriptionSocket(
          socketConnected: true,
          streamsToCustomCloud: false,
          keepAudioLocal: true,
          feedsOnDeviceSocket: false,
        ),
        isFalse,
      );
    });

    test('feeds the on-device lane while the WAL keeps the audio', () {
      expect(
        shouldFeedTranscriptionSocket(
          socketConnected: true,
          streamsToCustomCloud: false,
          keepAudioLocal: true,
          feedsOnDeviceSocket: true,
        ),
        isTrue,
      );
    });

    test('feeds normally when nothing is retained locally', () {
      expect(
        shouldFeedTranscriptionSocket(
          socketConnected: true,
          streamsToCustomCloud: false,
          keepAudioLocal: false,
          feedsOnDeviceSocket: false,
        ),
        isTrue,
      );
    });
  });
}
