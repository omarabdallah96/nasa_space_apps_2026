import '../data/models/fire_record.dart';

enum FireStatus { below, normal, above, extreme }

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const monthShort = [
  'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D',
];

/// "Is this fire season normal?" for one month of one region.
class AnomalySummary {
  const AnomalySummary({
    required this.year,
    required this.month,
    required this.value,
    required this.median,
    required this.ratio,
    required this.rank,
    required this.yearsCompared,
    required this.status,
  });

  final int year, month;
  final int value;
  final double median;

  /// value / median of the baseline. 1.0 = exactly usual.
  final double ratio;

  /// 1 = highest of all years for this calendar month.
  final int rank;
  final int yearsCompared;
  final FireStatus status;

  String get monthName => monthNames[month - 1];

  /// The one-sentence answer shown at the top of the home screen.
  String sentence(String regionName) {
    final comparison = switch (status) {
      FireStatus.below => ratio < 0.05
          ? 'almost no fire activity'
          : 'below the usual level (${_pct(ratio)} of normal)',
      FireStatus.normal => 'within the normal range (${_ratio(ratio)} the usual level)',
      FireStatus.above => '${_ratio(ratio)} the usual level',
      FireStatus.extreme => '${_ratio(ratio)} the usual level — extreme',
    };
    return '$monthName $year in $regionName: $comparison. '
        '${_ordinal(rank)} highest $monthName of $yearsCompared years.';
  }

  static String _ratio(double r) => '${r.toStringAsFixed(1)}×';
  static String _pct(double r) => '${(r * 100).round()}%';
}

String _ordinal(int n) {
  if (n == 1) return 'The';
  final mod100 = n % 100;
  final suffix = (mod100 >= 11 && mod100 <= 13)
      ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$suffix';
}

/// Compares one month with the baseline band and ranks it against all years.
AnomalySummary summarize(FireRecord record, {int? year, int? month}) {
  final y = year ?? record.latestYear;
  final m = month ?? record.latestMonth;
  final current = record.at(y, m);
  if (current == null) {
    throw ArgumentError('No data for $y-$m in ${record.regionId}');
  }

  final band = record.seasonFor(m);
  final value = current.harmonized;
  final ratio = band.median <= 0 ? 0.0 : value / band.median;

  final sameMonth = record.monthly.where((c) => c.month == m).toList();
  final rank = 1 + sameMonth.where((c) => c.harmonized > value).length;

  final status = value > band.p90
      ? (ratio >= 2.0 ? FireStatus.extreme : FireStatus.above)
      : value < band.p10
          ? FireStatus.below
          : FireStatus.normal;

  return AnomalySummary(
    year: y,
    month: m,
    value: value,
    median: band.median,
    ratio: ratio,
    rank: rank,
    yearsCompared: sameMonth.length,
    status: status,
  );
}

/// Months whose typical (median) activity is at least [share] of the peak
/// month. This is the region's critical period.
List<int> criticalMonths(FireRecord record, {double share = 0.5}) {
  final peak = record.season.map((s) => s.median).reduce((a, b) => a > b ? a : b);
  return [
    for (final s in record.season)
      if (peak > 0 && s.median >= peak * share) s.month,
  ];
}

/// Yearly harmonized (or raw) totals, used by the seam view and Fire Rings.
Map<int, int> yearlyTotals(FireRecord record, {required bool harmonized}) {
  final totals = <int, int>{};
  for (final c in record.monthly) {
    totals[c.year] = (totals[c.year] ?? 0) + c.value(harmonized: harmonized);
  }
  return totals;
}
