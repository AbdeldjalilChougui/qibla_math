import 'dart:math' as math;

/// Converts degrees to radians.
double degToRad(double degrees) => degrees * math.pi / 180.0;

/// Converts radians to degrees.
double radToDeg(double radians) => radians * 180.0 / math.pi;

/// Normalises any angle in degrees into the half-open range `[0, 360)`.
///
/// `NaN` and infinities produce `NaN`.
double normalizeDegrees(double degrees) {
  final a = degrees % 360.0; // Dart's % is non-negative for a positive divisor.
  // A tiny negative input can round up to exactly 360.0.
  return a >= 360.0 ? 0.0 : a;
}

/// Signed shortest angular difference `a - b` in degrees, in `(-180, 180]`.
///
/// A positive result means [a] lies clockwise of [b]. Exactly opposite
/// directions return `+180`.
double signedAngleDifference(double a, double b) {
  final d = normalizeDegrees(a - b);
  return d > 180.0 ? d - 360.0 : d;
}

/// One step of an exponential moving average on a circle.
///
/// Moves [previous] toward [current] by the fraction [alpha] (in `[0, 1]`)
/// of the shortest signed difference, so a heading that crosses 359° to 0°
/// is smoothed through north instead of sweeping back through south.
///
/// Pass `null` for [previous] on the first sample; the normalised [current]
/// is returned. The result is in `[0, 360)`.
double smoothAngle(double? previous, double current, {required double alpha}) {
  if (!(alpha >= 0 && alpha <= 1)) {
    throw ArgumentError.value(alpha, 'alpha', 'must be in [0, 1]');
  }
  if (previous == null) return normalizeDegrees(current);
  final delta = signedAngleDifference(current, previous);
  return normalizeDegrees(previous + alpha * delta);
}

/// Stateful circular exponential moving average for streams of headings.
///
/// ```dart
/// final ema = CircularEma(alpha: 0.2);
/// ema.add(359);
/// ema.add(1); // 359.4, not 287.
/// ```
class CircularEma {
  /// Creates a smoother. [alpha] must be in `(0, 1]`; lower is smoother.
  CircularEma({required this.alpha}) {
    if (!(alpha > 0 && alpha <= 1)) {
      throw ArgumentError.value(alpha, 'alpha', 'must be in (0, 1]');
    }
  }

  /// Smoothing factor in `(0, 1]`.
  final double alpha;

  double? _value;

  /// Current smoothed angle in `[0, 360)`, or `null` before the first sample.
  double? get value => _value;

  /// Feeds one sample (degrees) and returns the new smoothed angle.
  double add(double degrees) =>
      _value = smoothAngle(_value, degrees, alpha: alpha);

  /// Forgets all history; the next [add] seeds the average.
  void reset() => _value = null;
}

/// Circular (vector) mean of [degrees], in `[0, 360)`.
///
/// Returns `null` when the mean is undefined: the input is empty or the
/// angles cancel out (for example `[0, 180]`).
double? circularMean(Iterable<double> degrees) {
  var s = 0.0;
  var c = 0.0;
  var n = 0;
  for (final d in degrees) {
    final r = degToRad(d);
    s += math.sin(r);
    c += math.cos(r);
    n++;
  }
  if (n == 0) return null;
  // Mean resultant length below this is numerical noise: no direction.
  if (math.sqrt(s * s + c * c) / n < 1e-9) return null;
  return normalizeDegrees(radToDeg(math.atan2(s, c)));
}
