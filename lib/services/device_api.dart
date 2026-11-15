import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/models/zone.dart';

/// Registers this phone for instant (push) alerts: its push token, its alert
/// zones and its last location (`PUT /devices`). Only used after the person
/// turns on instant alerts.
class DeviceApi {
  DeviceApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `https://firesight.coding-now.online/api/v1`
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<void> register({
    required String installationId,
    required String? pushToken,
    required String platform,
    required String lang,
    required List<AlertZone> zones,
    LatLng? location,
    DateTime? locatedAt,
    String? authToken,
  }) async {
    final res = await _client
        .put(
          Uri.parse('$baseUrl/devices'),
          headers: {
            'Content-Type': 'application/json',
            if (authToken != null) 'Authorization': 'Bearer $authToken',
          },
          body: jsonEncode({
            'installationId': installationId,
            'token': pushToken,
            'platform': platform,
            'lang': lang,
            if (location != null)
              'location': {
                'lat': location.latitude,
                'lon': location.longitude,
                'at': (locatedAt ?? DateTime.now()).toUtc().toIso8601String(),
              },
            'zones': [
              for (final z in zones)
                {
                  'id': z.id,
                  'name': z.name,
                  'lat': z.center.latitude,
                  'lon': z.center.longitude,
                  'radiusKm': z.radiusKm,
                },
            ],
          }),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw http.ClientException('PUT /devices → ${res.statusCode} ${res.body}');
  }

  Future<void> unregister(String installationId) async {
    final res = await _client.delete(Uri.parse('$baseUrl/devices/$installationId')).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw http.ClientException('DELETE /devices → ${res.statusCode}');
    }
  }
}
