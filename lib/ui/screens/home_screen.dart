import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import '../widgets/burn_planner_card.dart';
import '../widgets/common.dart';
import '../widgets/danger_forecast_card.dart';
import '../widgets/fire_rings.dart';
import '../widgets/fire_weather_card.dart';
import '../widgets/near_me_card.dart';
import '../widgets/air_card.dart';
import '../widgets/nearest_help_card.dart';
import '../widgets/season_chart.dart';
import '../widgets/share_card.dart';
import 'report_screen.dart';

/// "Is this fire season normal?" — the one-sentence answer first, quick
/// actions, near me, fire weather, then the science for the curious.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onOpenMap});

  /// Switches to the Map tab.
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(message: s.t('app_name'), child: const EmberLogo(size: 30)),
            const SizedBox(width: 24),
            const Flexible(child: AppBarRegionPicker()),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: RecordLoader(
              builder: (context, region, record) =>
                  _HomeBody(region, record, onOpenMap: onOpenMap),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody(this.region, this.record, {this.onOpenMap});
  final Region region;
  final FireRecord record;
  final VoidCallback? onOpenMap;

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
    final weatherPoint = user != null && region.contains(user)
        ? user
        : region.center;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // 1. The answer.
        Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  statusColor.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('question'),
                        style: text.labelLarge?.copyWith(
                          color: Ember.textMuted,
                        ),
                      ),
                    ),
                    InfoButton(
                      title: s.t('question'),
                      body: s.t('info_answer'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusBadge(
                        status: summary.status,
                        label: s.status(summary.status),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.sentence(summary, region),
                        style: text.headlineSmall?.copyWith(height: 1.35),
                      ),
                      const SizedBox(height: 18),
                      _UsualMeter(ratio: summary.ratio, color: statusColor),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Stat(
                            label: s.t('fires_this_month'),
                            value: '${summary.value}',
                          ),
                          _Stat(
                            label: s.t('usual_month'),
                            value: summary.median.round().toString(),
                          ),
                          _Stat(
                            label: s.t('rank_label'),
                            value: s.rankOf(
                              summary.rank,
                              summary.yearsCompared,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => showShareCard(context, region, record),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: Text(s.t('share')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 2. What can I do right now?
        _QuickActions(onOpenMap: onOpenMap),
        const SizedBox(height: 16),
        // 3. Around me.
        const NearMeCard(),
        const NearestHelpCard(),
        const AirCard(),
        const SizedBox(height: 16),
        // 4. What is coming.
        DangerForecastCard(point: weatherPoint),
        const SizedBox(height: 16),
        FireWeatherCard(record: record, point: weatherPoint),
        const SizedBox(height: 16),
        BurnPlannerCard(record: record, point: weatherPoint),
        const SizedBox(height: 16),
        SectionCard(
          title: s.t('season'),
          subtitle:
              '${s.t('critical_period')}: ${critical.map(s.month).join(s.ar ? '، ' : ', ')}',
          info: s.t('info_season'),
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
        // 5. For the curious.
        Card(
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.science_outlined, color: Ember.amber),
              title: Text(
                s.t('science_details'),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                s.t('science_details_sub'),
                style: text.bodySmall?.copyWith(color: Ember.textMuted),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                SectionCard(
                  title: s.t('fire_rings'),
                  subtitle: s.t('fire_rings_sub'),
                  info: s.t('info_rings'),
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
                const SizedBox(height: 12),
                _EvidenceCard(record.evidence),
                const SizedBox(height: 8),
                Text(
                  '${s.t('units')}: ${record.units}',
                  style: monoStyle(size: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Big status label with an icon, so colour is never the only signal.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.label});
  final FireStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Ember.forStatus(status);
    final icon = switch (status) {
      FireStatus.below => Icons.trending_down,
      FireStatus.normal => Icons.check_circle_outline,
      FireStatus.above => Icons.trending_up,
      FireStatus.extreme => Icons.warning_amber_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where this month sits between "fewer" and "more" than usual
/// (log scale, ¼× … 4×, usual in the middle).
class _UsualMeter extends StatelessWidget {
  const _UsualMeter({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final r = ratio <= 0.25 ? 0.25 : ratio;
    final t = ((math.log(r) / math.ln2) / 4 + 0.5).clamp(0.0, 1.0);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: AlignmentDirectional.centerStart,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          Ember.calm,
                          Ember.amber,
                          Ember.ember,
                          Ember.extreme,
                        ],
                      ),
                    ),
                  ),
                  // "Usual" tick in the middle.
                  PositionedDirectional(
                    start: w / 2 - 1,
                    child: Container(
                      width: 2,
                      height: 16,
                      color: Ember.text.withValues(alpha: 0.6),
                    ),
                  ),
                  PositionedDirectional(
                    start: (w * t - 11).clamp(0.0, math.max(0.0, w - 22)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(color: Ember.surface, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(s.t('meter_less'), style: monoStyle(size: 11)),
            const Spacer(),
            Text(s.t('meter_usual'), style: monoStyle(size: 11)),
            const Spacer(),
            Text(s.t('meter_more'), style: monoStyle(size: 11)),
          ],
        ),
      ],
    );
  }
}

/// The three things people most often need: report, look, call.
class _QuickActions extends StatelessWidget {
  const _QuickActions({this.onOpenMap});
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        _ActionTile(
          icon: Icons.add_a_photo_outlined,
          label: s.t('report_fire'),
          color: Ember.ember,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ReportScreen()),
          ),
        ),
        const SizedBox(width: 8),
        _ActionTile(
          icon: Icons.travel_explore,
          label: s.t('quick_map'),
          color: Ember.amber,
          onTap: onOpenMap,
        ),
        const SizedBox(width: 8),
        _ActionTile(
          icon: Icons.call,
          label: s.t('call_125'),
          color: Ember.extreme,
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final uri = Uri(scheme: 'tel', path: '125');
            if (!await launchUrl(uri)) {
              messenger.showSnackBar(
                SnackBar(content: Text('${s.t('could_not_open')} $uri')),
              );
            }
          },
        ),
        const SizedBox(width: 8),
        _ActionTile(
          icon: Icons.sms_outlined,
          label: s.t('sms_location'),
          color: Ember.extreme,
          onTap: () async {
            final state = AppScope.read(context);
            final messenger = ScaffoldMessenger.of(context);
            if (state.userPosition == null) await state.locateMe();
            final pos = state.userPosition;
            final where = pos == null
                ? ''
                : ' https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
            final uri = Uri(
              scheme: 'sms',
              path: '125',
              queryParameters: {'body': '${s.t('sms_text')}$where'},
            );
            if (!await launchUrl(uri)) {
              messenger.showSnackBar(
                SnackBar(content: Text('${s.t('could_not_open')} $uri')),
              );
            }
          },
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Ember.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Ember.textMuted),
        ),
        const SizedBox(height: 2),
        Text(value, style: monoStyle(size: 17, color: Ember.text)),
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
      info: s.t('info_evidence'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ErrorBar(
            label: s.t('raw_record'),
            value: e.heldOutErrorRaw,
            color: Ember.ash,
          ),
          const SizedBox(height: 8),
          _ErrorBar(
            label: s.t('harmonized'),
            value: e.heldOutErrorHarmonized,
            color: Ember.ember,
          ),
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
  const _ErrorBar({
    required this.label,
    required this.value,
    required this.color,
  });
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
        child: Text(
          '${(value * 100).round()}%',
          style: monoStyle(size: 12, color: Ember.text),
          textAlign: TextAlign.end,
        ),
      ),
    ],
  );
}
