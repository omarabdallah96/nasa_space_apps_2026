import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/models/fire_record.dart';
import 'package:nasa_space_apps_2026/data/models/hotspot.dart';
import 'package:nasa_space_apps_2026/data/models/region.dart';
import 'package:nasa_space_apps_2026/domain/anomaly.dart';
import 'package:nasa_space_apps_2026/l10n/strings.dart';
import 'package:nasa_space_apps_2026/services/alert_engine.dart';
import 'package:nasa_space_apps_2026/services/location_service.dart';
import 'package:nasa_space_apps_2026/services/weather_service.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('assets/mock/$name.json').readAsStringSync())
        as Map<String, dynamic>;

FireRecord record(String id) => FireRecord.fromJson(_json('record_$id'));
List<Region> regions() => (_json('regions')['regions'] as List)
    .map((e) => Region.fromJson(e as Map<String, dynamic>))
    .toList();
List<Hotspot> hotspots(String id) => (_json('hotspots_$id')['hotspots'] as List)
    .map((e) => Hotspot.fromJson(e as Map<String, dynamic>))
    .toList();

const calm = FireWeather(
    temperatureC: 15, humidity: 65, windKmh: 6, gustKmh: 12, precipitationMm: 0);

void main() {
  final lebanon = regions().firstWhere((r) => r.id == 'lebanon');

  group('near me', () {
    test('Beirut is in Lebanon', () {
      final m = matchRegion(regions(), const LatLng(33.89, 35.50))!;
      expect(m.region.id, 'lebanon');
      expect(m.inside, isTrue);
    });

    test('Nicosia is in Cyprus, not Lebanon', () {
      expect(matchRegion(regions(), const LatLng(35.17, 33.36))!.region.id, 'cyprus');
    });

    test('Cairo is outside all regions; nearest is reported with distance', () {
      final m = matchRegion(regions(), const LatLng(30.04, 31.24))!;
      expect(m.inside, isFalse);
      expect(m.distanceKm, greaterThan(100));
    });

    test('compass direction', () {
      const a = LatLng(33.0, 35.0);
      expect(compassIndex(a, const LatLng(34.0, 35.0)), 0); // north
      expect(compassIndex(a, const LatLng(33.0, 36.0)), 2); // east
      expect(compassIndex(a, const LatLng(32.0, 35.0)), 4); // south
    });
  });

  group('alert engine', () {
    const engine = AlertEngine();

    test('anomaly alert when latest month is above normal', () {
      final r = record('lebanon');
      final alerts = engine.evaluate(
          region: lebanon, record: r, hotspots: const [], now: DateTime(2026, 11, 14));
      final s = summarize(r);
      final hasAnomaly = alerts.any((a) => a.type == AlertType.anomaly);
      expect(hasAnomaly,
          s.status == FireStatus.above || s.status == FireStatus.extreme);
    });

    test('season-start warning ~2 weeks before the critical period', () {
      final r = record('lebanon');
      final first = criticalMonths(r).first;
      final now = DateTime(2027, first, 1).subtract(const Duration(days: 14));
      final alerts = engine.evaluate(
          region: lebanon, record: r, hotspots: const [], now: now);
      final soon = alerts.where((a) => a.type == AlertType.seasonSoon).toList();
      expect(soon, hasLength(1));
      expect(soon.single.days, 14);
      expect(soon.single.month, first);
    });

    test('in-season alert inside the critical period', () {
      final r = record('lebanon');
      final m = criticalMonths(r).first;
      final alerts = engine.evaluate(
          region: lebanon, record: r, hotspots: const [], now: DateTime(2027, m, 10));
      expect(alerts.any((a) => a.type == AlertType.inSeason), isTrue);
    });

    test('nearby hotspot alert when the user is close to a detection', () {
      final spots = hotspots('lebanon').where((h) => h.confidence != 'low').toList();
      final user = LatLng(spots.first.position.latitude + 0.01,
          spots.first.position.longitude);
      final alerts = engine.evaluate(
          region: lebanon,
          record: record('lebanon'),
          hotspots: spots,
          now: DateTime(2026, 11, 14),
          user: user);
      final near = alerts.firstWhere((a) => a.type == AlertType.nearbyHotspot);
      expect(near.distanceKm, lessThan(2));
      expect(near.level, AlertLevel.danger);
    });

    test('alert ids are stable (no duplicate notifications)', () {
      List<String> ids() => engine
          .evaluate(
              region: lebanon,
              record: record('lebanon'),
              hotspots: hotspots('lebanon'),
              now: DateTime(2026, 11, 14))
          .map((a) => a.id)
          .toList();
      expect(ids(), ids());
    });
  });

  group('burn advice', () {
    final r = record('lebanon');
    final quietMonth = (r.season.toList()
          ..sort((a, b) => a.median.compareTo(b.median)))
        .first
        .month;

    test('calm weather in a quiet month is not unsafe because of weather', () {
      final a = burnAdvice(weather: calm, record: r, now: DateTime(2027, quietMonth, 10));
      expect(a.reasons, isNot(contains('why_wind_high')));
      expect(a.reasons, isNot(contains('why_humidity_low')));
      expect(a.quietMonths, contains(quietMonth));
    });

    test('strong wind or dry air is unsafe', () {
      const windy = FireWeather(
          temperatureC: 20, humidity: 50, windKmh: 35, gustKmh: 55, precipitationMm: 0);
      const dry = FireWeather(
          temperatureC: 30, humidity: 15, windKmh: 5, gustKmh: 8, precipitationMm: 0);
      for (final w in [windy, dry]) {
        expect(burnAdvice(weather: w, record: r, now: DateTime(2027, quietMonth, 10)).level,
            BurnLevel.unsafe);
      }
    });

    test('the critical period is always unsafe', () {
      final m = criticalMonths(r).first;
      final a = burnAdvice(weather: calm, record: r, now: DateTime(2027, m, 10));
      expect(a.level, BurnLevel.unsafe);
      expect(a.reasons, contains('why_critical_period'));
    });
  });

  group('l10n', () {
    test('every key used in lib/ exists in English and Arabic', () {
      final used = <String>{};
      final keyPattern = RegExp(r"""\.t\('([a-z0-9_]+)'\)""");
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        used.addAll(keyPattern.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
      }
      // Dynamic keys: statuses, labels, burn levels, burn reasons, location errors.
      used.addAll([
        for (final s in FireStatus.values) 'status_${s.name}',
        for (final l in BurnLevel.values) 'burn_${l.name}',
        'why_wind_high', 'why_wind_moderate', 'why_humidity_low',
        'why_humidity_moderate', 'why_hot', 'why_anomaly',
        'why_critical_period', 'why_raining',
        'loc_off', 'loc_denied', 'loc_failed',
        'label_wildfire', 'label_agriculturalBurn', 'label_industrial',
        'label_falseAlarm', 'label_unsure',
      ]);
      expect(used.difference(S.englishKeys), isEmpty, reason: 'missing English');
      expect(used.difference(S.arabicKeys), isEmpty, reason: 'missing Arabic');
      expect(S.englishKeys.difference(S.arabicKeys), isEmpty);
    });

    test('Arabic sentence uses Levantine month names', () {
      final s = summarize(record('lebanon'), year: 2019, month: 10);
      final text = const S(true).sentence(s, lebanon);
      expect(text, contains('تشرين الأول 2019'));
      expect(text, contains('لبنان'));
    });

    test('alert texts render in both languages', () {
      final alerts = const AlertEngine().evaluate(
          region: lebanon,
          record: record('lebanon'),
          hotspots: hotspots('lebanon'),
          now: DateTime(2026, 11, 14),
          user: hotspots('lebanon').first.position);
      for (final ar in [false, true]) {
        for (final a in alerts) {
          expect(S(ar).alertTitle(a), isNotEmpty);
          expect(S(ar).alertBody(a), isNotEmpty);
        }
      }
    });
  });
}
