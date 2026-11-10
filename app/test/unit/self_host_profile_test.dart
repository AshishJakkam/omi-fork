import 'package:flutter_test/flutter_test.dart';
import 'package:omi/env/env.dart';
import 'package:omi/env/environment_profile.dart';

/// The self_host profile exists so a build can talk to a backend its operator runs.
///
/// Both shipping profiles refuse that: `production` pins `https://api.omi.me/`, and
/// `localProd` is debug-only. These cases pin the compensating trade — the authority is
/// free, but it must be public https and it must name a Firebase project, so a
/// half-configured deployment fails at startup instead of silently sending credentials
/// somewhere unexpected.
void main() {
  group('self_host profile', () {
    test('carries no defaults, because there is nothing honest to default to', () {
      expect(AppEnvironmentProfile.selfHost.defaultApiBaseUrl, isEmpty);
      expect(AppEnvironmentProfile.selfHost.firebaseProjectId, isEmpty);
      expect(AppEnvironmentProfile.selfHost.usesFirebaseAuthEmulator, isFalse);
      expect(AppEnvironmentProfile.selfHost.authCallbackScheme, 'openmind');
    });

    test('is selectable by name at build time', () {
      // OMI_APP_PROFILE is a compile-time define, so this asserts the router accepts
      // the name rather than that a define was set for this test run.
      expect(AppEnvironmentProfile.selfHost.name, 'self_host');
    });

    test('accepts a public https authority in a release build', () {
      for (final endpoint in [
        'https://omi-selfhost.fly.dev/',
        'https://omi.example.com/',
        'https://omi.example.com:8443/',
      ]) {
        Env.validateStartupRouting(
          productionFamily: true,
          configuredProfile: AppEnvironmentProfile.selfHost,
          configuredApiBaseUrl: endpoint,
          releaseBuild: true,
        );
      }
    });

    test('rejects loopback-insecure, plain http and placeholders', () {
      for (final endpoint in [
        'http://127.0.0.1:8000/',
        'http://omi.example.com/',
        'https://',
        '',
      ]) {
        expect(
          () => Env.validateStartupRouting(
            productionFamily: true,
            configuredProfile: AppEnvironmentProfile.selfHost,
            configuredApiBaseUrl: endpoint,
            releaseBuild: true,
          ),
          throwsStateError,
          reason: endpoint,
        );
      }
    });

    test('accepts https to a private host, because TLS is the property that matters', () {
      // Serving a self-hosted backend on a LAN behind TLS is legitimate; it is the
      // absence of TLS that must be refused, not the address family.
      Env.validateStartupRouting(
        productionFamily: true,
        configuredProfile: AppEnvironmentProfile.selfHost,
        configuredApiBaseUrl: 'https://192.168.1.20/',
        releaseBuild: true,
      );
    });

    test('accepts any non-empty Firebase project, but not an empty one', () {
      Env.validateFirebaseProject(
        projectId: 'my-own-omi-project',
        configuredProfile: AppEnvironmentProfile.selfHost,
      );
      expect(
        () => Env.validateFirebaseProject(projectId: '', configuredProfile: AppEnvironmentProfile.selfHost),
        throwsStateError,
      );
    });

    test('OAuth still runs against the configured authority, not the production one', () {
      expect(
        Env.authApiBaseUrlForProfile(
          AppEnvironmentProfile.selfHost,
          servingApiBaseUrl: 'https://omi.example.com/',
        ),
        'https://omi.example.com/',
      );
    });
  });
}
