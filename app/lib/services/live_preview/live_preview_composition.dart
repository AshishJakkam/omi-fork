import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:opus_dart/opus_dart.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/services/capture/uplink_silence_timer.dart';
import 'package:omi/services/experiments/live_preview_gate.dart';
import 'package:omi/services/live_preview/live_preview_controller.dart';
import 'package:omi/services/live_preview/live_preview_engine.dart';
import 'package:omi/services/live_preview/live_preview_notes.dart';
import 'package:omi/services/freemium_transcription_service.dart';
import 'package:omi/services/live_preview/live_preview_telemetry.dart';
import 'package:omi/models/stt_provider.dart';
import 'package:omi/services/live_preview/whisper_window_preview_engine.dart';
import 'package:omi/services/sockets/on_device_whisper_provider.dart';

/// Production wiring: the native engine per platform (iOS
/// `LivePreviewPlugin.swift`, Android `LivePreviewPlugin.kt`); on Android,
/// Omi's downloaded Whisper model is the windowed fallback. Other platforms
/// have no preview controller, so they never declare `local_preview=enabled`.
LivePreviewController? composeLivePreview() {
  if (!Platform.isIOS && !Platform.isAndroid) return null;
  SimpleOpusDecoder? decoder;
  final android = Platform.isAndroid;
  final controller = LivePreviewController(
    engine: android
        ? FallbackLivePreviewEngine(primary: MethodChannelLivePreviewEngine(), fallback: _downloadedWhisper)
        // iOS used to preview only with the OS recogniser, so choosing the downloaded model - which
        // people do precisely when Apple handles their language badly - still previewed with Apple.
        : _ChosenLocalPreviewEngine(MethodChannelLivePreviewEngine()),
    telemetry: LivePreviewTelemetry(),
    platform: android ? LivePreviewPlatform.android : LivePreviewPlatform.ios,
    osMajor: android ? 0 : osMajorVersion(Platform.operatingSystemVersion),
    // On-device live notes: Apple Foundation Models on iOS 26+; Android has no
    // engine in this release (the Summary shows the quiet line).
    notesEngine: android ? noLivePreviewNotesEngine : methodChannelLivePreviewNotes,
    // A preview-only decoder: capture's Opus bytes are copied before decoding.
    decodeOpus: (Uint8List opus) => (decoder ??= SimpleOpusDecoder(sampleRate: 16000, channels: 1)).decode(input: opus),
    conversationGap: () => UplinkSilenceTimer.fromPreference(SharedPreferencesUtil().conversationSilenceDuration),
    requestAllowed: LivePreviewGate.requestAllowed,
  );
  if (android) {
    unawaited(DeviceInfoPlugin()
        .androidInfo
        .then((info) => controller.osMajor = osMajorVersion(info.version.release))
        .catchError((Object _) => 0));
  }
  return controller;
}

/// The Whisper model the user already downloaded for on-device transcription,
/// or null. Never downloads one.
Future<LivePreviewEngine?> _downloadedWhisper() async {
  final service = FreemiumTranscriptionService();
  await service.checkReadiness();
  final model = service.cachedModelPath;
  if (model == null) return null;
  final whisper = OnDeviceWhisperProvider(modelPath: model, onDeviceOverflowEnabled: false);
  return WhisperWindowPreviewEngine(
    transcribe: (wav, language) async => (await whisper.transcribe(wav, language: language))?.rawText,
  );
}

/// First integer in an OS version string ("Version 26.1 (Build 23B85)" → 26).
int osMajorVersion(String version) => int.tryParse(RegExp(r'\d+').firstMatch(version)?.group(0) ?? '') ?? 0;

/// On iOS the preview used to come from the OS recogniser whatever the reader chose, so picking
/// Omi's downloaded model - which people do when Apple handles their language badly - changed the
/// transcript but never the live preview.
///
/// This follows the choice: the windowed whisper engine when the on-device provider is selected and
/// a model is installed, otherwise the system engine, which stays as the fallback so a phone with a
/// broken model still previews something.
class _ChosenLocalPreviewEngine implements LivePreviewEngine {
  _ChosenLocalPreviewEngine(this._system);

  final LivePreviewEngine _system;
  final StreamController<LivePreviewResult> _results = StreamController.broadcast();
  LivePreviewEngine? _active;
  StreamSubscription<LivePreviewResult>? _forward;

  @override
  Stream<LivePreviewResult> get results => _results.stream;

  @override
  Future<LivePreviewStart> start(String language, {Set<LivePreviewEngineKind> exclude = const {}}) async {
    await _detach();
    final config = SharedPreferencesUtil().customSttConfig;
    final choseLocalWhisper = config.isEnabled && config.provider == SttProvider.onDeviceWhisper;

    if (choseLocalWhisper && !exclude.contains(LivePreviewEngineKind.whisper)) {
      try {
        final whisper = await _downloadedWhisper();
        if (whisper != null) {
          final started = await whisper.start(language, exclude: exclude);
          if (started.running) return _attach(whisper, started);
        }
      } catch (_) {
        // Fall through to the system engine rather than leaving the preview dead.
      }
    }

    final started = await _system.start(language, exclude: exclude);
    return _attach(_system, started);
  }

  LivePreviewStart _attach(LivePreviewEngine engine, LivePreviewStart start) {
    _active = engine;
    _forward = engine.results.listen(_results.add, onError: _results.addError);
    return start;
  }

  Future<void> _detach() async {
    final active = _active;
    _active = null;
    await _forward?.cancel();
    _forward = null;
    if (active != null) await active.stop();
  }

  @override
  Future<bool> feedPcm16(Uint8List pcm, {DateTime? startedAt}) =>
      _active?.feedPcm16(pcm, startedAt: startedAt) ?? Future.value(false);

  @override
  Future<void> stop() => _detach();
}
