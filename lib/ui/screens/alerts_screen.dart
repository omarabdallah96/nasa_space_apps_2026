import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/alert_engine.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Early warning: a status summary and the active alerts. Alerts refresh on
/// their own; pull down to force it. Zones and watched places live in Settings.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.onOpen});

  /// Called when a region is tapped (switches to the Today tab).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('alerts')),
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
            _StatusHero(alerts: state.alerts, checking: state.checkingAlerts),
            if (state.alerts.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final a in state.alerts) ...[
                _AlertTile(a, onTap: () {
                  state.select(a.region);
                  onOpen();
                }),
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

class _AlertTile extends StatelessWidget {
  const _AlertTile(this.alert, {required this.onTap});
  final FireAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final color = _levelColor(alert.level);
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
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Ember.textMuted),
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
