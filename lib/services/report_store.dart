import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the person on the ground saw at a hotspot.
enum ReportLabel { wildfire, smoke, agriculturalBurn, industrial, falseAlarm, unsure }

/// A ground-truth report: photo + GPS + label. Stored on the phone for now;
/// later uploaded so satellite detections can be checked against the ground.
class FieldReport {
  const FieldReport({
    required this.id,
    required this.position,
    required this.createdAt,
    required this.label,
    this.note = '',
    this.photoPath,
    this.hotspotSensor,
    this.hotspotTime,
    this.bearing,
    this.remoteId,
    this.deleteToken,
  });

  final String id;
  final LatLng position;
  final DateTime createdAt;
  final ReportLabel label;
  final String note;
  final String? photoPath;
  final String? hotspotSensor;
  final DateTime? hotspotTime;

  /// Compass direction the reporter pointed at the smoke (degrees from
  /// north). Used to triangulate the fire from several reports.
  final double? bearing;

  /// The backend's id once uploaded (null = not sent yet).
  final String? remoteId;

  /// Lets this phone delete its own report from the backend.
  final String? deleteToken;

  bool get uploaded => remoteId != null;

  FieldReport withRemote(String remoteId, String? deleteToken) => FieldReport(
        id: id,
        position: position,
        createdAt: createdAt,
        label: label,
        note: note,
        photoPath: photoPath,
        hotspotSensor: hotspotSensor,
        hotspotTime: hotspotTime,
        bearing: bearing,
        remoteId: remoteId,
        deleteToken: deleteToken,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': position.latitude,
        'lon': position.longitude,
        'createdAt': createdAt.toIso8601String(),
        'label': label.name,
        'note': note,
        'photoPath': photoPath,
        'hotspotSensor': hotspotSensor,
        'hotspotTime': hotspotTime?.toIso8601String(),
        'bearing': bearing,
        'remoteId': remoteId,
        'deleteToken': deleteToken,
      };

  factory FieldReport.fromJson(Map<String, dynamic> j) => FieldReport(
        id: j['id'] as String,
        position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        createdAt: DateTime.parse(j['createdAt'] as String),
        label: ReportLabel.values.firstWhere((l) => l.name == j['label'],
            orElse: () => ReportLabel.unsure),
        note: j['note'] as String? ?? '',
        photoPath: j['photoPath'] as String?,
        hotspotSensor: j['hotspotSensor'] as String?,
        hotspotTime: j['hotspotTime'] == null
            ? null
            : DateTime.parse(j['hotspotTime'] as String),
        bearing: (j['bearing'] as num?)?.toDouble(),
        remoteId: j['remoteId'] as String?,
        deleteToken: j['deleteToken'] as String?,
      );
}

class ReportStore {
  ReportStore(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'field_reports';

  List<FieldReport> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FieldReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<FieldReport> reports) => _prefs.setString(
      _key, jsonEncode(reports.map((r) => r.toJson()).toList()));

  /// Copies a picked photo into app storage so it survives cache clears.
  static Future<String?> keepPhoto(String? pickedPath, String reportId) async {
    if (pickedPath == null || kIsWeb) return pickedPath;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/reports');
    await dir.create(recursive: true);
    final ext = pickedPath.contains('.') ? pickedPath.split('.').last : 'jpg';
    final target = '${dir.path}/$reportId.$ext';
    await File(pickedPath).copy(target);
    return target;
  }
}
