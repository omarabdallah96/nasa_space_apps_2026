import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/danger_forecast.dart';
import '../../data/models/fire_record.dart';
import '../../l10n/strings.dart';
import '../../services/weather_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// "Best day to burn this week": the 7-day forecast ranked for
/// agricultural burning.
class BurnPlannerCard extends StatefulWidget {
  const BurnPlannerCard({super.key, required this.record, required this.point});

  final FireRecord record;
  final LatLng point;

  @override
  State<BurnPlannerCard> createState() => _BurnPlannerCardState();
}

class _BurnPlannerCardState extends State<BurnPlannerCard> {
  Future<(List<DayForecast>, List<DangerDay>?)>? _future;
  LatLng? _loadedFor;

  void _load() {
    _loadedFor = widget.point;
    final state = AppScope.read(context);
    // The danger forecast is a bonus: without it the planner still works.
    final danger = state.repository
        .getDangerForecast(widget.point)
        .then<List<DangerDay>?>((f) => f.days, onError: (Object _) => null);
    _future = Future.wait([state.weather.forecast(widget.point), danger])
        .then((r) => (r[0] as List<DayForecast>, r[1] as List<DangerDay>?));
  }

  static Color _color(BurnLevel l) => switch (l) {
        BurnLevel.safe => Ember.calm,
        BurnLevel.caution => Ember.amber,
        BurnLevel.unsafe => Ember.extreme,
      };

  @override
  Widget build(BuildContext context) {
    if (_loadedFor != widget.point) _load();
    final s = S.of(context);
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: s.t('burn_planner'),
      subtitle: s.t('burn_planner_sub'),
      info: s.t('info_planner'),
      child: FutureBuilder<(List<DayForecast>, List<DangerDay>?)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Row(children: [
              Expanded(child: Text(s.t('forecast_failed'), style: monoStyle())),
              TextButton(onPressed: () => setState(_load), child: Text(s.t('retry'))),
            ]);
          }
          if (!snap.hasData) return const LinearProgressIndicator(color: Ember.ember);

          final plan = planBurns(snap.data!.$1, widget.record, danger: snap.data!.$2);
          final best = plan.best;
          final today = DateUtils.dateOnly(DateTime.now());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Headline.
              Row(children: [
                Icon(best == null ? Icons.block : Icons.event_available,
                    color: best == null ? Ember.extreme : Ember.calm, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    best == null
                        ? s.t('no_safe_day')
                        : '${s.t('best_day')}: ${s.weekday(best.day.date.weekday)}',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 28),
                child: Text(
                  best == null
                      ? plan.days.first.advice.reasons.map(s.t).toSet().join(' · ')
                      : '${s.t('wind')} ${best.day.weather.windKmh.round()} km/h · '
                          '${s.t('humidity')} ${best.day.weather.humidity.round()}%',
                  style: text.bodySmall?.copyWith(color: Ember.textMuted),
                ),
              ),
              const SizedBox(height: 14),
              // Day strip.
              Row(
                children: [
                  for (final d in plan.days)
                    Expanded(
                      child: _DayTile(
                        label: DateUtils.isSameDay(d.day.date, today)
                            ? s.t('today')
                            : s.weekdayShort(d.day.date.weekday),
                        wind: d.day.weather.windKmh.round(),
                        color: _color(d.advice.level),
                        best: identical(d, best),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.label,
    required this.wind,
    required this.color,
    required this.best,
  });

  final String label;
  final int wind;
  final Color color;
  final bool best;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: best ? 0.22 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: best ? color : color.withValues(alpha: 0.3),
            width: best ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            FittedBox(
              child: Text(label,
                  style: monoStyle(size: 11, color: Ember.text)),
            ),
            const SizedBox(height: 6),
            Icon(best ? Icons.star : Icons.circle, size: best ? 16 : 10, color: color),
            const SizedBox(height: 6),
            FittedBox(child: Text('$wind', style: monoStyle(size: 12, color: Ember.text))),
            FittedBox(child: Text('km/h', style: monoStyle(size: 9))),
          ],
        ),
      );
}
