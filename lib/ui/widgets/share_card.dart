import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/fire_record.dart';
import '../../data/models/region.dart';
import '../../domain/anomaly.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import 'common.dart';
import 'fire_rings.dart';

/// Shows a preview of the PNG card and shares it (WhatsApp, X, ...).
Future<void> showShareCard(
    BuildContext context, Region region, FireRecord record) {
  final key = GlobalKey();
  final s = S.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ember.background,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t('share_card'),
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            FittedBox(
              child: RepaintBoundary(
                key: key,
                child: ShareCard(region: region, record: record),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: Text(s.t('share')),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _shareBoundary(key, region, s.sentence(summarize(record), region));
                  } catch (_) {
                    messenger.showSnackBar(SnackBar(content: Text(s.t('share_failed'))));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _shareBoundary(GlobalKey key, Region region, String text) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final name = 'ember_almanac_${region.id}.png';

  final XFile file;
  if (kIsWeb) {
    file = XFile.fromData(bytes, name: name, mimeType: 'image/png');
  } else {
    final path = '${(await getTemporaryDirectory()).path}/$name';
    await File(path).writeAsBytes(bytes);
    file = XFile(path, mimeType: 'image/png');
  }
  await SharePlus.instance.share(ShareParams(files: [file], text: text));
}

/// The card itself: sentence + Fire Rings + branding. Fixed size for a
/// consistent PNG.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.region, required this.record});

  final Region region;
  final FireRecord record;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final summary = summarize(record);
    final color = Ember.forStatus(summary.status);
    final text = Theme.of(context).textTheme;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Ember.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ember.outline),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), Ember.background],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Ember.ember, size: 20),
              const SizedBox(width: 6),
              Text(s.t('app_name'),
                  style: text.titleLarge?.copyWith(fontSize: 18)),
              const Spacer(),
              StatusPill(label: s.status(summary.status), color: color),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.sentence(summary, region),
              style: text.titleLarge?.copyWith(fontSize: 19, height: 1.3)),
          const SizedBox(height: 16),
          Center(
            child: FireRings(
              record: record,
              size: 250,
              caption: s.t('rings_caption'),
            ),
          ),
          const SizedBox(height: 14),
          Text(s.t('card_footer'),
              style: monoStyle(size: 9.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
