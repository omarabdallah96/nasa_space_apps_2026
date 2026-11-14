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
import 'package:nasa_space_apps_2026/theme/app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The map tile cache asks for a folder; give it a temp one in tests.
class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_test').path;
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
            FireWeather(
                temperatureC: 18, humidity: 40.0 + i * 5, windKmh: 20.0 - i * 2,
                gustKmh: 30, precipitationMm: 0),
          ),
      ];
}

Future<AppState> _state(String lang) async {
  SharedPreferences.setMockInitialValues({'language': lang, 'onboarded': true});
  final state = AppState(
    MockFireRepository(latency: Duration.zero),
    prefs: await SharedPreferences.getInstance(),
    notifications: _NoNotifications(),
    weather: _FakeWeather(),
  );
  return state;
}

/// Lets real async work (asset loading) finish, then rebuilds.
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
    testWidgets('all tabs render without layout errors ($lang)', (tester) async {
      // Fonts can't download in tests; ignore only that error.
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exception.toString().contains('GoogleFonts')) return;
        original?.call(d);
      };
      addTearDown(() => FlutterError.onError = original);

      await tester.binding.setSurfaceSize(const Size(400, 860));
      final state = await _state(lang);
      await tester.runAsync(() async {
        await tester.pumpWidget(FiresightApp(state: state, minSplash: Duration.zero));
        await state.init();
      });
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600)); // splash fade-out

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text(lang == 'ar' ? 'هل موسم الحرائق هذا طبيعي؟' : 'Is this fire season normal?'),
          findsOneWidget);

      for (final icon in [
        Icons.calendar_month_outlined,
        Icons.notifications_none,
      ]) {
        await tester.tap(find.byIcon(icon).last);
        await settle(tester);
      }
      // Settings tab.
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(lang == 'ar' ? 'الإعدادات' : 'Settings'), findsWidgets);
      await tester.drag(find.byType(ListView).last, const Offset(0, -800));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light/dark toggle switches colors and is remembered', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception.toString().contains('GoogleFonts')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    addTearDown(() => Ember.isDark = true);

    await tester.binding.setSurfaceSize(const Size(400, 860));
    final state = await _state('en');
    await tester.runAsync(() async {
      await tester.pumpWidget(FiresightApp(state: state, minSplash: Duration.zero));
      await state.init();
    });
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));

    Color bg() => tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold).last)).scaffoldBackgroundColor;
    final darkBg = bg();

    // Theme lives on the Settings tab.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Light'));
    await settle(tester);
    expect(state.darkMode, isFalse);
    expect(bg(), isNot(darkBg));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('dark_mode'), isFalse);

    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(state.darkMode, isTrue);
    expect(bg(), darkBg);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5)); // drain pending timers
  });

  testWidgets('first launch: splash, then onboarding, then the app', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception.toString().contains('GoogleFonts')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    await tester.binding.setSurfaceSize(const Size(400, 860));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(
      MockFireRepository(latency: Duration.zero),
      prefs: prefs,
      notifications: _NoNotifications(),
      weather: _FakeWeather(),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(FiresightApp(
          state: state, minSplash: const Duration(milliseconds: 300)));
      await state.init();
    });

    // Splash first.
    await tester.pump();
    expect(find.text('Firesight'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Then the intro (the splash timer runs in real time).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Next'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump(); // starts the page animation
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Allow location'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(prefs.getBool('onboarded'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
