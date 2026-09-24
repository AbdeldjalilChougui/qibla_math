import 'dart:math' as math;

import '../angles.dart';
import 'wmm2025_coefficients.dart';

/// Geomagnetic reference radius of the WMM in km.
const double _referenceRadiusKm = 6371.2;

/// WGS-84 semi-major axis in km and first eccentricity squared.
const double _wgs84AKm = 6378.137;
const double _wgs84F = 1 / 298.257223563;
const double _wgs84E2 = _wgs84F * (2 - _wgs84F);

/// One Gauss coefficient set of degree n and order m.
class WmmCoefficient {
  /// Creates a coefficient set.
  const WmmCoefficient({
    required this.g,
    required this.h,
    required this.gDot,
    required this.hDot,
  });

  /// Main-field coefficient g (nT) at the model epoch.
  final double g;

  /// Main-field coefficient h (nT) at the model epoch.
  final double h;

  /// Secular variation of g (nT/year).
  final double gDot;

  /// Secular variation of h (nT/year).
  final double hDot;
}

/// Thrown by [WorldMagneticModel.calculate] for a date outside the model's
/// validity period, unless `allowOutsideValidityPeriod` is set.
class WmmDateOutOfRangeException implements Exception {
  /// Creates the exception.
  const WmmDateOutOfRangeException({
    required this.decimalYear,
    required this.validFrom,
    required this.validUntil,
  });

  /// The rejected date as a decimal year.
  final double decimalYear;

  /// Start of the validity period (decimal year).
  final double validFrom;

  /// End of the validity period (decimal year).
  final double validUntil;

  @override
  String toString() => 'WmmDateOutOfRangeException: $decimalYear is outside '
      'the model validity period $validFrom-$validUntil';
}

/// How far a magnetic compass can be trusted at a location, from the
/// horizontal field strength (WMM2025 report, "blackout zones").
enum CompassReliability {
  /// H >= 6000 nT.
  reliable,

  /// 2000 nT <= H < 6000 nT: the WMM "caution zone"; compasses may be
  /// sluggish or erratic.
  caution,

  /// H < 2000 nT: the WMM "blackout zone" near the magnetic poles; a
  /// magnetic compass is unreliable.
  unreliable,
}

/// Magnetic field elements at one place and time.
///
/// Angles are in degrees, intensities in nanotesla (nT), rates per year.
class GeomagneticField {
  /// Creates a result. Normally obtained from [WorldMagneticModel.calculate].
  const GeomagneticField({
    required this.north,
    required this.east,
    required this.down,
    required this.northRate,
    required this.eastRate,
    required this.downRate,
    required this.gridVariation,
    required this.isOutsideValidityPeriod,
  });

  /// X: northward component (nT).
  final double north;

  /// Y: eastward component (nT).
  final double east;

  /// Z: downward component (nT).
  final double down;

  /// dX/dt (nT/year).
  final double northRate;

  /// dY/dt (nT/year).
  final double eastRate;

  /// dZ/dt (nT/year).
  final double downRate;

  /// Grid variation GV (degrees) for polar navigation: declination measured
  /// from grid north of the Universal Polar Stereographic projection.
  /// Defined at latitudes of 55° and beyond; `null` elsewhere.
  final double? gridVariation;

  /// True when the date was outside the model's validity period and
  /// `allowOutsideValidityPeriod` was used. Such values are extrapolations.
  final bool isOutsideValidityPeriod;

  /// H: horizontal intensity (nT).
  double get horizontalIntensity => math.sqrt(north * north + east * east);

  /// F: total intensity (nT).
  double get totalIntensity =>
      math.sqrt(north * north + east * east + down * down);

  /// D: declination (degrees, positive east of true north) in
  /// `(-180, 180]`. Add it to a magnetic heading to get a true heading.
  double get declination => radToDeg(math.atan2(east, north));

  /// I: inclination or dip (degrees, positive downward) in `[-90, 90]`.
  double get inclination => radToDeg(math.atan2(down, horizontalIntensity));

  /// dH/dt (nT/year).
  double get horizontalIntensityRate =>
      (north * northRate + east * eastRate) / horizontalIntensity;

  /// dF/dt (nT/year).
  double get totalIntensityRate =>
      (north * northRate + east * eastRate + down * downRate) / totalIntensity;

  /// dD/dt (degrees/year).
  double get declinationRate {
    final h = horizontalIntensity;
    return radToDeg((north * eastRate - east * northRate) / (h * h));
  }

  /// dI/dt (degrees/year).
  double get inclinationRate {
    final f = totalIntensity;
    return radToDeg(
        (horizontalIntensity * downRate - down * horizontalIntensityRate) /
            (f * f));
  }

  /// Compass reliability from [horizontalIntensity].
  CompassReliability get compassReliability {
    final h = horizontalIntensity;
    if (h < 2000) return CompassReliability.unreliable;
    if (h < 6000) return CompassReliability.caution;
    return CompassReliability.reliable;
  }
}

/// A World Magnetic Model: spherical-harmonic main field plus linear
/// secular variation.
///
/// ```dart
/// final d = WorldMagneticModel.wmm2025.declination(
///   latitude: 36.75, longitude: 3.06, decimalYear: decimalYear(DateTime.now()),
/// );
/// ```
class WorldMagneticModel {
  const WorldMagneticModel._({
    required this.name,
    required this.releaseDate,
    required this.epoch,
    required this.validFrom,
    required this.validUntil,
    required this.maxDegree,
    required List<(int, int, double, double, double, double)> rows,
  }) : _rows = rows;

  /// WMM2025 from NOAA NCEI and the British Geological Survey. Valid from
  /// 2025.0 to 2030.0. Coefficients are embedded from the official WMM.COF.
  static const wmm2025 = WorldMagneticModel._(
    name: wmm2025Name,
    releaseDate: wmm2025ReleaseDate,
    epoch: wmm2025Epoch,
    validFrom: wmm2025Epoch,
    validUntil: wmm2025Epoch + 5,
    maxDegree: wmm2025MaxDegree,
    rows: wmm2025Coefficients,
  );

  /// Model name, for example `WMM-2025`.
  final String name;

  /// Release date as printed in the coefficient file header.
  final String releaseDate;

  /// Epoch of the coefficients (decimal year).
  final double epoch;

  /// First valid date (decimal year).
  final double validFrom;

  /// Last valid date (decimal year).
  final double validUntil;

  /// Maximum spherical-harmonic degree N.
  final int maxDegree;

  final List<(int, int, double, double, double, double)> _rows;

  /// Coefficients of degree [n] (1..[maxDegree]) and order [m] (0..n).
  WmmCoefficient coefficient(int n, int m) {
    RangeError.checkValueInInterval(n, 1, maxDegree, 'n');
    RangeError.checkValueInInterval(m, 0, n, 'm');
    final r = _rows[n * (n + 1) ~/ 2 - 1 + m];
    return WmmCoefficient(g: r.$3, h: r.$4, gDot: r.$5, hDot: r.$6);
  }

  /// Magnetic field at geodetic [latitude] and [longitude] (degrees, WGS-84),
  /// [heightKm] above the WGS-84 ellipsoid, at [decimalYear] (use the
  /// top-level `decimalYear` function to convert a `DateTime`).
  ///
  /// Throws [WmmDateOutOfRangeException] when the date is outside
  /// [validFrom]..[validUntil], unless [allowOutsideValidityPeriod] is true;
  /// the result is then an extrapolation flagged by
  /// [GeomagneticField.isOutsideValidityPeriod]. Throws [ArgumentError] for
  /// a latitude outside `[-90, 90]` or non-finite input.
  GeomagneticField calculate({
    required double latitude,
    required double longitude,
    double heightKm = 0,
    required double decimalYear,
    bool allowOutsideValidityPeriod = false,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'must be in [-90, 90]');
    }
    if (!longitude.isFinite) {
      throw ArgumentError.value(longitude, 'longitude', 'must be finite');
    }
    if (!heightKm.isFinite) {
      throw ArgumentError.value(heightKm, 'heightKm', 'must be finite');
    }
    if (!decimalYear.isFinite) {
      throw ArgumentError.value(decimalYear, 'decimalYear', 'must be finite');
    }
    final outside = decimalYear < validFrom || decimalYear > validUntil;
    if (outside && !allowOutsideValidityPeriod) {
      throw WmmDateOutOfRangeException(
        decimalYear: decimalYear,
        validFrom: validFrom,
        validUntil: validUntil,
      );
    }
    final dt = decimalYear - epoch;

    // Geodetic to geocentric spherical coordinates.
    final phi = degToRad(latitude);
    final sinPhi = math.sin(phi);
    final cosPhi = math.cos(phi);
    final rc = _wgs84AKm / math.sqrt(1 - _wgs84E2 * sinPhi * sinPhi);
    final p = (rc + heightKm) * cosPhi;
    final z = (rc * (1 - _wgs84E2) + heightKm) * sinPhi;
    final r = math.sqrt(p * p + z * z);
    final phiC = math.asin(z / r); // Geocentric latitude.
    final lambda = degToRad(longitude);

    final n = maxDegree;
    final ct = math.sin(phiC); // cos(colatitude)
    final st = math.cos(phiC); // sin(colatitude)
    final legendre = _SchmidtLegendre(n, ct, st);

    final cosM = List<double>.filled(n + 1, 0);
    final sinM = List<double>.filled(n + 1, 0);
    for (var m = 0; m <= n; m++) {
      cosM[m] = math.cos(m * lambda);
      sinM[m] = math.sin(m * lambda);
    }

    // Field in local geocentric north/east/down, for the main field at
    // decimalYear and for the secular variation.
    var bx = 0.0, by = 0.0, bz = 0.0;
    var sx = 0.0, sy = 0.0, sz = 0.0;
    final ratio = _referenceRadiusKm / r;
    var rn = ratio * ratio; // (a/r)^(n+2), starting at n = 0.
    final atPole = st.abs() < 1e-10;
    for (var deg = 1; deg <= n; deg++) {
      rn *= ratio;
      for (var m = 0; m <= deg; m++) {
        final row = _rows[deg * (deg + 1) ~/ 2 - 1 + m];
        final g = row.$3 + dt * row.$5;
        final h = row.$4 + dt * row.$6;
        final gd = row.$5;
        final hd = row.$6;
        final pnm = legendre.p(deg, m);
        final dpnm = legendre.dp(deg, m); // d/d(colatitude)

        final cosTerm = g * cosM[m] + h * sinM[m];
        final cosTermSv = gd * cosM[m] + hd * sinM[m];
        bx += rn * cosTerm * dpnm;
        sx += rn * cosTermSv * dpnm;
        bz -= (deg + 1) * rn * cosTerm * pnm;
        sz -= (deg + 1) * rn * cosTermSv * pnm;
        if (!atPole) {
          final sinTerm = g * sinM[m] - h * cosM[m];
          final sinTermSv = gd * sinM[m] - hd * cosM[m];
          by += rn * m * sinTerm * pnm / st;
          sy += rn * m * sinTermSv * pnm / st;
        }
      }
    }
    if (atPole) {
      // P(n, m) / sin(colatitude) is 0/0 at the poles; only m = 1 survives.
      final ps = legendre.p1OverSinAtPole();
      rn = ratio * ratio;
      for (var deg = 1; deg <= n; deg++) {
        rn *= ratio;
        final row = _rows[deg * (deg + 1) ~/ 2]; // m = 1
        final g = row.$3 + dt * row.$5;
        final h = row.$4 + dt * row.$6;
        by += rn * (g * sinM[1] - h * cosM[1]) * ps[deg];
        sy += rn * (row.$5 * sinM[1] - row.$6 * cosM[1]) * ps[deg];
      }
    }

    // Rotate from geocentric to geodetic north/down.
    final psi = phiC - phi;
    final cp = math.cos(psi);
    final sp = math.sin(psi);
    final x = bx * cp - bz * sp;
    final zz = bx * sp + bz * cp;
    final xd = sx * cp - sz * sp;
    final zd = sx * sp + sz * cp;

    final decl = radToDeg(math.atan2(by, x));
    double? gv;
    if (latitude >= 55) {
      gv = signedAngleDifference(decl - longitude, 0);
    } else if (latitude <= -55) {
      gv = signedAngleDifference(decl + longitude, 0);
    }

    return GeomagneticField(
      north: x,
      east: by,
      down: zz,
      northRate: xd,
      eastRate: sy,
      downRate: zd,
      gridVariation: gv,
      isOutsideValidityPeriod: outside,
    );
  }

  /// Magnetic declination in degrees (positive east) at a place and time.
  /// Same arguments and exceptions as [calculate].
  double declination({
    required double latitude,
    required double longitude,
    double heightKm = 0,
    required double decimalYear,
    bool allowOutsideValidityPeriod = false,
  }) =>
      calculate(
        latitude: latitude,
        longitude: longitude,
        heightKm: heightKm,
        decimalYear: decimalYear,
        allowOutsideValidityPeriod: allowOutsideValidityPeriod,
      ).declination;

  /// True heading from a magnetic compass heading:
  /// `magneticHeading + declination`, in `[0, 360)`.
  double trueHeading({
    required double magneticHeading,
    required double latitude,
    required double longitude,
    double heightKm = 0,
    required double decimalYear,
    bool allowOutsideValidityPeriod = false,
  }) =>
      normalizeDegrees(magneticHeading +
          declination(
            latitude: latitude,
            longitude: longitude,
            heightKm: heightKm,
            decimalYear: decimalYear,
            allowOutsideValidityPeriod: allowOutsideValidityPeriod,
          ));
}

/// Schmidt semi-normalised associated Legendre functions P(n, m) of
/// cos(colatitude) and their derivatives with respect to colatitude.
class _SchmidtLegendre {
  _SchmidtLegendre(this.maxDegree, this.ct, this.st) {
    final size = (maxDegree + 1) * (maxDegree + 2) ~/ 2;
    _p = List<double>.filled(size, 0);
    _dp = List<double>.filled(size, 0);
    // Gauss-normalised recursion, then Schmidt scaling.
    _p[0] = 1;
    for (var n = 1; n <= maxDegree; n++) {
      for (var m = 0; m <= n; m++) {
        final i = _i(n, m);
        if (n == m) {
          final j = _i(n - 1, m - 1);
          _p[i] = st * _p[j];
          _dp[i] = st * _dp[j] + ct * _p[j];
        } else {
          final j = _i(n - 1, m);
          final k = _k(n, m);
          final p2 = m <= n - 2 ? _p[_i(n - 2, m)] : 0.0;
          final dp2 = m <= n - 2 ? _dp[_i(n - 2, m)] : 0.0;
          _p[i] = ct * _p[j] - k * p2;
          _dp[i] = ct * _dp[j] - st * _p[j] - k * dp2;
        }
      }
    }
    for (var n = 1; n <= maxDegree; n++) {
      for (var m = 0; m <= n; m++) {
        final s = _schmidt(n, m);
        _p[_i(n, m)] *= s;
        _dp[_i(n, m)] *= s;
      }
    }
  }

  final int maxDegree;
  final double ct;
  final double st;
  late final List<double> _p;
  late final List<double> _dp;

  static int _i(int n, int m) => n * (n + 1) ~/ 2 + m;

  static double _k(int n, int m) =>
      ((n - 1) * (n - 1) - m * m) / ((2 * n - 1) * (2 * n - 3));

  /// Factor from Gauss to Schmidt semi-normalisation.
  static double _schmidt(int n, int m) {
    var s = 1.0;
    for (var j = 1; j <= n; j++) {
      s *= (2 * j - 1) / j;
    }
    for (var j = 1; j <= m; j++) {
      s *= math.sqrt((n - j + 1) * (j == 1 ? 2 : 1) / (n + j));
    }
    return s;
  }

  double p(int n, int m) => _p[_i(n, m)];
  double dp(int n, int m) => _dp[_i(n, m)];

  /// Schmidt P(n, 1) / sin(colatitude) evaluated at a pole, n = 0..N.
  List<double> p1OverSinAtPole() {
    final ps = List<double>.filled(maxDegree + 1, 0);
    ps[0] = 1;
    for (var n = 1; n <= maxDegree; n++) {
      ps[n] = n == 1 ? ps[0] : ct * ps[n - 1] - _k(n, 1) * ps[n - 2];
    }
    return [
      for (var n = 0; n <= maxDegree; n++) n == 0 ? 0 : ps[n] * _schmidt(n, 1)
    ];
  }
}

/// Converts a date to the decimal year used by the World Magnetic Model:
/// the year plus the elapsed fraction of that (UTC) year.
double decimalYear(DateTime date) {
  final d = date.toUtc();
  final start = DateTime.utc(d.year);
  final end = DateTime.utc(d.year + 1);
  return d.year +
      d.difference(start).inMicroseconds / end.difference(start).inMicroseconds;
}
