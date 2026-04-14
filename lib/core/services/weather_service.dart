import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/models/weather_data.dart';

/// Servizio per recuperare previsioni meteo da Open-Meteo.
///
/// Open-Meteo è un'API gratuita open source (CC-BY 4.0) che non richiede
/// chiave API. https://open-meteo.com/
///
/// Cache in-memory con TTL 1 ora per evitare chiamate ripetute.
class WeatherService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const Duration _cacheTtl = Duration(hours: 1);

  // Cache condivisa tra tutte le istanze del servizio
  static final Map<String, _CachedWeather> _cache = {};

  Future<WeatherData?> getForecast(double lat, double lng) async {
    // Chiave cache con 2 decimali (aggrega location vicine ~1km)
    final key = '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';

    // Cache hit?
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.data.fetchedAt) < _cacheTtl) {
      debugPrint('[Weather] ⚡ Cache hit per $key');
      return cached.data;
    }

    try {
      final url = Uri.parse(
        '$_baseUrl?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum'
        '&forecast_days=5&timezone=auto',
      );

      debugPrint('[Weather] 🌐 Fetching: $url');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint('[Weather] API error: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = _parseResponse(json);

      if (data != null) {
        _cache[key] = _CachedWeather(data);
      }
      return data;
    } catch (e) {
      debugPrint('[Weather] Errore: $e');
      return null;
    }
  }

  WeatherData? _parseResponse(Map<String, dynamic> json) {
    try {
      final currentJson = json['current'] as Map<String, dynamic>?;
      final dailyJson = json['daily'] as Map<String, dynamic>?;
      if (currentJson == null || dailyJson == null) return null;

      final currentCode = (currentJson['weather_code'] as num?)?.toInt() ?? 0;
      final current = CurrentWeather(
        temperature: (currentJson['temperature_2m'] as num?)?.toDouble() ?? 0,
        humidity: (currentJson['relative_humidity_2m'] as num?)?.toDouble() ?? 0,
        windSpeed: (currentJson['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        weatherCode: currentCode,
        description: wmoCodeToDescription(currentCode),
        icon: wmoCodeToIcon(currentCode),
      );

      final dates = (dailyJson['time'] as List?)?.cast<String>() ?? [];
      final codes = (dailyJson['weather_code'] as List?)?.cast<num>() ?? [];
      final maxs = (dailyJson['temperature_2m_max'] as List?)?.cast<num>() ?? [];
      final mins = (dailyJson['temperature_2m_min'] as List?)?.cast<num>() ?? [];
      final precs = (dailyJson['precipitation_sum'] as List?)?.cast<num?>() ?? [];

      final daily = <DailyForecast>[];
      for (var i = 0; i < dates.length; i++) {
        final code = i < codes.length ? codes[i].toInt() : 0;
        daily.add(DailyForecast(
          date: DateTime.parse(dates[i]),
          tempMax: i < maxs.length ? maxs[i].toDouble() : 0,
          tempMin: i < mins.length ? mins[i].toDouble() : 0,
          precipitationMm: i < precs.length ? (precs[i]?.toDouble() ?? 0) : 0,
          weatherCode: code,
          icon: wmoCodeToIcon(code),
        ));
      }

      return WeatherData(
        current: current,
        daily: daily,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[Weather] Errore parsing: $e');
      return null;
    }
  }

  /// Svuota la cache (per debug / test)
  static void clearCache() => _cache.clear();
}

class _CachedWeather {
  final WeatherData data;
  _CachedWeather(this.data);
}
