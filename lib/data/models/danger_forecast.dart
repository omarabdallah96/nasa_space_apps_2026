import 'package:latlong2/latlong.dart';

/// EFFIS fire danger classes of the Fire Weather Index (FWI).
enum DangerLevel {
  veryLow,
  low,
  moderate,
  high,
  veryHigh,
  extreme;

  /// The backend writes `very_low`, `very_high`, ...
  static DangerLevel fromApi(String s) => switch (s) {
        'very_low' => veryLow,
        'low' => low,
        'moderate' => moderate,
        'high' => high,
        'very_high' => veryHigh,
        'extreme' => extreme,
        _ => moderate,
      };

  /// EFFIS class limits.
  static DangerLevel fromFwi(double fwi) => fwi >= 50
      ? extreme
      : fwi >= 38
          ? veryHigh
          : fwi >= 21.3
              ? high
              : fwi >= 11.2
                  ? moderate
                  : fwi >= 5.2
                      ? low
                      : veryLow;

  bool get isHighOrAbove => index >= high.index;
}

DateTime _date(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// What the 25-year record says is usual on this date in the country.
class UsualActivity {
  const UsualActivity({
    required this.cellDaysPerDay,
    required this.shareOfPeak,
    required this.inPeakSeason,
  });

  /// Median active-fire cell-days per day on this date.
  final double cellDaysPerDay;

  /// That median as a share of the busiest time of year, 0–1.
  final double shareOfPeak;
  final bool inPeakSeason;

  factory UsualActivity.fromJson(Map<String, dynamic> j) => UsualActivity(
        cellDaysPerDay: _d(j['cellDaysPerDay']),
        shareOfPeak: _d(j['shareOfPeak']),
        inPeakSeason: j['inPeakSeason'] == true,
      );
}

/// Noon weather that went into the index.
class NoonWeather {
  const NoonWeather({
    required this.temperatureC,
    required this.humidity,
    required this.windKmh,
    required this.rainMm,
  });
  final double temperatureC, humidity, windKmh, rainMm;

  factory NoonWeather.fromJson(Map<String, dynamic> j) => NoonWeather(
        temperatureC: _d(j['tempC']),
        humidity: _d(j['humidity']),
        windKmh: _d(j['windKmh']),
        rainMm: _d(j['rainMm']),
      );
}

/// One day of the forecast at one place.
class DangerDay {
  const DangerDay({
    required this.date,
    required this.level,
    required this.fwi,
    required this.usual,
    this.weather,
    this.drought,
  });

  final DateTime date;
  final DangerLevel level;
  final double fwi;
  final UsualActivity usual;
  final NoonWeather? weather;

  /// Drought Code: how dry the deep ground is (0 – 800+, above ~300 is dry).
  final double? drought;

  factory DangerDay.fromJson(Map<String, dynamic> j) => DangerDay(
        date: _date(j['date'] as String),
        level: DangerLevel.fromApi(j['level'] as String),
        fwi: _d(j['fwi']),
        usual: UsualActivity.fromJson(
            (j['usualInCountry'] ?? j['usual']) as Map<String, dynamic>),
        weather: j['weather'] == null
            ? null
            : NoonWeather.fromJson(j['weather'] as Map<String, dynamic>),
        drought: (j['components'] as Map<String, dynamic>?)?['dc'] == null
            ? null
            : _d((j['components'] as Map<String, dynamic>)['dc']),
      );
}

/// Fire danger at one place for the coming days (`GET /forecast?lat=&lon=`).
class DangerForecast {
  const DangerForecast({
    required this.regionId,
    required this.point,
    required this.generatedAt,
    required this.days,
  });

  final String regionId;

  /// The forecast grid point used.
  final LatLng point;
  final DateTime generatedAt;
  final List<DangerDay> days;

  factory DangerForecast.fromJson(Map<String, dynamic> j) {
    final p = j['point'] as Map<String, dynamic>;
    return DangerForecast(
      regionId: (j['country'] as Map<String, dynamic>)['slug'] as String,
      point: LatLng(_d(p['lat']), _d(p['lon'])),
      generatedAt: DateTime.parse(j['generatedAt'] as String),
      days: (j['days'] as List)
          .map((e) => DangerDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The most dangerous of the first [within] days (today first).
  DangerDay? worst({int within = 7}) {
    DangerDay? best;
    for (final d in days.take(within)) {
      if (best == null || d.fwi > best.fwi) best = d;
    }
    return best;
  }
}

/// One grid point of a country forecast, for the map.
class DangerPoint {
  const DangerPoint(this.position, this.levels, this.fwi);
  final LatLng position;
  final List<DangerLevel> levels;
  final List<double> fwi;
}

/// Fire danger over a whole country (`GET /countries/{id}/forecast`).
class RegionDanger {
  const RegionDanger({
    required this.regionId,
    required this.generatedAt,
    required this.days,
    required this.highShare,
    required this.points,
    required this.stepDegrees,
  });

  final String regionId;
  final DateTime generatedAt;

  /// Headline per day: the level of the most dangerous tenth of the country.
  final List<DangerDay> days;

  /// Share of the country at high or above, per day.
  final List<double> highShare;
  final List<DangerPoint> points;
  final double stepDegrees;

  factory RegionDanger.fromJson(Map<String, dynamic> j) {
    final days = <DangerDay>[];
    final shares = <double>[];
    for (final e in (j['days'] as List).cast<Map<String, dynamic>>()) {
      final fwi = e['fwi'] as Map<String, dynamic>;
      days.add(DangerDay(
        date: _date(e['date'] as String),
        level: DangerLevel.fromApi(e['level'] as String),
        fwi: _d(fwi['p90']),
        usual: UsualActivity.fromJson(e['usual'] as Map<String, dynamic>),
      ));
      shares.add(_d((e['areaShare'] as Map<String, dynamic>)['highOrAbove']));
    }
    return RegionDanger(
      regionId: (j['country'] as Map<String, dynamic>)['slug'] as String,
      generatedAt: DateTime.parse(j['generatedAt'] as String),
      days: days,
      highShare: shares,
      stepDegrees: _d((j['grid'] as Map<String, dynamic>)['stepDegrees']),
      points: [
        for (final p in (j['points'] as List).cast<Map<String, dynamic>>())
          DangerPoint(
            LatLng(_d(p['lat']), _d(p['lon'])),
            (p['level'] as List).map((l) => DangerLevel.fromApi(l as String)).toList(),
            (p['fwi'] as List).map(_d).toList(),
          ),
      ],
    );
  }
}
