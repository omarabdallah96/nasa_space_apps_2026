import 'package:latlong2/latlong.dart';

class Region {
  const Region({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.center,
  });

  final String id;
  final String name;
  final String nameAr;
  final double west, south, east, north;
  final LatLng center;

  factory Region.fromJson(Map<String, dynamic> json) {
    final bbox = (json['bbox'] as List).cast<num>();
    final center = (json['center'] as List).cast<num>();
    return Region(
      id: json['id'] as String,
      name: json['name'] as String,
      nameAr: json['nameAr'] as String? ?? json['name'] as String,
      west: bbox[0].toDouble(),
      south: bbox[1].toDouble(),
      east: bbox[2].toDouble(),
      north: bbox[3].toDouble(),
      center: LatLng(center[0].toDouble(), center[1].toDouble()),
    );
  }

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;
}
