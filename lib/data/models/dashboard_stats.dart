/// Statistiche dashboard utente
class DashboardStats {
  final int totalTracks;
  final double totalDistance; // metri
  final double totalElevationGain; // metri
  final int totalDuration; // secondi
  
  // Record
  final TrackRecord? longestTrack;
  final TrackRecord? highestElevationTrack;
  final TrackRecord? longestDurationTrack;
  
  // Per grafico a torta
  final Map<String, int> activityTypes;
  
  // Per time series
  final TimeSeriesData? timeSeries;

  const DashboardStats({
    this.totalTracks = 0,
    this.totalDistance = 0,
    this.totalElevationGain = 0,
    this.totalDuration = 0,
    this.longestTrack,
    this.highestElevationTrack,
    this.longestDurationTrack,
    this.activityTypes = const {},
    this.timeSeries,
  });

  double get totalDistanceKm => totalDistance / 1000;
  
  String get totalDurationFormatted {
    final hours = totalDuration ~/ 3600;
    final minutes = (totalDuration % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

/// Record singolo (traccia con valore)
class TrackRecord {
  final String name;
  final String? trackId;
  final double value;
  final String unit;

  const TrackRecord({
    required this.name,
    this.trackId,
    required this.value,
    required this.unit,
  });

  String get formatted {
    if (unit == 'km') return '${value.toStringAsFixed(1)} $unit';
    if (unit == 'm') return '${value.toStringAsFixed(0)} $unit';
    if (unit == 'h') {
      final hours = value ~/ 3600;
      final mins = (value % 3600) ~/ 60;
      return hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    }
    return '$value $unit';
  }
}

/// Dati time series per grafici
class TimeSeriesData {
  /// Dati per giorno: { '2025-01-09': { distance: { trekking: x, bike: y }, elevation: {...} } }
  final Map<String, DayData> byDay;
  
  /// Dati per settimana: { '2025-W02': { ... } }
  final Map<String, DayData> byWeek;
  
  /// Dati per mese: { '2025-01': { ... } }
  final Map<String, DayData> byMonth;

  const TimeSeriesData({
    this.byDay = const {},
    this.byWeek = const {},
    this.byMonth = const {},
  });
}

/// Dati per un singolo periodo (giorno/settimana/mese)
class DayData {
  final Map<String, double> distance; // { 'trekking': 5000, 'bike': 3000 }
  final Map<String, double> elevation; // { 'trekking': 200, 'bike': 100 }

  const DayData({
    this.distance = const {},
    this.elevation = const {},
  });

  factory DayData.fromMap(Map<String, dynamic> map) {
    return DayData(
      distance: _parseActivityMap(map['distance']),
      elevation: _parseActivityMap(map['elevation']),
    );
  }

  static Map<String, double> _parseActivityMap(dynamic data) {
    if (data == null) return {};
    if (data is! Map) return {};
    
    final result = <String, double>{};
    data.forEach((key, value) {
      if (value is num) {
        result[key.toString()] = value.toDouble();
      }
    });
    return result;
  }
}
