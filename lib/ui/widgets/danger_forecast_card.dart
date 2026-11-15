import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/danger_forecast.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// "Fire danger, next 7 days": the Fire Weather Index forecast where the user
/// is (or the centre of the region), one coloured tile per day.
class DangerForecastCard extends StatefulWidget {
  const DangerForecastCard({super.key, required this.point});

  /// The user's position when known and inside the region, else its centre.
  final LatLng point;

  @override
  State<DangerForecastCard> createState() => _DangerForecastCardState();
}

class _DangerForecastCardState extends State<DangerForecastCard> {
  Future<DangerForecast>? _future;
  LatLng? _loadedFor;

  void _load() {
    _loadedFor = widget.point;
    _future = AppScope.read(context).repository.getDangerForecast(widget.point);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedFor != widget.point) _load();
    final s = S.of(context);

    return SectionCard(
      title: s.t('danger_title'),
      subtitle: s.t('danger_sub'),
      info: s.t('info_danger'),
      child: FutureBuilder<DangerForecast>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Row(children: [
              Expanded(child: Text(s.t('forecast_failed'), style: monoStyle())),
              TextButton(onPressed: () => setState(_load), child: Text(s.t('retry'))),
            ]);
          }
          if (!snap.hasData) return const LinearProgressIndicator(color: Ember.ember);
          final f = snap.data!;
          if (f.days.isEmpty) return Text(s.t('forecast_failed'), style: monoStyle());
          return _Body(f);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.f);
  final DangerForecast f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final today = f.days.first;
    final worst = f.worst()!;
    final todayColor = Ember.forDanger(today.level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline: today's level, in words and colour.
        Row(children: [
          DangerPill(level: today.level, prefix: s.t('danger_today_is')),
          const Spacer(),
          Text('FWI ${today.fwi.round()}', style: monoStyle(size: 13, color: todayColor)),
        ]),
        const SizedBox(height: 10),
        Text(adviceFor(s, today.level), style: text.bodyMedium),
        const SizedBox(height: 4),
        Text(usualFor(s, today.usual), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        if (worst.level.index > today.level.index) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.trending_up, size: 18, color: Ember.forDanger(worst.level)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${s.t('danger_peak')}: ${s.weekday(worst.date.weekday)} · ${s.danger(worst.level)}',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            for (final (i, d) in f.days.take(7).indexed)
              Expanded(
                child: _DayTile(
                  day: d,
                  label: i == 0 ? s.t('today') : s.weekdayShort(d.date.weekday),
                  onTap: () => showDangerDay(context, d),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(s.t('danger_source'), style: monoStyle(size: 10)),
      ],
    );
  }
}

String adviceFor(S s, DangerLevel l) => l.isHighOrAbove
    ? s.t('danger_advice_high')
    : l == DangerLevel.moderate
        ? s.t('danger_advice_moderate')
        : s.t('danger_advice_low');

String usualFor(S s, UsualActivity u) => u.inPeakSeason
    ? s.t('danger_usual_peak')
    : u.shareOfPeak < 0.25
        ? s.t('danger_usual_low')
        : s.t('danger_usual_mid');

/// A level as a coloured pill with an icon, so colour is never the only signal.
class DangerPill extends StatelessWidget {
  const DangerPill({super.key, required this.level, this.prefix});
  final DangerLevel level;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = Ember.forDanger(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(dangerIcon(level), size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          prefix == null ? s.danger(level) : '$prefix: ${s.danger(level)}',
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

IconData dangerIcon(DangerLevel l) => switch (l) {
      DangerLevel.veryLow || DangerLevel.low => Icons.check_circle_outline,
      DangerLevel.moderate => Icons.info_outline,
      DangerLevel.high => Icons.warning_amber_rounded,
      DangerLevel.veryHigh || DangerLevel.extreme => Icons.local_fire_department,
    };

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.label, required this.onTap});
  final DangerDay day;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = Ember.forDanger(day.level);
    return Semantics(
      button: true,
      label: '$label: ${s.danger(day.level)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: color.withValues(alpha: 0.16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                FittedBox(child: Text(label, style: monoStyle(size: 11, color: Ember.text))),
                const SizedBox(height: 6),
                Icon(dangerIcon(day.level), size: 18, color: color),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text('${day.fwi.round()}',
                      style: monoStyle(size: 13, color: Ember.text)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One day in detail: level, noon weather, how dry the ground is, what is usual.
void showDangerDay(BuildContext context, DangerDay d) {
  final s = S.of(context);
  final text = Theme.of(context).textTheme;
  final w = d.weather;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Ember.surface,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.weekday(d.date.weekday)} ${d.date.day} ${s.month(d.date.month)}',
                style: text.titleLarge),
            const SizedBox(height: 10),
            Row(children: [
              DangerPill(level: d.level),
              const Spacer(),
              Text('${s.t('danger_index')}: ${d.fwi.toStringAsFixed(1)}',
                  style: monoStyle(size: 12)),
            ]),
            const SizedBox(height: 12),
            Text(adviceFor(s, d.level), style: text.bodyLarge),
            if (w != null) ...[
              const SizedBox(height: 16),
              Text(s.t('danger_noon'), style: monoStyle(size: 11)),
              const SizedBox(height: 8),
              Row(children: [
                _Fact(Icons.thermostat, s.t('temperature'), '${w.temperatureC.round()}°C'),
                _Fact(Icons.water_drop_outlined, s.t('humidity'), '${w.humidity.round()}%'),
                _Fact(Icons.air, s.t('wind'), '${w.windKmh.round()} km/h'),
                _Fact(Icons.umbrella_outlined, s.t('danger_rain'), '${w.rainMm.toStringAsFixed(w.rainMm < 10 ? 1 : 0)} mm'),
                if (d.drought != null)
                  _Fact(Icons.grass, s.t('danger_ground'), groundFor(s, d.drought!)),
              ]),
            ],
            const SizedBox(height: 16),
            Text(usualFor(s, d.usual), style: text.bodyMedium?.copyWith(color: Ember.textMuted)),
          ],
        ),
      ),
    ),
  );
}

/// Drought Code in words. Mediterranean summers reach 600–800.
String groundFor(S s, double dc) => dc >= 400
    ? s.t('danger_ground_very_dry')
    : dc >= 150
        ? s.t('danger_ground_dry')
        : s.t('danger_ground_moist');

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, size: 18, color: Ember.textMuted),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: monoStyle(size: 13, color: Ember.text))),
          FittedBox(child: Text(label, style: monoStyle(size: 10))),
        ]),
      );
}
