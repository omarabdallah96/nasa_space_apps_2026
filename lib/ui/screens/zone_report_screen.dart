import 'package:flutter/material.dart';

import '../../data/models/danger_forecast.dart';
import '../../data/models/fire_record.dart';
import '../../data/models/hotspot.dart';
import '../../data/models/region.dart';
import '../../data/models/zone.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/calendar_heatmap.dart';
import '../widgets/common.dart';
import '../widgets/season_chart.dart';
import 'paywall.dart';

/// Opens the report for a zone, or the paywall for free users.
Future<void> openZoneReport(BuildContext context, AlertZone zone) async {
  if (!AppScope.read(context).isPro) {
    final pro = await showPaywall(context, reasonKey: 'pro_reason_report');
    if (!pro || !context.mounted) return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ZoneReportScreen(zone: zone)),
  );
}

class _ReportData {
  const _ReportData({
    required this.region,
    required this.record,
    required this.fires,
    required this.forecast,
  });
  final Region region;
  final FireRecord record;

  /// Satellite detections inside the circle in the last 48 h; null when unavailable.
  final List<Hotspot>? fires;
  final DangerForecast? forecast;
}

/// The zone's own fire history (25 years, harmonized), what is burning in it
/// now, and its fire danger for the week. A Pro feature.
class ZoneReportScreen extends StatefulWidget {
  const ZoneReportScreen({super.key, required this.zone});
  final AlertZone zone;

  @override
  State<ZoneReportScreen> createState() => _ZoneReportScreenState();
}

class _ZoneReportScreenState extends State<ZoneReportScreen> {
  late Future<_ReportData> _future = _load();

  Future<_ReportData> _load() async {
    final state = AppScope.read(context);
    final z = widget.zone;
    final match = matchRegion(state.regions, z.center);
    if (match == null) throw StateError('No region');
    final b = z.bbox;
    final record = await state.repository
        .getAreaRecord(match.region.id, west: b.west, south: b.south, east: b.east, north: b.north);
    List<Hotspot>? fires;
    try {
      fires = (await state.repository.getRecentHotspots(match.region.id))
          .where((h) => h.confidence != 'low' && z.contains(h.position))
          .toList();
    } catch (_) {}
    DangerForecast? forecast;
    try {
      forecast = await state.repository.getDangerForecast(z.center);
    } catch (_) {}
    return _ReportData(region: match.region, record: record, fires: fires, forecast: forecast);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final z = widget.zone;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(z.name),
          Text('${s.t('zone_report')} · ${z.radiusKm.round()} ${s.t('km')}',
              style: TextStyle(fontSize: 12, color: Ember.textMuted)),
        ]),
      ),
      body: FutureBuilder<_ReportData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() => _future = _load()));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Ember.ember));
          }
          return _Report(zone: z, data: snap.data!);
        },
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.zone, required this.data});
  final AlertZone zone;
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final record = data.record;
    final summary = summarize(record);
    // The sentence names the zone, not the country.
    final place = Region(
      id: data.region.id,
      name: zone.name,
      nameAr: zone.name,
      west: data.region.west,
      south: data.region.south,
      east: data.region.east,
      north: data.region.north,
      center: zone.center,
    );
    final totals = yearlyTotals(record, harmonized: true);
    final complete = totals.entries.where((e) => e.key < record.latestYear).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final average = complete.isEmpty
        ? 0
        : complete.map((e) => e.value).reduce((a, b) => a + b) / complete.length;
    final critical = criticalMonths(record);
    final fires = data.fires;
    final nearest = fires == null ? null : nearestHotspot(fires, zone.center);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── This month ──
        SectionCard(
          title: s.t('zone_now'),
          trailing: StatusPill(label: s.status(summary.status), color: Ember.forStatus(summary.status)),
          child: Text(s.sentence(summary, place), style: text.bodyLarge?.copyWith(height: 1.4)),
        ),
        const SizedBox(height: 12),

        // ── Key numbers ──
        Row(children: [
          _Stat(
            value: fires == null ? '—' : '${fires.length}',
            label: s.t('zone_fires_48h'),
            color: (fires?.isNotEmpty ?? false) ? Ember.extreme : Ember.calm,
          ),
          const SizedBox(width: 8),
          _Stat(value: average.round().toString(), label: s.t('zone_avg_year')),
          const SizedBox(width: 8),
          _Stat(
            value: complete.isEmpty ? '—' : '${complete.first.key}',
            label: s.t('zone_worst_year'),
          ),
        ]),
        if (nearest != null) ...[
          const SizedBox(height: 8),
          Text(
            '${s.t('zone_nearest')}: ${nearest.distanceKm.toStringAsFixed(1)} ${s.t('km')} ${s.compass(nearest.compass)}',
            style: text.bodySmall?.copyWith(color: Ember.textMuted),
          ),
        ],
        const SizedBox(height: 12),

        // ── Danger this week ──
        if (data.forecast != null) ...[
          SectionCard(
            title: s.t('zone_danger_week'),
            child: Row(children: [
              for (final d in data.forecast!.days.take(7))
                Expanded(
                  child: Column(children: [
                    Text(s.weekdayShort(d.date.weekday), style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      height: 26,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Ember.forDanger(d.level),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(d.fwi.round().toString(), style: monoStyle(size: 10)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // ── Season ──
        SectionCard(
          title: s.t('zone_season'),
          subtitle: critical.isEmpty
              ? null
              : '${s.t('zone_critical')}: ${critical.map(s.month).join(' · ')}',
          child: SeasonChart(
            record: record,
            monthLabels: s.monthLetters,
            rangeLabel: s.t('normal_range'),
            medianLabel: s.t('median'),
            height: 170,
          ),
        ),
        const SizedBox(height: 12),

        // ── Every year ──
        SectionCard(
          title: s.t('zone_years'),
          subtitle: '${record.monthly.first.year}–${record.latestYear}',
          child: YearlyBars(record: record, harmonized: true),
        ),
        const SizedBox(height: 12),
        if (complete.length >= 3)
          SectionCard(
            title: s.t('zone_top_years'),
            child: Column(children: [
              for (final (i, e) in complete.take(3).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Text('${i + 1}.', style: monoStyle(size: 13)),
                    const SizedBox(width: 10),
                    Text('${e.key}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${e.value} ${s.t('zone_cells')}', style: monoStyle(size: 12)),
                  ]),
                ),
            ]),
          ),
        const SizedBox(height: 16),
        Text(s.t('zone_report_note'), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: color ?? Ember.text)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Ember.textMuted)),
            ]),
          ),
        ),
      );
}
