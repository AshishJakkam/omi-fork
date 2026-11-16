import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/stt/uplink_audio_conditioner.dart';

/// Builds 16-bit PCM from normalised doubles.
Uint8List pcm(List<double> samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return out;
}

List<double> unpack(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  return [for (var i = 0; i < bytes.length ~/ 2; i++) view.getInt16(i * 2, Endian.little) / 32768.0];
}

double rms(List<double> xs) => math.sqrt(xs.map((x) => x * x).reduce((a, b) => a + b) / xs.length);

/// Amplitude-modulated tone: a stand-in for speech that carries an envelope.
List<double> speechLike({int sampleRate = 16000, double seconds = 2, double level = 0.02}) => [
      for (var i = 0; i < sampleRate * seconds; i++)
        level * math.sin(2 * math.pi * 300 * i / sampleRate) * (0.5 + 0.5 * math.sin(2 * math.pi * 4 * i / sampleRate)),
    ];

void main() {
  group('UplinkAudioConditioner', () {
    test('removes DC offset and rumble the cloud endpoint ignored', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final out = unpack(conditioner.process(pcm(List<double>.filled(16000, 0.3))));
      // A constant offset is not speech; the high-pass must take it out.
      expect(rms(out.sublist(8000)).abs(), lessThan(0.02));
    });

    test('attenuates 60 Hz far more than 1 kHz', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      // Both tones ride the same gain, so comparing their output amplitudes
      // isolates the high-pass response from the AGC.
      final both = [
        for (var i = 0; i < 16000; i++)
          0.2 * math.sin(2 * math.pi * 60 * i / 16000) + 0.2 * math.sin(2 * math.pi * 1000 * i / 16000),
      ];
      final out = unpack(conditioner.process(pcm(both))).sublist(8000);

      double amplitudeAt(double hz) {
        var re = 0.0, im = 0.0;
        for (var i = 0; i < out.length; i++) {
          re += out[i] * math.cos(2 * math.pi * hz * i / 16000);
          im += out[i] * math.sin(2 * math.pi * hz * i / 16000);
        }
        return 2 * math.sqrt(re * re + im * im) / out.length;
      }

      expect(amplitudeAt(60), lessThan(amplitudeAt(1000) * 0.5));
    });

    test('lifts quiet speech toward the target level', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final quiet = speechLike(level: 0.01);
      final before = rms(quiet);
      final after = rms(unpack(conditioner.process(pcm(quiet))));
      expect(before, lessThan(0.01));
      expect(after, greaterThan(before * 3));
      expect(after, lessThan(0.4));
    });

    test('keeps a silent room silent instead of amplifying noise', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final out = unpack(conditioner.process(pcm(List<double>.filled(16000, 0))));
      expect(out.every((s) => s.abs() < 1e-3), isTrue);
    });

    test('does not pump steady room noise up to the target level', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final rng = math.Random(7);
      final hiss = [for (var i = 0; i < 16000 * 2; i++) (rng.nextDouble() * 2 - 1) * 0.004];
      final before = rms(hiss.sublist(8000));
      final after = rms(unpack(conditioner.process(pcm(hiss))).sublist(8000));
      // Speech-free hiss must not be lifted toward targetRms (0.08).
      expect(after, lessThan(before * 2));
    });

    test('moves energy into the speech band the cloud endpoint needs', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      // Muffled, quiet speech: a 200 Hz fundamental plus a formant, buried in rumble.
      List<double> build() => [
            for (var i = 0; i < 16000; i++)
              0.01 *
                      math.sin(2 * math.pi * 200 * i / 16000) *
                      (0.5 + 0.5 * math.sin(2 * math.pi * 4 * i / 16000)) +
                  0.01 *
                      math.sin(2 * math.pi * 1200 * i / 16000) *
                      (0.5 + 0.5 * math.sin(2 * math.pi * 4 * i / 16000)) +
                  0.05 * math.sin(2 * math.pi * 45 * i / 16000),
          ];

      /// Energy above ~300 Hz divided by energy below it.
      double speechOverRumble(List<double> xs) {
        // One-pole high-pass at 300 Hz; subtracting it leaves the rumble.
        const a = 1 / (1 + 2 * math.pi * 300 / 16000);
        var prevIn = 0.0, prevOut = 0.0;
        final high = <double>[];
        final low = <double>[];
        for (final x in xs) {
          final y = a * (prevOut + x - prevIn);
          prevIn = x;
          prevOut = y;
          high.add(y);
          low.add(x - y);
        }
        return rms(high) / rms(low);
      }

      final before = speechOverRumble(build());
      final after = speechOverRumble(unpack(conditioner.process(pcm(build()))));
      expect(after, greaterThan(before * 1.2));
    });

    test('never exceeds full scale on loud input', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final loud = [for (var i = 0; i < 16000; i++) 0.99 * math.sin(2 * math.pi * 200 * i / 16000)];
      final view = ByteData.sublistView(conditioner.process(pcm(loud)));
      final peak = [for (var i = 0; i < 16000; i++) view.getInt16(i * 2, Endian.little).abs()].reduce(math.max);
      expect(peak, lessThanOrEqualTo(32767));
    });

    test('treats a stream as a stream, not one big block', () {
      final whole = UplinkAudioConditioner(sampleRate: 16000);
      final chunked = UplinkAudioConditioner(sampleRate: 16000);
      final signal = pcm(speechLike(seconds: 2, level: 0.03));

      final once = rms(unpack(whole.process(signal)));

      final builder = BytesBuilder();
      for (var offset = 0; offset < signal.length; offset += 320) {
        builder.add(chunked.process(Uint8List.sublistView(signal, offset, math.min(offset + 320, signal.length))));
      }
      final perFrame = rms(unpack(builder.toBytes()));

      expect((once - perFrame).abs(), lessThan(0.05));
    });

    test('preserves sample count so the timeline stays aligned', () {
      final conditioner = UplinkAudioConditioner(sampleRate: 16000);
      final input = pcm(speechLike(seconds: 1));
      expect(conditioner.process(input).length, input.length);
    });
  });
}
