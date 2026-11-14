import 'package:flutter/material.dart';

import '../../data/models/hotspot.dart';
import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// GPS: where am I, which region, and how far is the nearest hotspot.
class NearMeCard extends StatelessWidget {
  const NearMeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;

    final Widget body;
    if (state.locating) {
      body = Row(children: [
        const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember)),
        const SizedBox(width: 12),
        Text(s.t('locating')),
      ]);
    } else if (state.userPosition == null) {
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('near_me_hint'), style: text.bodyMedium),
                if (state.locationError != null) ...[
                  const SizedBox(height: 4),
                  Text(s.t(state.locationError!),
                      style: text.bodySmall?.copyWith(color: Ember.extreme)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: state.locateMe,
            icon: const Icon(Icons.my_location, size: 18),
            label: Text(s.t('use_location')),
          ),
        ],
      );
    } else {
      final match = state.userRegion!;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  match.inside
                      ? '${s.t('you_are_in')} ${s.region(match.region)}'
                      : '${s.t('outside_regions')} ${s.region(match.region)} '
                          '(${match.distanceKm.round()} ${s.t('km_away')})',
                  style: text.titleMedium,
                ),
              ),
              IconButton(
                tooltip: s.t('use_location'),
                onPressed: state.locateMe,
                icon: Icon(Icons.refresh, color: Ember.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _NearestHotspot(regionId: match.region.id),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.near_me, size: 16, color: Ember.amber),
              const SizedBox(width: 6),
              Text(s.t('near_me'),
                  style: text.labelLarge?.copyWith(color: Ember.amber)),
            ]),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _NearestHotspot extends StatefulWidget {
  const _NearestHotspot({required this.regionId});
  final String regionId;

  @override
  State<_NearestHotspot> createState() => _NearestHotspotState();
}

class _NearestHotspotState extends State<_NearestHotspot> {
  Future<List<Hotspot>>? _future;
  String? _loadedFor;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    if (_loadedFor != widget.regionId) {
      _loadedFor = widget.regionId;
      _future = state.repository.getRecentHotspots(widget.regionId);
    }
    return FutureBuilder<List<Hotspot>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return Text(s.t('loading'), style: monoStyle());
        final near = nearestHotspot(snap.data!, state.userPosition!);
        if (near == null) return Text(s.t('no_hotspots'), style: monoStyle());
        final hours = DateTime.now().difference(near.hotspot.acquiredAt).inHours;
        final d = near.distanceKm.toStringAsFixed(near.distanceKm < 10 ? 1 : 0);
        final color = near.distanceKm <= 5
            ? Ember.extreme
            : near.distanceKm <= 25
                ? Ember.ember
                : Ember.textMuted;
        return Row(
          children: [
            Transform.rotate(
              angle: near.compass * 0.785398,
              child: Icon(Icons.navigation, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${s.t('nearest_hotspot')}: $d ${s.t('km_away')} '
                '${s.compass(near.compass)} · ${hours.clamp(0, 999)} ${s.t('hours_ago')}',
                style: monoStyle(size: 12, color: Ember.text),
              ),
            ),
          ],
        );
      },
    );
  }
}
