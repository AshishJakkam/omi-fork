import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:omi/models/custom_stt_config.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/on_device/on_device_engine.dart';
import 'package:omi/services/stt/stt_lane_models.dart';
import 'package:omi/utils/logger.dart';

/// Transcribes already-captured audio with the provider the reader chose.
///
/// The backlog lane only knew the on-device engines, so audio recorded before a cloud provider was
/// configured - or while its socket was down - was transcribed by a different engine, or not at
/// all. With a bring-your-own key that is the wrong engine for the language and the wrong meter:
/// the reader chose one provider for the whole app.
///
/// Gemini is served here by a flash-lite model asked to transcribe, not by `*-transcribe`: the
/// unary `generateContent` call to `gemini-3.5-transcribe` answers 200 with empty text for both
/// prompt shapes tried, so building this lane on that model would have failed silently.
class CloudBatchTranscriber {
  CloudBatchTranscriber({required this.config, http.Client? client}) : _client = client ?? http.Client();

  final CustomSttConfig config;
  final http.Client _client;

  /// Batch model used when the reader's selection is a streaming one, which a one-shot file call
  /// cannot reuse.
  static const String geminiBatchModel = 'gemini-3.1-flash-lite';

  static const String _prompt = 'Transcribe this audio verbatim. '
      'Return only the transcribed text with no commentary, labels or formatting. '
      'If there is no speech, return nothing at all.';

  bool get isUsable => config.isEnabled && supportsBatch(config.provider);

  /// Providers whose backlog can be served by a single request per chunk.
  static bool supportsBatch(SttProvider provider) =>
      provider == SttProvider.gemini || provider == SttProvider.geminiLive;

  /// Transcribes [wav] (mono PCM16 in a WAV container).
  ///
  /// Returns an empty result rather than throwing when the provider hears no speech, so one silent
  /// stretch cannot stall the whole backlog.
  Future<OnDeviceBatchResult> transcribe(List<int> wav, String language) async {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('${config.provider.name} is selected but has no API key');
    }

    final model = resolvedBatchModel();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inlineData': {'mimeType': 'audio/wav', 'data': base64Encode(wav)},
            },
            {'text': _prompt},
          ],
        },
      ],
      'generationConfig': {'temperature': 0},
    });

    final response = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('${config.provider.name} batch transcription failed: HTTP ${response.statusCode} '
          '${_bounded(response.body)}');
    }

    final text = extractText(response.body);
    if (text.isEmpty) return OnDeviceBatchResult(engine: 'cloud:$model', text: '', words: const []);
    return OnDeviceBatchResult(
      engine: 'cloud:$model',
      text: text,
      words: [OnDeviceWord(text, 0, 0)],
    );
  }

  /// The model that should answer a one-shot file for this config.
  ///
  /// The reader's backlog choice wins; a streaming selection cannot be reused for a batch call, so
  /// this falls back to the batch default rather than sending a Live model name to the unary
  /// endpoint.
  String resolvedBatchModel() {
    final configured = SttLaneModels.batchModel(config.provider);
    if (configured.isNotEmpty) return configured;
    return batchModelFor(config.model);
  }

  static String batchModelFor(String? chosen) {
    if (chosen != null && chosen.isNotEmpty && !chosen.contains('live') && !chosen.contains('native-audio')) {
      return chosen;
    }
    return geminiBatchModel;
  }

  /// Pulls the answer out of a `generateContent` payload.
  static String extractText(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return '';
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return '';
      final content = (candidates.first as Map)['content'];
      if (content is! Map) return '';
      final parts = content['parts'];
      if (parts is! List) return '';
      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is Map && part['text'] is String) buffer.write(part['text'] as String);
      }
      return buffer.toString().trim();
    } catch (e) {
      Logger.debug('[CloudBatch] Could not read transcription response: $e');
      return '';
    }
  }

  static String _bounded(String body) => body.length <= 160 ? body : '${body.substring(0, 160)}...';
}

/// The chunk transcriber the backlog should use for [config], or null to keep the on-device
/// engines.
///
/// This is what makes one provider serve the whole app: the live socket and the backlog stop
/// disagreeing about who transcribes. Returns null for providers that cannot transcribe a
/// one-shot file, so those keep today's behaviour rather than failing.
Future<OnDeviceBatchResult> Function(Uint8List, String)? cloudBacklogTranscriber(CustomSttConfig config) {
  if (!config.isEnabled || !CloudBatchTranscriber.supportsBatch(config.provider)) return null;
  if (config.apiKey == null || config.apiKey!.isEmpty) return null;
  final transcriber = CloudBatchTranscriber(config: config);
  return (Uint8List wav, String language) => transcriber.transcribe(wav, language);
}
