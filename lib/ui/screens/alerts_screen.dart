import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../services/alert_engine.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/zones_section.dart';

/// Early warning: a status summary, active alerts, emergency contacts, zones
/// and watched places. Alerts refresh on their own; pull down to force it.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.onOpen});

  /// Called when a region is tapped (switches to the Today tab).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final watched = state.regions.where((r) => state.watchlist.contains(r.id)).length;

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
              const SizedBox(height: 16),
              for (final a in state.alerts) ...[
                _AlertTile(a, onTap: () {
                  state.select(a.region);
                  onOpen();
                }),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 16),
            const _EmergencyCard(),
            const SizedBox(height: 28),
            const ZonesSection(),
            const SizedBox(height: 28),
            _SectionHeader(
              title: s.t('watched_places'),
              subtitle: s.t('watch_hint'),
              trailing: Text('$watched/${state.regions.length}', style: monoStyle(size: 12)),
            ),
            const SizedBox(height: 10),
            for (final r in state.regions) ...[
              _WatchTile(
                region: r,
                watched: state.watchlist.contains(r.id),
                onToggle: () => state.toggleWatch(r.id),
                onTap: () {
                  state.select(r);
                  onOpen();
                },
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            const _SmokeTip(),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(title, style: text.titleLarge?.copyWith(fontSize: 18))),
          ?trailing,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        ],
      ],
    );
  }
}

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: quiet
                  ? Icon(Icons.verified_user_outlined, color: color, size: 28)
                  : Text('${alerts.length}',
                      style: monoStyle(size: 22, color: color)
                          .copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quiet ? s.t('all_quiet') : s.t('active_alerts'),
                    style: text.titleLarge?.copyWith(fontSize: 22),
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
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in counts.entries)
                _LevelCount(color: _levelColor(e.key), label: _levelLabel(s, e.key), count: e.value),
            ]),
          ],
          const SizedBox(height: 14),
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
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 14, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 3),
                            Text(s.alertTitle(alert),
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(s.alertBody(alert),
                                style: text.bodySmall?.copyWith(
                                    color: Ember.textMuted, height: 1.35)),
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

class _WatchTile extends StatelessWidget {
  const _WatchTile({
    required this.region,
    required this.watched,
    required this.onToggle,
    required this.onTap,
  });

  final Region region;
  final bool watched;
  final VoidCallback onToggle, onTap;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repository;
    final s = S.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
          child: FutureBuilder<FireRecord>(
            future: repo.getRecord(region.id),
            builder: (context, snap) {
              final sum = snap.hasData ? summarize(snap.data!) : null;
              final statusColor = sum == null ? Ember.textMuted : Ember.forStatus(sum.status);
              return Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(s.region(region),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (sum != null) ...[
                            const SizedBox(width: 8),
                            StatusPill(label: s.status(sum.status), color: statusColor),
                          ],
                        ]),
                        const SizedBox(height: 3),
                        Text(
                          sum == null
                              ? s.t('loading')
                              : '${s.month(sum.month)} ${sum.year} · '
                                  '${sum.usuallyNone ? '${sum.value}' : '${s.ratio(sum.ratio)} ${s.t('usual_short')}'} · #${sum.rank}',
                          style: monoStyle(size: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.t(watched ? 'stop_watching' : 'watch'),
                    onPressed: onToggle,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          watched ? Ember.ember.withValues(alpha: 0.18) : Colors.transparent,
                    ),
                    icon: Icon(
                      watched ? Icons.notifications_active : Icons.notifications_none,
                      color: watched ? Ember.ember : Ember.textMuted,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Compact emergency strip: call or text Civil Defence with your location.
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  Future<void> _open(BuildContext context, Uri uri) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(uri)) {
      messenger.showSnackBar(SnackBar(content: Text('${s.t('could_not_open')} $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ember.extreme.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ember.extreme.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.emergency_outlined, color: Ember.extreme, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('emergency'),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(s.t('emergency_sub'),
                    style: text.bodySmall?.copyWith(color: Ember.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Ember.extreme),
                onPressed: () => _open(context, Uri(scheme: 'tel', path: '125')),
                icon: const Icon(Icons.call),
                label: Text(s.t('call_125')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (state.userPosition == null) await state.locateMe();
                  final pos = state.userPosition;
                  if (!context.mounted) return;
                  final where = pos == null
                      ? ''
                      : ' https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
                  await _open(
                    context,
                    Uri(scheme: 'sms', path: '125', queryParameters: {
                      'body': '${s.t('sms_text')}$where',
                    }),
                  );
                },
                icon: const Icon(Icons.sms_outlined),
                label: Text(s.t('sms_location')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SmokeTip extends StatelessWidget {
  const _SmokeTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ember.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.explore_outlined, size: 20, color: Ember.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(S.of(context).t('smoke_tip'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ember.textMuted)),
        ),
      ]),
    );
  }
}
