/// The harmonized fire record for one region. See docs/api_contract.md.
class FireRecord {
  const FireRecord({
    required this.regionId,
    required this.units,
    required this.baselineFrom,
    required this.baselineTo,
    required this.latestYear,
    required this.latestMonth,
    required this.evidence,
    required this.monthly,
    required this.season,
  });

  final String regionId;
  final String units;
  final int baselineFrom, baselineTo;
  final int latestYear, latestMonth;
  final Evidence evidence;
  final List<MonthlyCount> monthly;
  final List<SeasonBand> season; // 12 entries, index 0 = January

  int get firstYear => monthly.first.year;

  MonthlyCount? at(int year, int month) {
    final i = (year - firstYear) * 12 + (month - 1);
    if (i < 0 || i >= monthly.length) return null;
    return monthly[i];
  }

  SeasonBand seasonFor(int month) => season[month - 1];

  factory FireRecord.fromJson(Map<String, dynamic> json) {
    final baseline = json['baseline'] as Map<String, dynamic>;
    final latest = json['latest'] as Map<String, dynamic>;
    final monthly = (json['monthly'] as List)
        .map((e) => MonthlyCount.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.year != b.year ? a.year - b.year : a.month - b.month);
    final season = (json['season'] as List)
        .map((e) => SeasonBand.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.month - b.month);
    return FireRecord(
      regionId: json['regionId'] as String,
      units: json['units'] as String,
      baselineFrom: baseline['from'] as int,
      baselineTo: baseline['to'] as int,
      latestYear: latest['year'] as int,
      latestMonth: latest['month'] as int,
      evidence: Evidence.fromJson(json['evidence'] as Map<String, dynamic>),
      monthly: monthly,
      season: season,
    );
  }
}

enum Sensor { modis, viirs }

class MonthlyCount {
  const MonthlyCount({
    required this.year,
    required this.month,
    required this.sensor,
    required this.raw,
    required this.harmonized,
  });

  final int year, month;
  final Sensor sensor;
  final int raw, harmonized;

  int value({required bool harmonized}) => harmonized ? this.harmonized : raw;

  factory MonthlyCount.fromJson(Map<String, dynamic> json) => MonthlyCount(
        year: json['year'] as int,
        month: json['month'] as int,
        sensor: (json['sensor'] as String).toUpperCase() == 'MODIS'
            ? Sensor.modis
            : Sensor.viirs,
        raw: (json['raw'] as num).round(),
        harmonized: (json['harmonized'] as num).round(),
      );
}

class SeasonBand {
  const SeasonBand({
    required this.month,
    required this.p10,
    required this.median,
    required this.p90,
  });

  final int month;
  final double p10, median, p90;

  factory SeasonBand.fromJson(Map<String, dynamic> json) => SeasonBand(
        month: json['month'] as int,
        p10: (json['p10'] as num).toDouble(),
        median: (json['median'] as num).toDouble(),
        p90: (json['p90'] as num).toDouble(),
      );
}

class Evidence {
  const Evidence({
    required this.method,
    required this.overlapFrom,
    required this.overlapTo,
    required this.ratio,
    required this.heldOutErrorRaw,
    required this.heldOutErrorHarmonized,
  });

  final String method;
  final int overlapFrom, overlapTo;
  final double ratio;
  final double heldOutErrorRaw, heldOutErrorHarmonized;

  factory Evidence.fromJson(Map<String, dynamic> json) {
    final overlap = (json['overlapYears'] as List).cast<int>();
    return Evidence(
      method: json['method'] as String,
      overlapFrom: overlap[0],
      overlapTo: overlap[1],
      ratio: (json['ratio'] as num).toDouble(),
      heldOutErrorRaw: (json['heldOutErrorRaw'] as num).toDouble(),
      heldOutErrorHarmonized: (json['heldOutErrorHarmonized'] as num).toDouble(),
    );
  }
}
