import 'dart:io';

import 'package:qibla_math/qibla_math.dart';
import 'package:test/test.dart';

/// Rows of a whitespace-separated NOAA test-value file, comments skipped.
List<List<double>> _rows(String path) => File(path)
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
    .map((l) => l.trim().split(RegExp(r'\s+')).map(double.parse).toList())
    .toList();

// Tolerances. NOAA: "The computation was carried out with double precision
// arithmetic. Single precision arithmetic can cause differences of up to
// 0.1 nT." Angles are published to 0.01 degree.
const _nT = 0.1;
const _deg = 0.01;

void main() {
  const model = WorldMagneticModel.wmm2025;

  group('embedded coefficients', () {
    test('match the official WMM.COF byte for byte', () {
      // tool/data/WMM.COF is the unmodified file from NOAA's WMM2025COF.zip.
      final lines = File('tool/data/WMM.COF').readAsLinesSync();
      final header = lines.first.trim().split(RegExp(r'\s+'));
      expect(double.parse(header[0]), model.epoch);
      expect(header[1], model.name);
      var count = 0;
      for (final line in lines.skip(1)) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 6) break; // The 9999... trailer.
        final n = int.parse(f[0]);
        final m = int.parse(f[1]);
        final c = model.coefficient(n, m);
        expect(c.g, double.parse(f[2]), reason: 'g($n,$m)');
        expect(c.h, double.parse(f[3]), reason: 'h($n,$m)');
        expect(c.gDot, double.parse(f[4]), reason: 'gDot($n,$m)');
        expect(c.hDot, double.parse(f[5]), reason: 'hDot($n,$m)');
        count++;
      }
      expect(count, 90); // n = 1..12, m = 0..n.
      expect(model.maxDegree, 12);
    });

    test('validity period is 2025.0 to 2030.0', () {
      expect(model.validFrom, 2025.0);
      expect(model.validUntil, 2030.0);
    });
  });

  group('official WMM2025 test values (WMM2025_TestValues.txt, 100 points)',
      () {
    // From WMM2025COF.zip. Fields: year, height km, lat, lon, D, I, H, X,
    // Y, Z, F, dD/dt, dI/dt, dH/dt, dX/dt, dY/dt, dZ/dt, dF/dt.
    // Intensities and all rates are published here with 6 decimals, so on
    // top of NOAA's 0.1 nT tolerance they are also held to 0.01 nT and
    // 0.001 nT/yr (0.0001 deg/yr), which a double-precision implementation
    // meets. D and I are published to 0.01 degree.
    const tight = 0.01;
    const tightRate = 0.001;
    const tightAngleRate = 0.0001;
    final rows = _rows('test/data/WMM2025_TestValues.txt');

    test('file has 100 points', () => expect(rows, hasLength(100)));

    for (final r in rows) {
      test('${r[0]} h=${r[1]} lat=${r[2]} lon=${r[3]}', () {
        final f = model.calculate(
          latitude: r[2],
          longitude: r[3],
          heightKm: r[1],
          decimalYear: r[0],
        );
        expect(f.declination, closeTo(r[4], _deg), reason: 'D');
        expect(f.inclination, closeTo(r[5], _deg), reason: 'I');
        expect(f.horizontalIntensity, closeTo(r[6], tight), reason: 'H');
        expect(f.north, closeTo(r[7], tight), reason: 'X');
        expect(f.east, closeTo(r[8], tight), reason: 'Y');
        expect(f.down, closeTo(r[9], tight), reason: 'Z');
        expect(f.totalIntensity, closeTo(r[10], tight), reason: 'F');
        expect(f.declinationRate, closeTo(r[11], tightAngleRate),
            reason: 'dD/dt');
        expect(f.inclinationRate, closeTo(r[12], tightAngleRate),
            reason: 'dI/dt');
        expect(f.horizontalIntensityRate, closeTo(r[13], tightRate),
            reason: 'dH/dt');
        expect(f.northRate, closeTo(r[14], tightRate), reason: 'dX/dt');
        expect(f.eastRate, closeTo(r[15], tightRate), reason: 'dY/dt');
        expect(f.downRate, closeTo(r[16], tightRate), reason: 'dZ/dt');
        expect(f.totalIntensityRate, closeTo(r[17], tightRate),
            reason: 'dF/dt');
      });
    }
  });

  group('official WMM2025 test values (WMM2025_TEST_VALUES.txt, 12 points)',
      () {
    // From the NCEI WMM page, same numbers as WMM2025testvalues.pdf. Fields:
    // year, height km, lat, lon, X, Y, Z, H, F, I, D, GV, Xdot, Ydot, Zdot,
    // Hdot, Fdot, Idot, Ddot.
    final rows = _rows('test/data/WMM2025_TEST_VALUES.txt');

    test('file has 12 points', () => expect(rows, hasLength(12)));

    for (final r in rows) {
      test('${r[0]} h=${r[1]} lat=${r[2]} lon=${r[3]}', () {
        final f = model.calculate(
          latitude: r[2],
          longitude: r[3],
          heightKm: r[1],
          decimalYear: r[0],
        );
        expect(f.north, closeTo(r[4], _nT), reason: 'X');
        expect(f.east, closeTo(r[5], _nT), reason: 'Y');
        expect(f.down, closeTo(r[6], _nT), reason: 'Z');
        expect(f.horizontalIntensity, closeTo(r[7], _nT), reason: 'H');
        expect(f.totalIntensity, closeTo(r[8], _nT), reason: 'F');
        expect(f.inclination, closeTo(r[9], _deg), reason: 'I');
        expect(f.declination, closeTo(r[10], _deg), reason: 'D');
        if (r[11].isNaN) {
          expect(f.gridVariation, isNull, reason: 'GV');
        } else {
          expect(f.gridVariation, closeTo(r[11], _deg), reason: 'GV');
        }
        expect(f.northRate, closeTo(r[12], _nT), reason: 'Xdot');
        expect(f.eastRate, closeTo(r[13], _nT), reason: 'Ydot');
        expect(f.downRate, closeTo(r[14], _nT), reason: 'Zdot');
        expect(f.horizontalIntensityRate, closeTo(r[15], _nT), reason: 'Hdot');
        expect(f.totalIntensityRate, closeTo(r[16], _nT), reason: 'Fdot');
        expect(f.inclinationRate, closeTo(r[17], _deg), reason: 'Idot');
        expect(f.declinationRate, closeTo(r[18], _deg), reason: 'Ddot');
      });
    }
  });

  group('validity period', () {
    test('dates before 2025.0 or after 2030.0 throw by default', () {
      for (final y in [2024.999, 2030.001, 2019.0]) {
        expect(
          () => model.calculate(latitude: 0, longitude: 0, decimalYear: y),
          throwsA(isA<WmmDateOutOfRangeException>()
              .having((e) => e.decimalYear, 'decimalYear', y)),
        );
      }
    });

    test('the end points are valid', () {
      expect(
        model
            .calculate(latitude: 0, longitude: 0, decimalYear: 2025.0)
            .isOutsideValidityPeriod,
        isFalse,
      );
      expect(
        model
            .calculate(latitude: 0, longitude: 0, decimalYear: 2030.0)
            .isOutsideValidityPeriod,
        isFalse,
      );
    });

    test('allowOutsideValidityPeriod extrapolates and flags the result', () {
      final f = model.calculate(
        latitude: 36.75,
        longitude: 3.06,
        decimalYear: 2031,
        allowOutsideValidityPeriod: true,
      );
      expect(f.isOutsideValidityPeriod, isTrue);
      expect(f.declination.isFinite, isTrue);
    });
  });

  group('input handling', () {
    test('rejects latitudes outside [-90, 90] and non-finite input', () {
      expect(
        () => model.calculate(latitude: 90.5, longitude: 0, decimalYear: 2026),
        throwsArgumentError,
      );
      expect(
        () => model.calculate(
            latitude: 0, longitude: double.nan, decimalYear: 2026),
        throwsArgumentError,
      );
    });

    test('longitude may be given in [0, 360) or [-180, 180)', () {
      final a =
          model.calculate(latitude: -80, longitude: 240, decimalYear: 2025);
      final b =
          model.calculate(latitude: -80, longitude: -120, decimalYear: 2025);
      expect(a.declination, closeTo(b.declination, 1e-9));
      expect(a.totalIntensity, closeTo(b.totalIntensity, 1e-6));
    });

    test('geographic poles give finite values continuous with nearby points',
        () {
      for (final lat in [90.0, -90.0]) {
        final pole =
            model.calculate(latitude: lat, longitude: 0, decimalYear: 2026);
        final near = model.calculate(
            latitude: lat - lat.sign * 1e-6, longitude: 0, decimalYear: 2026);
        expect(pole.north, closeTo(near.north, 0.01));
        expect(pole.east, closeTo(near.east, 0.01));
        expect(pole.down, closeTo(near.down, 0.01));
      }
    });

    test('declination shortcut equals calculate().declination', () {
      final d = model.declination(
          latitude: 36.7538, longitude: 3.0588, decimalYear: 2026.5);
      final f = model.calculate(
          latitude: 36.7538, longitude: 3.0588, decimalYear: 2026.5);
      expect(d, f.declination);
    });
  });

  group('compass reliability (WMM blackout zones)', () {
    // WMM2025 report: blackout zone H < 2000 nT, caution zone
    // 2000 nT <= H < 6000 nT.
    test('classifies by horizontal intensity', () {
      final unreliable = model.calculate(
          latitude: 89, longitude: -121, heightKm: 28, decimalYear: 2025);
      expect(unreliable.horizontalIntensity, lessThan(2000));
      expect(unreliable.compassReliability, CompassReliability.unreliable);

      final caution = model.calculate(
          latitude: 82, longitude: 87, heightKm: 54, decimalYear: 2025);
      expect(caution.horizontalIntensity, inInclusiveRange(2000, 6000));
      expect(caution.compassReliability, CompassReliability.caution);

      final ok =
          model.calculate(latitude: 36.75, longitude: 3.06, decimalYear: 2026);
      expect(ok.compassReliability, CompassReliability.reliable);
    });
  });

  group('decimalYear', () {
    test('start of year and mid-year', () {
      expect(decimalYear(DateTime.utc(2025)), 2025.0);
      // 2025 has 365 days; noon on 2 July is 182.5 days in.
      expect(decimalYear(DateTime.utc(2025, 7, 2, 12)), closeTo(2025.5, 1e-12));
    });

    test('leap year', () {
      // 2028 has 366 days; 1 July 00:00 is 182 days in.
      expect(
          decimalYear(DateTime.utc(2028, 7)), closeTo(2028 + 182 / 366, 1e-12));
    });

    test('local times are converted to UTC', () {
      final local = DateTime(2026, 3, 15, 10);
      expect(decimalYear(local), decimalYear(local.toUtc()));
    });
  });

  group('true heading', () {
    test('trueHeadingFromMagnetic adds east declination', () {
      expect(trueHeadingFromMagnetic(100, 3.5), closeTo(103.5, 1e-12));
      expect(trueHeadingFromMagnetic(1, -3), closeTo(358, 1e-12));
      expect(trueHeadingFromMagnetic(359, 2), closeTo(1, 1e-9));
    });

    test('WorldMagneticModel.trueHeading uses the model declination', () {
      const lat = 51.5085, lon = -0.1257, year = 2026.0;
      final d =
          model.declination(latitude: lat, longitude: lon, decimalYear: year);
      final t = model.trueHeading(
        magneticHeading: 200,
        latitude: lat,
        longitude: lon,
        decimalYear: year,
      );
      expect(t, closeTo(normalizeDegrees(200 + d), 1e-12));
    });
  });
}
