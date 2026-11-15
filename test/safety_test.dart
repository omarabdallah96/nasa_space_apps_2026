import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/models/safety.dart';
import 'package:nasa_space_apps_2026/services/safety_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shaped like the backend's answers (server/safety.ts).
const _resources = {
  'center': {'lat': 33.62, 'lon': 35.7},
  'radiusKm': 10,
  'count': 2,
  'resources': [
    {
      'id': 'way/1',
      'kind': 'water',
      'detail': 'river',
      'name': 'Litani River',
      'nameAr': 'نهر الليطاني',
      'lat': 33.61,
      'lon': 35.69,
      'distanceKm': 1.09,
      'bearingDeg': 220,
    },
    {
      'id': 'node/2',
      'kind': 'fire_station',
      'detail': 'fire_station',
      'name': null,
      'nameAr': null,
      'lat': 33.6,
      'lon': 35.72,
      'distanceKm': 2.8,
      'bearingDeg': 140,
    },
  ],
};

const _escape = {
  'from': {'lat': 33.62, 'lon': 35.7},
  'wind': {'speedKmh': 8.5, 'fromDeg': 282},
  'danger': [
    [
      [33.65, 35.73],
      [33.64, 35.75],
      [33.63, 35.73],
      [33.65, 35.73],
    ],
  ],
  'startInDanger': false,
  'routes': [
    {
      'destination': {'name': 'Bab Maraa', 'nameAr': 'باب مارع', 'kind': 'town', 'detail': 'village', 'lat': 33.58, 'lon': 35.68},
      'distanceKm': 5.36,
      'durationMin': 7,
      'headingDeg': 204,
      'exposureKm': 0,
      'safe': true,
      'provider': 'osrm',
      'geometry': [
        [33.62, 35.7],
        [33.6, 35.69],
        [33.58, 35.68],
      ],
    },
    {
      'destination': {'name': null, 'nameAr': null, 'kind': 'direction', 'detail': 'away', 'lat': 33.6, 'lon': 35.6},
      'distanceKm': 9,
      'durationMin': 12,
      'headingDeg': 260,
      'exposureKm': 0.5,
      'safe': false,
      'provider': 'osrm',
      'geometry': [
        [33.62, 35.7],
        [33.6, 35.6],
      ],
    },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads resources and escape plans from the backend', () async {
    final asked = <Uri>[];
    final api = SafetyApi(
      baseUrl: 'https://x/api/v1',
      client: MockClient((req) async {
        asked.add(req.url);
        final body = req.url.path.endsWith('/resources') ? _resources : _escape;
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

    final res = await api.resources(const LatLng(33.62, 35.7));
    expect(res.offline, isFalse);
    expect(res.value.map((r) => r.kind), [ResourceKind.water, ResourceKind.fireStation]);
    expect(res.value.first.displayName(true), 'نهر الليطاني');
    expect(res.value.first.displayName(false), 'Litani River');
    expect(res.value[1].displayName(false), isNull);

    final far = const LatLng(34.5, 36.5), near = const LatLng(33.64, 35.73);
    final plan = await api.escape(const LatLng(33.62, 35.7), [far, near]);
    expect(plan.value.wind!.towardDeg, 102);
    expect(plan.value.danger.single, hasLength(4));
    expect(plan.value.routes.first.safe, isTrue);
    expect(plan.value.routes.first.points.last, const LatLng(33.58, 35.68));
    expect(plan.value.routes[1].destinationKind, isNull);

    // The nearest fire goes first.
    expect(asked.last.queryParameters['fires'], '33.6400,35.7300;34.5000,36.5000');
    expect(asked.first.queryParameters['radiusKm'], '10.0');
  });

  test('uses the saved copy when the server cannot be reached', () async {
    var online = true;
    final api = SafetyApi(
      baseUrl: 'https://x/api/v1',
      client: MockClient((req) async {
        if (!online) throw http.ClientException('no network');
        return http.Response.bytes(utf8.encode(jsonEncode(_escape)), 200);
      }),
    );
    const zone = LatLng(33.62, 35.7);
    await api.escape(zone, const []);
    online = false;
    final saved = await api.escape(zone, const []);
    expect(saved.offline, isTrue);
    expect(saved.value.routes, hasLength(2));
    // Nothing saved for this place: the error goes to the screen.
    expect(() => api.escape(const LatLng(10, 10), const []), throwsA(isA<http.ClientException>()));
  });

  test('a server error is not saved over a good copy', () async {
    var status = 200;
    final api = SafetyApi(
      baseUrl: 'https://x/api/v1',
      client: MockClient((_) async => status == 200
          ? http.Response.bytes(utf8.encode(jsonEncode(_resources)), 200)
          : http.Response('{"error":{}}', status)),
    );
    await api.resources(const LatLng(33.62, 35.7));
    status = 503;
    final r = await api.resources(const LatLng(33.62, 35.7));
    expect(r.offline, isTrue);
    expect(r.value, hasLength(2));
  });
}
