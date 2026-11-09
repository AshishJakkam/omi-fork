import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omi/env/environment_profile.dart';

/// The auth callback scheme lives in three places that must agree, and nothing
/// in the compiler connects them:
///
///   1. Dart - `Env.authRedirectUri` builds `redirect_uri=<scheme>://auth/callback`
///      from the profile, and `authenticateWithProvider` only completes when
///      app_links delivers a URI with that exact scheme.
///   2. iOS - `AUTH_CALLBACK_SCHEME` in the flavour xcconfig is what
///      `$(AUTH_CALLBACK_SCHEME)` registers with the OS in Info.plist.
///   3. Android - the prod manifest declares the intent filter.
///
/// When they diverge, OAuth completes in the browser, the OS hands the callback
/// to nobody (or to the other Omi build), and the app waits forever. That is a
/// silent hang, not an error, so it needs a test rather than a comment.
void main() {
  String? xcconfigScheme(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) return null;
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('AUTH_CALLBACK_SCHEME=')) continue;
      return trimmed.substring('AUTH_CALLBACK_SCHEME='.length).trim();
    }
    return null;
  }

  Set<String> androidManifestSchemes(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) return {};
    final pattern = RegExp(r'android:scheme="([^"]+)"');
    return pattern
        .allMatches(file.readAsStringSync())
        .map((match) => match.group(1)!)
        .toSet();
  }

  group('production identity', () {
    test('iOS registers the same callback scheme Dart sends', () {
      final registered = xcconfigScheme('ios/Flutter/prodRelease.xcconfig');

      expect(registered, isNotNull, reason: 'prodRelease.xcconfig must set AUTH_CALLBACK_SCHEME');
      expect(
        registered,
        AppEnvironmentProfile.production.authCallbackScheme,
        reason: 'Info.plist would register a scheme the app never listens for, so OAuth would hang',
      );
    });

    test('Android declares the same callback scheme Dart sends', () {
      final declared = androidManifestSchemes('android/app/src/prod/AndroidManifest.xml');

      expect(
        declared,
        contains(AppEnvironmentProfile.production.authCallbackScheme),
        reason: 'the prod intent filter must accept the redirect Dart asks for',
      );
    });

    test('the fork does not reuse the App Store app scheme', () {
      // "omi" belongs to the shipping app. If both builds register it, iOS picks
      // one arbitrarily when the callback arrives.
      expect(AppEnvironmentProfile.production.authCallbackScheme, isNot('omi'));
    });
  });

  group('local_dev identity', () {
    test('iOS registers the same callback scheme Dart sends', () {
      final registered = xcconfigScheme('ios/Flutter/devDebug.xcconfig');

      expect(registered, isNotNull, reason: 'devDebug.xcconfig must set AUTH_CALLBACK_SCHEME');
      expect(
        registered,
        AppEnvironmentProfile.localDev.authCallbackScheme,
        reason: 'dev builds would hang on OAuth for the same reason as prod',
      );
    });

    test('Android declares the same callback scheme Dart sends', () {
      final declared = androidManifestSchemes('android/app/src/dev/AndroidManifest.xml');

      expect(declared, contains(AppEnvironmentProfile.localDev.authCallbackScheme));
    });
  });
}
