# qibla_math

The maths behind qibla and compass features, in pure Dart with no dependencies:
great-circle qibla bearing, tilt-compensated heading from raw sensors, and
magnetic declination from the World Magnetic Model WMM2025. It works with any
sensor plugin, or none.

[![pub package](https://img.shields.io/pub/v/qibla_math.svg)](https://pub.dev/packages/qibla_math)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- **Qibla.** Initial great-circle bearing to the Kaaba from true north.
  Distance by haversine (sphere) or Vincenty (WGS-84 ellipsoid). Tested
  against published values for Algiers, Oran, Jakarta, London, New York,
  Auckland, Jeddah, Ta'if and Makkah.
- **Angles.** `normalizeDegrees` to `[0, 360)`, `signedAngleDifference` in
  `(-180, 180]`, a circular exponential moving average (`smoothAngle`,
  `CircularEma`) that crosses 359° to 0° the short way, and `circularMean`.
- **Compass labels.** 8, 16 and 32-point roses in English, French and Arabic.
- **Tilt-compensated heading.** A pure function that takes accelerometer and
  magnetometer readings in the Android device frame and returns heading,
  pitch, roll and the rotation matrix. Handles screen rotation (0°, 90°,
  180°, 270°). It does the same maths as Android's `getRotationMatrix`,
  `remapCoordinateSystem` and `getOrientation`.
- **Magnetic declination (WMM2025).** Full spherical-harmonic synthesis to
  degree 12. Gives X, Y, Z, H, F, declination, inclination, grid variation,
  all secular-variation rates, and the WMM "blackout zone" compass
  reliability. Coefficients come from the official NOAA `WMM.COF` through a
  generator script. Results match all 112 official NOAA test points. Dates
  outside 2025.0 to 2030.0 throw unless you opt in to extrapolation.
- **Qibla needle.** Needle angle relative to the device, the signed turn
  needed, and an `isFacingQibla` check with a tolerance.

## Install

```sh
dart pub add qibla_math
```

## Usage

```dart
import 'package:qibla_math/qibla_math.dart';

void main() {
  const lat = 36.7538, lon = 3.0588; // Algiers

  // Qibla bearing from true north, and distance.
  final qibla = qiblaBearing(lat, lon); // 105.41
  final km = qiblaDistanceKm(lat, lon); // 3926
  final kmWgs84 = qiblaDistanceKm(lat, lon, method: DistanceMethod.vincenty);

  // Magnetic declination from WMM2025.
  final field = WorldMagneticModel.wmm2025.calculate(
    latitude: lat,
    longitude: lon,
    decimalYear: decimalYear(DateTime.now()),
  );

  // Heading from raw sensor values (Android device frame).
  final reading = tiltCompensatedHeading(
    accelerometer: (x: 0.3, y: 1.2, z: 9.7),
    magnetometer: (x: -20.1, y: 5.4, z: -33.0),
    screenRotation: ScreenRotation.rotation0,
  );
  if (reading == null) return; // Free fall or unusable field.

  // Magnetic to true, then smooth.
  final ema = CircularEma(alpha: 0.2);
  final heading =
      ema.add(trueHeadingFromMagnetic(reading.heading, field.declination));

  // Where to draw the needle, and whether the user is facing the qibla.
  final needle = qiblaNeedleAngle(trueHeading: heading, qiblaBearing: qibla);
  final facing = isFacingQibla(
    trueHeading: heading,
    qiblaBearing: qibla,
    toleranceDegrees: 3,
  );

  print('$needle $facing $km $kmWgs84 ${compassLabel(qibla)}'); // ... ESE
  print(compassLabel(qibla, language: CompassLanguage.ar)); // شرق جنوب شرق
}
```

See `example/main.dart` for a runnable version.

### Conventions

- Bearings and headings are degrees clockwise from north, in `[0, 360)`.
  `qiblaBearing` is relative to **true** north. A magnetometer heading is
  relative to **magnetic** north, so add the declination
  (`trueHeadingFromMagnetic`) before you compare the two.
- Declination is positive east.
- Sensor vectors use the Android device frame: x to the right of the screen,
  y to its top, z out of the screen. At rest and face up, the accelerometer
  reads about `+9.8` on z. Units do not matter.
- Pitch is positive when the top edge tilts toward the ground. Roll is
  positive when the right edge tilts toward the ground. Both match
  Android's `SensorManager.getOrientation`.
- WMM heights are in km above the WGS-84 ellipsoid. Latitudes are geodetic.

## Limitations

- The qibla bearing uses the spherical great-circle convention, as most
  qibla calculators do. The geodesic azimuth on the WGS-84 ellipsoid differs
  by a few tenths of a degree (0.12° from London, 0.25° from Auckland). Use
  `vincentyInverse(...).initialBearing` if you want the ellipsoidal value. At the Kaaba itself the bearing is undefined and `0` is
  returned.
- Vincenty's method does not converge for points nearly antipodal to each
  other. For the Kaaba that means a small area of the South Pacific near
  21.4°S 140.2°W. It then throws `VincentyConvergenceException`, and you can
  fall back to haversine.
- Haversine distance is accurate to about 0.1 m close to the antipode,
  because the formula is ill-conditioned there.
- `tiltCompensatedHeading` assumes the accelerometer measures gravity only.
  During motion, use the gravity sensor, or low-pass filter the
  accelerometer first. It does not calibrate the magnetometer (hard or soft
  iron).
- The WMM gives the main field of the Earth's core. It does not include
  crustal anomalies, magnetic storms or local disturbances such as steel
  structures, cars or phone cases. The WMM2025 technical report gives the
  model's own uncertainty estimates.
- Grid variation is only computed where the WMM uses the polar
  stereographic grid (latitude 55° and beyond). Elsewhere it is `null`, as
  in the NOAA test file. The UTM grid variation at mid-latitudes is not
  implemented.
- The WMM2025 validity period is 2025.0 to 2030.0. `calculate` throws
  `WmmDateOutOfRangeException` outside that period unless you pass
  `allowOutsideValidityPeriod: true`, which extrapolates the linear secular
  variation and sets `isOutsideValidityPeriod`. Update the package when
  WMM2030 comes out.
- The English and French 32-point names are the standard mariner's names
  ("by" and "quart"). There is no single standard Arabic name for the 32-point
  "by" points. The Arabic 32-point labels copy the French pattern: the
  nearest 8-point name, then "ربع" (quarter), then the 8-point name it leans
  toward, for example `شمال ربع شمال شرق` for N by E. The Arabic 8- and 16-point
  names are standard full names. Arabic has no standard abbreviations, so
  full names are returned.

## Data sources

- **World Magnetic Model WMM2025.** NOAA National Centers for Environmental
  Information (NCEI) and the British Geological Survey. It is a US
  government work in the public domain.
  - Coefficients: `WMM.COF` (header `2025.0 WMM-2025 11/13/2024`) from
    [WMM2025COF.zip](https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip).
    The unmodified copy is in `tool/data/WMM.COF`.
    `dart run tool/generate_wmm_coefficients.dart` generates
    `lib/src/wmm/wmm2025_coefficients.dart` from it. A test checks that the
    embedded constants still match the file.
  - Test values: `WMM2025_TestValues.txt` (100 points, from the same zip) and
    [WMM2025_TEST_VALUES.txt](https://www.ncei.noaa.gov/sites/default/files/2025-02/WMM2025_TEST_VALUES.txt)
    (12 points, same values as
    [WMM2025testvalues.pdf](https://www.ncei.noaa.gov/sites/default/files/2025-02/WMM2025testvalues.pdf)).
    Both are in `test/data/`. The largest differences are 0.0007 nT on the
    100-point file, 0.05 nT on the 12-point file (which is rounded to 0.1 nT)
    and 0.005° on angles (rounded to 0.01°). NOAA's stated tolerance is
    0.1 nT.
  - Model page: <https://www.ncei.noaa.gov/products/world-magnetic-model>.
- **Kaaba coordinates** 21.4225°N, 39.826167°E (21°25′21″N 39°49′34.2″E),
  from [Wikidata Q29466](https://www.wikidata.org/wiki/Q29466), property
  P625 (CC0). They agree to about 2 m with the centroid of
  [OpenStreetMap way 103914569](https://www.openstreetmap.org/way/103914569).
- **Qibla reference values in the tests.**
  [al-habib.info Qibla Pointer](https://www.al-habib.info/qibla-pointer/)
  city pages (bearing to 0.1°, distance to 1 km), retrieved 2026-09-24.
  Also Khalid Shaukat, "Frequently asked questions on qibla direction"
  (1998), for Auckland and Wellington. Only these published numbers appear
  in the tests.
- **Geodesy references.** The Geoscience Australia Vincenty worked example
  (Flinders Peak to Buninyong, GRS80). GeographicLib 2.1 (C. F. F. Karney,
  *Algorithms for geodesics*, J. Geodesy 2013) was used to cross-check
  WGS-84 distances. WGS-84 constants are from NGA TR8350.2.

## License

MIT. See [LICENSE](LICENSE). The WMM coefficients and test values are in the
public domain.

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
