import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';

/// The two lanes a provider can run on, and the model each uses.
///
/// Live and backlog are different jobs: the live socket needs a streaming model that answers as
/// audio arrives, while the backlog sends one short file per chunk. A streaming model cannot answer
/// a file call, and a batch model cannot hold a socket, so each lane needs its own choice rather
/// than one shared field.
abstract final class SttLaneModels {
  static String _key(SttProvider provider) => 'sttBatchModel.${provider.name}';

  /// Models that can hold a streaming socket, best first.
  ///
  /// `gemini-3.5-transcribe-live` is purpose-built for transcription and roughly a third the price
  /// of the conversational model, which speaks back and only incidentally transcribes.
  static List<String> liveModels(SttProvider provider) {
    if (provider == SttProvider.geminiLive) {
      return const [
        'gemini-3.5-transcribe-live',
        'gemini-2.5-flash-native-audio-preview-12-2025',
      ];
    }
    return const [];
  }

  /// Models that can transcribe one short file, best first.
  ///
  /// `gemini-3.5-transcribe` is deliberately absent: its unary `generateContent` call answers 200
  /// with empty text for every prompt shape tried, so offering it here would fail silently.
  static List<String> batchModels(SttProvider provider) {
    if (provider == SttProvider.gemini || provider == SttProvider.geminiLive) {
      return const [
        'gemini-3.1-flash-lite',
        'gemini-3.8-flash',
        'gemini-2.5-flash',
      ];
    }
    return const [];
  }

  /// The batch model in force for [provider]: the reader's choice, else the cheapest default.
  static String batchModel(SttProvider provider) {
    final stored = SharedPreferencesUtil().getString(_key(provider));
    final supported = batchModels(provider);
    if (stored.isNotEmpty && supported.contains(stored)) return stored;
    return supported.isEmpty ? '' : supported.first;
  }

  static Future<void> setBatchModel(SttProvider provider, String model) =>
      SharedPreferencesUtil().saveString(_key(provider), model);

  /// Whether [provider] exposes a separate backlog model at all.
  static bool hasSeparateBatchModel(SttProvider provider) => batchModels(provider).isNotEmpty;

  /// Whether the backlog runs on the provider itself rather than on the phone.
  static bool backlogOnProvider(SttProvider provider) =>
      provider == SttProvider.gemini || provider == SttProvider.geminiLive;
}
