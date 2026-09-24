import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

/// A published qibla value: city coordinates as used by the publisher, the
/// published bearing (degrees from true north) and distance (km).
class _Published {
  const _Published(this.name, this.lat, this.lon, this.bearing, this.km);
  final String name;
  final double lat;
  final double lon;
  final double bearing;
  final double km;
}

// Source: al-habib.info Qibla Pointer city pages
// (https://www.al-habib.info/qibla-pointer/<city>/), retrieved 2026-09-24.
// Bearings are published to 0.1 degree and distances to 1 km, so the
// tolerances below are one unit of the published resolution.
const _alHabib = [
  _Published('Algiers', 36.7323, 3.0875, 105.4, 3923),
  _Published('Oran', 35.6991, -0.6359, 100.9, 4222),
  _Published('Jakarta', -6.2146, 106.8451, 295.2, 7920),
  _Published('London', 51.5085, -0.1257, 119.0, 4794),
  _Published('New York City', 40.7143, -74.0060, 58.5, 10306),
  _Published('Auckland', -36.8485, 174.7635, 261.2, 15365),
  // Close to Mecca.
  _Published('Jeddah', 21.4901, 39.1862, 96.4, 67),
  _Published('Ta\'if', 21.2703, 40.4158, 285.6, 63),
  _Published('Makkah (city centre, 0.5 km from the Kaaba)', 21.4266, 39.8256,
      172.6, 0),
];

void main() {
  group('Kaaba coordinates', () {
    test('match Wikidata Q29466 (21°25′21″N 39°49′34.2″E)', () {
      expect(kaabaLatitude, closeTo(21 + 25 / 60 + 21 / 3600, 1e-9));
      expect(kaabaLongitude, closeTo(39 + 49 / 60 + 34.2 / 3600, 1e-9));
    });
  });

  group('qiblaBearing matches published values', () {
    for (final p in _alHabib) {
      test(p.name, () {
        expect(qiblaBearing(p.lat, p.lon), closeTo(p.bearing, 0.1));
      });
    }

    // Khalid Shaukat, "Frequently asked questions on qibla direction"
    // (moonsighting.com, mirrored at faculty.kfupm.edu.sa, 1998), angles
    // published to the arc-minute as "west of true north":
    //   Auckland   36:55S 174:47E -> 98:54 W
    //   Wellington 41:17S 174:47E -> 103:38 W
    // The page does not state its Kaaba coordinates. With the whole-minute
    // position 21:25N 39:49E, the great-circle formula reproduces both
    // values to within rounding (half a minute).
    const shaukat = [
      (-(36 + 55 / 60), 174 + 47 / 60, 98 + 54 / 60),
      (-(41 + 17 / 60), 174 + 47 / 60, 103 + 38 / 60),
    ];

    test('reproduces Shaukat (1998) with his minute-rounded Kaaba', () {
      for (final (lat, lon, west) in shaukat) {
        final b = initialBearing(lat, lon, 21 + 25 / 60, 39 + 49 / 60);
        expect(360 - b, closeTo(west, 0.5 / 60));
      }
    });

    test('agrees with Shaukat (1998) within 2 arc-minutes', () {
      // 0.5' rounding plus up to ~1' from the Kaaba position difference.
      for (final (lat, lon, west) in shaukat) {
        expect(360 - qiblaBearing(lat, lon), closeTo(west, 2 / 60));
      }
    });
  });

  group('qiblaDistanceKm', () {
    for (final p in _alHabib) {
      test('haversine: ${p.name}', () {
        expect(qiblaDistanceKm(p.lat, p.lon), closeTo(p.km, 1.0));
      });
    }

    // Reference: GeographicLib 2.1 (C. F. F. Karney, "Algorithms for
    // geodesics", J. Geodesy 2013) Geodesic.WGS84.Inverse to the same
    // Kaaba coordinates. Vincenty agrees with it to well under a metre.
    test('vincenty on WGS-84 agrees with GeographicLib', () {
      const cases = [
        (51.5085, -0.1257, 4794.685320908786),
        (40.7143, -74.0060, 10323.826192601093),
        (-36.8485, 174.7635, 15368.798773563998),
      ];
      for (final (lat, lon, km) in cases) {
        expect(
          qiblaDistanceKm(lat, lon, method: DistanceMethod.vincenty),
          closeTo(km, 0.001),
        );
      }
    });

    test('distance at the Kaaba is zero', () {
      expect(qiblaDistanceKm(kaabaLatitude, kaabaLongitude), 0);
      expect(
        qiblaDistanceKm(kaabaLatitude, kaabaLongitude,
            method: DistanceMethod.vincenty),
        0,
      );
    });
  });

  group('qibla needle', () {
    test('needle angle is qibla minus heading in [0, 360)', () {
      expect(qiblaNeedleAngle(trueHeading: 30, qiblaBearing: 120), 90);
      expect(qiblaNeedleAngle(trueHeading: 350, qiblaBearing: 10),
          closeTo(20, 1e-9));
      expect(qiblaNeedleAngle(trueHeading: 10, qiblaBearing: 350),
          closeTo(340, 1e-9));
    });

    test('signed offset tells which way to turn', () {
      // Positive: turn clockwise (right).
      expect(
          qiblaOffset(trueHeading: 350, qiblaBearing: 10), closeTo(20, 1e-9));
      expect(
          qiblaOffset(trueHeading: 10, qiblaBearing: 350), closeTo(-20, 1e-9));
    });

    test('isFacingQibla uses the shortest angle and an inclusive tolerance',
        () {
      expect(isFacingQibla(trueHeading: 118, qiblaBearing: 119), isTrue);
      expect(isFacingQibla(trueHeading: 358, qiblaBearing: 2), isTrue);
      expect(isFacingQibla(trueHeading: 100, qiblaBearing: 119), isFalse);
      expect(
        isFacingQibla(trueHeading: 110, qiblaBearing: 119, toleranceDegrees: 9),
        isTrue,
      );
      expect(
        isFacingQibla(
            trueHeading: 110, qiblaBearing: 119, toleranceDegrees: 8.9),
        isFalse,
      );
    });

    test('rejects a negative tolerance', () {
      expect(
        () => isFacingQibla(
            trueHeading: 0, qiblaBearing: 0, toleranceDegrees: -1),
        throwsArgumentError,
      );
    });
  });
}
