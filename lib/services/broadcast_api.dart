import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/broadcast.dart';

/// Zone alerts sent from the admin page (`GET /broadcasts`). Every phone gets
/// all active ones and matches them to its own zones, so zones stay private.
class BroadcastApi {
  BroadcastApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `https://firesight.coding-now.online/api/v1`
  final String baseUrl;
  final http.Client _client;

  Future<List<Broadcast>> active() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/broadcasts'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw http.ClientException('GET /broadcasts → ${res.statusCode}');
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final b in json['broadcasts'] as List) Broadcast.fromJson(b as Map<String, dynamic>),
    ];
  }
}
