import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:omi/models/custom_stt_config.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/stt/cloud_batch_transcriber.dart';

/// The backlog has to transcribe with the provider the reader chose, not the on-device engines.
/// These cases pin which configs qualify, which model is used, and that a silent chunk does not
/// throw and stall the queue.
void main() {
  CustomSttConfig configFor(SttProvider provider, {String? key = 'k-test', String? model}) => CustomSttConfig(
        provider: provider,
        apiKey: key,
        model: model,
        language: 'en',
      );

  CloudBatchTranscriber withResponse(String body, {int status = 200}) => CloudBatchTranscriber(
        config: configFor(SttProvider.geminiLive),
        client: MockClient((_) async => http.Response(body, status, headers: {'content-type': 'application/json'})),
      );

  group('supportsBatch', () {
    test('serves Gemini, live or unary', () {
      expect(CloudBatchTranscriber.supportsBatch(SttProvider.gemini), isTrue);
      expect(CloudBatchTranscriber.supportsBatch(SttProvider.geminiLive), isTrue);
    });

    test('leaves on-device and other providers alone', () {
      expect(CloudBatchTranscriber.supportsBatch(SttProvider.onDeviceWhisper), isFalse);
      expect(CloudBatchTranscriber.supportsBatch(SttProvider.localWhisper), isFalse);
      expect(CloudBatchTranscriber.supportsBatch(SttProvider.omi), isFalse);
    });
  });

  group('cloudBacklogTranscriber', () {
    test('is offered for a configured Gemini key', () {
      expect(cloudBacklogTranscriber(configFor(SttProvider.geminiLive)), isNotNull);
    });

    test('is not offered without a key', () {
      expect(cloudBacklogTranscriber(configFor(SttProvider.geminiLive, key: '')), isNull);
    });

    test('is not offered for an on-device provider', () {
      expect(cloudBacklogTranscriber(configFor(SttProvider.onDeviceWhisper)), isNull);
    });

    test('is not offered when custom STT is off', () {
      expect(cloudBacklogTranscriber(CustomSttConfig.defaultConfig), isNull);
    });
  });

  group('batchModelFor', () {
    test('substitutes a batch model for a streaming selection', () {
      // A Live model cannot answer a one-shot file call.
      expect(CloudBatchTranscriber.batchModelFor('gemini-3.5-transcribe-live'),
          CloudBatchTranscriber.geminiBatchModel);
      expect(CloudBatchTranscriber.batchModelFor('gemini-2.5-flash-native-audio-preview-12-2025'),
          CloudBatchTranscriber.geminiBatchModel);
    });

    test('keeps an explicitly chosen batch model', () {
      expect(CloudBatchTranscriber.batchModelFor('gemini-3.1-flash-lite'), 'gemini-3.1-flash-lite');
    });

    test('falls back when no model is stored', () {
      expect(CloudBatchTranscriber.batchModelFor(null), CloudBatchTranscriber.geminiBatchModel);
    });
  });

  group('extractText', () {
    test('reads the candidate parts', () {
      final payload = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Hello there. '},
                {'text': 'Second sentence.'},
              ],
            },
          },
        ],
      });
      expect(CloudBatchTranscriber.extractText(payload), 'Hello there. Second sentence.');
    });

    test('returns empty for a blocked or empty answer', () {
      expect(CloudBatchTranscriber.extractText('{"candidates":[{"finishReason":"SAFETY"}]}'), '');
      expect(CloudBatchTranscriber.extractText('{"candidates":[]}'), '');
      expect(CloudBatchTranscriber.extractText('not json'), '');
    });
  });

  group('transcribe', () {
    test('returns the spoken text as one word', () async {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Accounting seemed manageable.'},
              ],
            },
          },
        ],
      });
      final result = await withResponse(body).transcribe(Uint8List.fromList(List.filled(64, 1)), 'en');
      expect(result.text, 'Accounting seemed manageable.');
      expect(result.engine, startsWith('cloud:'));
    });

    test('treats a silent chunk as empty, not as an error', () async {
      // One quiet stretch must not stall the whole backlog.
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '   '},
              ],
            },
          },
        ],
      });
      final result = await withResponse(body).transcribe(Uint8List.fromList(List.filled(64, 1)), 'en');
      expect(result.text, isEmpty);
    });

    test('reports an HTTP failure with the status', () async {
      final transcriber = withResponse('{"error":"invalid key"}', status: 400);
      await expectLater(
        transcriber.transcribe(Uint8List.fromList(List.filled(64, 1)), 'en'),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses to run without a key', () async {
      final transcriber = CloudBatchTranscriber(config: configFor(SttProvider.geminiLive, key: ''));
      await expectLater(
        transcriber.transcribe(Uint8List.fromList(List.filled(64, 1)), 'en'),
        throwsA(isA<StateError>()),
      );
    });

    test('sends the batch model, not the streaming one', () async {
      late Uri seen;
      final transcriber = CloudBatchTranscriber(
        config: configFor(SttProvider.geminiLive, model: 'gemini-3.5-transcribe-live'),
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'candidates': []}), 200);
        }),
      );
      await transcriber.transcribe(Uint8List.fromList(List.filled(64, 1)), 'en');
      expect(seen.toString(), contains(CloudBatchTranscriber.geminiBatchModel));
      expect(seen.toString(), isNot(contains('transcribe-live')));
    });
  });
}
