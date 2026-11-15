import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/safety.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../screens/safety_screen.dart';

/// Always on the home screen: the nearest civil defense centre, Red Cross
/// centre and hospital to where the person is, each one tap from navigation.
class NearestHelpCard extends StatefulWidget {
  const NearestHelpCard({super.key});

  @override
  State<NearestHelpCard> createState() => _NearestHelpCardState();
}

class _NearestHelpCardState extends State<NearestHelpCard> {
  Future<Saved<List<SafetyResource>>>? _future;
  String? _loadedFor;
  LatLng? _from;

  /// Asks again only after moving about a kilometre.
  static String _cell(LatLng p) =>
      '${p.latitude.toStringAsFixed(2)},${p.longitude.toStringAsFixed(2)}';

  void _load(AppState state, LatLng me, {bool force = false}) {
    final cell = _cell(me);
    if (!force && _loadedFor == cell) return;
    _loadedFor = cell;
    _from = me;
    _future = state.safetyApi!.nearestHelp(me);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    // Demo mode has no server to ask.
    if (state.safetyApi == null) return const SizedBox.shrink();

    final me = state.userPosition ?? state.lastKnownPosition;
    final Widget body;
    if (me == null) {
      body = Row(children: [
        Expanded(child: Text(s.t('help_hint'), style: text.bodyMedium)),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: state.locating ? null : state.locateMe,
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(s.t('use_location')),
        ),
      ]);
    } else {
      _load(state, me);
      body = FutureBuilder<Saved<List<SafetyResource>>>(
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
              Expanded(child: Text(s.t('safety_failed'), style: text.bodyMedium)),
              TextButton(
                onPressed: () => setState(() => _load(state, me, force: true)),
                child: Text(s.t('retry')),
              ),
            ]);
          }
          final all = snap.data!.value;
          SafetyResource? nearest(ResourceKind k) {
            for (final r in all) {
              if (r.kind == k) return r;
            }
            return null;
          }

          // Where civil defense is not on the map, the fire station stands in.
          final civil = nearest(ResourceKind.civilDefense) ?? nearest(ResourceKind.fireStation);
          return Column(children: [
            _HelpRow(
              kind: civil?.kind ?? ResourceKind.civilDefense,
              label: s.t(civil?.kind == ResourceKind.fireStation
                  ? 'res_fire_station'
                  : 'safety_civil_defense'),
              place: civil,
              from: _from!,
            ),
            _HelpRow(
              kind: ResourceKind.redCross,
              label: s.t('safety_red_cross'),
              place: nearest(ResourceKind.redCross),
              from: _from!,
            ),
            _HelpRow(
              kind: ResourceKind.hospital,
              label: s.t('res_hospital'),
              place: nearest(ResourceKind.hospital),
              from: _from!,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => openSafety(context, target: me),
                icon: const Icon(Icons.alt_route, size: 18),
                label: Text(s.t('help_ways_out')),
              ),
            ),
          ]);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.health_and_safety, size: 16, color: Ember.amber),
                const SizedBox(width: 6),
                Text(s.t('help_title'), style: text.labelLarge?.copyWith(color: Ember.amber)),
              ]),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.kind, required this.label, required this.place, required this.from});
  final ResourceKind kind;
  final String label;
  final SafetyResource? place;
  final LatLng from;

  Future<void> _navigate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String p(LatLng x) => '${x.latitude.toStringAsFixed(5)},${x.longitude.toStringAsFixed(5)}';
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': p(from),
      'destination': p(place!.position),
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(SnackBar(content: Text(uri.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final r = place;
    final name = r?.displayName(s.ar);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: r == null ? null : () => _navigate(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Opacity(opacity: r == null ? 0.45 : 1, child: ResourcePin(kind, size: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                r == null ? s.t('help_none') : (name ?? resourceDetail(s, r.detail)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ember.textMuted),
              ),
            ]),
          ),
          if (r != null) ...[
            const SizedBox(width: 8),
            Text('${formatKm(r.distanceKm)} · ${s.compass(compassIndex(r.bearingDeg))}',
                style: monoStyle(size: 12, color: Ember.text)),
            IconButton(
              tooltip: s.t('safety_navigate'),
              icon: const Icon(Icons.directions, color: Ember.ember),
              onPressed: () => _navigate(context),
            ),
          ],
        ]),
      ),
    );
  }
}
