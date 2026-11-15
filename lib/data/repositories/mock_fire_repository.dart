import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../models/danger_forecast.dart';
import '../models/fire_record.dart';
import '../models/hotspot.dart';
import '../models/region.dart';
import 'fire_repository.dart';

/// Reads the bundled JSON in assets/mock/. Same shapes as the real backend.
class MockFireRepository implements FireRepository {
  MockFireRepository({this.latency = const Duration(milliseconds: 250)});

  /// Fake network delay so loading states get exercised.
  final Duration latency;

  final _records = <String, FireRecord>{};

  Future<Map<String, dynamic>> _load(String name) async {
    await Future<void>.delayed(latency);
    final text = await rootBundle.loadString('assets/mock/$name.json');
    return jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<List<Region>> getRegions() async {
    final json = await _load('regions');
    return (json['regions'] as List)
        .map((e) => Region.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<FireRecord> getRecord(String regionId) async {
    final cached = _records[regionId];
    if (cached != null) return cached;
    final record = FireRecord.fromJson(await _load('record_$regionId'));
    return _records[regionId] = record;
  }

  /// Demo: the region's record scaled by the box's share of the region's area.
  @override
  Future<FireRecord> getAreaRecord(String regionId,
      {required double west, required double south, required double east, required double north}) async {
    final region = (await getRegions()).firstWhere((r) => r.id == regionId);
    final share = (((east - west) * (north - south)) /
            ((region.east - region.west) * (region.north - region.south)))
        .clamp(0.0, 1.0);
    final json = await _load('record_$regionId');
    num scale(Object? v) => (v as num) * share;
    for (final m in (json['monthly'] as List).cast<Map<String, dynamic>>()) {
      m['raw'] = scale(m['raw']);
      m['harmonized'] = scale(m['harmonized']);
    }
    for (final m in (json['season'] as List).cast<Map<String, dynamic>>()) {
      for (final k in ['p10', 'median', 'p90']) {
        m[k] = scale(m[k]);
      }
    }
    return FireRecord.fromJson(json);
  }

  @override
  Future<List<Hotspot>> getRecentHotspots(String regionId) async {
    final json = await _load('hotspots_$regionId');
    return (json['hotspots'] as List)
        .map((e) => Hotspot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Fire danger: generated, not bundled, so the demo always shows the
  // coming week. Drier east (Lebanon, Cyprus), a dry spell mid-week.

  static const _baseFwi = {'lebanon': 24.0, 'cyprus': 18.0, 'greece': 9.0, 'portugal': 4.0};

  static double _fwi(String regionId, LatLng p, int day) {
    final base = _baseFwi[regionId] ?? 10;
    final spell = 1 + 0.9 * math.exp(-math.pow(day - 3, 2) / 2);
    final place = 1 + 0.35 * math.sin(p.latitude * 7) * math.cos(p.longitude * 5);
    return math.max(0, base * spell * place);
  }

  static UsualActivity _usual(DateTime d) {
    final summer = math.cos((d.month - 8) / 12 * 2 * math.pi);
    final share = ((summer + 1) / 2).clamp(0.02, 1.0);
    return UsualActivity(
      cellDaysPerDay: (share * 12 * 10).roundToDouble() / 10,
      shareOfPeak: share,
      inPeakSeason: d.month >= 7 && d.month <= 9,
    );
  }

  static List<DateTime> get _week {
    final now = DateTime.now();
    return [for (var i = 0; i < 7; i++) DateTime(now.year, now.month, now.day + i)];
  }

  @override
  Future<DangerForecast> getDangerForecast(LatLng point) async {
    final regions = await getRegions();
    final region = regions.where((r) => r.contains(point)).firstOrNull;
    if (region == null) throw StateError('No forecast outside the regions.');
    return DangerForecast(
      regionId: region.id,
      point: point,
      generatedAt: DateTime.now(),
      days: [
        for (final (i, d) in _week.indexed)
          () {
            final fwi = _fwi(region.id, point, i);
            return DangerDay(
              date: d,
              level: DangerLevel.fromFwi(fwi),
              fwi: (fwi * 10).roundToDouble() / 10,
              usual: _usual(d),
              weather: NoonWeather(
                temperatureC: 18 + fwi / 4,
                humidity: (70 - fwi).clamp(15, 90),
                windKmh: 8 + fwi / 3,
                rainMm: fwi < 3 ? 2 : 0,
              ),
              drought: 150 + fwi * 10,
            );
          }(),
      ],
    );
  }

  @override
  Future<RegionDanger> getRegionDanger(String regionId) async {
    final region = (await getRegions()).firstWhere((r) => r.id == regionId);
    const step = 0.25;
    final points = <DangerPoint>[];
    for (var lat = region.south + step / 2; lat < region.north; lat += step) {
      for (var lon = region.west + step / 2; lon < region.east; lon += step) {
        final p = LatLng(lat, lon);
        final fwi = [for (var i = 0; i < 7; i++) _fwi(regionId, p, i)];
        points.add(DangerPoint(p, fwi.map(DangerLevel.fromFwi).toList(), fwi));
      }
    }
    final days = <DangerDay>[];
    final shares = <double>[];
    for (final (i, d) in _week.indexed) {
      final values = points.map((p) => p.fwi[i]).toList()..sort();
      final p90 = values[((values.length - 1) * 0.9).round()];
      days.add(DangerDay(date: d, level: DangerLevel.fromFwi(p90), fwi: p90, usual: _usual(d)));
      shares.add(values.where((v) => v >= 21.3).length / values.length);
    }
    return RegionDanger(
      regionId: regionId,
      generatedAt: DateTime.now(),
      days: days,
      highShare: shares,
      points: points,
      stepDegrees: step,
    );
  }
}
