import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../widgets/calendar_heatmap.dart';
import '../widgets/common.dart';

/// Burning calendar (year × month) with the seam toggle.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  bool _harmonized = true;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('burning_calendar'))),
      body: Column(
        children: [
          const RegionChips(),
          const SizedBox(height: 8),
          Expanded(
            child: RecordLoader(
              builder: (context, region, record) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(s.t('raw_sensors'))),
                      ButtonSegment(value: true, label: Text(s.t('harmonized'))),
                    ],
                    selected: {_harmonized},
                    onSelectionChanged: (v) => setState(() => _harmonized = v.first),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: s.t('the_seam'),
                    subtitle: s.t(_harmonized ? 'seam_fixed' : 'seam_raw'),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: YearlyBars(record: record, harmonized: _harmonized),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '${record.firstYear}–${record.latestYear}',
                    subtitle: s.t('tap_month'),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: CalendarHeatmap(
                        record: record,
                        harmonized: _harmonized,
                        monthLabels: s.monthLetters,
                        onCellTap: (c) => _showCell(context, record, c),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ScaleLegend(s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCell(BuildContext context, FireRecord record, MonthlyCount c) {
    final s = S.of(context);
    final sum = summarize(record, year: c.year, month: c.month);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Ember.surface,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${s.month(c.month)} ${c.year}',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                StatusPill(
                  label: s.status(sum.status),
                  color: Ember.forStatus(sum.status),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(s.t('sensor'), c.sensor == Sensor.modis ? 'MODIS' : 'VIIRS'),
            _row(s.t('raw_count'), '${c.raw}'),
            _row(s.t('harmonized'), '${c.harmonized}'),
            _row(s.t('usual_median'), sum.median.round().toString()),
            _row(s.t('vs_usual'), '${sum.ratio.toStringAsFixed(2)}×'),
            _row(s.t('rank'), '#${sum.rank} / ${sum.yearsCompared}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k, style: monoStyle(size: 13))),
            Text(v, style: monoStyle(size: 13, color: Ember.text)),
          ],
        ),
      );
}

class _ScaleLegend extends StatelessWidget {
  const _ScaleLegend(this.s);
  final S s;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(s.t('less'), style: monoStyle(size: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [for (var i = 0; i <= 10; i++) Ember.heat(i / 10)],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(s.t('more_fire'), style: monoStyle(size: 11)),
        ],
      );
}
