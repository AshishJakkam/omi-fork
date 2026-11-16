import 'dart:async';
import 'dart:convert';

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_provider.dart';

/// What a cloud provider charged for, in audio minutes, and the last thing it complained about.
///
/// A bring-your-own-key app hands the reader someone else's meter and then says nothing about it:
/// they cannot see how much audio went out, what it cost, or why a call failed. This keeps that in
/// one place so the settings page can state it plainly.
class SttUsageSnapshot {
  const SttUsageSnapshot({
    required this.audioSeconds,
    required this.sessionAudioSeconds,
    this.lastError,
    this.lastErrorAt,
  });

  /// Audio sent with this key since the totals were last cleared.
  final double audioSeconds;

  /// Audio sent since the app started, which is what "this session" means on the page.
  final double sessionAudioSeconds;

  /// The provider's own message for the most recent failure, when there was one.
  final String? lastError;

  final DateTime? lastErrorAt;

  double get audioMinutes => audioSeconds / 60;
  double get sessionAudioMinutes => sessionAudioSeconds / 60;

  bool get isEmpty => audioSeconds <= 0 && lastError == null;
}

/// Per-provider audio accounting and error capture for cloud speech-to-text.
abstract final class SttUsageTracker {
  /// Published prices, per minute of audio, as of November 2026. Estimates only: a vendor can
  /// change them, and output tokens are billed separately on some models.
  static const Map<String, double> _audioPricePerMinute = {
    'gemini-3.5-transcribe': 0.003,
    'gemini-3.5-transcribe-live': 0.005,
    'gemini-3.5-flash-lite': 0.002,
    'gemini-3.5-flash': 0.004,
    'gemini-3.8-flash': 0.004,
    'gemini-3.8-live': 0.006,
    'gemini-2.5-flash': 0.004,
    'gemini-2.5-flash-native-audio-preview-12-2025': 0.006,
    'whisper-1': 0.006,
    'gpt-4o-transcribe': 0.006,
    'gpt-4o-transcribe-diarize': 0.006,
    'nova-3': 0.0077,
  };

  /// Cheap enough to be a rounding error, but visible so nobody is surprised.
  static double estimateCostUsd(String model, double audioMinutes) {
    final price = _audioPricePerMinute[model] ?? 0;
    return price * audioMinutes;
  }

  static final Map<SttProvider, double> _sessionSeconds = {};

  static double _sessionFor(SttProvider provider) => _sessionSeconds[provider] ?? 0;

  static String _secondsKey(SttProvider provider) => 'sttUsage.${provider.name}.audioSeconds';
  static String _errorKey(SttProvider provider) => 'sttUsage.${provider.name}.lastError';
  static String _errorAtKey(SttProvider provider) => 'sttUsage.${provider.name}.lastErrorAt';

  /// Adds audio actually handed to a provider. [bytes] is 16-bit mono PCM at [sampleRate].
  static Future<void> recordAudio(SttProvider provider, int bytes, {int sampleRate = 16000}) async {
    if (bytes <= 0 || sampleRate <= 0) return;
    final seconds = bytes / (sampleRate * 2);
    _sessionSeconds[provider] = _sessionFor(provider) + seconds;
    try {
      final prefs = SharedPreferencesUtil();
      final total = double.tryParse(prefs.getString(_secondsKey(provider))) ?? 0;
      await prefs.saveString(_secondsKey(provider), (total + seconds).toStringAsFixed(1));
    } catch (_) {
      // Accounting must never interrupt a capture.
    }
  }

  /// Keeps the provider's own message, because "it stopped working" needs a reason.
  static Future<void> recordError(SttProvider provider, String message) async {
    try {
      final prefs = SharedPreferencesUtil();
      await prefs.saveString(_errorKey(provider), message.length > 160 ? message.substring(0, 160) : message);
      await prefs.saveString(_errorAtKey(provider), DateTime.now().toIso8601String());
    } catch (_) {
      // Same: never a reason to fail a capture.
    }
  }

  static SttUsageSnapshot snapshot(SttProvider provider) {
    final prefs = SharedPreferencesUtil();
    final error = prefs.getString(_errorKey(provider));
    return SttUsageSnapshot(
      audioSeconds: double.tryParse(prefs.getString(_secondsKey(provider))) ?? 0,
      sessionAudioSeconds: _sessionFor(provider),
      lastError: error.isEmpty ? null : error,
      lastErrorAt: DateTime.tryParse(prefs.getString(_errorAtKey(provider))),
    );
  }

  /// Clears the running total and the last error, for a reader starting fresh.
  static Future<void> reset(SttProvider provider) async {
    _sessionSeconds[provider] = 0;
    final prefs = SharedPreferencesUtil();
    await prefs.saveString(_secondsKey(provider), '');
    await prefs.saveString(_errorKey(provider), '');
    await prefs.saveString(_errorAtKey(provider), '');
  }

  /// A one-line summary for the settings page, or null when there is nothing to say.
  static String? describe(SttUsageSnapshot usage, String model) {
    if (usage.isEmpty) return null;
    final minutes = usage.audioMinutes;
    final cost = estimateCostUsd(model, minutes);
    final costPhrase = cost < 0.01 ? 'under a cent' : 'about \$${cost.toStringAsFixed(2)}';
    final parts = <String>['${minutes.toStringAsFixed(1)} min sent, $costPhrase'];
    if (usage.lastError != null) parts.add('last error: ${usage.lastError}');
    return parts.join(' · ');
  }

  /// Encodes the snapshot for diagnostics without exposing the key or the audio.
  static String debugJson(SttProvider provider) => jsonEncode({
        'provider': provider.name,
        'audio_seconds': snapshot(provider).audioSeconds,
        'last_error': snapshot(provider).lastError,
      });
}
