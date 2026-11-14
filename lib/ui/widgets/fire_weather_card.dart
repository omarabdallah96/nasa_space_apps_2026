import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/fire_record.dart';
import '../../l10n/strings.dart';
import '../../services/weather_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Current fire weather + "is it safe to burn today?" for farmers.
class FireWeatherCard extends StatefulWidget {
  const FireWeatherCard({super.key, required this.record, required this.point});

  final FireRecord record;

  /// The user's position when known, otherwise the region centre.
  final LatLng point;

  @override
  State<FireWeatherCard> createState() => _FireWeatherCardState();
}

class _FireWeatherCardState extends State<FireWeatherCard> {
  Future<FireWeather>? _future;
  LatLng? _loadedFor;

  void _load() {
    _loadedFor = widget.point;
    _future = AppScope.read(context).weather.current(widget.point);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedFor != widget.point) _load();
    final s = S.of(context);

    return SectionCard(
      title: s.t('fire_weather'),
      subtitle: s.t('fire_weather_sub'),
      child: FutureBuilder<FireWeather>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Row(children: [
              Expanded(child: Text(s.t('weather_failed'), style: monoStyle())),
              TextButton(
                onPressed: () => setState(_load),
                child: Text(s.t('retry')),
              ),
            ]);
          }
          if (!snap.hasData) {
            return const LinearProgressIndicator(color: Ember.ember);
          }
          final w = snap.data!;
          final advice = burnAdvice(weather: w, record: widget.record, now: DateTime.now());
          final color = switch (advice.level) {
            BurnLevel.safe => Ember.calm,
            BurnLevel.caution => Ember.amber,
            BurnLevel.unsafe => Ember.extreme,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _W(Icons.thermostat, s.t('temperature'), '${w.temperatureC.round()}°C'),
                _W(Icons.water_drop_outlined, s.t('humidity'), '${w.humidity.round()}%'),
                _W(Icons.air, s.t('wind'), '${w.windKmh.round()} km/h'),
                _W(Icons.storm_outlined, s.t('gusts'), '${w.gustKmh.round()} km/h'),
              ]),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        advice.level == BurnLevel.unsafe
                            ? Icons.block
                            : advice.level == BurnLevel.caution
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                        color: color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(s.burn(advice.level),
                          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    ]),
                    for (final r in advice.reasons)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 28, top: 4),
                        child: Text('• ${s.t(r)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${s.t('quiet_months')}: ${advice.quietMonths.map(s.month).join(s.ar ? '، ' : ', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ember.textMuted),
              ),
              const SizedBox(height: 4),
              Text(s.t('weather_source'), style: monoStyle(size: 10)),
            ],
          );
        },
      ),
    );
  }
}

class _W extends StatelessWidget {
  const _W(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 18, color: Ember.textMuted),
            const SizedBox(height: 4),
            Text(value, style: monoStyle(size: 13, color: Ember.text)),
            Text(label, style: monoStyle(size: 10)),
          ],
        ),
      );
}
