import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/experiments/on_device_overflow_gate.dart';

/// The fork's build-time override, kept in its own file because it changes the gate's answer:
/// the fail-closed assertions in `on_device_settings_test.dart` only hold while it is compiled out.
///
/// Run it both ways:
///   flutter test test/unit/on_device_overflow_gate_force_test.dart
///   flutter test --dart-define=OMI_ON_DEVICE_OVERFLOW_FORCE=true test/unit/on_device_overflow_gate_force_test.dart
void main() {
  test('fork override decides the gate, remote flag or not', () async {
    if (!OnDeviceOverflowGate.forkOverrideActive) {
      // Compiled without the define: nothing about the upstream contract changes.
      expect(await OnDeviceOverflowGate.read(readFlag: (_) async => false), isFalse);
      expect(await OnDeviceOverflowGate.read(readFlag: (_) async => throw StateError('offline')), isFalse);
      return;
    }

    // Compiled with it: a release build can opt in without PostHog, which is the whole point —
    // a fork signed with its own bundle id has no analytics identity to read the flag from.
    expect(await OnDeviceOverflowGate.read(readFlag: (_) async => false), isTrue);
    expect(await OnDeviceOverflowGate.read(readFlag: (_) async => throw StateError('offline')), isTrue);
  });
}
