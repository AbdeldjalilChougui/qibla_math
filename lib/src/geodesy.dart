import 'dart:math' as math;

import 'angles.dart';

/// Mean Earth radius in km, `R1 = (2a + b) / 3` for WGS-84 (IUGG, Moritz 1980).
const double meanEarthRadiusKm = 6371.0088;

/// A reference ellipsoid given by its semi-major axis and flattening.
class Ellipsoid {
  /// Creates an ellipsoid with semi-major axis [a] (metres) and flattening [f].
  const Ellipsoid({required this.a, required this.f});

  /// WGS-84: a = 6 378 137 m, 1/f = 298.257223563 (NGA TR8350.2).
  static const wgs84 = Ellipsoid(a: 6378137.0, f: 1 / 298.257223563);

  /// GRS80: a = 6 378 137 m, 1/f = 298.257222101 (Moritz 1980).
  static const grs80 = Ellipsoid(a: 6378137.0, f: 1 / 298.257222101);

  /// Semi-major (equatorial) axis in metres.
  final double a;

  /// Flattening `(a - b) / a`.
  final double f;

  /// Semi-minor (polar) axis in metres.
  double get b => a * (1 - f);

  /// First eccentricity squared, `f (2 - f)`.
  double get e2 => f * (2 - f);
}

/// Initial great-circle bearing on a sphere from point 1 to point 2, in
/// degrees clockwise from true north, in `[0, 360)`.
///
/// Returns `0` when the two points coincide (the bearing is undefined).
double initialBearing(double lat1, double lon1, double lat2, double lon2) {
  final p1 = degToRad(lat1);
  final p2 = degToRad(lat2);
  final dl = degToRad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return normalizeDegrees(radToDeg(math.atan2(y, x)));
}

/// Great-circle distance in km between two points on a sphere of radius
/// [radiusKm], using the haversine formula.
double haversineDistanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2, {
  double radiusKm = meanEarthRadiusKm,
}) {
  final p1 = degToRad(lat1);
  final p2 = degToRad(lat2);
  final dp = p2 - p1;
  final dl = degToRad(lon2 - lon1);
  final s1 = math.sin(dp / 2);
  final s2 = math.sin(dl / 2);
  final h = s1 * s1 + math.cos(p1) * math.cos(p2) * s2 * s2;
  // atan2 stays well conditioned near the antipode, where asin does not.
  final hc = h.clamp(0.0, 1.0);
  return 2 * radiusKm * math.atan2(math.sqrt(hc), math.sqrt(1 - hc));
}

/// Result of [vincentyInverse].
class VincentyResult {
  /// Creates a result.
  const VincentyResult({
    required this.distanceMeters,
    required this.initialBearing,
    required this.finalBearing,
    required this.iterations,
  });

  /// Geodesic distance on the ellipsoid in metres.
  final double distanceMeters;

  /// Forward azimuth at point 1, degrees from true north in `[0, 360)`.
  final double initialBearing;

  /// Forward azimuth at point 2 (direction of travel on arrival), degrees in
  /// `[0, 360)`. Add 180 to get the reverse azimuth.
  final double finalBearing;

  /// Number of iterations used.
  final int iterations;

  /// Geodesic distance in kilometres.
  double get distanceKm => distanceMeters / 1000.0;
}

/// Thrown when [vincentyInverse] does not converge, which happens for nearly
/// antipodal points.
class VincentyConvergenceException implements Exception {
  /// Creates the exception.
  const VincentyConvergenceException(this.message);

  /// Description of the failure.
  final String message;

  @override
  String toString() => 'VincentyConvergenceException: $message';
}

/// Vincenty's inverse formula (1975): geodesic distance and azimuths between
/// two points on an ellipsoid (WGS-84 by default).
///
/// Accurate to well under a millimetre for ordinary distances. For nearly
/// antipodal points the iteration may not converge; a
/// [VincentyConvergenceException] is thrown and callers can fall back to
/// [haversineDistanceKm].
VincentyResult vincentyInverse(
  double lat1,
  double lon1,
  double lat2,
  double lon2, {
  Ellipsoid ellipsoid = Ellipsoid.wgs84,
  int maxIterations = 200,
  double tolerance = 1e-12,
}) {
  final a = ellipsoid.a;
  final f = ellipsoid.f;
  final b = ellipsoid.b;

  final l = degToRad(lon2 - lon1);
  final u1 = math.atan((1 - f) * math.tan(degToRad(lat1)));
  final u2 = math.atan((1 - f) * math.tan(degToRad(lat2)));
  final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
  final sinU2 = math.sin(u2), cosU2 = math.cos(u2);

  var lambda = l;
  double sinSigma = 0, cosSigma = 0, sigma = 0;
  double cosSqAlpha = 0, cos2SigmaM = 0;
  double sinLambda = 0, cosLambda = 0;
  var iterations = 0;
  var converged = false;

  while (iterations < maxIterations) {
    iterations++;
    sinLambda = math.sin(lambda);
    cosLambda = math.cos(lambda);
    final t1 = cosU2 * sinLambda;
    final t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
    sinSigma = math.sqrt(t1 * t1 + t2 * t2);
    if (sinSigma == 0) {
      // Coincident points.
      return VincentyResult(
        distanceMeters: 0,
        initialBearing: 0,
        finalBearing: 0,
        iterations: iterations,
      );
    }
    cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
    sigma = math.atan2(sinSigma, cosSigma);
    final sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    // On the equator cosSqAlpha is 0 and cos2SigmaM is undefined; use 0.
    cos2SigmaM =
        cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha;
    final c = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha));
    final prev = lambda;
    lambda = l +
        (1 - c) *
            f *
            sinAlpha *
            (sigma +
                c *
                    sinSigma *
                    (cos2SigmaM +
                        c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
    if (lambda.abs() > math.pi) break; // Diverging: antipodal case.
    if ((lambda - prev).abs() < tolerance) {
      converged = true;
      break;
    }
  }
  if (!converged) {
    throw VincentyConvergenceException(
      'no convergence after $iterations iterations '
      '(points are nearly antipodal)',
    );
  }

  final uSq = cosSqAlpha * (a * a - b * b) / (b * b);
  final bigA =
      1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
  final bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
  final c2 = cos2SigmaM * cos2SigmaM;
  final deltaSigma = bigB *
      sinSigma *
      (cos2SigmaM +
          bigB /
              4 *
              (cosSigma * (-1 + 2 * c2) -
                  bigB /
                      6 *
                      cos2SigmaM *
                      (-3 + 4 * sinSigma * sinSigma) *
                      (-3 + 4 * c2)));
  final s = b * bigA * (sigma - deltaSigma);

  final alpha1 =
      math.atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda);
  final alpha2 =
      math.atan2(cosU1 * sinLambda, -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda);

  return VincentyResult(
    distanceMeters: s,
    initialBearing: normalizeDegrees(radToDeg(alpha1)),
    finalBearing: normalizeDegrees(radToDeg(alpha2)),
    iterations: iterations,
  );
}
