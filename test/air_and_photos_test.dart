import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasa_space_apps_2026/data/models/air.dart';
import 'package:nasa_space_apps_2026/services/report_api.dart';

void main() {
  group('AirQuality.fromJson', () {
    test('reads a real /air answer', () {
      final j = jsonDecode(File('test/fixtures/air_point.json').readAsStringSync()) as Map<String, dynamic>;
      final a = AirQuality.fromJson(j);
      expect(a.aqi, greaterThanOrEqualTo(0));
      expect(a.label, isNotEmpty);
      expect(a.headline, isNotEmpty);
      expect(a.advice, isNotEmpty);
      expect(a.pollutants.map((p) => p.key), contains('pm2_5'));
      expect(a.hours, isNotEmpty);
      expect(a.smokeTips, isNotEmpty);
      expect(a.co2Ppm, isNotNull);
    });

    test('maps every level, including the hyphenated one', () {
      expect(AirLevel.fromApi('very-unhealthy'), AirLevel.veryUnhealthy);
      expect(AirLevel.fromApi('hazardous'), AirLevel.hazardous);
      expect(AirLevel.fromApi('sensitive'), AirLevel.sensitive);
    });

    test('flags air getting worse in the next 24 h', () {
      final a = AirQuality.fromJson({
        'usAqi': 40,
        'level': 'good',
        'next24h': {'peakAqi': 160, 'peakAt': '2026-11-15T18:00', 'peakLevel': 'unhealthy', 'hours': []},
      });
      expect(a.worsening, isTrue);
      expect(a.peakAt!.hour, 18);
    });

    test('survives a minimal answer', () {
      final a = AirQuality.fromJson({'usAqi': 12, 'level': 'good', 'safe': true});
      expect(a.pollutants, isEmpty);
      expect(a.worsening, isFalse);
    });
  });

  group('shared report photos', () {
    final base = {
      'id': 'abc-1',
      'lat': 33.9,
      'lon': 35.5,
      'createdAt': '2026-11-15T14:34:45.152Z',
      'label': 'wildfire',
      'note': '',
    };

    test('a report with a photo points at the server', () {
      final r = ReportApi.fromApi({...base, 'hasPhoto': true}, baseUrl: 'https://x/api/v1');
      expect(r.photoUrl, 'https://x/api/v1/reports/abc-1/photo');
      expect(r.hasPhoto, isTrue);
    });

    test('a report without a photo has none', () {
      final r = ReportApi.fromApi({...base, 'hasPhoto': false}, baseUrl: 'https://x/api/v1');
      expect(r.photoUrl, isNull);
      expect(r.hasPhoto, isFalse);
    });
  });
}
