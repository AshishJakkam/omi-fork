import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/utils/logger.dart';

/// Where a model list came from, so the UI can say how current it is.
enum ModelCatalogSource {
  /// Just fetched from the provider with the reader's key.
  network,

  /// A list this key fetched earlier, still within [SttModelCatalogService.cacheTtl].
  cache,

  /// The provider's own catalogue could not be read, so the built-in list is showing.
  builtIn,
}

/// The models a provider offers, plus why the list looks the way it does.
class SttModelCatalog {
  const SttModelCatalog({
    required this.models,
    required this.source,
    this.note,
    this.fetchedAt,
  });

  final List<String> models;
  final ModelCatalogSource source;

  /// Set when a refresh failed: surfaced as one quiet line, never as a blocking error.
  final String? note;

  final DateTime? fetchedAt;

  /// Whether asking again could plausibly return something newer.
  bool get canRefresh => source != ModelCatalogSource.network;
}

/// Fetches each cloud provider's own model list with the reader's key.
///
/// A hard-coded list goes stale the moment a vendor renames a model, and the reader cannot see what
/// they are actually running. This asks the provider instead, caching the answer so an offline
/// launch still shows a real list, and falling back to the built-in list when the provider cannot be
/// reached. Nothing here throws: a catalogue is presentation, never a reason to block a capture.
abstract final class SttModelCatalogService {
  /// How long a fetched list is trusted before a refresh replaces it.
  static const Duration cacheTtl = Duration(hours: 24);

  /// Bounded so a provider that hangs cannot stall the settings page.
  static const Duration timeout = Duration(seconds: 8);

  /// Ids that are never transcription models, filtered because some vendors list everything
  /// together (OpenAI returns embeddings, images and TTS alongside audio models).
  static const List<String> _neverTranscribe = [
    'embedding',
    'tts',
    'image',
    'dall-e',
    'moderation',
    'realtime',
  ];

  static Future<SttModelCatalog> load(
    SttProvider provider, {
    String? apiKey,
    http.Client? client,
  }) async {
    final builtIn = SttProviderConfig.get(provider).supportedModels;
    final key = (apiKey ?? '').trim();
    final endpoint = _endpointFor(provider);

    if (endpoint == null || key.isEmpty) {
      return SttModelCatalog(models: builtIn, source: ModelCatalogSource.builtIn);
    }

    final cached = _readCache(provider, key);
    if (cached != null) return cached;

    try {
      final models = await _fetch(provider, endpoint, key, client);
      if (models.isEmpty) {
        return SttModelCatalog(
            models: builtIn, source: ModelCatalogSource.builtIn, note: 'no models returned');
      }
      unawaited(_writeCache(provider, key, models));
      return SttModelCatalog(
          models: models, source: ModelCatalogSource.network, fetchedAt: DateTime.now());
    } on _CatalogUnavailable catch (error) {
      // Offline, a rejected key, or a rate limit: keep the built-in list and say so once.
      return SttModelCatalog(models: builtIn, source: ModelCatalogSource.builtIn, note: error.reason);
    } catch (error) {
      Logger.debug('[SttModelCatalog] ${provider.name} unavailable: $error');
      return SttModelCatalog(models: builtIn, source: ModelCatalogSource.builtIn, note: 'unavailable');
    }
  }

  /// Forgets this provider's cached list, so the next load asks the provider again.
  static Future<void> clearCache(SttProvider provider) =>
      SharedPreferencesUtil().saveString('sttModels.${provider.name}', '');

  /// A stable, non-reversible tag for the key, so a cache belongs to the key without storing it.
  static String fingerprint(String apiKey) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(apiKey)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static Uri? _endpointFor(SttProvider provider) => switch (provider) {
        SttProvider.gemini || SttProvider.geminiLive =>
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models'),
        SttProvider.openai || SttProvider.openaiDiarize => Uri.parse('https://api.openai.com/v1/models'),
        SttProvider.deepgram || SttProvider.deepgramLive => Uri.parse('https://api.deepgram.com/v1/models'),
        // Vendors without a documented models endpoint stay on the built-in list.
        _ => null,
      };

  static Future<List<String>> _fetch(
    SttProvider provider,
    Uri endpoint,
    String apiKey,
    http.Client? client,
  ) async {
    final ownClient = client == null;
    final active = client ?? http.Client();
    final gemini = provider == SttProvider.gemini || provider == SttProvider.geminiLive;
    try {
      final uri = gemini
          ? endpoint.replace(queryParameters: {'key': apiKey, 'pageSize': '1000'})
          : endpoint;
      final request = http.Request('GET', uri);
      final deepgram = provider == SttProvider.deepgram || provider == SttProvider.deepgramLive;
      if (deepgram) {
        request.headers['Authorization'] = 'Token $apiKey';
      } else if (!gemini) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }

      final response = await active.send(request).then(http.Response.fromStream).timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const _CatalogUnavailable('key rejected');
      }
      if (response.statusCode == 429) {
        throw const _CatalogUnavailable('rate limited');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _CatalogUnavailable('http ${response.statusCode}');
      }
      return parse(provider, jsonDecode(response.body));
    } on _CatalogUnavailable {
      rethrow;
    } on TimeoutException {
      throw const _CatalogUnavailable('timed out');
    } on FormatException {
      throw const _CatalogUnavailable('unreadable response');
    } finally {
      if (ownClient) active.close();
    }
  }

  /// Extracts model ids from a provider's list response. Visible for testing.
  static List<String> parse(SttProvider provider, Object? body) {
    final ids = <String>[];
    // A streaming provider needs models that accept the Live socket, not the unary endpoint;
    // filtering both on `generateContent` hid every live model from the live picker.
    final requiredMethod =
        provider == SttProvider.geminiLive ? 'bidiGenerateContent' : 'generateContent';
    if (body is Map) {
      // Gemini: {models: [{name: "models/x", supportedGenerationMethods: ["generateContent"]}]}
      final models = body['models'];
      if (models is List) {
        for (final entry in models) {
          if (entry is! Map) continue;
          final name = entry['name'];
          if (name is! String) continue;
          final methods = entry['supportedGenerationMethods'];
          if (methods is List && !methods.contains(requiredMethod)) continue;
          ids.add(name.replaceFirst('models/', ''));
        }
      }
      // OpenAI / Deepgram style: {data: [{id: "..."}]}
      final data = body['data'];
      if (data is List) {
        for (final entry in data) {
          if (entry is Map && entry['id'] is String) ids.add(entry['id'] as String);
        }
      }
      // Deepgram also reports its speech models separately.
      final stt = body['stt_models'];
      if (stt is List) {
        for (final entry in stt) {
          if (entry is Map && entry['canonical_name'] is String) {
            ids.add(entry['canonical_name'] as String);
          }
        }
      }
    }

    final unique = <String>{};
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (_neverTranscribe.any(lower.contains)) continue;
      unique.add(trimmed);
    }
    return unique.toList()..sort();
  }

  static SttModelCatalog? _readCache(SttProvider provider, String apiKey) {
    try {
      final raw = SharedPreferencesUtil().getString('sttModels.${provider.name}');
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['fp'] != fingerprint(apiKey)) return null;
      final at = DateTime.tryParse(decoded['at'] as String? ?? '');
      final models = (decoded['models'] as List?)?.whereType<String>().toList() ?? const <String>[];
      if (at == null || models.isEmpty) return null;
      if (DateTime.now().difference(at) > cacheTtl) return null;
      return SttModelCatalog(models: models, source: ModelCatalogSource.cache, fetchedAt: at);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(SttProvider provider, String apiKey, List<String> models) async {
    try {
      await SharedPreferencesUtil().saveString(
        'sttModels.${provider.name}',
        jsonEncode({'fp': fingerprint(apiKey), 'at': DateTime.now().toIso8601String(), 'models': models}),
      );
    } catch (_) {
      // A cache that cannot be written only costs a refetch next time.
    }
  }
}

/// A catalogue that could not be read, with a reader-facing reason.
class _CatalogUnavailable implements Exception {
  const _CatalogUnavailable(this.reason);
  final String reason;
}
