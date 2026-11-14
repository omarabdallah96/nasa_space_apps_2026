import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/repositories/api_fire_repository.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/services/report_api.dart';
import 'package:nasa_space_apps_2026/services/report_store.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final _dir = Directory.systemTemp.createTempSync('ember_sync').path;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
}

class _NoNotifications extends NotificationService {
  @override
  bool get supported => false;
}

/// A tiny stand-in for the backend's /reports endpoints.
class _FakeBackend {
  final stored = <Map<String, dynamic>>[];
  final deleted = <String>[];
  bool offline = false;
  int posts = 0;

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    if (req.method == 'POST' && req.url.path.endsWith('/reports')) {
      posts++;
      final body = utf8.decode(req.bodyBytes);
      String field(String name) =>
          RegExp('name="$name"\\r\\n\\r\\n([^\\r]*)').firstMatch(body)!.group(1)!;
      final report = {
        'id': 'srv-${stored.length + 1}',
        'lat': double.parse(field('lat')),
        'lon': double.parse(field('lon')),
        'createdAt': field('createdAt'),
        'label': field('label'),
        'note': '',
        'bearing': double.parse(field('bearing')),
        'hasPhoto': false,
      };
      stored.add(report);
      return http.Response(jsonEncode({'report': report, 'deleteToken': 'tok-${report['id']}'}), 201);
    }
    if (req.method == 'GET' && req.url.path.endsWith('/reports')) {
      return http.Response(jsonEncode({'reports': stored}), 200);
    }
    if (req.method == 'DELETE') {
      expect(req.headers['X-Report-Token'], 'tok-${req.url.pathSegments.last}');
      deleted.add(req.url.pathSegments.last);
      return http.Response('{"deleted":true}', 200);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  // The fire and two places that see its smoke from different directions.
  const fire = LatLng(33.80, 35.70);
  const me = LatLng(33.70, 35.55);
  const neighbour = LatLng(33.92, 35.58);
  double bearing(LatLng from) => (const Distance().bearing(from, fire) + 360) % 360;

  Future<AppState> state(_FakeBackend backend) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final s = AppState(
      MockFireRepository(latency: Duration.zero),
      prefs: await SharedPreferences.getInstance(),
      notifications: _NoNotifications(),
      reportApi: ReportApi(baseUrl: 'https://api.test/api/v1', client: backend.client),
    );
    await s.init(checkOnStart: false);
    return s;
  }

  test('uploads a report, and crosses it with a neighbour\'s to find the fire', () async {
    final backend = _FakeBackend();
    // Someone else already reported the smoke.
    backend.stored.add({
      'id': 'other-1',
      'lat': neighbour.latitude,
      'lon': neighbour.longitude,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'label': 'smoke',
      'bearing': bearing(neighbour),
    });
    final s = await state(backend);

    await s.addReport(FieldReport(
      id: '1731580000000',
      position: me,
      createdAt: DateTime.now(),
      label: ReportLabel.smoke,
      bearing: bearing(me),
    ));

    expect(backend.posts, 1);
    expect(s.reports.single.remoteId, 'srv-2');
    expect(s.reports.single.deleteToken, 'tok-srv-2');
    // Own report comes back from the server too, but is not counted twice.
    expect(s.sharedReports.length, 2);
    expect(s.smokeEstimates, hasLength(1));
    expect(s.smokeEstimates.single.reports, hasLength(2));
    expect(const Distance().as(LengthUnit.Kilometer, s.smokeEstimates.single.center, fire),
        lessThan(1));

    // Deleting removes it from the server with its token.
    await s.deleteReport('1731580000000');
    expect(backend.deleted, ['srv-2']);
  });

  test('keeps reports queued while offline and sends them later', () async {
    final backend = _FakeBackend()..offline = true;
    final s = await state(backend);
    await s.addReport(FieldReport(
        id: '42000', position: me, createdAt: DateTime.now(), label: ReportLabel.wildfire, bearing: 10));
    expect(s.reports.single.uploaded, isFalse);

    backend.offline = false;
    await s.syncReports();
    expect(s.reports.single.uploaded, isTrue);
    // Survives a restart.
    final prefs = await SharedPreferences.getInstance();
    expect(ReportStore(prefs).load().single.remoteId, 'srv-1');
  });

  test('reads live hotspots, and falls back to the daily record', () async {
    PathProviderPlatform.instance = _FakePaths();
    var liveUp = true;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/live')) {
        if (!liveUp) return http.Response('{"error":{}}', 503);
        return http.Response(jsonEncode({
          'hotspots': [
            {'lat': 33.9, 'lon': 35.7, 'acquiredAt': '2026-11-14T11:10:00Z', 'sensor': 'VIIRS_NOAA21', 'confidence': 'high', 'frp': 4.2},
          ],
        }), 200);
      }
      return http.Response(jsonEncode({
        'hotspots': [
          {'latitude': 34.1, 'longitude': 35.9, 'acq_date': '2026-11-13', 'acq_time': '105', 'satellite': 'N20', 'instrument': 'VIIRS', 'confidence': 'l', 'frp': 1.0},
        ],
      }), 200);
    });

    final live = await ApiFireRepository(baseUrl: 'https://api.test/api/v1', client: client)
        .getRecentHotspots('lebanon');
    expect(live.single.sensor, 'VIIRS_NOAA21');
    expect(live.single.confidence, 'high');

    // A fresh install with no cached live answer and the live feed down.
    PathProviderPlatform.instance = _FakePaths();
    liveUp = false;
    final daily = await ApiFireRepository(baseUrl: 'https://api.test/api/v1', client: client)
        .getRecentHotspots('lebanon');
    expect(daily.single.acquiredAt, DateTime.utc(2026, 11, 13, 1, 5));
    expect(daily.single.confidence, 'low');
    expect(daily.single.sensor, 'VIIRS_NOAA20');
  });
}
