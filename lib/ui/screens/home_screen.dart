import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fire_rings.dart';
import '../widgets/season_chart.dart';

/// "Is this fire season normal?" — the one-sentence answer, Fire Rings,
/// season chart and evidence for the selected region.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ember Almanac')),
      body: Column(
        children: [
          const RegionChips(),
          const SizedBox(height: 8),
          Expanded(
            child: RecordLoader(
              builder: (context, region, record) => _HomeBody(region, record),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody(this.region, this.record);
  final Region region;
  final FireRecord record;

  @override
  Widget build(BuildContext context) {
    final summary = summarize(record);
    final critical = criticalMonths(record);
    final text = Theme.of(context).textTheme;
    final statusColor = Ember.forStatus(summary.status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // The answer.
        Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [statusColor.withValues(alpha: 0.16), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Is this fire season normal?',
                        style: text.labelLarge?.copyWith(color: Ember.textMuted)),
                    const Spacer(),
                    StatusPill(
                      label: Ember.labelForStatus(summary.status),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(summary.sentence(region.name),
                    style: text.headlineSmall?.copyWith(height: 1.3)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(label: 'This month', value: '${summary.value}'),
                    _Stat(label: 'Usual', value: summary.median.round().toString()),
                    _Stat(label: 'Rank', value: '#${summary.rank} / ${summary.yearsCompared}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Fire Rings',
          subtitle: 'One ring per year, read it like a tree',
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) =>
                  FireRings(record: record, size: c.maxWidth.clamp(200, 340)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Season',
          subtitle: 'Critical period: ${critical.map((m) => monthNames[m - 1]).join(', ')}',
          child: SeasonChart(record: record),
        ),
        const SizedBox(height: 16),
        _EvidenceCard(record.evidence),
        const SizedBox(height: 12),
        Text('Units: ${record.units}',
            style: monoStyle(size: 10), textAlign: TextAlign.center),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: monoStyle(size: 11)),
            const SizedBox(height: 2),
            Text(value, style: monoStyle(size: 16, color: Ember.text)),
          ],
        ),
      );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard(this.e);
  final Evidence e;

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).round()}%';
    return SectionCard(
      title: 'Evidence',
      subtitle: 'How accurate is the stitching?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ErrorBar(label: 'Raw record', value: e.heldOutErrorRaw, color: Ember.ash),
          const SizedBox(height: 8),
          _ErrorBar(label: 'Harmonized', value: e.heldOutErrorHarmonized, color: Ember.ember),
          const SizedBox(height: 12),
          Text(
            'Yearly error on held-out years drops from ${pct(e.heldOutErrorRaw)} '
            'to ${pct(e.heldOutErrorHarmonized)}. VIIRS sees '
            '${e.ratio.toStringAsFixed(1)}× more fire cells than MODIS here '
            '(overlap ${e.overlapFrom}–${e.overlapTo}).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: monoStyle(size: 11))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0, 1),
                minHeight: 10,
                color: color,
                backgroundColor: Ember.surfaceHigh,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${(value * 100).round()}%',
                style: monoStyle(size: 12, color: Ember.text),
                textAlign: TextAlign.right),
          ),
        ],
      );
}
