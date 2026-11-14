import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/models/fire_record.dart';
import '../domain/anomaly.dart';

class FireWeather {
  const FireWeather({
    required this.temperatureC,
    required this.humidity,
    required this.windKmh,
    required this.gustKmh,
    required this.precipitationMm,
  });

  final double temperatureC, humidity, windKmh, gustKmh, precipitationMm;

  factory FireWeather.fromOpenMeteo(Map<String, dynamic> json) {
    final c = json['current'] as Map<String, dynamic>;
    double v(String k) => (c[k] as num?)?.toDouble() ?? 0;
    return FireWeather(
      temperatureC: v('temperature_2m'),
      humidity: v('relative_humidity_2m'),
      windKmh: v('wind_speed_10m'),
      gustKmh: v('wind_gusts_10m'),
      precipitationMm: v('precipitation'),
    );
  }
}

/// Current weather from Open-Meteo (free, no API key).
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<FireWeather> current(LatLng p) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': p.latitude.toStringAsFixed(3),
      'longitude': p.longitude.toStringAsFixed(3),
      'current': 'temperature_2m,relative_humidity_2m,wind_speed_10m,'
          'wind_gusts_10m,precipitation',
      'wind_speed_unit': 'kmh',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Open-Meteo ${res.statusCode}');
    }
    return FireWeather.fromOpenMeteo(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

enum BurnLevel { safe, caution, unsafe }

/// Reasons are keys in lib/l10n/strings.dart.
class BurnAdvice {
  const BurnAdvice(this.level, this.reasons, this.quietMonths);
  final BurnLevel level;
  final List<String> reasons;

  /// The 3 months with the least fire activity historically.
  final List<int> quietMonths;
}

/// Is today a reasonable day for an agricultural burn?
/// Combines current weather with the harmonized fire record.
BurnAdvice burnAdvice({
  required FireWeather weather,
  required FireRecord record,
  required DateTime now,
}) {
  final unsafe = <String>[];
  final caution = <String>[];

  if (weather.windKmh >= 25 || weather.gustKmh >= 40) {
    unsafe.add('why_wind_high');
  } else if (weather.windKmh >= 15) {
    caution.add('why_wind_moderate');
  }

  if (weather.humidity < 25) {
    unsafe.add('why_humidity_low');
  } else if (weather.humidity < 40) {
    caution.add('why_humidity_moderate');
  }

  if (weather.temperatureC >= 32) caution.add('why_hot');

  final status = summarize(record).status;
  if (status == FireStatus.extreme || status == FireStatus.above) {
    unsafe.add('why_anomaly');
  }
  if (criticalMonths(record).contains(now.month)) {
    unsafe.add('why_critical_period');
  }

  if (weather.precipitationMm > 0.5) caution.add('why_raining');

  final quiet = [...record.season]..sort((a, b) => a.median.compareTo(b.median));
  final quietMonths = quiet.take(3).map((s) => s.month).toList()..sort();

  final level = unsafe.isNotEmpty
      ? BurnLevel.unsafe
      : caution.isNotEmpty
          ? BurnLevel.caution
          : BurnLevel.safe;
  return BurnAdvice(level, [...unsafe, ...caution], quietMonths);
}
