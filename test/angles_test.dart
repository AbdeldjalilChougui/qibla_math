import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeDegrees', () {
    test('keeps values already in range', () {
      expect(normalizeDegrees(0), 0);
      expect(normalizeDegrees(123.5), 123.5);
      expect(normalizeDegrees(359.999), closeTo(359.999, 1e-12));
    });

    test('wraps negatives and values >= 360', () {
      expect(normalizeDegrees(-10), closeTo(350, 1e-9));
      expect(normalizeDegrees(370), closeTo(10, 1e-9));
      expect(normalizeDegrees(360), 0);
      expect(normalizeDegrees(-360), 0);
      expect(normalizeDegrees(720.25), closeTo(0.25, 1e-9));
      expect(normalizeDegrees(-1080.5), closeTo(359.5, 1e-9));
    });

    test('never returns 360 for tiny negative inputs', () {
      final r = normalizeDegrees(-1e-15);
      expect(r, greaterThanOrEqualTo(0));
      expect(r, lessThan(360));
    });

    test('propagates NaN', () {
      expect(normalizeDegrees(double.nan).isNaN, isTrue);
    });
  });

  group('signedAngleDifference', () {
    test('returns a - b for small differences', () {
      expect(signedAngleDifference(30, 10), closeTo(20, 1e-12));
      expect(signedAngleDifference(10, 30), closeTo(-20, 1e-12));
    });

    test('takes the short way across 0/360', () {
      expect(signedAngleDifference(350, 10), closeTo(-20, 1e-9));
      expect(signedAngleDifference(10, 350), closeTo(20, 1e-9));
      expect(signedAngleDifference(1, 359), closeTo(2, 1e-9));
    });

    test('range is (-180, 180]: exactly opposite gives +180', () {
      expect(signedAngleDifference(0, 180), 180);
      expect(signedAngleDifference(180, 0), 180);
      expect(signedAngleDifference(90, 270), 180);
      expect(signedAngleDifference(270, 90), 180);
    });

    test('accepts unnormalised inputs', () {
      expect(signedAngleDifference(-350, 725), closeTo(5, 1e-9));
    });

    test('is always within (-180, 180]', () {
      for (var a = -720.0; a <= 720; a += 17.3) {
        for (var b = -720.0; b <= 720; b += 23.9) {
          final d = signedAngleDifference(a, b);
          expect(d, greaterThan(-180));
          expect(d, lessThanOrEqualTo(180));
          // b + d must land on a (compared circularly, since 0 == 360).
          expect(signedAngleDifference(b + d, a), closeTo(0, 1e-6));
        }
      }
    });
  });

  group('smoothAngle', () {
    test('first sample returns the normalised value', () {
      expect(smoothAngle(null, 42, alpha: 0.3), closeTo(42, 1e-12));
      expect(smoothAngle(null, -90, alpha: 0.3), closeTo(270, 1e-12));
    });

    test('moves toward the target by alpha', () {
      expect(smoothAngle(0, 10, alpha: 0.2), closeTo(2, 1e-9));
    });

    test('crosses 359 -> 1 the short way', () {
      expect(smoothAngle(359, 1, alpha: 0.2), closeTo(359.4, 1e-9));
      expect(smoothAngle(1, 359, alpha: 0.5), closeTo(0, 1e-9));
      expect(smoothAngle(2, 358, alpha: 0.75), closeTo(359, 1e-9));
    });

    test('alpha 1 jumps to the target, alpha 0 holds', () {
      expect(smoothAngle(10, 200, alpha: 1), closeTo(200, 1e-9));
      expect(smoothAngle(10, 200, alpha: 0), closeTo(10, 1e-9));
    });

    test('rejects alpha outside [0, 1]', () {
      expect(() => smoothAngle(0, 1, alpha: -0.1), throwsArgumentError);
      expect(() => smoothAngle(0, 1, alpha: 1.1), throwsArgumentError);
    });
  });

  group('CircularEma', () {
    test('starts empty and seeds with the first sample', () {
      final ema = CircularEma(alpha: 0.5);
      expect(ema.value, isNull);
      expect(ema.add(350), closeTo(350, 1e-12));
      expect(ema.value, closeTo(350, 1e-12));
    });

    test('converges across the wrap without sweeping through 180', () {
      final ema = CircularEma(alpha: 0.5)..add(350);
      final seen = <double>[];
      for (var i = 0; i < 30; i++) {
        seen.add(ema.add(10));
      }
      expect(ema.value, closeTo(10, 1e-6));
      for (final v in seen) {
        expect(v >= 350 || v <= 10, isTrue, reason: 'went the long way: $v');
      }
    });

    test('reset forgets history', () {
      final ema = CircularEma(alpha: 0.1)..add(100);
      ema.reset();
      expect(ema.value, isNull);
      expect(ema.add(5), closeTo(5, 1e-12));
    });

    test('rejects alpha outside (0, 1]', () {
      expect(() => CircularEma(alpha: 0), throwsArgumentError);
      expect(() => CircularEma(alpha: 1.5), throwsArgumentError);
    });
  });

  group('circularMean', () {
    test('mean of angles around north is north, not south', () {
      expect(circularMean([350, 10])!, closeTo(0, 1e-9));
      expect(circularMean([355, 5, 0])!, closeTo(0, 1e-9));
    });

    test('ordinary mean for a tight cluster', () {
      expect(circularMean([80, 90, 100])!, closeTo(90, 1e-9));
    });

    test('result is in [0, 360)', () {
      expect(circularMean([340, 350])!, closeTo(345, 1e-9));
    });

    test('returns null when undefined', () {
      expect(circularMean(<double>[]), isNull);
      expect(circularMean([0, 180]), isNull);
      expect(circularMean([0, 120, 240]), isNull);
    });

    test('single angle is its own mean', () {
      expect(circularMean([-45])!, closeTo(315, 1e-9));
    });
  });
}
