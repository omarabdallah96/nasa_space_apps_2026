import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/safety.dart';
import '../data/models/zone.dart';

/// Nearby water and services (`GET /resources`), the nearest help
/// (`GET /help`) and escape routes (`GET /escape`). Every answer is also kept on the phone, because during a
/// fire the network is often the first thing to go.
class SafetyApi {
  SafetyApi({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _prefix = 'safety.v1.';

  /// The server may need to ask OpenStreetMap, which can take half a minute.
  static const _timeout = Duration(seconds: 60);

  static String _p(LatLng p, [int digits = 3]) =>
      '${p.latitude.toStringAsFixed(digits)},${p.longitude.toStringAsFixed(digits)}';

  Future<Saved<List<SafetyResource>>> resources(LatLng at, {double radiusKm = 10}) async {
    final r = radiusKm.clamp(0.5, 25).toStringAsFixed(1);
    final saved = await _get(
      'res.${_p(at)}.$r',
      Uri.parse('$baseUrl/resources?lat=${at.latitude}&lon=${at.longitude}&radiusKm=$r'),
    );
    return Saved(
      [
        for (final j in saved.value['resources'] as List)
          SafetyResource.fromJson(j as Map<String, dynamic>),
      ],
      savedAt: saved.savedAt,
    );
  }

  /// The nearest civil defense centres, Red Cross centres, hospitals and fire
  /// stations to a person (`GET /help`), up to three of each, nearest first.
  Future<Saved<List<SafetyResource>>> nearestHelp(LatLng at) async {
    final saved = await _get(
      // About a kilometre: walking around does not ask the server again.
      'help.${_p(at, 2)}',
      Uri.parse('$baseUrl/help?lat=${at.latitude}&lon=${at.longitude}'),
    );
    return Saved(
      [
        for (final j in saved.value['resources'] as List)
          SafetyResource.fromJson(j as Map<String, dynamic>),
      ],
      savedAt: saved.savedAt,
    );
  }

  /// Routes away from [fires]. With no fires: exits in different directions.
  Future<Saved<EscapePlan>> escape(LatLng from, List<LatLng> fires) async {
    // The nearest fires matter most, and the server takes at most 200.
    final near = [...fires]
      ..sort((a, b) => _d2(from, a).compareTo(_d2(from, b)));
    final list = near.take(200).map((f) => _p(f, 4)).join(';');
    final saved = await _get(
      // Fires change by the hour, so the saved copy is per place, not per fire list.
      'esc.${_p(from)}.${fires.isEmpty ? 'exits' : 'fire'}',
      Uri.parse('$baseUrl/escape?lat=${from.latitude}&lon=${from.longitude}'
          '${list.isEmpty ? '' : '&fires=$list'}'),
    );
    return Saved(EscapePlan.fromJson(saved.value), savedAt: saved.savedAt);
  }

  /// Saves exits and resources of each zone ahead of time, for use offline.
  Future<void> prefetchZones(List<AlertZone> zones) async {
    for (final z in zones) {
      try {
        await resources(z.center, radiusKm: z.radiusKm);
        await escape(z.center, const []);
      } catch (e) {
        debugPrint('safety: could not save zone ${z.name} ($e)');
      }
    }
  }

  static double _d2(LatLng a, LatLng b) {
    final dy = a.latitude - b.latitude, dx = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  Future<Saved<Map<String, dynamic>>> _get(String key, Uri uri) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        throw http.ClientException('GET ${uri.path} → ${res.statusCode}', uri);
      }
      final text = utf8.decode(res.bodyBytes);
      final json = jsonDecode(text) as Map<String, dynamic>;
      await prefs.setString('$_prefix$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'body': json}));
      return Saved(json);
    } catch (e) {
      final copy = prefs.getString('$_prefix$key');
      if (copy == null) rethrow;
      final j = jsonDecode(copy) as Map<String, dynamic>;
      return Saved(j['body'] as Map<String, dynamic>, savedAt: DateTime.parse(j['at'] as String));
    }
  }
}
