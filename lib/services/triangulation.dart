import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'location_service.dart';
import 'report_store.dart';

/// A fire location estimated from 2+ ground reports that point at the same
/// smoke from different places: where their compass lines cross.
class SmokeEstimate {
  const SmokeEstimate({
    required this.center,
    required this.radiusKm,
    required this.reports,
    required this.latest,
  });

  final LatLng center;

  /// Rough uncertainty: spread of the crossings plus compass error.
  final double radiusKm;
  final List<FieldReport> reports;
  final DateTime latest;
}

/// Where two compass lines cross, in a local flat projection (fine for the
/// tens of kilometres involved).
class _Crossing {
  _Crossing(this.point, this.a, this.b, this.rangeKm);
  final LatLng point;
  final FieldReport a, b;
  final double rangeKm; // mean distance from the two observers
}

const _kmPerDegLat = 110.574;
double _kmPerDegLon(double lat) => 111.320 * math.cos(lat * math.pi / 180);

_Crossing? _intersect(FieldReport a, FieldReport b,
    {required double maxRangeKm, required double minAngleDeg}) {
  final lat0 = (a.position.latitude + b.position.latitude) / 2;
  final kx = _kmPerDegLon(lat0);
  // Observer B relative to A, in km (x = east, y = north).
  final px = (b.position.longitude - a.position.longitude) * kx;
  final py = (b.position.latitude - a.position.latitude) * _kmPerDegLat;
  if (math.sqrt(px * px + py * py) < 0.3) return null; // same spot

  // Bearings: degrees clockwise from north → unit vectors.
  final t1 = a.bearing! * math.pi / 180, t2 = b.bearing! * math.pi / 180;
  final d1x = math.sin(t1), d1y = math.cos(t1);
  final d2x = math.sin(t2), d2y = math.cos(t2);

  final cross = d1x * d2y - d1y * d2x;
  if (cross.abs() < math.sin(minAngleDeg * math.pi / 180)) return null; // ~parallel

  // A + s·d1 = B + u·d2
  final s = (px * d2y - py * d2x) / cross;
  final u = (px * d1y - py * d1x) / cross;
  if (s <= 0 || u <= 0) return null; // behind one of the observers
  if (s > maxRangeKm || u > maxRangeKm) return null;

  final x = s * d1x, y = s * d1y;
  final point = LatLng(
    a.position.latitude + y / _kmPerDegLat,
    a.position.longitude + x / kx,
  );
  return _Crossing(point, a, b, (s + u) / 2);
}

/// Groups compass-line crossings into fire estimates, biggest first.
///
/// Only recent reports with a locked compass bearing are used. A real
/// deployment would gather reports from many phones via the backend; on one
/// phone it also works by reporting the same smoke from two places.
List<SmokeEstimate> triangulate(
  List<FieldReport> reports, {
  DateTime? now,
  Duration window = const Duration(hours: 12),
  double maxRangeKm = 40,
  double minAngleDeg = 12,
  double clusterKm = 5,
  double compassErrorDeg = 5,
}) {
  final t = now ?? DateTime.now();
  final usable = reports
      .where((r) => r.bearing != null && t.difference(r.createdAt) <= window)
      .toList();

  final crossings = <_Crossing>[];
  for (var i = 0; i < usable.length; i++) {
    for (var j = i + 1; j < usable.length; j++) {
      final c = _intersect(usable[i], usable[j],
          maxRangeKm: maxRangeKm, minAngleDeg: minAngleDeg);
      if (c != null) crossings.add(c);
    }
  }

  // Greedy clustering of crossings.
  final clusters = <List<_Crossing>>[];
  for (final c in crossings) {
    List<_Crossing>? home;
    for (final cl in clusters) {
      if (distanceKm(_centroid(cl), c.point) <= clusterKm) {
        home = cl;
        break;
      }
    }
    home == null ? clusters.add([c]) : home.add(c);
  }

  final estimates = [
    for (final cl in clusters)
      () {
        final center = _centroid(cl);
        final spread = cl.map((c) => distanceKm(center, c.point)).reduce(math.max);
        final meanRange = cl.map((c) => c.rangeKm).reduce((a, b) => a + b) / cl.length;
        final compass = meanRange * math.tan(compassErrorDeg * math.pi / 180);
        final members = {for (final c in cl) ...[c.a, c.b]}.toList();
        return SmokeEstimate(
          center: center,
          radiusKm: math.max(0.5, math.max(spread, compass)),
          reports: members,
          latest: members.map((r) => r.createdAt).reduce((a, b) => a.isAfter(b) ? a : b),
        );
      }(),
  ]..sort((a, b) => b.reports.length.compareTo(a.reports.length));
  return estimates;
}

LatLng _centroid(List<_Crossing> cl) => LatLng(
      cl.map((c) => c.point.latitude).reduce((a, b) => a + b) / cl.length,
      cl.map((c) => c.point.longitude).reduce((a, b) => a + b) / cl.length,
    );

/// Point [km] away from [from] along [bearingDeg] (for drawing the lines).
LatLng project(LatLng from, double bearingDeg, double km) =>
    const Distance().offset(from, km * 1000, bearingDeg);

/// Demo: three observers around a hypothetical fire, each pointing at it with
/// a few degrees of compass error. Lets the feature be shown on one phone.
List<FieldReport> demoSmokeReports({DateTime? now}) {
  final t = now ?? DateTime.now();
  const fire = LatLng(33.705, 35.535); // hills east of Damour, Lebanon
  const observers = [
    (LatLng(33.888, 35.495), 2.5), // Beirut
    (LatLng(33.563, 35.375), -3.0), // Saida
    (LatLng(33.808, 35.600), 4.0), // Aley
  ];
  return [
    for (final (i, (p, error)) in observers.indexed)
      FieldReport(
        id: 'demo_${t.millisecondsSinceEpoch}_$i',
        position: p,
        createdAt: t.subtract(Duration(minutes: 10 * i)),
        label: ReportLabel.smoke,
        note: 'Demo',
        bearing: (const Distance().bearing(p, fire) + error + 360) % 360,
      ),
  ];
}
