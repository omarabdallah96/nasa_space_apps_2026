import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/models/fire_record.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/domain/anomaly.dart';
import 'package:nasa_space_apps_2026/services/background_checks.dart';
import 'package:nasa_space_apps_2026/services/location_service.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/services/report_store.dart';
import 'package:nasa_space_apps_2026/services/triangulation.dart';
import 'package:nasa_space_apps_2026/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

FireRecord record(String id) => FireRecord.fromJson(
    jsonDecode(File('assets/mock/record_$id.json').readAsStringSync())
        as Map<String, dynamic>);

FieldReport smoke(String id, LatLng from, LatLng fire, {double error = 0, DateTime? at}) =>
    FieldReport(
      id: id,
      position: from,
      createdAt: at ?? DateTime(2026, 11, 14, 12),
      label: ReportLabel.smoke,
      bearing: (const Distance().bearing(from, fire) + error + 360) % 360,
    );

class _RecordingNotifications extends NotificationService {
  final sent = <String>[];
  @override
  bool get supported => false;
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool urgent = false,
  }) async =>
      sent.add(title);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 14, 13);

  group('smoke triangulation', () {
    const fire = LatLng(33.70, 35.53);

    test('two perfect reports cross at the fire', () {
      final est = triangulate([
        smoke('a', const LatLng(33.89, 35.50), fire),
        smoke('b', const LatLng(33.56, 35.38), fire),
      ], now: now);
      expect(est, hasLength(1));
      // The flat local projection costs <100 m at ~20 km range; compass
      // error (5° ≈ 1.7 km at that range) dominates in practice.
      expect(distanceKm(est.single.center, fire), lessThan(0.2));
      expect(est.single.reports, hasLength(2));
    });

    test('three reports with compass error still land close', () {
      final est = triangulate(demoSmokeReports(now: now), now: now);
      expect(est, hasLength(1));
      expect(est.single.reports, hasLength(3));
      expect(distanceKm(est.single.center, const LatLng(33.705, 35.535)),
          lessThan(est.single.radiusKm));
    });

    test('parallel lines, lines pointing away, and old reports give nothing', () {
      const a = LatLng(33.80, 35.50), b = LatLng(33.80, 35.60);
      FieldReport r(String id, LatLng p, double bearing, {DateTime? at}) => FieldReport(
          id: id, position: p, createdAt: at ?? now, label: ReportLabel.smoke, bearing: bearing);
      expect(triangulate([r('1', a, 0), r('2', b, 0)], now: now), isEmpty); // parallel
      expect(triangulate([r('1', a, 270), r('2', b, 90)], now: now), isEmpty); // diverging
      expect(
          triangulate([
            smoke('1', const LatLng(33.89, 35.50), fire, at: now.subtract(const Duration(days: 2))),
            smoke('2', const LatLng(33.56, 35.38), fire),
          ], now: now),
          isEmpty); // first report too old
    });

    test('reports without a compass bearing are ignored', () {
      final noBearing = FieldReport(
          id: 'x', position: const LatLng(33.8, 35.5), createdAt: now, label: ReportLabel.wildfire);
      expect(triangulate([noBearing, smoke('a', const LatLng(33.56, 35.38), fire)], now: now),
          isEmpty);
    });

    test('bearing survives save/load', () {
      final r = smoke('a', const LatLng(33.56, 35.38), fire);
      expect(FieldReport.fromJson(r.toJson()).bearing, closeTo(r.bearing!, 1e-9));
    });
  });

  group('burn planner', () {
    final r = record('lebanon');
    final quiet = (r.season.toList()..sort((a, b) => a.median.compareTo(b.median))).first.month;
    DayForecast day(int d, {double wind = 8, double hum = 60, double gust = 15}) => DayForecast(
        DateTime(2027, quiet, d),
        FireWeather(temperatureC: 16, humidity: hum, windKmh: wind, gustKmh: gust, precipitationMm: 0));

    test('picks the calmest, most humid day and skips unsafe ones', () {
      final plan = planBurns([
        day(1, wind: 30, gust: 50), // unsafe: wind
        day(2, wind: 12, hum: 45),
        day(3, wind: 5, hum: 70), // best
        day(4, hum: 18), // unsafe: dry
      ], r);
      expect(plan.best!.day.date.day, 3);
      expect(plan.days[0].score, double.infinity);
      expect(plan.days[3].score, double.infinity);
    });

    test('no safe day inside the critical period', () {
      final critical = criticalMonths(r).first;
      final plan = planBurns([
        for (var d = 1; d <= 7; d++)
          DayForecast(DateTime(2027, critical, d),
              const FireWeather(temperatureC: 18, humidity: 70, windKmh: 5, gustKmh: 9, precipitationMm: 0)),
      ], r);
      expect(plan.best, isNull);
    });

    test('parses the Open-Meteo daily format', () {
      final days = DayForecast.listFromOpenMeteo({
        'daily': {
          'time': ['2026-11-14', '2026-11-15'],
          'temperature_2m_max': [21.3, 19.0],
          'relative_humidity_2m_min': [41, 55],
          'wind_speed_10m_max': [14.2, 8.1],
          'wind_gusts_10m_max': [30.0, 18.4],
          'precipitation_sum': [0.0, null],
        }
      });
      expect(days, hasLength(2));
      expect(days[1].date.day, 15);
      expect(days[1].weather.windKmh, 8.1);
      expect(days[1].weather.precipitationMm, 0);
    });
  });

  group('background check', () {
    test('notifies new alerts once, without the app UI', () async {
      SharedPreferences.setMockInitialValues({
        'watchlist': ['lebanon'],
        // The user was last seen in Beirut.
        'last_lat': 33.89,
        'last_lon': 35.50,
        'field_reports': jsonEncode(demoSmokeReports().map((r) => r.toJson()).toList()),
      });
      final notes = _RecordingNotifications();
      await runBackgroundCheck(
          repository: MockFireRepository(latency: Duration.zero), notifications: notes);
      expect(notes.sent, isNotEmpty);
      // The triangulated smoke ~22 km from Beirut is among them.
      expect(notes.sent.any((t) => t.contains('ground reports')), isTrue);

      // Second run: nothing new, so nothing is sent again.
      final again = _RecordingNotifications();
      await runBackgroundCheck(
          repository: MockFireRepository(latency: Duration.zero), notifications: again);
      expect(again.sent, isEmpty);
    });
  });
}
