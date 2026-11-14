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
        await tester.pumpWidget(EmberAlmanacApp(state: state, minSplash: Duration.zero));
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
      expect(tester.takeException(), isNull);
    });
  }

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
      await tester.pumpWidget(EmberAlmanacApp(
          state: state, minSplash: const Duration(milliseconds: 300)));
      await state.init();
    });

    // Splash first.
    await tester.pump();
    expect(find.text('Ember Almanac'), findsOneWidget);
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
