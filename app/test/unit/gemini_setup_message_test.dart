import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/sockets/pure_streaming_stt.dart';

/// The Gemini Live setup frame decides whether the session transcribes at all.
///
/// Upstream sent `responseModalities: ['AUDIO']` unconditionally, which is the conversational
/// shape. A dedicated speech-to-text model answers nothing to that setup, so picking one looked
/// indistinguishable from a dead socket. These cases pin both shapes.
void main() {
  Map<String, dynamic> setupFor(String model, {String language = 'en'}) =>
      GeminiStreamingSttSocket.buildSetupMessage(model: model, language: language)['setup']
          as Map<String, dynamic>;

  group('buildSetupMessage', () {
    test('asks a transcription model for text, not speech', () {
      final setup = setupFor('gemini-3.5-transcribe-live');
      final modalities = (setup['generationConfig'] as Map)['responseModalities'] as List;
      expect(modalities, ['TEXT']);
    });

    test('leaves a conversational model asking for audio', () {
      final setup = setupFor('gemini-2.5-flash-native-audio-preview-12-2025');
      final modalities = (setup['generationConfig'] as Map)['responseModalities'] as List;
      expect(modalities, ['AUDIO']);
    });

    test('names the model with the models/ prefix the endpoint expects', () {
      expect(setupFor('gemini-3.5-transcribe-live')['model'], 'models/gemini-3.5-transcribe-live');
    });

    test('tells a transcription model which language to expect', () {
      final setup = setupFor('gemini-3.5-transcribe-live', language: 'te');
      expect((setup['inputAudioTranscription'] as Map)['languageCodes'], ['te']);
    });

    test('omits language codes for auto-detect', () {
      // 'multi' is the app's "let the provider decide" value; it is not a language code.
      final setup = setupFor('gemini-3.5-transcribe-live', language: 'multi');
      expect((setup['inputAudioTranscription'] as Map).containsKey('languageCodes'), isFalse);
    });

    test('never sends language codes to a conversational model', () {
      final setup = setupFor('gemini-2.5-flash-native-audio-preview-12-2025', language: 'te');
      expect((setup['inputAudioTranscription'] as Map), isEmpty);
    });
  });
}
