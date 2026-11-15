import 'package:latlong2/latlong.dart';

/// What a nearby place is good for in a fire.
enum ResourceKind { water, civilDefense, redCross, fireStation, hospital, assemblyPoint, town }

ResourceKind _kind(String s) => switch (s) {
      'water' => ResourceKind.water,
      'civil_defense' => ResourceKind.civilDefense,
      'red_cross' => ResourceKind.redCross,
      'fire_station' => ResourceKind.fireStation,
      'hospital' => ResourceKind.hospital,
      'assembly_point' => ResourceKind.assemblyPoint,
      _ => ResourceKind.town,
    };

/// A place from OpenStreetMap near a fire or zone (`GET /resources`).
class SafetyResource {
  const SafetyResource({
    required this.id,
    required this.kind,
    required this.detail,
    required this.position,
    required this.distanceKm,
    required this.bearingDeg,
    this.name,
    this.nameAr,
  });

  final String id;
  final ResourceKind kind;

  /// hydrant, water_tank, suction_point, pond, lake, reservoir, river, canal,
  /// civil_defense, red_cross, ambulance_station, fire_station, hospital,
  /// clinic, assembly_point…
  final String detail;
  final String? name, nameAr;
  final LatLng position;
  final double distanceKm;
  final int bearingDeg;

  String? displayName(bool ar) => ar ? (nameAr ?? name) : name;

  factory SafetyResource.fromJson(Map<String, dynamic> j) => SafetyResource(
        id: j['id'] as String,
        kind: _kind(j['kind'] as String),
        detail: j['detail'] as String? ?? '',
        name: j['name'] as String?,
        nameAr: j['nameAr'] as String?,
        position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        bearingDeg: (j['bearingDeg'] as num).toInt(),
      );
}

class Wind {
  const Wind({required this.speedKmh, required this.fromDeg});
  final double speedKmh;

  /// Where the wind comes from (weather convention); the fire is pushed the other way.
  final int fromDeg;
  int get towardDeg => (fromDeg + 180) % 360;
}

class EscapeRoute {
  const EscapeRoute({
    required this.destination,
    required this.destinationKind,
    required this.distanceKm,
    required this.durationMin,
    required this.headingDeg,
    required this.exposureKm,
    required this.safe,
    required this.points,
    this.destinationName,
    this.destinationNameAr,
  });

  final LatLng destination;

  /// A [ResourceKind] name, or null for "straight away from the fire".
  final ResourceKind? destinationKind;
  final String? destinationName, destinationNameAr;
  final double distanceKm;
  final int durationMin;
  final int headingDeg;

  /// Kilometres driven inside a danger area (after first leaving it).
  final double exposureKm;
  final bool safe;
  final List<LatLng> points;

  String? displayName(bool ar) => ar ? (destinationNameAr ?? destinationName) : destinationName;

  factory EscapeRoute.fromJson(Map<String, dynamic> j) {
    final d = j['destination'] as Map<String, dynamic>;
    final kind = d['kind'] as String;
    return EscapeRoute(
      destination: LatLng((d['lat'] as num).toDouble(), (d['lon'] as num).toDouble()),
      destinationKind: kind == 'direction' ? null : _kind(kind),
      destinationName: d['name'] as String?,
      destinationNameAr: d['nameAr'] as String?,
      distanceKm: (j['distanceKm'] as num).toDouble(),
      durationMin: (j['durationMin'] as num).toInt(),
      headingDeg: (j['headingDeg'] as num).toInt(),
      exposureKm: (j['exposureKm'] as num).toDouble(),
      safe: j['safe'] as bool,
      points: [
        for (final p in j['geometry'] as List)
          LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
    );
  }
}

/// `GET /escape`: danger areas around the fires and routes that avoid them.
class EscapePlan {
  const EscapePlan({
    required this.from,
    required this.wind,
    required this.danger,
    required this.startInDanger,
    required this.routes,
  });

  final LatLng from;
  final Wind? wind;
  final List<List<LatLng>> danger;
  final bool startInDanger;

  /// Best first.
  final List<EscapeRoute> routes;

  factory EscapePlan.fromJson(Map<String, dynamic> j) {
    final f = j['from'] as Map<String, dynamic>;
    final w = j['wind'] as Map<String, dynamic>?;
    return EscapePlan(
      from: LatLng((f['lat'] as num).toDouble(), (f['lon'] as num).toDouble()),
      wind: w == null
          ? null
          : Wind(speedKmh: (w['speedKmh'] as num).toDouble(), fromDeg: (w['fromDeg'] as num).toInt()),
      danger: [
        for (final ring in j['danger'] as List)
          [
            for (final p in ring as List)
              LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
      ],
      startInDanger: j['startInDanger'] as bool? ?? false,
      routes: [
        for (final r in j['routes'] as List) EscapeRoute.fromJson(r as Map<String, dynamic>),
      ],
    );
  }
}

/// An answer, and when it was saved if it came from the phone's copy because
/// the server could not be reached.
class Saved<T> {
  const Saved(this.value, {this.savedAt});
  final T value;
  final DateTime? savedAt;
  bool get offline => savedAt != null;
}
