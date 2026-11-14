import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasa_space_apps_2026/data/models/fire_record.dart';
import 'package:nasa_space_apps_2026/domain/anomaly.dart';

FireRecord loadRecord(String id) => FireRecord.fromJson(
      jsonDecode(File('assets/mock/record_$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  const regions = ['lebanon', 'portugal', 'greece', 'cyprus'];

  group('mock data follows the contract', () {
    for (final id in regions) {
      test(id, () {
        final r = loadRecord(id);
        expect(r.season, hasLength(12));
        // No gaps from first year to latest month.
        final expected = (r.latestYear - r.firstYear) * 12 + r.latestMonth;
        expect(r.monthly, hasLength(expected));
        for (final c in r.monthly) {
          if (c.sensor == Sensor.viirs) expect(c.raw, c.harmonized);
          expect(c.year >= 2012, c.sensor == Sensor.viirs);
        }
      });
    }
  });

  test('raw record jumps at 2012, harmonized record does not', () {
    final r = loadRecord('lebanon');
    final raw = yearlyTotals(r, harmonized: false);
    final fixed = yearlyTotals(r, harmonized: true);
    double mean(Map<int, int> t, int a, int b) =>
        [for (var y = a; y <= b; y++) t[y]!].reduce((x, y) => x + y) / (b - a + 1);
    final rawJump = mean(raw, 2012, 2016) / mean(raw, 2007, 2011);
    final fixedJump = mean(fixed, 2012, 2016) / mean(fixed, 2007, 2011);
    expect(rawJump, greaterThan(2.0));
    expect(fixedJump, lessThan(rawJump / 2));
  });

  test('summary flags the October 2019 Lebanon fires as extreme', () {
    final s = summarize(loadRecord('lebanon'), year: 2019, month: 10);
    expect(s.status, FireStatus.extreme);
    expect(s.rank, 1);
    expect(s.sentence('Lebanon'), contains('October 2019 in Lebanon'));
  });

  test('critical months for Lebanon fall in late summer / autumn', () {
    final months = criticalMonths(loadRecord('lebanon'));
    expect(months, contains(9));
    expect(months, isNot(contains(1)));
  });

  test('ordinal wording', () {
    final s = summarize(loadRecord('portugal'));
    expect(s.sentence('Portugal'), matches(RegExp(r'(The|\d+(st|nd|rd|th)) highest')));
  });
}
