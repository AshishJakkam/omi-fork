import 'dart:math' as math;
import 'dart:typed_data';

/// Conditions microphone audio before it leaves the phone for a cloud STT socket.
///
/// Phone-mic chunks recorded on a phone lying on a desk came back at about
/// -35 dBFS with 12% of their energy below 120 Hz and only 7% in the 1-3 kHz
/// band that carries intelligibility. Gemini's streaming endpoint ignored that
/// stream completely — no `voiceActivity`, no `inputTranscription` — while the
/// identical audio transcribed once the rumble was removed and the level lifted.
/// Whisper tolerated the raw audio, which is why on-device text appeared but the
/// cloud transcript stayed empty.
///
/// Two stages, both stateful and therefore safe to run frame by frame:
///  * a cascaded one-pole high-pass at [cutoffHz] removes rumble and DC offset;
///  * a slow RMS-following gain lifts quiet speech toward [targetRms], capped so
///    background noise in a silent room is never amplified into a false signal,
///    then a soft limiter keeps peaks inside full scale.
///
/// Input and output are little-endian 16-bit mono PCM, the format these sockets
/// publish in `mimeType`.
class UplinkAudioConditioner {
  UplinkAudioConditioner({
    required this.sampleRate,
    this.cutoffHz = 100,
    this.targetRms = 0.08,
    this.maxGain = 20,
    this.speechToNoiseRatio = 2.0,
  })  : assert(sampleRate > 0),
        _decay = 1.0 / (1.0 + 2 * math.pi * cutoffHz / sampleRate);

  /// Sample rate of the PCM passed to [process].
  final int sampleRate;

  /// High-pass corner frequency. Speech fundamentals start above this.
  final double cutoffHz;

  /// Level the gain stage aims for, in normalised full-scale units.
  final double targetRms;

  /// Upper bound on the lift applied to very quiet input.
  final double maxGain;

  /// How far a block must stand above the tracked noise floor before it is
  /// treated as speech and given gain.
  final double speechToNoiseRatio;

  /// One-pole high-pass coefficient.
  final double _decay;

  // Two cascaded high-pass sections, each with its own input/output history.
  double _in1 = 0, _out1 = 0;
  double _in2 = 0, _out2 = 0;

  double _gain = 1;
  double _blockSumSquares = 0;
  int _blockSamples = 0;

  /// Slow estimate of the room's noise level, used to tell speech from hiss.
  double? _noiseFloor;

  /// Samples per gain update: 10 ms, long enough to measure, short enough to
  /// track the syllable gaps speech is full of.
  int get _blockSize => math.max(1, sampleRate ~/ 100);

  /// Conditions [pcm] in place-equivalent fashion, returning a new buffer.
  Uint8List process(Uint8List pcm) {
    final out = Uint8List(pcm.length);
    final view = ByteData.sublistView(pcm);
    final outView = ByteData.sublistView(out);
    final samples = pcm.length ~/ 2;
    for (var i = 0; i < samples; i++) {
      final x = view.getInt16(i * 2, Endian.little) / 32768.0;
      final filtered = _highPass(x);
      _blockSumSquares += filtered * filtered;
      _blockSamples++;
      if (_blockSamples >= _blockSize) {
        _updateGain();
      }
      final scaled = _limit(filtered * _gain);
      final value = (scaled * 32767).round().clamp(-32768, 32767);
      outView.setInt16(i * 2, value, Endian.little);
    }
    return out;
  }

  double _highPass(double x) {
    final y1 = _decay * (_out1 + x - _in1);
    _in1 = x;
    _out1 = y1;
    final y2 = _decay * (_out2 + y1 - _in2);
    _in2 = y1;
    _out2 = y2;
    return y2;
  }

  void _updateGain() {
    final rms = math.sqrt(_blockSumSquares / _blockSamples);
    _blockSumSquares = 0;
    _blockSamples = 0;
    // A silent room measures near zero; lifting that would manufacture a signal
    // the model could latch onto, so hold the current gain instead.
    if (rms < 1e-4) return;

    // Track the quietest recent block as the noise floor: fall fast, rise slowly,
    // so a pause between words is measured as noise rather than resetting it.
    final floor = _noiseFloor;
    if (floor == null || rms < floor) {
      _noiseFloor = floor == null ? rms : floor + (rms - floor) * 0.5;
    } else {
      _noiseFloor = floor + (rms - floor) * 0.002;
    }

    // Only content that stands clear of the floor earns gain. Otherwise hiss is
    // pumped up to the target and the model is handed loud noise all session.
    final hasSpeech = rms > _noiseFloor! * speechToNoiseRatio;
    if (!hasSpeech) {
      _gain += (1.0 - _gain) * 0.08;
      return;
    }

    final desired = (targetRms / rms).clamp(1.0, maxGain);
    // Attack quickly enough to reach working level inside the first word,
    // release slowly enough to avoid pumping between syllables.
    _gain += (desired - _gain) * (desired > _gain ? 0.35 : 0.08);
  }

  double _limit(double v) {
    const knee = 0.7;
    final magnitude = v.abs();
    if (magnitude <= knee) return v;
    final limited = knee + (1 - knee) * _tanh((magnitude - knee) / (1 - knee));
    return v.isNegative ? -limited : limited;
  }

  static double _tanh(double x) {
    if (x > 12) return 1;
    if (x < -12) return -1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}
