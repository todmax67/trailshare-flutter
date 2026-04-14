import 'package:flutter/material.dart';

/// Meteo attuale + forecast dei prossimi giorni
class WeatherData {
  final CurrentWeather current;
  final List<DailyForecast> daily;
  final DateTime fetchedAt;

  const WeatherData({
    required this.current,
    required this.daily,
    required this.fetchedAt,
  });
}

class CurrentWeather {
  final double temperature; // °C
  final double humidity; // %
  final double windSpeed; // km/h
  final int weatherCode; // WMO code
  final String description;
  final IconData icon;

  const CurrentWeather({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.weatherCode,
    required this.description,
    required this.icon,
  });
}

class DailyForecast {
  final DateTime date;
  final double tempMax;
  final double tempMin;
  final double precipitationMm;
  final int weatherCode;
  final IconData icon;

  const DailyForecast({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.precipitationMm,
    required this.weatherCode,
    required this.icon,
  });
}

/// Mappa i codici WMO (https://open-meteo.com/en/docs#weathervariables) ad icone Material
IconData wmoCodeToIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code >= 1 && code <= 3) return Icons.wb_cloudy;
  if (code >= 45 && code <= 48) return Icons.foggy;
  if (code >= 51 && code <= 57) return Icons.grain;
  if (code >= 61 && code <= 67) return Icons.umbrella;
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 80 && code <= 82) return Icons.water_drop;
  if (code >= 85 && code <= 86) return Icons.ac_unit;
  if (code >= 95 && code <= 99) return Icons.thunderstorm;
  return Icons.cloud;
}

/// Descrizione testuale in italiano del codice WMO
String wmoCodeToDescription(int code) {
  if (code == 0) return 'Sereno';
  if (code == 1) return 'Prevalentemente sereno';
  if (code == 2) return 'Parzialmente nuvoloso';
  if (code == 3) return 'Nuvoloso';
  if (code >= 45 && code <= 48) return 'Nebbia';
  if (code == 51) return 'Pioviggine leggera';
  if (code == 53) return 'Pioviggine';
  if (code == 55) return 'Pioviggine intensa';
  if (code == 56 || code == 57) return 'Pioviggine gelata';
  if (code == 61) return 'Pioggia leggera';
  if (code == 63) return 'Pioggia';
  if (code == 65) return 'Pioggia intensa';
  if (code == 66 || code == 67) return 'Pioggia gelata';
  if (code == 71) return 'Neve leggera';
  if (code == 73) return 'Neve';
  if (code == 75) return 'Neve intensa';
  if (code == 77) return 'Granelli di neve';
  if (code == 80) return 'Rovesci leggeri';
  if (code == 81) return 'Rovesci';
  if (code == 82) return 'Rovesci violenti';
  if (code == 85 || code == 86) return 'Rovesci di neve';
  if (code == 95) return 'Temporale';
  if (code == 96 || code == 99) return 'Temporale con grandine';
  return 'N/D';
}
