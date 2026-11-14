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

/// Early warning: active alerts, watched places, and an emergency card.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.onOpen});

  /// Called when a region is tapped (switches to the Today tab).
  final VoidCallback onOpen;

  Future<void> _checkAndNotify(BuildContext context) async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await state.notifications.requestPermission();
    await state.checkAlerts(notify: allowed);
    messenger.showSnackBar(SnackBar(
      content: Text(s.t(!state.notifications.supported || allowed
          ? 'notifications_sent'
          : 'notifications_denied')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('alerts'))),
      body: RefreshIndicator(
        color: Ember.ember,
        onRefresh: () => state.checkAlerts(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('alerts_intro'),
                style: text.bodyMedium?.copyWith(color: Ember.textMuted)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.checkingAlerts ? null : () => _checkAndNotify(context),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(s.t('check_notify')),
            ),
            const SizedBox(height: 20),
            Text(s.t('active_alerts'), style: text.titleLarge?.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            if (state.checkingAlerts && state.alerts.isEmpty)
              const LinearProgressIndicator(color: Ember.ember)
            else if (state.alerts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline, color: Ember.calm),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.t('no_alerts'))),
                  ]),
                ),
              )
            else
              for (final a in state.alerts) ...[
                _AlertTile(a, onTap: () {
                  state.select(a.region);
                  onOpen();
                }),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 20),
            Text(s.t('watched_places'), style: text.titleLarge?.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
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
            const SizedBox(height: 20),
            const _EmergencyCard(),
          ],
        ),
      ),
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
    final color = switch (alert.level) {
      AlertLevel.info => Ember.amber,
      AlertLevel.warning => Ember.ember,
      AlertLevel.danger => Ember.extreme,
    };
    final icon = switch (alert.type) {
      AlertType.anomaly => Icons.trending_up,
      AlertType.seasonSoon => Icons.event_outlined,
      AlertType.inSeason => Icons.local_fire_department_outlined,
      AlertType.nearbyHotspot => Icons.near_me,
      AlertType.detections => Icons.satellite_alt_outlined,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.alertTitle(alert),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(s.alertBody(alert),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
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
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
          child: FutureBuilder<FireRecord>(
            future: repo.getRecord(region.id),
            builder: (context, snap) {
              final sum = snap.hasData ? summarize(snap.data!) : null;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.region(region),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          sum == null
                              ? s.t('loading')
                              : '${s.month(sum.month)} ${sum.year} · '
                                  '${s.ratio(sum.ratio)} ${s.t('usual_short')} · #${sum.rank}',
                          style: monoStyle(size: 12),
                        ),
                      ],
                    ),
                  ),
                  if (sum != null)
                    StatusPill(label: s.status(sum.status), color: Ember.forStatus(sum.status)),
                  IconButton(
                    tooltip: s.t(watched ? 'stop_watching' : 'watch'),
                    onPressed: onToggle,
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
    final p = state.userPosition;
    return Card(
      color: Ember.extreme.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.emergency_outlined, color: Ember.extreme),
              const SizedBox(width: 8),
              Text(s.t('emergency'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
            ]),
            const SizedBox(height: 4),
            Text(s.t('emergency_sub'), style: Theme.of(context).textTheme.bodySmall),
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
                    if (p == null) await state.locateMe();
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
      ),
    );
  }
}
