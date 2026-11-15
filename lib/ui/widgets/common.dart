import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Dropdown to switch region. Lists only watched places (plus the user's
/// own region and the current selection); the last entry opens a sheet to
/// add or remove places from the watchlist.
class RegionChips extends StatelessWidget {
  const RegionChips({super.key});

  static const _addValue = '__add__';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final ids = {
      ...state.watchlist,
      ?state.userRegion?.region.id,
      ?state.selected?.id,
    };
    final shown = state.regions.where((r) => ids.contains(r.id)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.place, color: Ember.ember, size: 20),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            // Controlled: picking "Add a place" never becomes the shown value.
            value: state.selected?.id,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            items: [
              for (final r in shown)
                DropdownMenuItem(
                  value: r.id,
                  child: Text(
                    s.region(r),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              DropdownMenuItem(
                value: _addValue,
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: Ember.ember,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.t('add_place'),
                      style: const TextStyle(color: Ember.ember),
                    ),
                  ],
                ),
              ),
            ],
            onChanged: (id) {
              if (id == null) return;
              if (id == _addValue) {
                showPlacePicker(context);
                return;
              }
              state.select(state.regions.firstWhere((r) => r.id == id));
            },
          ),
        ),
      ),
    );
  }
}

/// Compact place switcher for an app bar: shows the selected place and opens
/// a menu of watched places plus "Add a place".
class AppBarRegionPicker extends StatelessWidget {
  const AppBarRegionPicker({super.key});

  static const _addValue = '__add__';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final ids = {
      ...state.watchlist,
      ?state.userRegion?.region.id,
      ?state.selected?.id,
    };
    final shown = state.regions.where((r) => ids.contains(r.id)).toList();
    final current = state.selected;

    return PopupMenuButton<String>(
      tooltip: s.t('add_place'),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (id) {
        if (id == _addValue) {
          showPlacePicker(context);
        } else {
          state.select(state.regions.firstWhere((r) => r.id == id));
        }
      },
      itemBuilder: (_) => [
        for (final r in shown)
          PopupMenuItem(
            value: r.id,
            child: Row(
              children: [
                Icon(
                  r.id == current?.id ? Icons.place : Icons.place_outlined,
                  size: 18,
                  color: r.id == current?.id ? Ember.ember : Ember.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.region(r),
                    style: TextStyle(
                      fontWeight: r.id == current?.id
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _addValue,
          child: Row(
            children: [
              const Icon(
                Icons.add_circle_outline,
                size: 18,
                color: Ember.ember,
              ),
              const SizedBox(width: 10),
              Text(
                s.t('add_place'),
                style: const TextStyle(color: Ember.ember),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Ember.ember.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Ember.ember.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place, size: 18, color: Ember.ember),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                current == null ? s.t('add_place') : s.region(current),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Ember.ember),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with every region; tick to watch, tap a name to open it.
Future<void> showPlacePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ember.surface,
    builder: (_) => const _PlacePicker(),
  );
}

class _PlacePicker extends StatefulWidget {
  const _PlacePicker();

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final q = _query.trim().toLowerCase();
    final list = state.regions
        .where(
          (r) =>
              q.isEmpty ||
              r.name.toLowerCase().contains(q) ||
              r.nameAr.contains(q),
        )
        .toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  s.t('add_place'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  s.t('choose_places'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Ember.textMuted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: s.t('search_places'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final watched = state.watchlist.contains(r.id);
                    return CheckboxListTile(
                      value: watched,
                      activeColor: Ember.ember,
                      title: Text(s.region(r)),
                      secondary: Icon(
                        r.id == state.selected?.id
                            ? Icons.place
                            : Icons.place_outlined,
                        color: r.id == state.selected?.id
                            ? Ember.ember
                            : Ember.textMuted,
                      ),
                      onChanged: (_) => setState(() {
                        state.toggleWatch(r.id);
                        // Jump to a newly added place.
                        if (!watched) state.select(r);
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.t('done')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads the selected region's record and rebuilds when it changes.
class RecordLoader extends StatefulWidget {
  const RecordLoader({super.key, required this.builder});

  final Widget Function(BuildContext context, Region region, FireRecord record)
  builder;

  @override
  State<RecordLoader> createState() => _RecordLoaderState();
}

class _RecordLoaderState extends State<RecordLoader> {
  String? _regionId;
  Future<FireRecord>? _future;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final region = state.selected!;
    if (region.id != _regionId) {
      _regionId = region.id;
      _future = state.repository.getRecord(region.id);
    }
    return FutureBuilder<FireRecord>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            onRetry: () {
              setState(() => _regionId = null);
            },
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Ember.ember),
          );
        }
        return widget.builder(context, region, snap.data!);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, color: Ember.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            S.of(context).t('could_not_load'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            style: monoStyle(size: 11),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(S.of(context).t('retry')),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A titled card section.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.info,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Plain-language help shown from a "?" button next to the title.
  final String? info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: text.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (info != null) InfoButton(title: title, body: info!),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: text.bodySmall?.copyWith(color: Ember.textMuted),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// Opens a bottom sheet that explains something in plain words.
Future<void> showHelp(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final s = S.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ember.surface,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Long text scrolls; the button below always stays visible.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: Ember.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(sheet).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t('how_to_read'),
                      style: Theme.of(
                        sheet,
                      ).textTheme.labelMedium?.copyWith(color: Ember.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      body,
                      style: Theme.of(
                        sheet,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(s.t('got_it')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A small "?" that explains the thing next to it.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.title, required this.body});
  final String title, body;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: S.of(context).t('how_to_read'),
    visualDensity: VisualDensity.compact,
    icon: Icon(Icons.help_outline, size: 20, color: Ember.textMuted),
    onPressed: () => showHelp(context, title: title, body: body),
  );
}

/// A circled number + title, for step-by-step forms.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.number,
    required this.title,
    this.subtitle,
    this.optional = false,
    this.done = false,
  });

  final int number;
  final String title;
  final String? subtitle;
  final bool optional, done;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? Ember.calm : Ember.ember.withValues(alpha: 0.16),
          ),
          child: done
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text(
                  '$number',
                  style: const TextStyle(
                    color: Ember.ember,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: title),
                    if (optional)
                      TextSpan(
                        text: '  (${s.t('optional')})',
                        style: text.bodySmall?.copyWith(color: Ember.textMuted),
                      ),
                  ],
                ),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: Ember.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
