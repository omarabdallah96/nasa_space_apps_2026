import 'package:latlong2/latlong.dart';

class Hotspot {
  const Hotspot({
    required this.position,
    required this.acquiredAt,
    required this.sensor,
    required this.confidence,
    required this.frp,
  });

  final LatLng position;
  final DateTime acquiredAt;
  final String sensor;
  final String confidence;
  final double frp; // fire radiative power, MW

  factory Hotspot.fromJson(Map<String, dynamic> json) => Hotspot(
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
        acquiredAt: DateTime.parse(json['acquiredAt'] as String),
        sensor: json['sensor'] as String,
        confidence: json['confidence'] as String,
        frp: (json['frp'] as num).toDouble(),
      );
}
