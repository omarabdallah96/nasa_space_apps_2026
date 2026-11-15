import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nasa_space_apps_2026/data/repositories/mock_fire_repository.dart';
import 'package:nasa_space_apps_2026/services/auth_api.dart';
import 'package:nasa_space_apps_2026/services/notification_service.dart';
import 'package:nasa_space_apps_2026/state/app_state.dart';
import 'package:nasa_space_apps_2026/ui/screens/auth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotifications extends NotificationService {
  @override
  bool get supported => false;
}

/// A tiny stand-in for the backend's /auth endpoints.
class _FakeAuthBackend {
  final users = <String, ({String password, String name})>{};
  final sessions = <String, String>{}; // token → email
  final zones = <String, List<dynamic>>{}; // email → zones saved to the account
  bool offline = false;
  var _n = 0;

  Map<String, dynamic> _user(String email) => {
        'id': 'u-$email',
        'email': email,
        'name': users[email]!.name,
        'createdAt': '2026-11-15T10:00:00.000Z',
      };

  http.Response _error(int status, String code) =>
      http.Response(jsonEncode({'error': {'code': code, 'message': code}}), status);

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    final path = req.url.path.replaceFirst('/api/v1', '');
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final token = req.headers['Authorization']?.replaceFirst('Bearer ', '');
    final me = sessions[token];
    String open(String email) {
      final t = 'token-${++_n}-aaaaaaaaaaaaaaaaaaaa';
      sessions[t] = email;
      return t;
    }

    switch ((req.method, path)) {
      case ('POST', '/auth/register'):
        final email = (body['email'] as String).trim().toLowerCase();
        if (users.containsKey(email)) return _error(409, 'email_taken');
        users[email] = (password: body['password'] as String, name: body['name'] as String? ?? '');
        return http.Response(jsonEncode({'user': _user(email), 'token': open(email)}), 201);
      case ('POST', '/auth/login'):
        final email = (body['email'] as String).trim().toLowerCase();
        if (users[email]?.password != body['password']) return _error(401, 'wrong_credentials');
        return http.Response(jsonEncode({'user': _user(email), 'token': open(email)}), 200);
      case ('GET', '/auth/me'):
        if (me == null) return _error(401, 'signed_out');
        return http.Response(jsonEncode({'user': _user(me)}), 200);
      case ('PATCH', '/auth/me'):
        if (me == null) return _error(401, 'signed_out');
        users[me] = (password: users[me]!.password, name: body['name'] as String);
        return http.Response(jsonEncode({'user': _user(me)}), 200);
      case ('GET', '/me/zones'):
        if (me == null) return _error(401, 'signed_out');
        final saved = zones[me];
        return http.Response(
            jsonEncode({'zones': saved ?? [], 'updatedAt': saved == null ? null : '2026-11-15T12:00:00.000Z'}), 200);
      case ('PUT', '/me/zones'):
        if (me == null) return _error(401, 'signed_out');
        zones[me] = body['zones'] as List<dynamic>;
        return http.Response(jsonEncode({'zones': zones[me], 'updatedAt': '2026-11-15T12:00:00.000Z'}), 200);
      case ('POST', '/auth/logout'):
        sessions.remove(token);
        return http.Response('{"signedIn":false}', 200);
      case ('DELETE', '/auth/me'):
        if (me == null) return _error(401, 'signed_out');
        if (users[me]!.password != body['password']) return _error(401, 'wrong_credentials');
        users.remove(me);
        sessions.removeWhere((_, e) => e == me);
        return http.Response('{"deleted":true}', 200);
    }
    return _error(404, 'not_found');
  });
}

Future<AppState> _state(_FakeAuthBackend backend,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, ...prefs});
  final s = AppState(
    MockFireRepository(latency: Duration.zero),
    prefs: await SharedPreferences.getInstance(),
    notifications: _NoNotifications(),
    authApi: AuthApi(baseUrl: 'https://api.test/api/v1', client: backend.client),
  );
  await s.init(checkOnStart: false);
  return s;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts as a guest, signs up, and is still signed in after a restart', () async {
    final backend = _FakeAuthBackend();
    var s = await _state(backend);
    expect(s.isGuest, isTrue);
    expect(s.accountsAvailable, isTrue);

    await s.register(' Rana@Example.com ', 'password-1', name: 'Rana');
    expect(s.isGuest, isFalse);
    expect(s.user!.email, 'rana@example.com');
    expect(s.user!.displayName, 'Rana');

    // Restart: prefs and secure storage keep the session (mock values persist in-process).
    final prefs = await SharedPreferences.getInstance();
    s = await _state(backend, prefs: {'account_user': prefs.getString('account_user')!});
    expect(s.user?.email, 'rana@example.com');
  });

  test('wrong password and taken email are reported', () async {
    final backend = _FakeAuthBackend();
    final s = await _state(backend);
    await s.register('a@b.co', 'password-1');
    await s.signOut();
    expect(s.isGuest, isTrue);

    await expectLater(s.signIn('a@b.co', 'nope'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'wrong_credentials')));
    await expectLater(s.register('a@b.co', 'password-2'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'email_taken')));
    expect(s.isGuest, isTrue);

    await s.signIn('A@B.CO ', 'password-1');
    expect(s.isGuest, isFalse);
  });

  test('an ended session signs out on launch; offline keeps the saved user', () async {
    final backend = _FakeAuthBackend();
    var s = await _state(backend);
    await s.register('a@b.co', 'password-1');
    final saved = (await SharedPreferences.getInstance()).getString('account_user')!;

    backend.offline = true;
    s = await _state(backend, prefs: {'account_user': saved});
    await s.refreshAccount();
    expect(s.user?.email, 'a@b.co');

    backend.offline = false;
    backend.sessions.clear(); // e.g. expired on the server
    s = await _state(backend, prefs: {'account_user': saved});
    await s.refreshAccount();
    expect(s.isGuest, isTrue);
  });

  test('renames and deletes the account', () async {
    final backend = _FakeAuthBackend();
    final s = await _state(backend);
    await s.register('a@b.co', 'password-1');
    await s.updateName('Omar');
    expect(s.user!.name, 'Omar');

    await expectLater(s.deleteAccount('wrong'), throwsA(isA<AuthException>()));
    expect(s.isGuest, isFalse);
    await s.deleteAccount('password-1');
    expect(s.isGuest, isTrue);
    expect(backend.users, isEmpty);
  });

  group('zones saved to the account', () {
    List<String> names(AppState s) => [for (final z in s.zones) z.name];

    test('come back after a reinstall', () async {
      final backend = _FakeAuthBackend();
      var s = await _state(backend);
      await s.register('a@b.co', 'password-1');
      await s.addZone('Akkar', const LatLng(34.45, 36.24), 10);
      await pumpEventQueue();
      expect([for (final z in backend.zones['a@b.co']!) z['name']], ['Akkar']);

      // Reinstall: no zones on the phone, the session signed in again.
      final user = (await SharedPreferences.getInstance()).getString('account_user')!;
      s = await _state(backend, prefs: {'account_user': user});
      await s.refreshAccount();
      expect(names(s), ['Akkar']);
    });

    test('signing in keeps the guest zones and adds the account ones', () async {
      final backend = _FakeAuthBackend();
      var s = await _state(backend);
      await s.register('a@b.co', 'password-1');
      await s.addZone('Akkar', const LatLng(34.45, 36.24), 10);
      await pumpEventQueue();

      s = await _state(backend); // New phone, as a guest.
      await s.addZone('Home', const LatLng(33.89, 35.52), 5);
      await s.signIn('a@b.co', 'password-1');
      await pumpEventQueue();
      expect(names(s), ['Akkar', 'Home']);
      expect([for (final z in backend.zones['a@b.co']!) z['name']], ['Akkar', 'Home']);
    });

    test('a change made offline is uploaded on the next launch, not overwritten', () async {
      final backend = _FakeAuthBackend();
      final s = await _state(backend);
      await s.register('a@b.co', 'password-1');
      await s.addZone('Akkar', const LatLng(34.45, 36.24), 10);
      await pumpEventQueue();

      backend.offline = true;
      await s.deleteZone(s.zones.single.id);
      await pumpEventQueue();
      expect(backend.zones['a@b.co'], isNotEmpty);

      backend.offline = false;
      final prefs = await SharedPreferences.getInstance();
      final next = await _state(backend, prefs: {
        for (final k in prefs.getKeys()) k: prefs.get(k)!,
      });
      await next.refreshAccount();
      expect(next.zones, isEmpty);
      expect(backend.zones['a@b.co'], isEmpty);
    });
  });

  test('demo mode has no accounts', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(MockFireRepository(latency: Duration.zero),
        prefs: await SharedPreferences.getInstance(), notifications: _NoNotifications());
    await s.init(checkOnStart: false);
    expect(s.accountsAvailable, isFalse);
    expect(s.isGuest, isTrue);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('sign-in screen shows errors, then signs in ($lang)', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final backend = _FakeAuthBackend()
        ..users['a@b.co'] = (password: 'password-1', name: 'Rana');
      late AppState state;
      await tester.runAsync(() async => state = await _state(backend));
      bool? result;
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await AuthScreen.open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Client-side check first.
      await tester.enterText(find.byKey(const ValueKey('auth_email')), 'not-an-email');
      await tester.tap(find.byKey(const ValueKey('auth_submit')));
      await tester.pump();
      expect(find.text(lang == 'ar' ? 'أدخل بريداً إلكترونياً صحيحاً' : 'Enter a valid email address'),
          findsOneWidget);

      // Wrong password comes back from the server.
      await tester.enterText(find.byKey(const ValueKey('auth_email')), 'a@b.co');
      await tester.enterText(find.byKey(const ValueKey('auth_password')), 'wrong-password');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('auth_submit')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(
          find.text(lang == 'ar'
              ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة'
              : 'Wrong email or password'),
          findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('auth_password')), 'password-1');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('auth_submit')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(state.user?.displayName, 'Rana');
      expect(tester.takeException(), isNull);
    });
  }
}
