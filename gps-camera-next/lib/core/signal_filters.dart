import 'dart:math' as math;

/// Exponential low-pass filter whose smoothing depends on elapsed time, not
/// on the sample count, so it removes the same frequencies whatever rate the
/// sensor delivers. Starts at the first sample, so there is no warm-up lag.
class LowPass {
  LowPass(this.cutoffHz);

  /// The −3 dB corner. Lower is smoother and slower.
  final double cutoffHz;
  double? _value;
  Duration? _at;

  double? get value => _value;

  /// [at] is the sample time (any monotonic clock).
  double add(double x, Duration at) {
    final previous = _value;
    final last = _at;
    _at = at;
    if (previous == null || last == null) return _value = x;
    final dt = (at - last).inMicroseconds / 1e6;
    // A long gap (sensor paused) restarts from the new reading.
    if (dt <= 0 || dt > 1) return _value = dt <= 0 ? previous : x;
    final alpha = (1 - math.exp(-2 * math.pi * cutoffHz * dt)).clamp(
      0.001,
      1.0,
    );
    return _value = previous + alpha * (x - previous);
  }

  void reset() {
    _value = null;
    _at = null;
  }
}

/// [LowPass] for a compass heading in degrees. Filters the heading's sine and
/// cosine, so turning through north (359° → 1°) is a 2° turn, not a 358° swing.
class HeadingLowPass {
  HeadingLowPass(double cutoffHz)
    : _sin = LowPass(cutoffHz),
      _cos = LowPass(cutoffHz);

  final LowPass _sin;
  final LowPass _cos;

  /// Returns the smoothed heading in [0, 360).
  double add(double degrees, Duration at) {
    final r = degrees * math.pi / 180;
    final s = _sin.add(math.sin(r), at);
    final c = _cos.add(math.cos(r), at);
    return (math.atan2(s, c) * 180 / math.pi + 360) % 360;
  }

  void reset() {
    _sin.reset();
    _cos.reset();
  }
}
