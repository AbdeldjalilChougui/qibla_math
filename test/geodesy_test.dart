import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

double _dms(num d, num m, num s) => d + m / 60 + s / 3600;

void main() {
  group('initialBearing', () {
    test('cardinal directions on the equator and meridian', () {
      expect(initialBearing(0, 0, 10, 0), closeTo(0, 1e-9));
      expect(initialBearing(0, 0, 0, 10), closeTo(90, 1e-9));
      expect(initialBearing(0, 0, -10, 0), closeTo(180, 1e-9));
      expect(initialBearing(0, 0, 0, -10), closeTo(270, 1e-9));
    });

    test('is in [0, 360)', () {
      for (var lat = -80.0; lat <= 80; lat += 40) {
        for (var lon = -179.0; lon <= 179; lon += 51) {
          final b = initialBearing(lat, lon, 21.4, 39.8);
          expect(b, greaterThanOrEqualTo(0));
          expect(b, lessThan(360));
        }
      }
    });
  });

  group('haversineDistanceKm', () {
    test('zero for identical points', () {
      expect(haversineDistanceKm(12.3, 45.6, 12.3, 45.6), 0);
    });

    test('quarter meridian on the mean sphere', () {
      // pi/2 * R
      expect(haversineDistanceKm(0, 0, 90, 0),
          closeTo(meanEarthRadiusKm * 1.5707963267948966, 1e-9));
    });

    test('antipodes are half a circumference', () {
      // Haversine is ill-conditioned at the antipode: 1 - h is ~1e-16, whose
      // square root is ~1e-8 rad, i.e. ~0.1 m. 1 m bounds that honestly.
      expect(haversineDistanceKm(10, 20, -10, -160),
          closeTo(meanEarthRadiusKm * 3.141592653589793, 1e-3));
    });

    test('custom radius', () {
      expect(haversineDistanceKm(0, 0, 0, 90, radiusKm: 1),
          closeTo(1.5707963267948966, 1e-12));
    });
  });

  group('vincentyInverse', () {
    // Geoscience Australia worked example (Flinders Peak to Buninyong, GRS80),
    // published in the GDA2020 Technical Manual and GA's geodetic
    // calculation pages. s = 54 972.271 m, azimuth 306°52'05.37",
    // reverse azimuth 127°10'25.07".
    test('Flinders Peak to Buninyong (Geoscience Australia)', () {
      final r = vincentyInverse(
        -_dms(37, 57, 3.72030),
        _dms(144, 25, 29.52440),
        -_dms(37, 39, 10.15610),
        _dms(143, 55, 35.38390),
        ellipsoid: Ellipsoid.grs80,
      );
      expect(r.distanceMeters, closeTo(54972.271, 0.001));
      expect(r.initialBearing, closeTo(_dms(306, 52, 5.37), 0.01 / 3600));
      // The published reverse azimuth is the final bearing + 180.
      expect(normalizeDegrees(r.finalBearing + 180),
          closeTo(_dms(127, 10, 25.07), 0.01 / 3600));
    });

    test('zero distance for coincident points', () {
      final r = vincentyInverse(21.4, 39.8, 21.4, 39.8);
      expect(r.distanceMeters, 0);
    });

    test('equatorial arc equals a * dLon', () {
      final r = vincentyInverse(0, 0, 0, 1);
      expect(r.distanceMeters,
          closeTo(Ellipsoid.wgs84.a * 0.017453292519943295, 1e-6));
      expect(r.initialBearing, closeTo(90, 1e-9));
    });

    test('meridian quadrant of WGS-84 is 10 001 965.729 m', () {
      // Known value of the WGS-84 meridian quadrant (equator to pole).
      final r = vincentyInverse(0, 0, 90, 0);
      expect(r.distanceMeters, closeTo(10001965.729, 0.001));
    });

    test('throws for nearly antipodal points where it cannot converge', () {
      expect(
        () => vincentyInverse(0, 0, 0.5, 179.7),
        throwsA(isA<VincentyConvergenceException>()),
      );
    });
  });
}
