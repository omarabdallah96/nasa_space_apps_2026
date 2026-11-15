import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/models/hotspot.dart';
import 'package:nasa_space_apps_2026/data/models/region.dart';
import 'package:nasa_space_apps_2026/data/models/zone.dart';
import 'package:nasa_space_apps_2026/data/repositories/api_fire_repository.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/services/alert_engine.dart';
import 'package:nasa_space_apps_2026/l10n/strings.dart';
import 'package:nasa_space_apps_2026/services/auth_api.dart';
import 'package:nasa_space_apps_2026/services/broadcast_api.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:nasa_space_apps_2026/ui/screens/zone_report_screen.dart';
import 'package:nasa_space_apps_2026/ui/widgets/zones_section.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_zones').path;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
  @override
  Future<String?> getApplicationCachePath() async => _dir;
  @override
  Future<String?> getTemporaryPath() async => _dir;
}

class _NoNotifications extends NotificationService {
  @override
  bool get supported => false;
}

// Two mock Lebanon hotspots (assets/mock/hotspots_lebanon.json).
const _fireA = LatLng(33.3346, 35.3953);
const _fireB = LatLng(33.2571, 35.9545);

Future<AppState> _state({Map<String, Object> prefs = const {}, AuthApi? auth}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'watchlist': <String>[], ...prefs});
  final s = AppState(
    MockFireRepository(latency: Duration.zero),
    prefs: await SharedPreferences.getInstance(),
    notifications: _NoNotifications(),
    authApi: auth,
  );
  await s.init(checkOnStart: false);
  return s;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PathProviderPlatform.instance = _FakePaths();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Asset loads are cached across tests; a cached load from an earlier
    // widget test never completes in the next one.
    rootBundle.clear();
  });

  group('zone model', () {
    final z = AlertZone(
        id: 'z', name: 'Farm', center: const LatLng(33.9, 35.8), radiusKm: 10, createdAt: DateTime(2026));

    test('contains points by distance, and its box holds the circle', () {
      expect(z.contains(const LatLng(33.95, 35.8)), isTrue); // ~5.6 km
      expect(z.contains(const LatLng(34.0, 35.8)), isFalse); // ~11 km
      final b = z.bbox;
      expect(b.north - b.south, closeTo(20 / 111.32, 1e-6));
      expect(b.east - b.west, greaterThan(b.north - b.south)); // degrees of longitude are shorter
    });

    test('survives JSON', () {
      final back = AlertZone.fromJson(jsonDecode(jsonEncode(z.toJson())) as Map<String, dynamic>);
      expect((back.name, back.center, back.radiusKm), (z.name, z.center, z.radiusKm));
    });
  });

  test('a zone alert counts confident fires inside the circle only', () {
    const engine = AlertEngine();
    final region = Region.fromJson({
      'id': 'lebanon', 'name': 'Lebanon', 'bbox': [35, 33, 36.7, 34.7], 'center': [33.9, 35.8],
    });
    Hotspot h(LatLng p, [String conf = 'nominal']) =>
        Hotspot(position: p, acquiredAt: DateTime(2026), sensor: 'VIIRS', confidence: conf, frp: 3);
    final zone = AlertZone(id: 'z', name: 'Farm', center: _fireA, radiusKm: 5, createdAt: DateTime(2026));

    expect(engine.zoneFire(zone: zone, region: region, hotspots: [h(_fireB)]), isNull);
    expect(engine.zoneFire(zone: zone, region: region, hotspots: [h(_fireA, 'low')]), isNull);
    final a = engine.zoneFire(
        zone: zone, region: region, hotspots: [h(_fireA), h(const LatLng(33.36, 35.40)), h(_fireB)])!;
    expect(a.count, 2);
    expect(a.level, AlertLevel.danger); // one is at the center
    expect(a.id, contains('_zz'));
  });

  test('one zone is free; Pro raises the limit; extra zones pause when Pro ends', () async {
    final s = await _state();
    expect((s.isPro, s.zoneLimit, s.canAddZone), (false, 1, true));
    expect(await s.addZone('Farm', _fireA, 5), isTrue);
    expect(await s.addZone('Village', _fireB, 5), isFalse);
    expect(s.zones, hasLength(1));

    s.setProTest(true); // debug-only switch (tests run in debug mode)
    expect(s.isPro, isTrue);
    expect(await s.addZone('Village', _fireB, 5), isTrue);
    expect(s.activeZones, hasLength(2));

    // Restart: zones are kept.
    final saved = (await SharedPreferences.getInstance()).getString('zones')!;
    final again = await _state(prefs: {'zones': saved});
    expect(again.zones.map((z) => z.name), ['Farm', 'Village']);
    expect(again.activeZones.map((z) => z.name), ['Farm']); // Pro off: the second is paused
  });

  test('a zone alert from the admin reaches overlapping zones and people inside only', () async {
    Map<String, Object> bc(String id, LatLng c, double r) => {
          'id': id, 'title': 'Fire $id', 'message': 'Avoid the area', 'titleAr': 'حريق $id', 'messageAr': '',
          'level': 'danger', 'lat': c.latitude, 'lon': c.longitude, 'radiusKm': r,
          'expiresAt': '2026-12-01T00:00:00Z',
        };
    final client = MockClient((req) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'broadcasts': [
            bc('near', const LatLng(33.40, 35.40), 5), // ~7 km from the farm: circles overlap (5 + 3)
            bc('far', const LatLng(34.40, 36.00), 5), // north Lebanon: no zone there
          ],
        })),
        200));
    SharedPreferences.setMockInitialValues({'onboarded': true, 'watchlist': <String>[]});
    final s = AppState(MockFireRepository(latency: Duration.zero),
        prefs: await SharedPreferences.getInstance(),
        notifications: _NoNotifications(),
        broadcastApi: BroadcastApi(baseUrl: 'https://api.test/api/v1', client: client));
    await s.init(checkOnStart: false);
    await s.addZone('Farm', _fireA, 3);
    await s.checkAlerts();

    var official = s.alerts.where((a) => a.type == AlertType.official).toList();
    expect(official.map((a) => a.broadcast!.id), ['near']);
    expect(official.single.zone!.name, 'Farm');
    expect(official.single.level, AlertLevel.danger);
    expect(const S(true).alertTitle(official.single), 'حريق near');
    expect(const S(false).alertBody(official.single), contains('your zone "Farm"'));

    // Standing inside the far circle reaches the user without a zone.
    s.lastKnownPosition = const LatLng(34.41, 36.01);
    await s.checkAlerts();
    official = s.alerts.where((a) => a.type == AlertType.official).toList();
    expect(official.map((a) => a.broadcast!.id).toSet(), {'near', 'far'});
    expect(official.firstWhere((a) => a.broadcast!.id == 'far').zone, isNull);
  });

  test('a Pro plan on the account lifts the limit', () async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({
          'user': {'id': 'u', 'email': 'a@b.co', 'name': '', 'plan': 'pro', 'createdAt': '2026-11-15T00:00:00Z'},
          'token': 'tok-aaaaaaaaaaaaaaaaaaaaaaaa',
        }),
        200));
    final s = await _state(auth: AuthApi(baseUrl: 'https://api.test/api/v1', client: client));
    expect(s.isPro, isFalse);
    await s.signIn('a@b.co', 'password-1');
    expect((s.isPro, s.zoneLimit), (true, AppState.proZoneLimit));
  });

  test('checking alerts finds a fire inside a zone', () async {
    final s = await _state();
    await s.addZone('Farm', _fireA, 3);
    await s.checkAlerts();
    final zoneAlerts = s.alerts.where((a) => a.zone?.name == 'Farm').toList();
    expect(zoneAlerts.map((a) => a.type), contains(AlertType.zoneFire));
  });

  test('the API asks for the zone record with a bbox', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add(req.url.toString());
      return http.Response('{}', 500); // the URL is what this test checks
    });
    final repo = ApiFireRepository(baseUrl: 'https://api.test/api/v1', client: client);
    await expectLater(
        repo.getAreaRecord('lebanon', west: 35.5, south: 33.8, east: 35.7, north: 34), throwsA(anything));
    expect(asked, hasLength(3));
    expect(asked.every((u) => u.contains('bbox=35.500,33.800,35.700,34.000')), isTrue);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('free users meet the paywall; Pro users get the zone report ($lang)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Map tiles cannot load in tests.
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        final msg = d.exception.toString();
        if (msg.contains('GoogleFonts') || msg.contains('HTTP request failed') ||
            msg.contains('HttpException') || msg.contains('SocketException')) {
          return;
        }
        original?.call(d);
      };
      addTearDown(() => FlutterError.onError = original);
      late AppState state;
      await tester.runAsync(() async {
        state = await _state(prefs: {'language': lang});
        await state.addZone('Farm', _fireA, 10);
      });
      Widget app(Widget home) => AppScope(
            state: state,
            child: MaterialApp(
              locale: Locale(lang),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: home,
            ),
          );
      await tester.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: ZonesSection()))));
      expect(find.text('Farm'), findsOneWidget);

      // Second zone: paywall.
      await tester.tap(find.byKey(const ValueKey('add_zone')));
      await tester.pumpAndSettle();
      expect(find.text('Firesight Pro'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro_test_switch')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro_test_switch')));
      await tester.pumpAndSettle();
      expect(state.isPro, isTrue);
      Navigator.of(tester.element(find.byKey(const ValueKey('pro_test_switch')))).pop();
      await tester.pumpAndSettle();
      // Now Pro: the editor for the second zone opens.
      expect(find.byKey(const ValueKey('zone_save')), findsOneWidget);

      // The report, in a fresh app.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(ZoneReportScreen(zone: state.zones.first)));
      // The report loads bundled demo files: real async work, then frames.
      for (var i = 0; i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(lang == 'ar' ? 'هذا الشهر' : 'This month'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text(lang == 'ar' ? 'موسم الحرائق هنا' : 'Fire season here'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(lang == 'ar' ? 'موسم الحرائق هنا' : 'Fire season here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
