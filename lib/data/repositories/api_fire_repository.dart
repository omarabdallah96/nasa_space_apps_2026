import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/fire_record.dart';
import '../models/hotspot.dart';
import '../models/region.dart';
import 'fire_repository.dart';

/// Reads the Firesight backend (`/api/v1`, see the backend README) and maps
/// its answers onto the shapes in docs/api_contract.md.
///
/// Offline mode: every successful response is saved to disk. If the network
/// fails, the last saved copy is used, so watched places keep working in the
/// field. Set `useMockData = false` in lib/config.dart to switch to this.
class ApiFireRepository implements FireRepository {
  ApiFireRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `https://cedx.coding-now.online/api/v1`
  final String baseUrl;
  final http.Client _client;
  final _records = <String, FireRecord>{};

  /// True when the last response came from the offline cache.
  bool servedFromCache = false;

  /// The backend has no Arabic names; these cover the packaged countries.
  static const _arabicNames = {
    'lebanon': 'لبنان',
    'portugal': 'البرتغال',
    'greece': 'اليونان',
    'cyprus': 'قبرص',
  };

  /// The backend's raw record is MODIS until 2012 and VIIRS after.
  static const _firstViirsYear = 2012;

  /// The contract promises near-real-time detections from the last 48 hours.
  static const _hotspotHours = 48;

  Future<Map<String, dynamic>> _get(String path) async {
    final cacheName = path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/$path'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw HttpException('GET $path → ${res.statusCode}');
      }
      final body = utf8.decode(res.bodyBytes);
      await _writeCache(cacheName, body);
      servedFromCache = false;
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      final cached = await _readCache(cacheName);
      if (cached == null) rethrow;
      servedFromCache = true;
      return jsonDecode(cached) as Map<String, dynamic>;
    }
  }

  Future<File?> _cacheFile(String name) async {
    if (kIsWeb) return null;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/cache');
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  Future<void> _writeCache(String name, String body) async =>
      (await _cacheFile(name))?.writeAsString(body);

  Future<String?> _readCache(String name) async {
    final f = await _cacheFile(name);
    return f != null && await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<List<Region>> getRegions() async {
    final json = await _get('countries');
    return (json['countries'] as List).map((e) {
      final c = e as Map<String, dynamic>;
      final slug = c['slug'] as String;
      // `focus` is the mainland box (Portugal's `bbox` reaches the Azores).
      final box = ((c['focus'] ?? c['bbox']) as List).cast<num>();
      return Region.fromJson({
        'id': slug,
        'name': c['name'],
        'nameAr': _arabicNames[slug] ?? c['name'],
        'bbox': box,
        'center': [(box[1] + box[3]) / 2, (box[0] + box[2]) / 2],
      });
    }).toList();
  }

  @override
  Future<FireRecord> getRecord(String regionId) async {
    final cached = _records[regionId];
    if (cached != null) return cached;
    final results = await Future.wait([
      _get('countries/$regionId/calendar?mode=harmonized'),
      _get('countries/$regionId/calendar?mode=raw'),
      _get('countries/$regionId/method'),
    ]);
    final record = FireRecord.fromJson(
        recordFromApi(regionId, results[0], results[1], results[2]));
    return _records[regionId] = record;
  }

  /// Builds a docs/api_contract.md record from the backend's calendars and method.
  @visibleForTesting
  static Map<String, dynamic> recordFromApi(
    String regionId,
    Map<String, dynamic> harmonized,
    Map<String, dynamic> raw,
    Map<String, dynamic> method,
  ) {
    final hYears = (harmonized['years'] as List).cast<Map<String, dynamic>>();
    final rawByYear = {
      for (final y in (raw['years'] as List).cast<Map<String, dynamic>>())
        y['year'] as int: (y['values'] as List),
    };

    // Latest complete month: the one before the month still running.
    int latestYear, latestMonth;
    final partial = harmonized['partialMonth'] as Map<String, dynamic>?;
    if (partial != null) {
      latestYear = partial['year'] as int;
      latestMonth = (partial['month'] as int) - 1;
      if (latestMonth == 0) {
        latestYear -= 1;
        latestMonth = 12;
      }
    } else {
      final last = hYears.last;
      final values = last['values'] as List;
      latestYear = last['year'] as int;
      latestMonth = values.lastIndexWhere((v) => v != null) + 1;
    }

    // The app indexes months from January of the first year, so start at the
    // first year whose January is covered (the record begins in November 2000).
    final monthly = <Map<String, dynamic>>[];
    var started = false;
    for (final y in hYears) {
      final year = y['year'] as int;
      final values = y['values'] as List;
      if (!started && values.first == null) continue;
      started = true;
      for (var m = 1; m <= 12; m++) {
        if (year > latestYear || (year == latestYear && m > latestMonth)) break;
        final h = (values[m - 1] as num?) ?? 0;
        final r = (rawByYear[year]?[m - 1] as num?) ?? 0;
        monthly.add({
          'year': year,
          'month': m,
          'sensor': year < _firstViirsYear ? 'MODIS' : 'VIIRS',
          'raw': r,
          'harmonized': h,
        });
      }
    }

    final usual = harmonized['usual'] as Map<String, dynamic>;
    final baseline = (usual['baselineYears'] as List).cast<int>();
    final median = (usual['median'] as List).cast<num>();
    final p10 = (usual['p10'] as List).cast<num>();
    final p90 = (usual['p90'] as List).cast<num>();

    final ratio = method['viirsPerModisCellDay'] as Map<String, dynamic>;
    final validation = method['heldOutValidation'] as Map<String, dynamic>;
    final suomiEnd = method['suomiNppLastDay'] as String?;
    final overlapEnd = suomiEnd != null
        ? int.parse(suomiEnd.substring(0, 4))
        : latestYear;

    return {
      'regionId': regionId,
      'units': harmonized['unit'],
      'baseline': {'from': baseline[0], 'to': baseline[1]},
      'latest': {'year': latestYear, 'month': latestMonth},
      'evidence': {
        'method':
            'Per-month VIIRS/MODIS ratio of 1 km cell-days over the years both '
                'sensors flew, applied to MODIS-only years',
        'overlapYears': [_firstViirsYear, overlapEnd],
        'ratio': ratio['annual'],
        'heldOutErrorRaw': validation['yearlyErrorRaw'],
        'heldOutErrorHarmonized': validation['yearlyError'],
      },
      'monthly': monthly,
      'season': [
        for (var m = 0; m < 12; m++)
          {'month': m + 1, 'p10': p10[m], 'median': median[m], 'p90': p90[m]},
      ],
    };
  }

  @override
  Future<List<Hotspot>> getRecentHotspots(String regionId) async {
    // Default window is the last 7 days of the record; keep the last 48 hours.
    final json = await _get('countries/$regionId/hotspots');
    return hotspotsFromApi(json);
  }

  @visibleForTesting
  static List<Hotspot> hotspotsFromApi(Map<String, dynamic> json) {
    final spots = (json['hotspots'] as List)
        .cast<Map<String, dynamic>>()
        .map((h) => Hotspot.fromJson({
              'lat': h['latitude'],
              'lon': h['longitude'],
              'acquiredAt': _acquiredAt(h['acq_date'] as String, '${h['acq_time']}'),
              'sensor': _sensor('${h['satellite']}', '${h['instrument']}'),
              'confidence': _confidence(h['confidence']),
              'frp': h['frp'] ?? 0,
            }))
        .toList();
    if (spots.isEmpty) return spots;
    final newest = spots
        .map((s) => s.acquiredAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final cutoff = newest.subtract(const Duration(hours: _hotspotHours));
    return spots.where((s) => !s.acquiredAt.isBefore(cutoff)).toList();
  }

  /// FIRMS gives `acq_date` YYYY-MM-DD and `acq_time` HHMM, both UTC.
  static String _acquiredAt(String date, String time) {
    final t = time.padLeft(4, '0');
    return '${date}T${t.substring(0, 2)}:${t.substring(2, 4)}:00Z';
  }

  static String _sensor(String satellite, String instrument) {
    if (instrument.toUpperCase() == 'MODIS') return 'MODIS';
    switch (satellite.toUpperCase()) {
      case 'N20':
      case 'NOAA-20':
      case '1':
        return 'VIIRS_NOAA20';
      case 'N21':
      case 'NOAA-21':
      case '2':
        return 'VIIRS_NOAA21';
      default:
        return 'VIIRS_SNPP';
    }
  }

  /// VIIRS uses l/n/h; MODIS uses 0–100.
  static String _confidence(Object? c) {
    if (c is num) return c < 30 ? 'low' : (c >= 80 ? 'high' : 'nominal');
    final s = '$c'.toLowerCase();
    final n = num.tryParse(s);
    if (n != null) return _confidence(n);
    if (s.startsWith('l')) return 'low';
    if (s.startsWith('h')) return 'high';
    return 'nominal';
  }
}
