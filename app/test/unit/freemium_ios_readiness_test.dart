import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/freemium_transcription_service.dart';
import 'package:omi/services/sockets/apple_speech_readiness.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _SupportDir extends PathProviderPlatform {
  _SupportDir(this.path);
  final String path;

  @override
  Future<String> getApplicationSupportPath() async => path;
}

AppleSpeechReadiness _apple({required bool ready}) =>
    AppleSpeechReadiness('sfspeech', ready ? 'ready' : 'notDetermined');

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('freemium_readiness');
    await Directory('${dir.path}/models').create(recursive: true);
    PathProviderPlatform.instance = _SupportDir(dir.path);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// iOS readiness used to ask Apple's recognizer only, so a phone with a usable whisper model
  /// reported "Transcription is unavailable" and the on-device queue stopped draining. The model
  /// is what the runner actually runs, so it has to be enough on its own.
  test('a whisper model on iOS is ready even when Apple speech is not', () async {
    await File('${dir.path}/models/ggml-base.bin').writeAsBytes([0]);

    final service = FreemiumTranscriptionService.testing(
      iosOverride: true,
      appleReadinessReader: (_) async => _apple(ready: false),
    );

    expect(await service.checkReadiness(), FreemiumReadiness.ready);
  });

  test('an installed whisper model is cached for the runner', () async {
    final path = '${dir.path}/models/ggml-base.bin';
    await File(path).writeAsBytes([0]);

    final service = FreemiumTranscriptionService.testing(
      iosOverride: true,
      appleReadinessReader: (_) async => _apple(ready: false),
    );
    await service.checkReadiness();

    expect(service.cachedModelPath?.replaceAll('\\', '/'), path.replaceAll('\\', '/'));
  });

  test('without a model, iOS still falls back to Apple readiness', () async {
    final service = FreemiumTranscriptionService.testing(
      iosOverride: true,
      appleReadinessReader: (_) async => _apple(ready: false),
    );

    expect(await service.checkReadiness(), FreemiumReadiness.requiresSetup);
  });

  test('without a model, a ready Apple engine is enough', () async {
    final service = FreemiumTranscriptionService.testing(
      iosOverride: true,
      appleReadinessReader: (_) async => _apple(ready: true),
    );

    expect(await service.checkReadiness(), FreemiumReadiness.ready);
  });
}
