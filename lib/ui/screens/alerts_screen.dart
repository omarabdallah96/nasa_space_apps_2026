import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../services/alert_engine.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'safety_screen.dart';
import 'zone_report_screen.dart';

/// Shell tabs an alert can switch to (their index in the bottom bar).
enum AlertTab { today, history, map }

/// What tapping an alert does.
enum AlertAction { today, history, map, safety, zoneReport, details }

AlertAction alertAction(FireAlert a) => switch (a.type) {
      AlertType.anomaly => AlertAction.today,
      AlertType.seasonSoon || AlertType.inSeason => AlertAction.history,
      AlertType.detections => AlertAction.map,
      AlertType.nearbyHotspot || AlertType.groundSmoke || AlertType.zoneFire =>
        a.position != null || a.zone != null ? AlertAction.safety : AlertAction.map,
      AlertType.dangerForecast => a.zone != null ? AlertAction.zoneReport : AlertAction.today,
      AlertType.official => AlertAction.details,
    };

String _actionLabel(S s, AlertAction a) => s.t(switch (a) {
      AlertAction.today => 'alert_action_today',
      AlertAction.history => 'alert_action_history',
      AlertAction.map => 'alert_action_map',
      AlertAction.safety => 'alert_action_safety',
      AlertAction.zoneReport => 'alert_action_zone',
      AlertAction.details => 'alert_action_details',
    });

IconData _actionIcon(AlertAction a) => switch (a) {
      AlertAction.today => Icons.local_fire_department_outlined,
      AlertAction.history => Icons.calendar_month_outlined,
      AlertAction.map => Icons.map_outlined,
      AlertAction.safety => Icons.alt_route,
      AlertAction.zoneReport => Icons.insights_outlined,
      AlertAction.details => Icons.campaign_outlined,
    };

/// Opens what the alert is about: the region's status, its fire calendar,
/// the map, escape routes around the fire, the zone report, or the full
/// message of an alert from the Firesight team.
Future<void> openAlert(
  BuildContext context,
  FireAlert a, {
  required void Function(AlertTab tab) onTab,
}) async {
  final state = AppScope.read(context);
  state.select(a.region);
  switch (alertAction(a)) {
    case AlertAction.today:
      onTab(AlertTab.today);
    case AlertAction.history:
      onTab(AlertTab.history);
    case AlertAction.map:
      onTab(AlertTab.map);
    case AlertAction.safety:
      final zone = a.zone;
      if (zone != null && a.type == AlertType.zoneFire) {
        // The screen finds the zone's live fires itself.
        await openSafety(context, target: zone.center, zone: zone);
      } else {
        final p = a.position ?? zone!.center;
        final fires = await _firesAround(state, a, p);
        if (context.mounted) await openSafety(context, target: p, fires: fires);
      }
    case AlertAction.zoneReport:
      await openZoneReport(context, a.zone!);
    case AlertAction.details:
      await _showOfficial(context, a);
  }
}

/// The fire, plus every detection around it: they are part of the same danger.
Future<List<LatLng>> _firesAround(AppState state, FireAlert a, LatLng p) async {
  try {
    final spots = await state.repository
        .getRecentHotspots(a.region.id)
        .timeout(const Duration(seconds: 4));
    return [
      p,
      for (final h in spots)
        if (h.position != p && distanceKm(h.position, p) <= 30) h.position,
    ];
  } catch (_) {
    return [p];
  }
}

Future<void> _showOfficial(BuildContext context, FireAlert a) {
  final s = S.of(context);
  final b = a.broadcast;
  final color = _levelColor(a.level);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Ember.surface,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.campaign_outlined, color: color),
              const SizedBox(width: 8),
              Text(_levelLabel(s, a.level).toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ]),
            const SizedBox(height: 8),
            Text(s.alertTitle(a), style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(s.alertBody(a), style: Theme.of(sheet).textTheme.bodyLarge),
            const SizedBox(height: 20),
            if (b != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    openSafety(context, target: b.center, zone: a.zone);
                  },
                  icon: const Icon(Icons.alt_route),
                  label: Text(s.t('alert_action_safety')),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(s.t('close'), style: TextStyle(color: Ember.text)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Early warning: a status summary and the active alerts. Alerts refresh on
/// their own; pull down to force it. Tap an alert to act on it; clear it with
/// its close button or a swipe. Zones and watched places live in Settings.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.onTab});

  /// Switches the shell to another tab, for alerts that open one.
  final void Function(AlertTab tab) onTab;

  void _clear(BuildContext context, List<FireAlert> list) =>
      AppScope.read(context).dismissAlerts(list);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final alerts = state.alerts;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('alerts')),
        actions: [
          if (alerts.isNotEmpty)
            IconButton(
              key: const ValueKey('clear_all_alerts'),
              tooltip: s.t('alerts_clear_all'),
              icon: const Icon(Icons.clear_all),
              onPressed: () => _clear(context, alerts),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: state.checkingAlerts
              ? const LinearProgressIndicator(minHeight: 2, color: Ember.ember)
              : const SizedBox(height: 2),
        ),
      ),
      body: RefreshIndicator(
        color: Ember.ember,
        onRefresh: () => state.checkAlerts(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StatusHero(alerts: alerts, checking: state.checkingAlerts),
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final a in alerts) ...[
                Dismissible(
                  key: ValueKey(a.id),
                  background: const _ClearBackground(AlignmentDirectional.centerStart),
                  secondaryBackground: const _ClearBackground(AlignmentDirectional.centerEnd),
                  onDismissed: (_) => _clear(context, [a]),
                  child: _AlertTile(
                    a,
                    onTap: () => openAlert(context, a, onTab: onTab),
                    onClear: () => _clear(context, [a]),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Color _levelColor(AlertLevel l) => switch (l) {
      AlertLevel.info => Ember.amber,
      AlertLevel.warning => Ember.ember,
      AlertLevel.danger => Ember.extreme,
    };

String _levelLabel(S s, AlertLevel l) => s.t('level_${l.name}');

/// The headline: "All quiet", or how many alerts and how serious they are.
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.alerts, required this.checking});
  final List<FireAlert> alerts;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final quiet = alerts.isEmpty;
    // Alerts are sorted most severe first.
    final color = quiet ? Ember.calm : _levelColor(alerts.first.level);
    final counts = {
      for (final l in AlertLevel.values.reversed)
        l: alerts.where((a) => a.level == l).length,
    }..removeWhere((_, n) => n == 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.05)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: quiet
                  ? Icon(Icons.verified_user_outlined, color: color, size: 22)
                  : Text('${alerts.length}',
                      style: monoStyle(size: 18, color: color)
                          .copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quiet ? s.t('all_quiet') : s.t('active_alerts'),
                    style: text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quiet ? s.t('all_quiet_sub') : s.t('alerts_found'),
                    style: text.bodySmall?.copyWith(color: Ember.textMuted),
                  ),
                ],
              ),
            ),
          ]),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in counts.entries)
                _LevelCount(color: _levelColor(e.key), label: _levelLabel(s, e.key), count: e.value),
            ]),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Icon(checking ? Icons.sync : Icons.schedule, size: 14, color: Ember.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(checking ? s.t('loading') : s.t('alerts_auto'),
                  style: monoStyle(size: 11)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _LevelCount extends StatelessWidget {
  const _LevelCount({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$count $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// Shown behind an alert while it is swiped away.
class _ClearBackground extends StatelessWidget {
  const _ClearBackground(this.alignment);
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Ember.textMuted.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.done_all, color: Ember.text, size: 20),
          const SizedBox(width: 6),
          Text(S.of(context).t('alert_clear'),
              style: TextStyle(color: Ember.text, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile(this.alert, {required this.onTap, required this.onClear});
  final FireAlert alert;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final color = _levelColor(alert.level);
    final action = alertAction(alert);
    final icon = switch (alert.type) {
      AlertType.anomaly => Icons.trending_up,
      AlertType.seasonSoon => Icons.event_outlined,
      AlertType.inSeason => Icons.local_fire_department_outlined,
      AlertType.nearbyHotspot => Icons.near_me,
      AlertType.detections => Icons.satellite_alt_outlined,
      AlertType.groundSmoke => Icons.explore_outlined,
      AlertType.dangerForecast => Icons.thermostat_auto,
      AlertType.zoneFire => Icons.radar,
      AlertType.official => Icons.campaign_outlined,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: alert.level == AlertLevel.danger
              ? color.withValues(alpha: 0.6)
              : Ember.outline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 4, 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _levelLabel(s, alert.level).toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(s.alertTitle(alert),
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(s.alertBody(alert),
                                style: text.bodySmall?.copyWith(
                                    color: Ember.textMuted, height: 1.3),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            // What tapping does.
                            Row(children: [
                              Icon(_actionIcon(action), size: 14, color: color),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(_actionLabel(s, action),
                                    style: TextStyle(
                                        color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                              Icon(Icons.chevron_right, size: 16, color: color),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: s.t('alert_clear'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close, size: 18, color: Ember.textMuted),
                        onPressed: onClear,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
