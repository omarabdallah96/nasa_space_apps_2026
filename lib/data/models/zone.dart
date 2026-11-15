import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';

/// A circle the user draws on the map to get alerts for: a farm, a village,
/// a forest. One is free; more need Pro.
class AlertZone {
  const AlertZone({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusKm,
    required this.createdAt,
  });

  final String id;
  final String name;
  final LatLng center;
  final double radiusKm;
  final DateTime createdAt;

  static const minRadiusKm = 1.0, maxRadiusKm = 50.0, defaultRadiusKm = 10.0;

  bool contains(LatLng p) => distanceKm(center, p) <= radiusKm;

  /// The box around the circle, as west, south, east, north. The backend's
  /// record queries take a box, so a zone report covers this box.
  ({double west, double south, double east, double north}) get bbox {
    final dLat = radiusKm / 111.32;
    final dLon = radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180).abs().clamp(0.01, 1));
    return (
      west: center.longitude - dLon,
      south: center.latitude - dLat,
      east: center.longitude + dLon,
      north: center.latitude + dLat,
    );
  }

  AlertZone copyWith({String? name, double? radiusKm}) => AlertZone(
        id: id,
        name: name ?? this.name,
        center: center,
        radiusKm: radiusKm ?? this.radiusKm,
        createdAt: createdAt,
      );

  factory AlertZone.fromJson(Map<String, dynamic> j) => AlertZone(
        id: j['id'] as String,
        name: j['name'] as String,
        center: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        radiusKm: (j['radiusKm'] as num).toDouble(),
        // Zones the server took from a phone have no createdAt.
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': center.latitude,
        'lon': center.longitude,
        'radiusKm': radiusKm,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
