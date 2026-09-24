import 'package:qibla_math/qibla_math.dart';

void main() {
  // Algiers.
  const lat = 36.7538;
  const lon = 3.0588;

  // 1. Qibla direction and distance.
  final qibla = qiblaBearing(lat, lon);
  final km = qiblaDistanceKm(lat, lon);
  final kmEllipsoid =
      qiblaDistanceKm(lat, lon, method: DistanceMethod.vincenty);
  print('Qibla: ${qibla.toStringAsFixed(2)}° from true north '
      '(${compassLabel(qibla)}), ${km.toStringAsFixed(0)} km '
      '(${kmEllipsoid.toStringAsFixed(1)} km on WGS-84)');

  // 2. Magnetic declination from WMM2025.
  final year = decimalYear(DateTime.utc(2026, 9, 24));
  final field = WorldMagneticModel.wmm2025.calculate(
    latitude: lat,
    longitude: lon,
    decimalYear: year,
  );
  print('Declination ${field.declination.toStringAsFixed(2)}°, '
      'inclination ${field.inclination.toStringAsFixed(2)}°, '
      'F = ${field.totalIntensity.toStringAsFixed(0)} nT, '
      'compass ${field.compassReliability.name}');

  // 3. Heading from raw sensors (device lying flat, top edge toward
  //    magnetic east), then corrected to true north.
  final reading = tiltCompensatedHeading(
    accelerometer: (x: 0.0, y: 0.0, z: 9.81),
    magnetometer: (x: -28.0, y: 0.0, z: -32.0),
  );
  if (reading == null) return;
  final heading = trueHeadingFromMagnetic(reading.heading, field.declination);
  print('Magnetic heading ${reading.heading.toStringAsFixed(1)}°, '
      'true heading ${heading.toStringAsFixed(1)}°');

  // 4. Smooth a noisy stream and point the needle.
  final ema = CircularEma(alpha: 0.2);
  for (final h in [heading - 2, heading + 1, heading - 1, heading]) {
    ema.add(h);
  }
  final needle = qiblaNeedleAngle(trueHeading: ema.value!, qiblaBearing: qibla);
  final facing = isFacingQibla(trueHeading: ema.value!, qiblaBearing: qibla);
  print('Rotate the needle ${needle.toStringAsFixed(1)}° clockwise; '
      'facing qibla: $facing');
  print('In French: ${compassLabel(qibla, language: CompassLanguage.fr)}, '
      'in Arabic: ${compassLabel(qibla, language: CompassLanguage.ar)}');
}
