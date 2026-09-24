import 'angles.dart';

/// How finely [compassLabel] divides the circle.
enum CompassPrecision {
  /// Cardinal and intercardinal points (45° sectors).
  points8(8),

  /// Adds the secondary intercardinals such as NNE (22.5° sectors).
  points16(16),

  /// The mariner's 32-point rose with "by" points such as NbE (11.25° sectors).
  points32(32);

  const CompassPrecision(this.count);

  /// Number of points on the rose.
  final int count;
}

/// Language of the labels produced by [compassLabel].
enum CompassLanguage {
  /// English abbreviations (N, NNE, NbE, ...).
  en,

  /// French abbreviations (N, NNE, NqNE, ... with O for ouest).
  fr,

  /// Arabic full names (شمال، شمال شرق، ...). Arabic has no standard
  /// abbreviations, so full words are returned.
  ar,
}

const _en32 = [
  'N', 'NbE', 'NNE', 'NEbN', 'NE', 'NEbE', 'ENE', 'EbN', //
  'E', 'EbS', 'ESE', 'SEbE', 'SE', 'SEbS', 'SSE', 'SbE', //
  'S', 'SbW', 'SSW', 'SWbS', 'SW', 'SWbW', 'WSW', 'WbS', //
  'W', 'WbN', 'WNW', 'NWbW', 'NW', 'NWbN', 'NNW', 'NbW', //
];

const _fr32 = [
  'N', 'NqNE', 'NNE', 'NEqN', 'NE', 'NEqE', 'ENE', 'EqNE', //
  'E', 'EqSE', 'ESE', 'SEqE', 'SE', 'SEqS', 'SSE', 'SqSE', //
  'S', 'SqSO', 'SSO', 'SOqS', 'SO', 'SOqO', 'OSO', 'OqSO', //
  'O', 'OqNO', 'ONO', 'NOqO', 'NO', 'NOqN', 'NNO', 'NqNO', //
];

const _ar8 = [
  'شمال', 'شمال شرق', 'شرق', 'جنوب شرق', //
  'جنوب', 'جنوب غرب', 'غرب', 'شمال غرب', //
];

const _ar16 = [
  'شمال', 'شمال شمال شرق', 'شمال شرق', 'شرق شمال شرق', //
  'شرق', 'شرق جنوب شرق', 'جنوب شرق', 'جنوب جنوب شرق', //
  'جنوب', 'جنوب جنوب غرب', 'جنوب غرب', 'غرب جنوب غرب', //
  'غرب', 'غرب شمال غرب', 'شمال غرب', 'شمال شمال غرب', //
];

/// Arabic 32-point rose. Even indices are the 16-point names. The odd
/// ("by") points follow the French "quart" construction: the nearest
/// 8-point name, then "ربع" (quarter), then the neighbouring 8-point name
/// it leans toward. There is no single standard Arabic nomenclature for
/// these points; see the README.
final List<String> _ar32 = List.unmodifiable([
  for (var i = 0; i < 32; i++)
    if (i.isEven) _ar16[i ~/ 2] else _byPoint(i, _ar8, ' ربع '),
]);

String _byPoint(int i, List<String> eight, String joiner) {
  // i is odd: it sits one step (11.25°) from an 8-point name at a multiple
  // of 4, and three steps from the other neighbour.
  final lower = i ~/ 4; // 8-point index just counter-clockwise.
  final nearestIsLower = i % 4 == 1;
  final base = nearestIsLower ? lower : (lower + 1) % 8;
  final toward = nearestIsLower ? (lower + 1) % 8 : lower;
  return '${eight[base]}$joiner${eight[toward]}';
}

List<String> _table32(CompassLanguage language) => switch (language) {
      CompassLanguage.en => _en32,
      CompassLanguage.fr => _fr32,
      CompassLanguage.ar => _ar32,
    };

/// All labels of a rose, starting at north and going clockwise.
List<String> compassLabels({
  CompassPrecision precision = CompassPrecision.points16,
  CompassLanguage language = CompassLanguage.en,
}) {
  final all = _table32(language);
  final step = 32 ~/ precision.count;
  return List.unmodifiable([for (var i = 0; i < 32; i += step) all[i]]);
}

/// The compass point label nearest to [headingDegrees].
///
/// Each point owns a sector centred on it; a heading exactly on a sector
/// boundary goes to the clockwise point. Any angle is accepted and
/// normalised first.
///
/// ```dart
/// compassLabel(342); // 'NNW'
/// compassLabel(270, language: CompassLanguage.fr); // 'O'
/// ```
String compassLabel(
  double headingDegrees, {
  CompassPrecision precision = CompassPrecision.points16,
  CompassLanguage language = CompassLanguage.en,
}) {
  final n = precision.count;
  final sector = 360.0 / n;
  final index = ((normalizeDegrees(headingDegrees) / sector) + 0.5).floor() % n;
  return _table32(language)[index * (32 ~/ n)];
}
