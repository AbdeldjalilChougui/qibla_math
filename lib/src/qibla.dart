import 'angles.dart';
import 'geodesy.dart';

/// Latitude of the Kaaba in degrees: 21°25′21″N.
///
/// Source: Wikidata item Q29466, property P625 (CC0), cross-checked against
/// the centroid of OpenStreetMap way 103914569 (about 2 m away).
const double kaabaLatitude = 21.4225;

/// Longitude of the Kaaba in degrees: 39°49′34.2″E. Same source as
/// [kaabaLatitude].
const double kaabaLongitude = 39.826166666666667;

/// Distance formula used by [qiblaDistanceKm].
enum DistanceMethod {
  /// Great circle on a sphere of radius [meanEarthRadiusKm] (haversine).
  /// Error up to about 0.5 % against the ellipsoid.
  haversine,

  /// Geodesic on the WGS-84 ellipsoid (Vincenty 1975). Sub-millimetre, but
  /// throws [VincentyConvergenceException] near the Kaaba's antipode in the
  /// South Pacific.
  vincenty,
}

/// Qibla direction from a location: the initial great-circle bearing toward
/// the Kaaba in degrees clockwise from **true** north, in `[0, 360)`.
///
/// This is the spherical great-circle convention used by most qibla
/// calculators. At the Kaaba itself the direction is undefined and `0` is
/// returned.
double qiblaBearing(double latitude, double longitude) =>
    initialBearing(latitude, longitude, kaabaLatitude, kaabaLongitude);

/// Distance from a location to the Kaaba in kilometres.
double qiblaDistanceKm(
  double latitude,
  double longitude, {
  DistanceMethod method = DistanceMethod.haversine,
}) =>
    switch (method) {
      DistanceMethod.haversine =>
        haversineDistanceKm(latitude, longitude, kaabaLatitude, kaabaLongitude),
      DistanceMethod.vincenty =>
        vincentyInverse(latitude, longitude, kaabaLatitude, kaabaLongitude)
            .distanceKm,
    };

/// Angle to draw a qibla needle at, relative to the top of the device, in
/// `[0, 360)` clockwise.
///
/// [trueHeading] is where the device points (degrees from true north; use
/// [trueHeadingFromMagnetic] to correct a magnetic heading) and
/// [qiblaBearing] comes from the top-level `qiblaBearing` function.
double qiblaNeedleAngle({
  required double trueHeading,
  required double qiblaBearing,
}) =>
    normalizeDegrees(qiblaBearing - trueHeading);

/// Signed turn from the current heading to the qibla, in `(-180, 180]`.
/// Positive means turn clockwise (to the right).
double qiblaOffset({
  required double trueHeading,
  required double qiblaBearing,
}) =>
    signedAngleDifference(qiblaBearing, trueHeading);

/// Whether the device faces the qibla within [toleranceDegrees] either side
/// (inclusive).
bool isFacingQibla({
  required double trueHeading,
  required double qiblaBearing,
  double toleranceDegrees = 5,
}) {
  if (toleranceDegrees < 0) {
    throw ArgumentError.value(
        toleranceDegrees, 'toleranceDegrees', 'must not be negative');
  }
  return qiblaOffset(trueHeading: trueHeading, qiblaBearing: qiblaBearing)
          .abs() <=
      toleranceDegrees;
}

/// Converts a magnetic heading to a true heading:
/// `trueHeading = magneticHeading + declination`, normalised to `[0, 360)`.
///
/// [declination] is positive east, as returned by
/// `WorldMagneticModel.declination`.
double trueHeadingFromMagnetic(double magneticHeading, double declination) =>
    normalizeDegrees(magneticHeading + declination);
