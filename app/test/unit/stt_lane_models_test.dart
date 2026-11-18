import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/stt/stt_lane_models.dart';

/// Live and backlog are separate jobs, so each lane keeps its own model. These cases pin the
/// defaults, the per-provider storage, and the one model that must never be offered.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  group('liveModels', () {
    test('leads with the dedicated transcription model', () {
      expect(SttLaneModels.liveModels(SttProvider.geminiLive).first, 'gemini-3.5-transcribe-live');
    });

    test('is empty for providers without a live lane', () {
      expect(SttLaneModels.liveModels(SttProvider.openai), isEmpty);
    });
  });

  group('batchModels', () {
    test('leads with a cheap model that answers a file call', () {
      expect(SttLaneModels.batchModels(SttProvider.geminiLive).first, 'gemini-3.1-flash-lite');
    });

    test('never offers the transcribe model', () {
      // Its unary generateContent call returns 200 with empty text, so offering it would fail
      // silently - exactly the kind of dead option this list exists to avoid.
      final models = SttLaneModels.batchModels(SttProvider.geminiLive);
      expect(models.any((m) => m.contains('transcribe')), isFalse);
    });

    test('offers nothing for on-device providers', () {
      expect(SttLaneModels.batchModels(SttProvider.onDeviceWhisper), isEmpty);
      expect(SttLaneModels.hasSeparateBatchModel(SttProvider.onDeviceWhisper), isFalse);
    });
  });

  group('batchModel', () {
    test('defaults to the first supported model', () {
      expect(SttLaneModels.batchModel(SttProvider.geminiLive), 'gemini-3.1-flash-lite');
    });

    test('returns the stored choice', () async {
      await SttLaneModels.setBatchModel(SttProvider.geminiLive, 'gemini-3.8-flash');
      expect(SttLaneModels.batchModel(SttProvider.geminiLive), 'gemini-3.8-flash');
    });

    test('ignores a stored model this lane cannot use', () async {
      // A stale or hand-edited preference must not become a dead request.
      await SttLaneModels.setBatchModel(SttProvider.geminiLive, 'not-a-real-model');
      expect(SttLaneModels.batchModel(SttProvider.geminiLive), 'gemini-3.1-flash-lite');
    });

    test('keeps the choice per provider', () async {
      await SttLaneModels.setBatchModel(SttProvider.geminiLive, 'gemini-3.8-flash');
      expect(SttLaneModels.batchModel(SttProvider.gemini), 'gemini-3.1-flash-lite');
    });
  });
}
