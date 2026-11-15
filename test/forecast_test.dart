// Fire danger forecast: parsing the backend, alerts, the burn planner, and
// the Today card.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/models/danger_forecast.dart';
import 'package:nasa_space_apps_2026/data/models/fire_record.dart';
import 'package:nasa_space_apps_2026/data/models/region.dart';
import 'package:nasa_space_apps_2026/data/repositories/api_fire_repository.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/domain/anomaly.dart';
import 'package:nasa_space_apps_2026/l10n/strings.dart';
import 'package:nasa_space_apps_2026/services/alert_engine.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/services/weather_service.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:nasa_space_apps_2026/ui/widgets/danger_forecast_card.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_forecast').path;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
}

class _NoNotifications extends NotificationService {
  @override
  bool get supported => false;
}

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

const _lebanon = Region(
  id: 'lebanon',
  name: 'Lebanon',
  nameAr: 'لبنان',
  west: 35.1,
  south: 33.05,
  east: 36.62,
  north: 34.69,
  center: LatLng(33.87, 35.86),
);

DangerDay _day(DateTime date, DangerLevel level) => DangerDay(
      date: date,
      level: level,
      fwi: level.index * 10.0,
      usual: const UsualActivity(cellDaysPerDay: 1, shareOfPeak: 0.1, inPeakSeason: false),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PathProviderPlatform.instance = _FakePaths();
  });

  group('parsing the backend', () {
    test('point forecast', () {
      final f = DangerForecast.fromJson(_fixture('forecast_point'));
      expect(f.regionId, 'lebanon');
      expect(f.days, hasLength(3));
      final d = f.days.first;
      expect(d.date, DateTime(2026, 11, 15));
      expect(d.level, DangerLevel.fromFwi(d.fwi));
      expect(d.weather, isNotNull);
      expect(d.drought, greaterThan(0));
      expect(f.worst(), isNotNull);
    });

    test('country forecast for the map', () {
      final f = RegionDanger.fromJson(_fixture('forecast_lebanon'));
      expect(f.regionId, 'lebanon');
      expect(f.days, hasLength(3));
      expect(f.highShare, hasLength(3));
      expect(f.points, hasLength(3));
      expect(f.points.first.levels, hasLength(3));
      expect(f.stepDegrees, greaterThan(0));
    });

    test('danger classes follow EFFIS', () {
      expect([0, 5.2, 11.2, 21.3, 38, 50].map((v) => DangerLevel.fromFwi(v.toDouble())), [
        DangerLevel.veryLow,
        DangerLevel.low,
        DangerLevel.moderate,
        DangerLevel.high,
        DangerLevel.veryHigh,
        DangerLevel.extreme,
      ]);
      expect(DangerLevel.fromApi('very_high'), DangerLevel.veryHigh);
    });
  });

  test('the API is asked once per place for a few minutes', () async {
    var calls = 0;
    final repo = ApiFireRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((req) async {
        calls++;
        expect(req.url.path, '/api/v1/forecast');
        expect(req.url.queryParameters['lat'], '33.89');
        return http.Response(jsonEncode(_fixture('forecast_point')), 200);
      }),
    );
    final a = await repo.getDangerForecast(const LatLng(33.8912, 35.5));
    final b = await repo.getDangerForecast(const LatLng(33.8899, 35.5));
    expect(a.days.length, b.days.length);
    expect(calls, 1);
  });

  group('danger alerts', () {
    const engine = AlertEngine();
    final now = DateTime(2026, 8, 10, 9);
    final today = DateTime(2026, 8, 10);

    test('very high within 3 days warns, extreme is a danger', () {
      final a = engine.dangerAlert(region: _lebanon, now: now, days: [
        _day(today, DangerLevel.high),
        _day(today.add(const Duration(days: 2)), DangerLevel.veryHigh),
      ])!;
      expect(a.level, AlertLevel.warning);
      expect(a.days, 2);
      expect(a.id, contains('2026-8-12'));
      final b = engine.dangerAlert(region: _lebanon, now: now, nearUser: true, days: [
        _day(today, DangerLevel.extreme),
      ])!;
      expect(b.level, AlertLevel.danger);
      const s = S(false);
      expect(s.alertTitle(b), 'Lebanon: extreme fire danger forecast');
      expect(s.alertBody(b), startsWith('Today: extreme fire danger near you.'));
      expect(const S(true).alertBody(b), contains('شديد'));
    });

    test('high, or very high later in the week, does not alert', () {
      expect(
        engine.dangerAlert(region: _lebanon, now: now, days: [
          _day(today, DangerLevel.high),
          _day(today.add(const Duration(days: 4)), DangerLevel.extreme),
        ]),
        isNull,
      );
    });
  });

  test('the burn planner never picks a high-danger day', () {
    final record = FireRecord.fromJson(jsonDecode(
        File('assets/mock/record_lebanon.json').readAsStringSync()) as Map<String, dynamic>);
    // A month outside the critical period, calm weather every day.
    final quiet = [...record.season]..sort((a, b) => a.median.compareTo(b.median));
    final start = DateTime(2027, quiet.first.month, 1);
    const calm = FireWeather(
        temperatureC: 15, humidity: 60, windKmh: 5, gustKmh: 10, precipitationMm: 0);
    final days = [for (var i = 0; i < 3; i++) DayForecast(start.add(Duration(days: i)), calm)];
    final plain = planBurns(days, record);
    expect(plain.best, isNotNull);
    final withDanger = planBurns(days, record, danger: [
      for (final d in days) _day(d.date, DangerLevel.high),
    ]);
    expect(withDanger.best, isNull);
    expect(withDanger.days.first.advice.reasons, contains('why_danger_high'));
  });

  test('fires in a month that usually has none read as more, not 0.0x', () {
    final json = jsonDecode(File('assets/mock/record_lebanon.json').readAsStringSync())
        as Map<String, dynamic>;
    for (final m in (json['season'] as List).cast<Map<String, dynamic>>()) {
      m['p10'] = 0;
      m['median'] = 0;
      m['p90'] = 0;
    }
    final monthly = (json['monthly'] as List).cast<Map<String, dynamic>>();
    monthly.last['harmonized'] = 29;
    final sum = summarize(FireRecord.fromJson(json));
    expect(sum.usuallyNone, isTrue);
    expect(sum.status, FireStatus.extreme);
    expect(sum.sentence('Lebanon'), contains('29 fire cells, in a month that usually has almost none'));
    expect(sum.sentence('Lebanon'), isNot(contains('0.0×')));
    expect(const S(true).sentence(sum, _lebanon), contains('لا تكاد تحدث'));
  });

  testWidgets('the Today card shows the week and opens a day', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final state = AppState(
      MockFireRepository(latency: Duration.zero),
      prefs: await SharedPreferences.getInstance(),
      notifications: _NoNotifications(),
    );
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if ('${d.exception}'.contains('google_fonts')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    await tester.pumpWidget(AppScope(
      state: state,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DangerForecastCard(point: LatLng(33.9, 35.6))),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Fire danger forecast'), findsOneWidget);
    expect(find.textContaining('Today: '), findsOneWidget);
    expect(find.text('Today'), findsOneWidget); // the first day tile
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Weather at noon'), findsOneWidget);
  });
}
