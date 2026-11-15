import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/services/broadcast_api.dart';
import 'package:nasa_space_apps_2026/services/device_api.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/services/push_service.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_instant').path;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
}

/// Records notifications instead of showing them.
class _Notifications extends NotificationService {
  final shown = <String>[];
  @override
  bool get supported => true;
  @override
  Future<void> init() async {}
  @override
  Future<void> show({required int id, required String title, required String body, AlertSound sound = AlertSound.chime}) async =>
      shown.add(title);
}

/// The backend's /devices and /broadcasts endpoints.
class _Server {
  final puts = <Map<String, dynamic>>[];
  final deletes = <String>[];
  late final client = MockClient((req) async {
    if (req.method == 'PUT' && req.url.path.endsWith('/devices')) {
      puts.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"ok":true,"push":true,"zones":1}', 200);
    }
    if (req.method == 'DELETE' && req.url.path.contains('/devices/')) {
      deletes.add(req.url.pathSegments.last);
      return http.Response('{"deleted":true}', 200);
    }
    if (req.url.path.endsWith('/broadcasts')) {
      return http.Response(
          jsonEncode({
            'broadcasts': [
              {
                'id': 'b1', 'title': 'Fire near the farm', 'message': 'Avoid the area', 'level': 'danger',
                'lat': 33.335, 'lon': 35.395, 'radiusKm': 5, 'expiresAt': '2099-01-01T00:00:00Z',
              },
            ],
          }),
          200);
    }
    return http.Response('{}', 404);
  });
}

const _farm = LatLng(33.3346, 35.3953);

Future<(AppState, _Notifications)> _state(_Server server, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'watchlist': <String>[], ...prefs});
  final notifications = _Notifications();
  final api = 'https://api.test/api/v1';
  final s = AppState(
    MockFireRepository(latency: Duration.zero),
    prefs: await SharedPreferences.getInstance(),
    notifications: notifications,
    deviceApi: DeviceApi(baseUrl: api, client: server.client),
    broadcastApi: BroadcastApi(baseUrl: api, client: server.client),
  );
  await s.init(checkOnStart: false);
  return (s, notifications);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // the demo data are bundled assets
  setUpAll(() => PathProviderPlatform.instance = _FakePaths());
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('nothing is sent until instant alerts are turned on', () async {
    final server = _Server();
    final (s, _) = await _state(server);
    expect(s.instantAlerts, isNull); // the app asks once
    await s.addZone('Farm', _farm, 3);
    await Future<void>.delayed(Duration.zero);
    expect(server.puts, isEmpty);
  });

  test('turned on: zones and the last location go to the server, and follow changes', () async {
    final server = _Server();
    final (s, _) = await _state(server, prefs: {
      'last_lat': 33.9, 'last_lon': 35.5, 'last_located_at': '2026-11-15T09:00:00.000Z',
    });
    await s.setInstantAlerts(true);
    expect(server.puts, hasLength(1));
    final first = server.puts.single;
    expect(first['installationId'], isA<String>());
    expect(first['token'], isNull); // no Firebase in tests
    expect(first['location'], {'lat': 33.9, 'lon': 35.5, 'at': '2026-11-15T09:00:00.000Z'});
    expect(first['zones'], isEmpty);

    await s.addZone('Farm', _farm, 3);
    await Future<void>.delayed(Duration.zero);
    final zones = server.puts.last['zones'] as List;
    expect(zones.single, containsPair('name', 'Farm'));
    expect(zones.single, containsPair('radiusKm', 3.0));

    s.setLanguage('ar');
    await Future<void>.delayed(Duration.zero);
    expect(server.puts.last['lang'], 'ar');

    // Off: the server forgets the phone.
    await s.setInstantAlerts(false);
    expect(server.deletes, [first['installationId']]);
    final count = server.puts.length;
    await s.addZone('Village', const LatLng(34, 36), 3).catchError((_) => false);
    expect(server.puts.length, count);
  });

  test('a zone alert that already arrived by push is not notified again', () async {
    final server = _Server();
    final (s, notifications) = await _state(server);
    await s.addZone('Farm', _farm, 3);
    await rememberPushed(await SharedPreferences.getInstance(), 'b1');
    await s.checkAlerts(notify: true, onlyNew: true);
    expect(s.alerts.where((a) => a.broadcast?.id == 'b1'), hasLength(1)); // still listed in the app
    expect(notifications.shown, isNot(contains('Fire near the farm')));
  });

  test('without push, the alert check notifies the zone alert', () async {
    final server = _Server();
    final (s, notifications) = await _state(server);
    await s.addZone('Farm', _farm, 3);
    await s.checkAlerts(notify: true, onlyNew: true);
    expect(notifications.shown, contains('Fire near the farm'));
  });
}
