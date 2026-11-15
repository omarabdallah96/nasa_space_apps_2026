import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/zone.dart';

/// A signed-in person. Signing in is optional: the app works as a guest.
class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
    this.plan = 'free',
  });

  final String id;
  final String email;
  final String name;
  final DateTime createdAt;

  /// 'free' or 'pro'. Set on the server (by a purchase, or by an admin).
  final String plan;
  bool get isPro => plan == 'pro';

  /// The name when set, otherwise the part of the email before the @.
  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        plan: j['plan'] as String? ?? 'free',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'plan': plan,
      };
}

/// A failed account request. [code] is the backend's error code
/// (`wrong_credentials`, `email_taken`, `weak_password`, `bad_email`,
/// `rate_limited`, `signed_out`…) or `offline` when the server was not reached.
class AuthException implements Exception {
  const AuthException(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'AuthException($code${message == null ? '' : ': $message'})';
}

/// The backend's `/auth` endpoints. Bearer tokens, no cookies.
class AuthApi {
  AuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `https://cedx.coding-now.online/api/v1`
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<({AccountUser user, String token})> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final j = await _send('POST', '/auth/register',
        body: {'email': email, 'password': password, 'name': name});
    return (user: AccountUser.fromJson(j['user'] as Map<String, dynamic>), token: j['token'] as String);
  }

  Future<({AccountUser user, String token})> login({
    required String email,
    required String password,
  }) async {
    final j = await _send('POST', '/auth/login', body: {'email': email, 'password': password});
    return (user: AccountUser.fromJson(j['user'] as Map<String, dynamic>), token: j['token'] as String);
  }

  /// Throws `AuthException('signed_out')` when the token is no longer valid.
  Future<AccountUser> me(String token) async =>
      AccountUser.fromJson((await _send('GET', '/auth/me', token: token))['user'] as Map<String, dynamic>);

  Future<AccountUser> updateName(String token, String name) async => AccountUser.fromJson(
      (await _send('PATCH', '/auth/me', token: token, body: {'name': name}))['user'] as Map<String, dynamic>);

  Future<void> logout(String token) => _send('POST', '/auth/logout', token: token);

  Future<void> deleteAccount(String token, String password) =>
      _send('DELETE', '/auth/me', token: token, body: {'password': password});

  /// Alert zones saved to the account. [saved] is false when the app never
  /// saved them: the server then answers with the zones of the user's newest
  /// phone, if any.
  Future<({List<AlertZone> zones, bool saved})> zones(String token) async {
    final j = await _send('GET', '/me/zones', token: token);
    return (
      zones: [for (final z in j['zones'] as List) AlertZone.fromJson(z as Map<String, dynamic>)],
      saved: j['updatedAt'] != null,
    );
  }

  Future<void> saveZones(String token, List<AlertZone> zones) =>
      _send('PUT', '/me/zones', token: token, body: {'zones': [for (final z in zones) z.toJson()]});

  Future<Map<String, dynamic>> _send(String method, String path,
      {String? token, Map<String, dynamic>? body}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } on Exception {
      // Timeout, ClientException, SocketException: the server was not reached.
      throw const AuthException('offline');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final error = json['error'];
    if (error is Map) {
      throw AuthException(error['code'] as String? ?? 'unknown', error['message'] as String?);
    }
    throw AuthException(res.statusCode == 401 ? 'signed_out' : 'unknown');
  }
}
