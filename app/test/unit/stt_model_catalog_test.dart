import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/stt/stt_model_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  group('parsing a provider catalogue', () {
    test('the unary picker keeps only models that generate content', () {
      final models = SttModelCatalogService.parse(SttProvider.gemini, {
        'models': [
          {'name': 'models/gemini-3.5-transcribe', 'supportedGenerationMethods': ['generateContent']},
          {'name': 'models/gemini-3.8-live', 'supportedGenerationMethods': ['bidiGenerateContent']},
          {'name': 'models/text-embedding-005', 'supportedGenerationMethods': ['embedContent']},
        ],
      });
      expect(models, ['gemini-3.5-transcribe']);
    });

    test('the live picker keeps only models that accept the live socket', () {
      final models = SttModelCatalogService.parse(SttProvider.geminiLive, {
        'models': [
          {'name': 'models/gemini-3.5-transcribe', 'supportedGenerationMethods': ['generateContent']},
          {'name': 'models/gemini-3.5-transcribe-live', 'supportedGenerationMethods': ['bidiGenerateContent']},
          {'name': 'models/gemini-3.8-live', 'supportedGenerationMethods': ['bidiGenerateContent']},
        ],
      });
      expect(models, ['gemini-3.5-transcribe-live', 'gemini-3.8-live']);
    });

    test('OpenAI shape drops everything that is not speech', () {
      final models = SttModelCatalogService.parse(SttProvider.openai, {
        'data': [
          {'id': 'whisper-1'},
          {'id': 'gpt-4o-transcribe'},
          {'id': 'text-embedding-3-large'},
          {'id': 'gpt-image-1'},
          {'id': 'tts-1-hd'},
        ],
      });
      expect(models, ['gpt-4o-transcribe', 'whisper-1']);
    });

    test('a body with no recognisable list yields an empty catalogue', () {
      expect(SttModelCatalogService.parse(SttProvider.openai, {'unexpected': true}), isEmpty);
      expect(SttModelCatalogService.parse(SttProvider.openai, null), isEmpty);
    });
  });

  group('loading with a key', () {
    test('a live list is returned and cached for next time', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
            jsonEncode({
              'models': [
                {'name': 'models/gemini-3.5-transcribe', 'supportedGenerationMethods': ['generateContent']},
              ]
            }),
            200);
      });

      final first = await SttModelCatalogService.load(SttProvider.gemini, apiKey: 'k', client: client);
      expect(first.source, ModelCatalogSource.network);
      expect(first.models, ['gemini-3.5-transcribe']);

      final second = await SttModelCatalogService.load(SttProvider.gemini, apiKey: 'k', client: client);
      expect(second.source, ModelCatalogSource.cache);
      expect(second.models, ['gemini-3.5-transcribe']);
      expect(calls, 1, reason: 'a cached list must not be fetched again');
    });

    test('being offline falls back to the built-in list instead of throwing', () async {
      final client = MockClient((request) async => throw http.ClientException('offline'));
      final catalog = await SttModelCatalogService.load(SttProvider.gemini, apiKey: 'k', client: client);
      expect(catalog.source, ModelCatalogSource.builtIn);
      expect(catalog.models, SttProviderConfig.get(SttProvider.gemini).supportedModels);
      expect(catalog.note, isNotNull);
    });

    test('a rejected key is named, and still leaves a usable list', () async {
      final client = MockClient((request) async => http.Response('{"error":"bad key"}', 401));
      final catalog = await SttModelCatalogService.load(SttProvider.openai, apiKey: 'k', client: client);
      expect(catalog.source, ModelCatalogSource.builtIn);
      expect(catalog.note, 'key rejected');
      expect(catalog.models, isNotEmpty);
    });

    test('a rate limit keeps the built-in list rather than clearing it', () async {
      final client = MockClient((request) async => http.Response('{}', 429));
      final catalog = await SttModelCatalogService.load(SttProvider.deepgram, apiKey: 'k', client: client);
      expect(catalog.source, ModelCatalogSource.builtIn);
      expect(catalog.note, 'rate limited');
    });

    test('a different key does not reuse another key\'s cache', () async {
      var seen = 0;
      final client = MockClient((request) async {
        seen++;
        final model = seen == 1 ? 'gemini-3.5-transcribe' : 'gemini-3.8-flash';
        return http.Response(
            jsonEncode({
              'models': [
                {'name': 'models/$model', 'supportedGenerationMethods': ['generateContent']},
              ]
            }),
            200);
      });

      await SttModelCatalogService.load(SttProvider.gemini, apiKey: 'first', client: client);
      final other = await SttModelCatalogService.load(SttProvider.gemini, apiKey: 'second', client: client);
      expect(other.source, ModelCatalogSource.network);
      expect(other.models, ['gemini-3.8-flash']);
    });

    test('no key means no request at all', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      });
      final catalog = await SttModelCatalogService.load(SttProvider.gemini, apiKey: '', client: client);
      expect(calls, 0);
      expect(catalog.source, ModelCatalogSource.builtIn);
    });

    test('a provider without a models endpoint never calls out', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      });
      final catalog = await SttModelCatalogService.load(SttProvider.localWhisper, apiKey: 'k', client: client);
      expect(calls, 0);
      expect(catalog.source, ModelCatalogSource.builtIn);
    });
  });
}
