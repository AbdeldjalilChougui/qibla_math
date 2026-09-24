import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

void main() {
  group('compassLabel english', () {
    test('8 points', () {
      const expected = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
      for (var i = 0; i < 8; i++) {
        expect(
          compassLabel(i * 45.0, precision: CompassPrecision.points8),
          expected[i],
        );
      }
    });

    test('16 points is the default', () {
      expect(compassLabel(0), 'N');
      expect(compassLabel(22.5), 'NNE');
      expect(compassLabel(90), 'E');
      expect(compassLabel(247.5), 'WSW');
      expect(compassLabel(342), 'NNW');
    });

    test('32 points uses "by" names', () {
      expect(compassLabel(11.25, precision: CompassPrecision.points32), 'NbE');
      expect(compassLabel(33.75, precision: CompassPrecision.points32), 'NEbN');
      expect(compassLabel(78.75, precision: CompassPrecision.points32), 'EbN');
      expect(compassLabel(348.75, precision: CompassPrecision.points32), 'NbW');
    });

    test('sector boundaries round half up, and wrap to N', () {
      // 8 points: sectors are 45 wide centred on each point.
      expect(compassLabel(22.49, precision: CompassPrecision.points8), 'N');
      expect(compassLabel(22.5, precision: CompassPrecision.points8), 'NE');
      expect(compassLabel(337.5, precision: CompassPrecision.points8), 'N');
      expect(compassLabel(359.99, precision: CompassPrecision.points8), 'N');
      expect(compassLabel(-45, precision: CompassPrecision.points8), 'NW');
      expect(compassLabel(720, precision: CompassPrecision.points8), 'N');
    });
  });

  group('compassLabel french', () {
    test('uses O for ouest', () {
      expect(
        compassLabel(270,
            precision: CompassPrecision.points8, language: CompassLanguage.fr),
        'O',
      );
      expect(compassLabel(225, language: CompassLanguage.fr), 'SO');
      expect(compassLabel(292.5, language: CompassLanguage.fr), 'ONO');
    });

    test('32 points uses "quart" (q)', () {
      expect(
        compassLabel(11.25,
            precision: CompassPrecision.points32, language: CompassLanguage.fr),
        'NqNE',
      );
      expect(
        compassLabel(258.75,
            precision: CompassPrecision.points32, language: CompassLanguage.fr),
        'OqSO',
      );
    });
  });

  group('compassLabel arabic', () {
    test('8 and 16 points use full names', () {
      expect(
        compassLabel(0,
            precision: CompassPrecision.points8, language: CompassLanguage.ar),
        'شمال',
      );
      expect(
        compassLabel(135,
            precision: CompassPrecision.points8, language: CompassLanguage.ar),
        'جنوب شرق',
      );
      expect(compassLabel(292.5, language: CompassLanguage.ar), 'غرب شمال غرب');
    });

    test('32 points exist for every sector', () {
      final seen = <String>{};
      for (var i = 0; i < 32; i++) {
        seen.add(compassLabel(i * 11.25,
            precision: CompassPrecision.points32,
            language: CompassLanguage.ar));
      }
      expect(seen, hasLength(32));
    });
  });

  test('every table has the right number of distinct labels', () {
    for (final lang in CompassLanguage.values) {
      for (final p in CompassPrecision.values) {
        final labels = compassLabels(precision: p, language: lang);
        expect(labels, hasLength(p.count));
        expect(labels.toSet(), hasLength(p.count));
      }
    }
  });

  test('coarser tables are subsets at matching indices', () {
    for (final lang in CompassLanguage.values) {
      final l8 =
          compassLabels(precision: CompassPrecision.points8, language: lang);
      final l16 = compassLabels(language: lang);
      final l32 =
          compassLabels(precision: CompassPrecision.points32, language: lang);
      for (var i = 0; i < 8; i++) {
        expect(l16[i * 2], l8[i]);
        expect(l32[i * 4], l8[i]);
      }
      for (var i = 0; i < 16; i++) {
        expect(l32[i * 2], l16[i]);
      }
    }
  });
}
