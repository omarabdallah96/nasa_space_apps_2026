import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/main.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/services/weather_service.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:nasa_space_apps_2026/ui/screens/report_screen.dart';
import 'package:nasa_space_apps_2026/ui/widgets/compass_aim.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_ux').path;
  @override
  Future<String?> getApplicationCachePath() async => _dir;
  @override
  Future<String?> getTemporaryPath() async => _dir;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

class _NoNotifications extends NotificationService {
  @override
  bool get supported => false;
}

class _FakeWeather extends WeatherService {
  @override
  Future<FireWeather> current(LatLng p) async => const FireWeather(
      temperatureC: 24, humidity: 30, windKmh: 18, gustKmh: 30, precipitationMm: 0);

  @override
  Future<List<DayForecast>> forecast(LatLng p, {int days = 7}) async => [
        for (var i = 0; i < days; i++)
          DayForecast(
            DateUtils.dateOnly(DateTime.now()).add(Duration(days: i)),
            const FireWeather(
                temperatureC: 18, humidity: 50, windKmh: 10, gustKmh: 20, precipitationMm: 0),
          ),
      ];
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PathProviderPlatform.instance = _FakePaths();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('help sheet, map legend and stepped report work on a small phone ($lang)',
        (tester) async {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        final msg = d.exception.toString();
        if (msg.contains('GoogleFonts') || msg.contains('HTTP request failed')) return;
        original?.call(d);
      };
      addTearDown(() => FlutterError.onError = original);

      await tester.binding.setSurfaceSize(const Size(360, 740));
      SharedPreferences.setMockInitialValues({'language': lang, 'onboarded': true});
      final state = AppState(
        MockFireRepository(latency: Duration.zero),
        prefs: await SharedPreferences.getInstance(),
        notifications: _NoNotifications(),
        weather: _FakeWeather(),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(FiresightApp(state: state, minSplash: Duration.zero));
        await state.init();
      });
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));

      // The answer card has a "?" that explains it.
      await tester.tap(find.byIcon(Icons.help_outline).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      await tester.tap(find.text(lang == 'ar' ? 'فهمت' : 'Got it'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Map tab: legend explains the symbols.
      await tester.tap(find.byIcon(Icons.map_outlined).last);
      await settle(tester);
      await tester.tap(find.byIcon(Icons.info_outline).last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text(lang == 'ar' ? 'دليل الخريطة' : 'Map legend'), findsWidgets);
      await tester.tapAt(const Offset(180, 40)); // dismiss the sheet
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Report: Send is disabled until a label is chosen; compass only for smoke.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const ReportScreen()));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      FilledButton send() => tester.widget<FilledButton>(find.ancestor(
          of: find.byIcon(Icons.send), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(send().onPressed, isNull);
      expect(find.byType(CompassAim), findsNothing);

      await tester.tap(find.text(lang == 'ar' ? 'دخان من بعيد' : 'Smoke in the distance'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CompassAim), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
