import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Saved places with their current status. Push alerts plug in here later.
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key, required this.onOpen});

  /// Called when a region is tapped (switches to the Home tab).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Watchlist')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Get alerted when a saved place is above normal, or when its '
            'critical fire period is about to start.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Ember.textMuted),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 10),
          ],
        ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: FutureBuilder<FireRecord>(
            future: repo.getRecord(region.id),
            builder: (context, snap) {
              final s = snap.hasData ? summarize(snap.data!) : null;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(region.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(
                          s == null
                              ? 'Loading…'
                              : '${s.monthName} ${s.year} · ${s.ratio.toStringAsFixed(1)}× usual · '
                                  'rank #${s.rank}',
                          style: monoStyle(size: 12),
                        ),
                      ],
                    ),
                  ),
                  if (s != null)
                    StatusPill(
                      label: Ember.labelForStatus(s.status),
                      color: Ember.forStatus(s.status),
                    ),
                  IconButton(
                    tooltip: watched ? 'Stop watching' : 'Watch',
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
