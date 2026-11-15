import 'package:latlong2/latlong.dart';

/// A zone alert sent from the admin page: a message for a circle. The phone
/// shows it when the circle overlaps one of its zones or contains the user.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.title,
    required this.message,
    this.titleAr = '',
    this.messageAr = '',
    required this.level,
    required this.center,
    required this.radiusKm,
    required this.expiresAt,
  });

  final String id;
  final String title, message, titleAr, messageAr;

  /// 'info', 'warning' or 'danger'.
  final String level;
  final LatLng center;
  final double radiusKm;
  final DateTime expiresAt;

  String titleIn(bool ar) => ar && titleAr.isNotEmpty ? titleAr : title;
  String messageIn(bool ar) => ar && messageAr.isNotEmpty ? messageAr : message;

  factory Broadcast.fromJson(Map<String, dynamic> j) => Broadcast(
        id: j['id'] as String,
        title: j['title'] as String,
        message: j['message'] as String,
        titleAr: j['titleAr'] as String? ?? '',
        messageAr: j['messageAr'] as String? ?? '',
        level: j['level'] as String? ?? 'warning',
        center: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        radiusKm: (j['radiusKm'] as num).toDouble(),
        expiresAt: DateTime.parse(j['expiresAt'] as String),
      );
}
