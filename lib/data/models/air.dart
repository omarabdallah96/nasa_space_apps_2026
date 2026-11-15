/// Air quality at a point (`GET /air`), from the Copernicus CAMS model via
/// the backend. The server writes the words (label, headline, advice, tips)
/// in the asked language, so the app and the website give the same advice.
enum AirLevel {
  good,
  moderate,
  sensitive,
  unhealthy,
  veryUnhealthy,
  hazardous;

  static AirLevel fromApi(String? s) => switch (s) {
        'good' => good,
        'moderate' => moderate,
        'sensitive' => sensitive,
        'unhealthy' => unhealthy,
        'very-unhealthy' => veryUnhealthy,
        'hazardous' => hazardous,
        _ => moderate,
      };
}

class AirPollutant {
  const AirPollutant({required this.key, required this.value, required this.aqi, required this.level});

  /// The API name: pm2_5, pm10, carbon_monoxide, nitrogen_dioxide, ozone, sulphur_dioxide.
  final String key;

  /// µg/m³.
  final double value;
  final int? aqi;
  final AirLevel level;
}

class AirHour {
  const AirHour(this.time, this.aqi);
  final DateTime time;
  final int? aqi;
}

class AirQuality {
  const AirQuality({
    required this.aqi,
    required this.level,
    required this.safe,
    required this.main,
    required this.label,
    required this.headline,
    required this.advice,
    required this.pollutants,
    required this.hours,
    this.peakAqi,
    this.peakAt,
    this.peakLevel,
    this.co2Ppm,
    this.co2Note,
    this.smokeTips = const [],
    this.indoorTips = const [],
    this.source = '',
    this.note = '',
  });

  final int aqi;
  final AirLevel level;
  final bool safe;

  /// The pollutant that sets the index.
  final String? main;
  final String label;
  final String headline;
  final List<String> advice;
  final List<AirPollutant> pollutants;
  final List<AirHour> hours;
  final int? peakAqi;
  final DateTime? peakAt;
  final AirLevel? peakLevel;
  final int? co2Ppm;
  final String? co2Note;
  final List<String> smokeTips;
  final List<String> indoorTips;
  final String source;
  final String note;

  /// The next 24 hours get worse than now.
  bool get worsening => peakAqi != null && peakLevel != null && peakLevel!.index > level.index;

  static List<String> _strings(Object? v) => [for (final e in (v as List?) ?? const []) e as String];

  /// Times come in the place's local time without an offset; kept as-is.
  static DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory AirQuality.fromJson(Map<String, dynamic> j) {
    final pol = (j['pollutants'] as Map<String, dynamic>?) ?? const {};
    final next = j['next24h'] as Map<String, dynamic>?;
    final co2 = j['co2'] as Map<String, dynamic>?;
    final tips = j['tips'] as Map<String, dynamic>?;
    return AirQuality(
      aqi: (j['usAqi'] as num?)?.round() ?? 0,
      level: AirLevel.fromApi(j['level'] as String?),
      safe: j['safe'] as bool? ?? true,
      main: j['main'] as String?,
      label: j['label'] as String? ?? '',
      headline: j['headline'] as String? ?? '',
      advice: _strings(j['advice']),
      pollutants: [
        for (final e in pol.entries)
          if (e.value is Map && (e.value as Map)['value'] is num)
            AirPollutant(
              key: e.key,
              value: ((e.value as Map)['value'] as num).toDouble(),
              aqi: ((e.value as Map)['aqi'] as num?)?.round(),
              level: AirLevel.fromApi((e.value as Map)['level'] as String?),
            ),
      ],
      hours: [
        for (final h in (next?['hours'] as List?) ?? const [])
          if (_time((h as Map)['time']) != null) AirHour(_time(h['time'])!, (h['usAqi'] as num?)?.round()),
      ],
      peakAqi: (next?['peakAqi'] as num?)?.round(),
      peakAt: _time(next?['peakAt']),
      peakLevel: next?['peakLevel'] == null ? null : AirLevel.fromApi(next!['peakLevel'] as String),
      co2Ppm: (co2?['ppm'] as num?)?.round(),
      co2Note: co2?['note'] as String?,
      smokeTips: _strings(tips?['smoke']),
      indoorTips: _strings(tips?['indoor']),
      source: j['source'] as String? ?? '',
      note: j['note'] as String? ?? '',
    );
  }
}
