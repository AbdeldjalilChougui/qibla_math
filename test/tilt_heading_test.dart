import 'dart:math' as math;

import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

/// A 3-vector in the world East-North-Up frame.
typedef _V = (double, double, double);

double _dot(_V a, _V b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
_V _add(_V a, _V b) => (a.$1 + b.$1, a.$2 + b.$2, a.$3 + b.$3);
_V _scale(_V a, double k) => (a.$1 * k, a.$2 * k, a.$3 * k);

const double _g = 9.80665;

/// Simulates what an Android device reports at rest.
///
/// Starting flat and face up with its top edge pointing at [azimuth]
/// (degrees clockwise from magnetic north), the device is pitched by [pitch]
/// about its x axis (top edge down for positive values) and then rolled by
/// [roll] about its new y axis (right edge down for positive values).
/// The field has horizontal strength [bh] toward north and vertical strength
/// [bz] downward (µT), as in the northern hemisphere.
({Vector3 accel, Vector3 mag}) _readings({
  required double azimuth,
  double pitch = 0,
  double roll = 0,
  double bh = 30,
  double bz = 35,
}) {
  final psi = azimuth * math.pi / 180;
  final th = pitch * math.pi / 180;
  final ph = roll * math.pi / 180;
  // Device axes in world ENU coordinates.
  final _V x0 = (math.cos(psi), -math.sin(psi), 0.0);
  final _V y0 = (math.sin(psi), math.cos(psi), 0.0);
  const _V z0 = (0.0, 0.0, 1.0);
  final y1 = _add(_scale(y0, math.cos(th)), _scale(z0, -math.sin(th)));
  final z1 = _add(_scale(z0, math.cos(th)), _scale(y0, math.sin(th)));
  final x2 = _add(_scale(x0, math.cos(ph)), _scale(z1, -math.sin(ph)));
  final z2 = _add(_scale(z1, math.cos(ph)), _scale(x0, math.sin(ph)));
  const _V up = (0.0, 0.0, 1.0);
  final _V b = (0.0, bh, -bz);
  return (
    // An accelerometer at rest reads +g along "up".
    accel: (
      x: _g * _dot(x2, up),
      y: _g * _dot(y1, up),
      z: _g * _dot(z2, up),
    ),
    mag: (x: _dot(x2, b), y: _dot(y1, b), z: _dot(z2, b)),
  );
}

void main() {
  group('tiltCompensatedHeading, device flat', () {
    test('top edge to magnetic north reads 0', () {
      final r = tiltCompensatedHeading(
        accelerometer: (x: 0, y: 0, z: _g),
        magnetometer: (x: 0, y: 30, z: -35),
      )!;
      expect(r.heading, closeTo(0, 1e-9));
      expect(r.pitch, closeTo(0, 1e-9));
      expect(r.roll, closeTo(0, 1e-9));
    });

    test('top edge to east reads 90', () {
      // Top (y) east, right side (x) south: north is -x.
      final r = tiltCompensatedHeading(
        accelerometer: (x: 0, y: 0, z: _g),
        magnetometer: (x: -30, y: 0, z: -35),
      )!;
      expect(r.heading, closeTo(90, 1e-9));
    });

    test('recovers every azimuth', () {
      for (var az = 0.0; az < 360; az += 7.5) {
        final s = _readings(azimuth: az);
        final r = tiltCompensatedHeading(
            accelerometer: s.accel, magnetometer: s.mag)!;
        expect(signedAngleDifference(r.heading, az), closeTo(0, 1e-9));
      }
    });
  });

  group('tilt compensation', () {
    test('heading is unchanged by pitch and roll; angles are recovered', () {
      for (final az in [0.0, 45.0, 137.0, 222.0, 359.0]) {
        for (final pitch in [-60.0, -20.0, 0.0, 35.0, 70.0]) {
          for (final roll in [-50.0, -10.0, 0.0, 25.0, 80.0]) {
            final s = _readings(azimuth: az, pitch: pitch, roll: roll);
            final r = tiltCompensatedHeading(
                accelerometer: s.accel, magnetometer: s.mag)!;
            final where = 'az=$az pitch=$pitch roll=$roll';
            expect(signedAngleDifference(r.heading, az), closeTo(0, 1e-9),
                reason: where);
            expect(r.pitch, closeTo(pitch, 1e-9), reason: where);
            expect(r.roll, closeTo(roll, 1e-9), reason: where);
          }
        }
      }
    });

    test('an uncompensated reading would be wrong when tilted', () {
      // Sanity check that the fixture really tilts: naive atan2 of the raw
      // horizontal magnetometer components is off by several degrees.
      final s = _readings(azimuth: 60, pitch: 40, roll: 0, bh: 20, bz: 45);
      final naive =
          normalizeDegrees(math.atan2(-s.mag.x, s.mag.y) * 180 / math.pi);
      expect(signedAngleDifference(naive, 60).abs(), greaterThan(5));
      final r =
          tiltCompensatedHeading(accelerometer: s.accel, magnetometer: s.mag)!;
      expect(r.heading, closeTo(60, 1e-9));
    });

    test('southern hemisphere field (pointing up) works too', () {
      final s = _readings(azimuth: 300, pitch: 15, roll: -30, bh: 25, bz: -40);
      final r =
          tiltCompensatedHeading(accelerometer: s.accel, magnetometer: s.mag)!;
      expect(r.heading, closeTo(300, 1e-9));
    });

    test('scale of the inputs does not matter', () {
      final s = _readings(azimuth: 123, pitch: 10, roll: 20);
      final r = tiltCompensatedHeading(
        accelerometer: (x: s.accel.x * 3, y: s.accel.y * 3, z: s.accel.z * 3),
        magnetometer: (x: s.mag.x / 7, y: s.mag.y / 7, z: s.mag.z / 7),
      )!;
      expect(r.heading, closeTo(123, 1e-9));
    });

    test('rotation matrix is orthonormal, rows East, North, Up', () {
      final s = _readings(azimuth: 30, pitch: 20, roll: 10);
      final r =
          tiltCompensatedHeading(accelerometer: s.accel, magnetometer: s.mag)!;
      final m = r.rotationMatrix;
      expect(m, hasLength(9));
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          final d = m[i * 3] * m[j * 3] +
              m[i * 3 + 1] * m[j * 3 + 1] +
              m[i * 3 + 2] * m[j * 3 + 2];
          expect(d, closeTo(i == j ? 1 : 0, 1e-12));
        }
      }
    });
  });

  group('screen rotation remapping', () {
    test('heading follows the top of the screen', () {
      // Display.ROTATION_90: the right edge (+x) is the top of the screen.
      const expectedOffset = {
        ScreenRotation.rotation0: 0.0,
        ScreenRotation.rotation90: 90.0,
        ScreenRotation.rotation180: 180.0,
        ScreenRotation.rotation270: 270.0,
      };
      for (final az in [0.0, 80.0, 250.0]) {
        final s = _readings(azimuth: az);
        for (final e in expectedOffset.entries) {
          final r = tiltCompensatedHeading(
            accelerometer: s.accel,
            magnetometer: s.mag,
            screenRotation: e.key,
          )!;
          expect(
            signedAngleDifference(r.heading, az + e.value),
            closeTo(0, 1e-9),
            reason: '${e.key} az=$az',
          );
        }
      }
    });

    test('fromDegrees maps display rotation values', () {
      expect(ScreenRotation.fromDegrees(0), ScreenRotation.rotation0);
      expect(ScreenRotation.fromDegrees(90), ScreenRotation.rotation90);
      expect(ScreenRotation.fromDegrees(180), ScreenRotation.rotation180);
      expect(ScreenRotation.fromDegrees(270), ScreenRotation.rotation270);
      expect(ScreenRotation.fromDegrees(-90), ScreenRotation.rotation270);
      expect(() => ScreenRotation.fromDegrees(45), throwsArgumentError);
    });
  });

  group('degenerate input', () {
    test('free fall (no gravity) returns null', () {
      expect(
        tiltCompensatedHeading(
          accelerometer: (x: 0, y: 0, z: 0),
          magnetometer: (x: 0, y: 30, z: -35),
        ),
        isNull,
      );
    });

    test('field parallel to gravity (magnetic pole) returns null', () {
      expect(
        tiltCompensatedHeading(
          accelerometer: (x: 0, y: 0, z: _g),
          magnetometer: (x: 0, y: 0, z: -50),
        ),
        isNull,
      );
    });

    test('no field returns null', () {
      expect(
        tiltCompensatedHeading(
          accelerometer: (x: 0, y: 0, z: _g),
          magnetometer: (x: 0, y: 0, z: 0),
        ),
        isNull,
      );
    });

    test('non-finite input returns null', () {
      expect(
        tiltCompensatedHeading(
          accelerometer: (x: double.nan, y: 0, z: _g),
          magnetometer: (x: 0, y: 30, z: -35),
        ),
        isNull,
      );
    });
  });
}
