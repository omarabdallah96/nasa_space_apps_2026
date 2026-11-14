import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'report_store.dart';

/// Shares ground reports through the backend (`/api/v1/reports`), so compass
/// lines from different people can be crossed to locate a fire.
class ReportApi {
  ReportApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `https://cedx.coding-now.online/api/v1`
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  /// Sends one report with its photo. Safe to retry: the backend returns the
  /// first copy for the same device + report id.
  Future<({String id, String? deleteToken})> upload(
      FieldReport r, String deviceId) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/reports'))
      ..fields.addAll({
        'deviceId': deviceId,
        'clientId': r.id,
        'lat': '${r.position.latitude}',
        'lon': '${r.position.longitude}',
        'createdAt': r.createdAt.toUtc().toIso8601String(),
        'label': r.label.name,
        if (r.note.isNotEmpty) 'note': r.note,
        if (r.bearing != null) 'bearing': '${r.bearing! % 360}',
        if (r.hotspotSensor != null) 'hotspotSensor': r.hotspotSensor!,
        if (r.hotspotTime != null)
          'hotspotTime': r.hotspotTime!.toUtc().toIso8601String(),
      });
    final photo = r.photoPath;
    if (photo != null && !kIsWeb && await File(photo).exists()) {
      final ext = photo.split('.').last.toLowerCase();
      final type = ext == 'png' ? 'png' : ext == 'webp' ? 'webp' : 'jpeg';
      req.files.add(await http.MultipartFile.fromPath('photo', photo,
          contentType: http.MediaType('image', type)));
    }
    final res = await http.Response.fromStream(
        await _client.send(req).timeout(_timeout));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HttpException('POST /reports → ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final report = json['report'] as Map<String, dynamic>;
    return (id: report['id'] as String, deleteToken: json['deleteToken'] as String?);
  }

  /// Reports from everyone in these countries since [since].
  Future<List<FieldReport>> nearby(Iterable<String> regionIds, DateTime since) async {
    final out = <FieldReport>[];
    for (final id in regionIds) {
      final uri = Uri.parse('$baseUrl/reports').replace(queryParameters: {
        'country': id,
        'since': since.toUtc().toIso8601String(),
      });
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        throw HttpException('GET /reports → ${res.statusCode}');
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      out.addAll((json['reports'] as List).map((e) => fromApi(e as Map<String, dynamic>)));
    }
    return out;
  }

  Future<void> delete(String remoteId, String token) async {
    final res = await _client.delete(Uri.parse('$baseUrl/reports/$remoteId'),
        headers: {'X-Report-Token': token}).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw HttpException('DELETE /reports → ${res.statusCode}');
    }
  }

  /// A report someone else sent. Its photo stays on the server.
  @visibleForTesting
  static FieldReport fromApi(Map<String, dynamic> j) => FieldReport(
        id: 'remote-${j['id']}',
        remoteId: j['id'] as String,
        position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        createdAt: DateTime.parse(j['createdAt'] as String),
        label: ReportLabel.values.firstWhere((l) => l.name == j['label'],
            orElse: () => ReportLabel.unsure),
        note: j['note'] as String? ?? '',
        hotspotSensor: j['hotspotSensor'] as String?,
        hotspotTime: j['hotspotTime'] == null
            ? null
            : DateTime.parse(j['hotspotTime'] as String),
        bearing: (j['bearing'] as num?)?.toDouble(),
      );
}
