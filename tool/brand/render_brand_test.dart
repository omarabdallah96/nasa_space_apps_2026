// Renders the Ember Almanac logo (lib/ui/brand/ember_logo.dart) to the PNGs
// used for the launcher icon and the native splash screen.
//
// Run:   flutter test tool/brand/render_brand_test.dart
// Then:  dart run flutter_launcher_icons
//        dart run flutter_native_splash:create

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa_space_apps_2026/ui/brand/ember_logo.dart';

Future<void> _render(String path, int px, EmberLogoPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(px.toDouble(), px.toDouble());
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path');
}

void main() {
  testWidgets('render brand assets', (tester) async {
    await tester.runAsync(() async {
      // Full launcher icon (iOS, legacy Android): square, the OS rounds it.
      await _render('assets/brand/icon.png', 1024,
          const EmberLogoPainter(background: true, scale: 0.82, cornerRadius: 0));
      // Android adaptive icon foreground: transparent, inside the 66% safe zone.
      await _render('assets/brand/icon_foreground.png', 1024,
          const EmberLogoPainter(scale: 0.56));
      // Native splash: transparent logo. Android 12 crops to a circle of
      // 2/3 the image, so the logo stays inside that.
      await _render('assets/brand/splash_logo.png', 1152,
          const EmberLogoPainter(scale: 0.58));
      // Android notification icon: white silhouette.
      for (final (dir, px) in [('mdpi', 24), ('hdpi', 36), ('xhdpi', 48), ('xxhdpi', 72), ('xxxhdpi', 96)]) {
        await _render('android/app/src/main/res/drawable-$dir/ic_stat_ember.png', px,
            const EmberLogoPainter(scale: 0.98, monochrome: true));
      }
      // Logo for README / slides.
      await _render('assets/brand/logo.png', 512,
          const EmberLogoPainter(scale: 0.96));
    });
  });
}
