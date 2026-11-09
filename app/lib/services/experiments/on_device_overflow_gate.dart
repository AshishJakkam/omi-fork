import 'package:flutter/foundation.dart';

import 'package:omi/utils/analytics/analytics_manager.dart';

/// Client presentation gate for on-device transcription once live hours run out (the at-cap
/// choice sheet, model setup, schedule, queue banner, provenance and settings). Off leaves every
/// existing surface exactly as it is.
///
/// Evaluated from the PostHog flag `mobile-on-device-overflow`, registered in
/// `config/feature-flags.yaml`. Fail-closed: no analytics identity or a failed read means off.
/// Lifecycle: rollout; owner: dazheng; review-by: 2026-11-13; default off.
abstract final class OnDeviceOverflowGate {
  static const enabledFlag = 'mobile-on-device-overflow';

  /// Debug-build override: `--dart-define=OMI_ON_DEVICE_OVERFLOW=true`.
  static const _debugForce = bool.fromEnvironment('OMI_ON_DEVICE_OVERFLOW');

  /// Build-time override honored in every mode: `--dart-define=OMI_ON_DEVICE_OVERFLOW_FORCE=true`.
  ///
  /// [_debugForce] cannot help a release build, and release is where this matters: the PostHog
  /// flag defaults off and the read fails closed, so a build that has no analytics identity for
  /// the flag — a fork signed with its own bundle id — can never turn on-device transcription on.
  /// The feature then looks broken rather than disabled: recordings are stamped for local custody
  /// by the capture route while the runner stays inactive, so the queue never drains.
  static const _releaseForce = bool.fromEnvironment('OMI_ON_DEVICE_OVERFLOW_FORCE');

  static bool get debugOverrideActive => kDebugMode && _debugForce;

  /// True when this build was compiled to run the feature regardless of the remote flag.
  static bool get forkOverrideActive => _releaseForce;

  static Future<bool> read({Future<bool> Function(String key)? readFlag}) async {
    if (forkOverrideActive) return true;
    if (debugOverrideActive) return true;
    try {
      return await (readFlag ?? AnalyticsManager().isFeatureEnabled)(enabledFlag);
    } catch (_) {
      return false;
    }
  }
}
