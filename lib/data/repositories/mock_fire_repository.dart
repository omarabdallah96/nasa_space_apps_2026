import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

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

  @override
  Future<List<Hotspot>> getRecentHotspots(String regionId) async {
    final json = await _load('hotspots_$regionId');
    return (json['hotspots'] as List)
        .map((e) => Hotspot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
