import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/report_store.dart';
import '../../theme/app_theme.dart';
import '../screens/map_screen.dart' show labelIcon;

/// The photo of a report: from the phone for this phone's reports, from the
/// server for everyone else's. Null when the report has none.
class ReportPhoto extends StatelessWidget {
  const ReportPhoto(this.report, {super.key, this.size, this.fit = BoxFit.cover});

  final FieldReport report;

  /// Square thumbnail of this size; full width when null.
  final double? size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox.square(
      dimension: size ?? 48,
      child: Icon(Icons.broken_image_outlined, color: Ember.textMuted),
    );
    final local = report.photoPath;
    final remote = report.photoUrl;
    if (local != null && !kIsWeb) {
      return Image.file(File(local),
          width: size, height: size, fit: fit, errorBuilder: (_, _, _) => fallback);
    }
    if (remote != null) {
      return Image.network(
        remote,
        width: size,
        height: size,
        fit: fit,
        // Keeps memory low for list thumbnails.
        cacheWidth: size == null ? null : (size! * 3).round(),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                width: size ?? double.infinity,
                height: size ?? 220,
                child: const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember),
                  ),
                ),
              ),
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Details of one field report, opened from its marker on the map.
void showReportSheet(BuildContext context, FieldReport r, {required bool mine}) {
  final s = S.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ember.surface,
    builder: (sheet) {
      final text = Theme.of(sheet).textTheme;
      final age = DateTime.now().difference(r.createdAt);
      final ago = age.inMinutes < 60
          ? '${age.inMinutes.clamp(1, 59)} ${s.t('report_min_ago')}'
          : '${age.inHours} ${s.t('report_h_ago')}';
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(labelIcon(r.label), color: mine ? Ember.calm : Ember.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(s.label(r.label), style: text.titleLarge)),
              ]),
              const SizedBox(height: 4),
              Text('${s.t(mine ? 'report_by_you' : 'report_by_other')} · $ago', style: monoStyle(size: 12)),
              if (r.hasPhoto) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SizedBox(width: double.infinity, child: ReportPhoto(r)),
                  ),
                ),
              ],
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.note, style: text.bodyLarge),
              ],
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${r.position.latitude.toStringAsFixed(4)}, ${r.position.longitude.toStringAsFixed(4)}'
                  '${r.bearing == null ? '' : ' · ${r.bearing!.round()}°'}',
                  style: monoStyle(size: 12),
                ),
              ),
              if (r.bearing != null) ...[
                const SizedBox(height: 4),
                Text(s.t('report_bearing_note'), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
              ],
            ],
          ),
        ),
      );
    },
  );
}
