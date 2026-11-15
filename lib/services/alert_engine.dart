import 'package:latlong2/latlong.dart';

import '../data/models/danger_forecast.dart';
import '../data/models/fire_record.dart';
import '../data/models/hotspot.dart';
import '../data/models/region.dart';
import '../domain/anomaly.dart';
import 'location_service.dart';

enum AlertType { anomaly, seasonSoon, inSeason, nearbyHotspot, detections, groundSmoke, dangerForecast }

enum AlertLevel { info, warning, danger }

/// One alert for one watched region. The text is built by the UI from these
/// fields, so it can be shown in English or Arabic.
class FireAlert {
  const FireAlert({
    required this.type,
    required this.level,
    required this.region,
    this.summary,
    this.month,
    this.days,
    this.lastYearRatio,
    this.count,
    this.distanceKm,
    this.compass,
    this.estimateKey,
    this.danger,
    this.date,
  });

  final AlertType type;
  final AlertLevel level;
  final Region region;
  final AnomalySummary? summary;
  final int? month; // season start / end month
  final int? days; // days until the season starts
  final double? lastYearRatio;
  final int? count;
  final double? distanceKm;
  final int? compass;

  /// Rounded position of a ground-smoke estimate (for a stable id).
  final String? estimateKey;

  /// Forecast fire danger, and the day it is forecast for.
  final DangerLevel? danger;
  final DateTime? date;

  /// Stable id, used so the same alert is not notified twice.
  String get id => '${type.name}_${region.id}_${summary?.year ?? ''}'
      '${summary?.month ?? ''}_${month ?? ''}_${count ?? ''}_${estimateKey ?? ''}'
      '${danger == null ? '' : '_${danger!.name}_${date!.year}-${date!.month}-${date!.day}'}';
}

/// Turns the harmonized record into early-warning alerts.
class AlertEngine {
  const AlertEngine({this.seasonWarningDays = 30, this.nearbyKm = 25, this.dangerDays = 3});

  /// Forecast danger alerts look this many days ahead, today included.
  final int dangerDays;

  /// Warn this many days before the critical period starts.
  final int seasonWarningDays;

  /// Hotspots closer than this to the user trigger an alert.
  final double nearbyKm;

  List<FireAlert> evaluate({
    required Region region,
    required FireRecord record,
    required List<Hotspot> hotspots,
    required DateTime now,
    LatLng? user,
  }) {
    final alerts = <FireAlert>[];

    // 1. The latest month is above normal.
    final s = summarize(record);
    if (s.status == FireStatus.above || s.status == FireStatus.extreme) {
      alerts.add(FireAlert(
        type: AlertType.anomaly,
        level: s.status == FireStatus.extreme ? AlertLevel.danger : AlertLevel.warning,
        region: region,
        summary: s,
      ));
    }

    // 2. Critical period: starting soon, or already running.
    final critical = criticalMonths(record).toSet();
    if (critical.isNotEmpty && critical.length < 12) {
      if (critical.contains(now.month)) {
        var end = now.month;
        while (critical.contains(end % 12 + 1) && end % 12 + 1 != now.month) {
          end = end % 12 + 1;
        }
        alerts.add(FireAlert(
          type: AlertType.inSeason,
          level: AlertLevel.warning,
          region: region,
          month: end,
        ));
      } else {
        final start = _nextSeasonStart(critical, now);
        final days = start.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (days <= seasonWarningDays) {
          final lastYear = record.at(start.year - 1, start.month);
          final median = record.seasonFor(start.month).median;
          alerts.add(FireAlert(
            type: AlertType.seasonSoon,
            level: AlertLevel.info,
            region: region,
            month: start.month,
            days: days,
            lastYearRatio: lastYear == null || median <= 0
                ? null
                : lastYear.harmonized / median,
          ));
        }
      }
    }

    // 3. Recent detections: near the user, or many in the region.
    final confident = hotspots.where((h) => h.confidence != 'low').toList();
    final near = user == null ? null : nearestHotspot(confident, user);
    if (near != null && near.distanceKm <= nearbyKm) {
      alerts.add(FireAlert(
        type: AlertType.nearbyHotspot,
        level: near.distanceKm <= 5 ? AlertLevel.danger : AlertLevel.warning,
        region: region,
        distanceKm: near.distanceKm,
        compass: near.compass,
      ));
    } else if (confident.isNotEmpty) {
      alerts.add(FireAlert(
        type: AlertType.detections,
        level: AlertLevel.info,
        region: region,
        count: confident.length,
      ));
    }

    return alerts;
  }

  /// Very high or extreme fire danger forecast in the next [dangerDays] days.
  /// [days] is the forecast near the user (pass [nearUser]) or the region's
  /// headline. One alert per place: the worst of those days.
  FireAlert? dangerAlert({
    required Region region,
    required List<DangerDay> days,
    required DateTime now,
    bool nearUser = false,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    DangerDay? worst;
    for (final d in days) {
      final ahead = d.date.difference(today).inDays;
      if (ahead < 0 || ahead >= dangerDays) continue;
      if (worst == null || d.level.index > worst.level.index) worst = d;
    }
    if (worst == null || worst.level.index < DangerLevel.veryHigh.index) return null;
    return FireAlert(
      type: AlertType.dangerForecast,
      level: worst.level == DangerLevel.extreme ? AlertLevel.danger : AlertLevel.warning,
      region: region,
      danger: worst.level,
      date: worst.date,
      days: worst.date.difference(today).inDays,
      distanceKm: nearUser ? 0 : null,
    );
  }

  /// First day of the next month that starts a critical period.
  static DateTime _nextSeasonStart(Set<int> critical, DateTime now) {
    for (var i = 1; i <= 12; i++) {
      final m = (now.month - 1 + i) % 12 + 1;
      final prev = (m + 10) % 12 + 1;
      if (critical.contains(m) && !critical.contains(prev)) {
        final year = now.year + ((now.month - 1 + i) ~/ 12);
        return DateTime(year, m, 1);
      }
    }
    return DateTime(now.year + 1, now.month, 1);
  }
}
