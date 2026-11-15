import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/hotspot.dart';
import '../data/models/region.dart';

class LocationException implements Exception {
  const LocationException(this.messageKey);

  /// A key in lib/l10n/strings.dart.
  final String messageKey;

  @override
  String toString() => messageKey;
}

class LocationService {
  const LocationService();

  /// The position without asking anything: null when location is off or not
  /// allowed yet. Used to keep the last location fresh at app start.
  Future<LatLng?> positionIfAllowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<LatLng> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('loc_off');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException('loc_denied');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LatLng(p.latitude, p.longitude);
  }
}

const _distance = Distance();

double distanceKm(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b) / 1000;

/// Compass direction from [from] to [to]: 0 = N, 1 = NE, ... 7 = NW.
int compassIndex(LatLng from, LatLng to) {
  final bearing = (_distance.bearing(from, to) + 360) % 360;
  return ((bearing + 22.5) ~/ 45) % 8;
}

class RegionMatch {
  const RegionMatch(this.region, {required this.inside, required this.distanceKm});
  final Region region;
  final bool inside;

  /// Distance to the region centre (0 if inside).
  final double distanceKm;
}

/// The region the user is in, or the closest one if they are outside all.
RegionMatch? matchRegion(List<Region> regions, LatLng p) {
  if (regions.isEmpty) return null;
  final inside = regions.where((r) => r.contains(p)).toList();
  if (inside.isNotEmpty) {
    // Several boxes may overlap: pick the one whose centre is closest.
    inside.sort((a, b) =>
        distanceKm(p, a.center).compareTo(distanceKm(p, b.center)));
    return RegionMatch(inside.first, inside: true, distanceKm: 0);
  }
  final sorted = [...regions]
    ..sort((a, b) => distanceKm(p, a.center).compareTo(distanceKm(p, b.center)));
  return RegionMatch(sorted.first,
      inside: false, distanceKm: distanceKm(p, sorted.first.center));
}

class NearestHotspot {
  const NearestHotspot(this.hotspot, this.distanceKm, this.compass);
  final Hotspot hotspot;
  final double distanceKm;
  final int compass;
}

NearestHotspot? nearestHotspot(List<Hotspot> spots, LatLng p) {
  NearestHotspot? best;
  for (final h in spots) {
    final d = distanceKm(p, h.position);
    if (best == null || d < best.distanceKm) {
      best = NearestHotspot(h, d, compassIndex(p, h.position));
    }
  }
  return best;
}
