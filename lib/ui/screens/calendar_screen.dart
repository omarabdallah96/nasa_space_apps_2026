import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../domain/anomaly.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Burning calendar')),
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
                    segments: const [
                      ButtonSegment(value: false, label: Text('Raw sensors')),
                      ButtonSegment(value: true, label: Text('Harmonized')),
                    ],
                    selected: {_harmonized},
                    onSelectionChanged: (s) => setState(() => _harmonized = s.first),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'The seam',
                    subtitle: _harmonized
                        ? 'One fair record: MODIS years converted to VIIRS-equivalent'
                        : 'Raw counts jump in 2012 — only because VIIRS has sharper eyes',
                    child: YearlyBars(record: record, harmonized: _harmonized),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '${record.firstYear}–${record.latestYear}',
                    subtitle: 'Tap a month to see its numbers',
                    child: CalendarHeatmap(
                      record: record,
                      harmonized: _harmonized,
                      onCellTap: (c) => _showCell(context, record, c),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _ScaleLegend(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCell(BuildContext context, FireRecord record, MonthlyCount c) {
    final s = summarize(record, year: c.year, month: c.month);
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
                Text('${monthNames[c.month - 1]} ${c.year}',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                StatusPill(
                  label: Ember.labelForStatus(s.status),
                  color: Ember.forStatus(s.status),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Sensor', c.sensor == Sensor.modis ? 'MODIS' : 'VIIRS'),
            _row('Raw count', '${c.raw}'),
            _row('Harmonized', '${c.harmonized}'),
            _row('Usual (median)', s.median.round().toString()),
            _row('vs usual', '${s.ratio.toStringAsFixed(2)}×'),
            _row('Rank', '#${s.rank} of ${s.yearsCompared}'),
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
  const _ScaleLegend();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Less', style: monoStyle(size: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [for (var i = 0; i <= 10; i++) Ember.heat(i / 10)],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('More fire', style: monoStyle(size: 11)),
        ],
      );
}
