import 'dart:math' as math;

import 'angles.dart';

/// A sensor reading in the Android device frame: x to the right of the
/// screen, y to the top of the screen, z out of the screen toward the user.
///
/// Any unit works (m/s² for the accelerometer, µT for the magnetometer);
/// only directions are used.
typedef Vector3 = ({double x, double y, double z});

/// How the screen is rotated from the device's natural orientation, as
/// reported by Android's `Display.getRotation()`.
enum ScreenRotation {
  /// Natural orientation (`Surface.ROTATION_0`).
  rotation0(0),

  /// `Surface.ROTATION_90`: the device's right edge (+x) is at the top of
  /// the screen.
  rotation90(90),

  /// `Surface.ROTATION_180`: upside down.
  rotation180(180),

  /// `Surface.ROTATION_270`: the device's left edge (-x) is at the top of
  /// the screen.
  rotation270(270);

  const ScreenRotation(this.degrees);

  /// Rotation in degrees: 0, 90, 180 or 270.
  final int degrees;

  /// Maps 0, 90, 180 or 270 (any multiple of 90, negatives allowed) to a
  /// value. Throws [ArgumentError] for other angles.
  static ScreenRotation fromDegrees(int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(degrees, 'degrees', 'must be a multiple of 90');
    }
    return values[(degrees % 360) ~/ 90];
  }
}

/// Orientation of the device computed by [tiltCompensatedHeading].
class TiltHeading {
  /// Creates a result.
  const TiltHeading({
    required this.heading,
    required this.pitch,
    required this.roll,
    required this.rotationMatrix,
  });

  /// Direction the top of the screen points, projected on the horizontal
  /// plane, in degrees clockwise from **magnetic** north, `[0, 360)`.
  /// Add the declination to get a true heading.
  final double heading;

  /// Rotation about the screen's x axis in degrees, `[-90, 90]`. Positive
  /// when the top edge of the screen tilts toward the ground. Same value as
  /// Android's `SensorManager.getOrientation()[1]`, in degrees.
  final double pitch;

  /// Rotation about the screen's y axis in degrees, `(-180, 180]`. Positive
  /// when the right edge of the screen tilts toward the ground. Same value
  /// as Android's `SensorManager.getOrientation()[2]`, in degrees.
  final double roll;

  /// Row-major 3x3 rotation matrix from the (remapped) screen frame to the
  /// world frame whose rows are East, North (magnetic) and Up. Same layout
  /// as Android's `SensorManager.getRotationMatrix` followed by
  /// `remapCoordinateSystem`.
  final List<double> rotationMatrix;
}

// Axis codes as in android.hardware.SensorManager.
const _axisX = 1;
const _axisY = 2;
const _axisMinusX = _axisX | 0x80;
const _axisMinusY = _axisY | 0x80;

/// Tilt-compensated compass heading from raw accelerometer and magnetometer
/// readings in the Android device frame.
///
/// The accelerometer must be (close to) at rest so that it measures gravity
/// only; it reads `+9.8` on z when the device lies face up. The heading is
/// that of the top of the screen for the given [screenRotation], relative to
/// magnetic north.
///
/// Returns `null` when the direction is undefined: no gravity (free fall),
/// no magnetic field, the field parallel to gravity, or non-finite input.
///
/// This is the same computation as Android's
/// `SensorManager.getRotationMatrix`, `remapCoordinateSystem` and
/// `getOrientation`, written as a pure function so it can be tested and used
/// with any sensor plugin.
TiltHeading? tiltCompensatedHeading({
  required Vector3 accelerometer,
  required Vector3 magnetometer,
  ScreenRotation screenRotation = ScreenRotation.rotation0,
}) {
  var ax = accelerometer.x, ay = accelerometer.y, az = accelerometer.z;
  final ex = magnetometer.x, ey = magnetometer.y, ez = magnetometer.z;
  if (![ax, ay, az, ex, ey, ez].every((v) => v.isFinite)) return null;

  final normA = math.sqrt(ax * ax + ay * ay + az * az);
  final normE = math.sqrt(ex * ex + ey * ey + ez * ez);
  if (normA == 0 || normE == 0) return null;

  // H = E x A points east.
  var hx = ey * az - ez * ay;
  var hy = ez * ax - ex * az;
  var hz = ex * ay - ey * ax;
  final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
  // normH / (normE * normA) is the sine of the angle between field and
  // gravity. Below ~0.06 degrees the east direction is noise.
  if (normH < 1e-3 * normE * normA) return null;
  hx /= normH;
  hy /= normH;
  hz /= normH;
  ax /= normA;
  ay /= normA;
  az /= normA;
  // M = A x H points (magnetic) north.
  final mx = ay * hz - az * hy;
  final my = az * hx - ax * hz;
  final mz = ax * hy - ay * hx;

  final r = <double>[hx, hy, hz, mx, my, mz, ax, ay, az];
  final out = switch (screenRotation) {
    ScreenRotation.rotation0 => r,
    ScreenRotation.rotation90 => _remap(r, _axisY, _axisMinusX),
    ScreenRotation.rotation180 => _remap(r, _axisMinusX, _axisMinusY),
    ScreenRotation.rotation270 => _remap(r, _axisMinusY, _axisX),
  };

  // SensorManager.getOrientation.
  final azimuth = math.atan2(out[1], out[4]);
  final pitch = math.asin((-out[7]).clamp(-1.0, 1.0));
  final roll = math.atan2(-out[6], out[8]);

  return TiltHeading(
    heading: normalizeDegrees(radToDeg(azimuth)),
    pitch: radToDeg(pitch),
    roll: radToDeg(roll),
    rotationMatrix: List.unmodifiable(out),
  );
}

/// Port of `SensorManager.remapCoordinateSystem` for a 3x3 matrix.
List<double> _remap(List<double> inR, int xAxis, int yAxis) {
  var zAxis = xAxis ^ yAxis;
  final x = (xAxis & 0x3) - 1;
  final y = (yAxis & 0x3) - 1;
  final z = (zAxis & 0x3) - 1;
  // Keep the new frame right-handed.
  final axisY = (z + 1) % 3;
  final axisZ = (z + 2) % 3;
  if (((x ^ axisY) | (y ^ axisZ)) != 0) zAxis ^= 0x80;
  final sx = xAxis >= 0x80;
  final sy = yAxis >= 0x80;
  final sz = zAxis >= 0x80;
  final out = List<double>.filled(9, 0);
  for (var j = 0; j < 3; j++) {
    final o = j * 3;
    for (var i = 0; i < 3; i++) {
      if (x == i) out[o + i] = sx ? -inR[o] : inR[o];
      if (y == i) out[o + i] = sy ? -inR[o + 1] : inR[o + 1];
      if (z == i) out[o + i] = sz ? -inR[o + 2] : inR[o + 2];
    }
  }
  return out;
}
