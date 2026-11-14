import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import '../widgets/burn_planner_card.dart';
import '../widgets/common.dart';
import '../widgets/fire_rings.dart';
import '../widgets/fire_weather_card.dart';
import '../widgets/near_me_card.dart';
import '../widgets/season_chart.dart';
import '../widgets/share_card.dart';
import 'onboarding_screen.dart';

/// "Is this fire season normal?" — near me, the one-sentence answer,
/// Fire Rings, season chart, fire weather and evidence.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          const EmberLogo(size: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Text(s.t('app_name'), overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: s.t('intro'),
            icon: Icon(Icons.help_outline, color: Ember.textMuted),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (route) => OnboardingScreen(onDone: () => Navigator.pop(route)),
              ),
            ),
          ),
          IconButton(
            tooltip: s.t(state.darkMode ? 'light_mode' : 'dark_mode'),
            icon: Icon(
              state.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: Ember.textMuted,
            ),
            onPressed: () => state.setDarkMode(!state.darkMode),
          ),
          TextButton(
            onPressed: () => state.setLanguage(s.ar ? 'en' : 'ar'),
            child: Text(s.t('language'), style: const TextStyle(color: Ember.amber)),
          ),
        ],
      ),
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
    final s = S.of(context);
    final state = AppScope.of(context);
    final summary = summarize(record);
    final critical = criticalMonths(record);
    final text = Theme.of(context).textTheme;
    final statusColor = Ember.forStatus(summary.status);

    // Weather at the user's position if they are in this region, else centre.
    final user = state.userPosition;
    final weatherPoint =
        user != null && region.contains(user) ? user : region.center;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const NearMeCard(),
        const SizedBox(height: 16),
        // The answer.
        Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [statusColor.withValues(alpha: 0.16), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.t('question'),
                          style: text.labelLarge?.copyWith(color: Ember.textMuted)),
                    ),
                    StatusPill(label: s.status(summary.status), color: statusColor),
                  ],
                ),
                const SizedBox(height: 12),
                Text(s.sentence(summary, region),
                    style: text.headlineSmall?.copyWith(height: 1.35)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(label: s.t('this_month'), value: '${summary.value}'),
                    _Stat(label: s.t('usual'), value: summary.median.round().toString()),
                    _Stat(label: s.t('rank'), value: '#${summary.rank} / ${summary.yearsCompared}'),
                    IconButton.filledTonal(
                      tooltip: s.t('share'),
                      onPressed: () => showShareCard(context, region, record),
                      icon: const Icon(Icons.ios_share),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: s.t('fire_rings'),
          subtitle: s.t('fire_rings_sub'),
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) => FireRings(
                record: record,
                size: c.maxWidth.clamp(200, 340),
                caption: s.t('rings_caption'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: s.t('season'),
          subtitle:
              '${s.t('critical_period')}: ${critical.map(s.month).join(s.ar ? '، ' : ', ')}',
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SeasonChart(
              record: record,
              monthLabels: s.monthLetters,
              rangeLabel: s.t('normal_range'),
              medianLabel: s.t('median'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FireWeatherCard(record: record, point: weatherPoint),
        const SizedBox(height: 16),
        BurnPlannerCard(record: record, point: weatherPoint),
        const SizedBox(height: 16),
        _EvidenceCard(record.evidence),
        const SizedBox(height: 12),
        Text('${s.t('units')}: ${record.units}',
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
    final s = S.of(context);
    String pct(double v) => '${(v * 100).round()}%';
    return SectionCard(
      title: s.t('evidence'),
      subtitle: s.t('evidence_sub'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ErrorBar(label: s.t('raw_record'), value: e.heldOutErrorRaw, color: Ember.ash),
          const SizedBox(height: 8),
          _ErrorBar(label: s.t('harmonized'), value: e.heldOutErrorHarmonized, color: Ember.ember),
          const SizedBox(height: 12),
          Text(
            s.ar
                ? 'ينخفض الخطأ السنوي في السنوات المحجوبة من ${pct(e.heldOutErrorRaw)} '
                    'إلى ${pct(e.heldOutErrorHarmonized)}. يرصد VIIRS '
                    '${s.ratio(e.ratio)} خلايا حريق أكثر من MODIS هنا '
                    '(فترة التداخل ${e.overlapFrom}–${e.overlapTo}).'
                : 'Yearly error on held-out years drops from ${pct(e.heldOutErrorRaw)} '
                    'to ${pct(e.heldOutErrorHarmonized)}. VIIRS sees '
                    '${s.ratio(e.ratio)} more fire cells than MODIS here '
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
          SizedBox(width: 96, child: Text(label, style: monoStyle(size: 11))),
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
                textAlign: TextAlign.end),
          ),
        ],
      );
}
