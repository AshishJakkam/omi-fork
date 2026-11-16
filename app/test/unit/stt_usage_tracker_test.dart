import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/stt/stt_usage_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    await SttUsageTracker.reset(SttProvider.geminiLive);
  });

  test('counts audio by bytes, not by wall clock', () async {
    // 20 seconds of 16 kHz 16-bit mono is 640,000 bytes.
    await SttUsageTracker.recordAudio(SttProvider.geminiLive, 640000);
    final usage = SttUsageTracker.snapshot(SttProvider.geminiLive);
    expect(usage.audioSeconds, closeTo(20, 0.01));
    expect(usage.sessionAudioSeconds, closeTo(20, 0.01));
  });

  test('ignores empty or nonsensical sends', () async {
    await SttUsageTracker.recordAudio(SttProvider.geminiLive, 0);
    await SttUsageTracker.recordAudio(SttProvider.geminiLive, -100);
    expect(SttUsageTracker.snapshot(SttProvider.geminiLive).audioSeconds, 0);
  });

  test('totals accumulate across sends', () async {
    await SttUsageTracker.recordAudio(SttProvider.deepgram, 320000);
    await SttUsageTracker.recordAudio(SttProvider.deepgram, 320000);
    expect(SttUsageTracker.snapshot(SttProvider.deepgram).audioSeconds, closeTo(20, 0.01));
    expect(SttUsageTracker.snapshot(SttProvider.geminiLive).audioSeconds, 0,
        reason: 'providers are accounted separately');
  });

  test('estimates a cost from the published per-minute price', () {
    expect(SttUsageTracker.estimateCostUsd('gemini-3.5-transcribe', 60), closeTo(0.18, 0.0001));
    expect(SttUsageTracker.estimateCostUsd('gemini-3.5-transcribe-live', 60), closeTo(0.30, 0.0001));
    expect(SttUsageTracker.estimateCostUsd('unknown-model', 60), 0,
        reason: 'an unknown price must not invent a number');
  });

  test('describes the spend and the provider error, and stays quiet when empty', () async {
    expect(SttUsageTracker.describe(SttUsageTracker.snapshot(SttProvider.gemini), 'gemini-3.5-transcribe'), isNull);

    await SttUsageTracker.recordAudio(SttProvider.gemini, 1920000); // 60 s = 1.0 min
    await SttUsageTracker.recordError(SttProvider.gemini, 'quota exceeded');
    final line = SttUsageTracker.describe(SttUsageTracker.snapshot(SttProvider.gemini), 'gemini-3.5-transcribe');
    expect(line, contains('1.0 min sent'));
    // One minute of the cheapest transcribe model is three tenths of a cent, so the line says so
    // rather than printing a misleading "$0.00".
    expect(line, contains('under a cent'));
    expect(line, contains('quota exceeded'));
  });

  test('a long provider message is bounded before it is stored', () async {
    await SttUsageTracker.recordError(SttProvider.gemini, 'x' * 500);
    expect(SttUsageTracker.snapshot(SttProvider.gemini).lastError!.length, lessThanOrEqualTo(160));
  });

  test('reset clears both the total and the error', () async {
    await SttUsageTracker.recordAudio(SttProvider.gemini, 320000);
    await SttUsageTracker.recordError(SttProvider.gemini, 'boom');
    await SttUsageTracker.reset(SttProvider.gemini);
    final usage = SttUsageTracker.snapshot(SttProvider.gemini);
    expect(usage.audioSeconds, 0);
    expect(usage.lastError, isNull);
    expect(usage.sessionAudioSeconds, 0);
  });
}
