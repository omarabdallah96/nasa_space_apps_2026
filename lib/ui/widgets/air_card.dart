import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/air.dart';
import '../../data/models/safety.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Colour of each US AQI class, close to the official scale but readable on
/// both themes.
Color airColor(AirLevel l) => switch (l) {
      AirLevel.good => const Color(0xFF4CAF7A),
      AirLevel.moderate => const Color(0xFFE0B020),
      AirLevel.sensitive => Ember.amber,
      AirLevel.unhealthy => Ember.ember,
      AirLevel.veryUnhealthy => Ember.extreme,
      AirLevel.hazardous => const Color(0xFF8E2C48),
    };

/// Home screen: is the air safe to breathe where I am? Smoke from a fire can
/// make it dangerous far from the flames. Text comes from the server
/// (`GET /air`) in the app's language.
class AirCard extends StatefulWidget {
  const AirCard({super.key, this.point});

  /// Where to ask about; the person's position when null.
  final LatLng? point;

  @override
  State<AirCard> createState() => _AirCardState();
}

class _AirCardState extends State<AirCard> {
  Future<Saved<AirQuality>>? _future;
  String? _loadedFor;
  bool _open = false;

  void _load(AppState state, LatLng at, String lang, {bool force = false}) {
    // Asks again after moving about a kilometre or switching language.
    final key = '${at.latitude.toStringAsFixed(2)},${at.longitude.toStringAsFixed(2)},$lang';
    if (!force && _loadedFor == key) return;
    _loadedFor = key;
    _future = state.safetyApi!.air(at, lang: lang);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    // Demo mode has no server to ask.
    if (state.safetyApi == null) return const SizedBox.shrink();

    final at = widget.point ?? state.userPosition ?? state.lastKnownPosition;
    final Widget body;
    if (at == null) {
      body = Row(children: [
        Expanded(child: Text(s.t('air_hint'), style: text.bodyMedium)),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: state.locating ? null : state.locateMe,
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(s.t('use_location')),
        ),
      ]);
    } else {
      final lang = s.ar ? 'ar' : 'en';
      _load(state, at, lang);
      body = FutureBuilder<Saved<AirQuality>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Row(children: [
              const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember)),
              const SizedBox(width: 12),
              Text(s.t('loading')),
            ]);
          }
          if (snap.hasError) {
            return Row(children: [
              Expanded(child: Text(s.t('air_failed'), style: text.bodyMedium)),
              TextButton(
                onPressed: () => setState(() => _load(state, at, lang, force: true)),
                child: Text(s.t('retry')),
              ),
            ]);
          }
          return _body(context, snap.data!);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.masks_outlined, size: 16, color: Ember.amber),
                const SizedBox(width: 6),
                Text(s.t('air_title'), style: text.labelLarge?.copyWith(color: Ember.amber, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Saved<AirQuality> saved) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final a = saved.value;
    final color = airColor(a.level);
    final muted = text.bodySmall?.copyWith(color: Ember.textMuted);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 2.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${a.aqi}',
                style: monoStyle(size: 18, color: Ember.text).copyWith(fontWeight: FontWeight.w700)),
            Text('AQI', style: monoStyle(size: 9)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.label, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
            const SizedBox(height: 2),
            Text(a.headline, style: text.bodyMedium),
          ]),
        ),
      ]),
      if (a.worsening) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.trending_up, size: 16, color: airColor(a.peakLevel!)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${s.t('air_peak')} ${a.peakAqi}'
              '${a.peakAt == null ? '' : ' · ${_hm(a.peakAt!)}'}',
              style: text.bodySmall?.copyWith(color: Ember.text),
            ),
          ),
        ]),
      ],
      if (saved.savedAt != null) ...[
        const SizedBox(height: 6),
        Text('${s.t('air_saved')} ${_hm(saved.savedAt!)}', style: muted),
      ],
      if (_open) ..._details(context, a),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
          label: Text(s.t(_open ? 'air_less' : 'air_more')),
        ),
      ),
    ]);
  }

  List<Widget> _details(BuildContext context, AirQuality a) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Ember.textMuted);
    Widget heading(String key) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(s.t(key), style: text.labelLarge),
        );
    Widget bullet(String line) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(top: 7, end: 8),
              child: Icon(Icons.circle, size: 5, color: Ember.ember),
            ),
            Expanded(child: Text(line, style: text.bodyMedium)),
          ]),
        );

    return [
      if (a.advice.isNotEmpty) ...[heading('air_what_to_do'), for (final l in a.advice) bullet(l)],
      if (a.pollutants.isNotEmpty) ...[
        heading('air_pollutants'),
        for (final p in a.pollutants)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: airColor(p.level), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.t('air_${p.key}'),
                  style: TextStyle(fontWeight: p.key == a.main ? FontWeight.w800 : FontWeight.w500),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${_num(p.value)} µg/m³', style: monoStyle(size: 12, color: Ember.text)),
              ),
            ]),
          ),
      ],
      if (a.co2Note != null) ...[heading('air_co2'), Text(a.co2Note!, style: text.bodyMedium)],
      if (a.smokeTips.isNotEmpty) ...[heading('air_smoke_tips'), for (final l in a.smokeTips) bullet(l)],
      const SizedBox(height: 10),
      Text(a.note.isNotEmpty ? '${a.note}\n${a.source}' : a.source, style: muted),
    ];
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _num(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
}
