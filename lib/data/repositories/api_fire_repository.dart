import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/fire_record.dart';
import '../models/hotspot.dart';
import '../models/region.dart';
import 'fire_repository.dart';

/// Reads the endpoints in docs/api_contract.md.
///
/// Offline mode: every successful response is saved to disk. If the network
/// fails, the last saved copy is used, so watched places keep working in the
/// field. Set `useMockData = false` in lib/main.dart to switch to this.
class ApiFireRepository implements FireRepository {
  ApiFireRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final _records = <String, FireRecord>{};

  /// True when the last response came from the offline cache.
  bool servedFromCache = false;

  Future<Map<String, dynamic>> _get(String path) async {
    final cacheName = path.replaceAll('/', '_');
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/$path'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw HttpException('GET $path → ${res.statusCode}');
      }
      await _writeCache(cacheName, res.body);
      servedFromCache = false;
      return jsonDecode(res.body) as Map<String, dynamic>;
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
    final json = await _get('regions.json');
    return (json['regions'] as List)
        .map((e) => Region.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<FireRecord> getRecord(String regionId) async {
    final cached = _records[regionId];
    if (cached != null) return cached;
    final record = FireRecord.fromJson(await _get('record/$regionId.json'));
    return _records[regionId] = record;
  }

  @override
  Future<List<Hotspot>> getRecentHotspots(String regionId) async {
    final json = await _get('hotspots/$regionId.json');
    return (json['hotspots'] as List)
        .map((e) => Hotspot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
