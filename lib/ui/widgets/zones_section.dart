import 'package:flutter/material.dart';

import '../../data/models/zone.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../screens/paywall.dart';
import '../screens/zone_editor_screen.dart';
import '../screens/zone_report_screen.dart';

/// "My alert zones" on the Alerts tab: the zones, how many are free, and a
/// button to add one (the paywall when the free zone is used).
class ZonesSection extends StatelessWidget {
  const ZonesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final active = state.activeZones.map((z) => z.id).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(s.t('zones_title'), style: text.titleLarge?.copyWith(fontSize: 18)),
          ),
          if (state.isPro)
            const Icon(Icons.workspace_premium, color: Ember.amber, size: 20)
          else
            Text('${state.zones.length.clamp(0, AppState.freeZoneLimit)}/${AppState.freeZoneLimit} ${s.t('zones_free')}',
                style: monoStyle(size: 12)),
        ]),
        const SizedBox(height: 4),
        Text(s.t('zones_intro'), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        const SizedBox(height: 10),
        for (final z in state.zones) ...[
          ZoneTile(zone: z, paused: !active.contains(z.id)),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const ValueKey('add_zone'),
          onPressed: () => addZone(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          icon: Icon(state.canAddZone ? Icons.add_location_alt_outlined : Icons.lock_outline,
              color: Ember.ember),
          label: Text(s.t(state.canAddZone ? 'zone_add' : 'zone_add_pro'),
              style: TextStyle(color: Ember.text)),
        ),
      ],
    );
  }
}

class ZoneTile extends StatelessWidget {
  const ZoneTile({super.key, required this.zone, this.paused = false});
  final AlertZone zone;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final alerts = state.alerts.where((a) => a.zone?.id == zone.id).length;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => showZoneActions(context, zone),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 4, 6, 4),
        leading: CircleAvatar(
          backgroundColor: (paused ? Ember.textMuted : Ember.ember).withValues(alpha: 0.16),
          child: Icon(Icons.radar, color: paused ? Ember.textMuted : Ember.ember),
        ),
        title: Text(zone.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          paused
              ? s.t('zone_paused')
              : '${zone.radiusKm.round()} km · ${alerts == 0 ? s.t('zone_quiet') : '$alerts ${s.t('alerts_found')}'}',
          style: TextStyle(color: paused ? Ember.amber : Ember.textMuted),
        ),
        trailing: TextButton.icon(
          onPressed: () => openZoneReport(context, zone),
          icon: Icon(state.isPro ? Icons.summarize_outlined : Icons.lock_outline, size: 18),
          label: Text(s.t('zone_report')),
        ),
      ),
    );
  }
}

/// Report / edit / delete for one zone.
Future<void> showZoneActions(BuildContext context, AlertZone zone) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final s = S.of(sheet);
        final state = AppScope.read(context);
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(zone.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${zone.radiusKm.round()} km'),
            ),
            ListTile(
              leading: Icon(state.isPro ? Icons.summarize_outlined : Icons.lock_outline),
              title: Text(s.t('zone_report')),
              onTap: () {
                Navigator.pop(sheet);
                openZoneReport(context, zone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(s.t('zone_edit')),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => ZoneEditorScreen(zone: zone)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Ember.extreme),
              title: Text(s.t('zone_delete'), style: const TextStyle(color: Ember.extreme)),
              onTap: () {
                Navigator.pop(sheet);
                state.deleteZone(zone.id);
              },
            ),
            if (!state.isPro)
              ListTile(
                leading: const Icon(Icons.workspace_premium, color: Ember.amber),
                title: Text(s.t('pro_title')),
                onTap: () {
                  Navigator.pop(sheet);
                  showPaywall(context);
                },
              ),
          ]),
        );
      },
    );
