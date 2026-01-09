import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track.dart';
import '../models/dashboard_stats.dart';

/// Repository per calcolare statistiche dashboard
class DashboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Calcola le statistiche dashboard per l'utente corrente
  Future<DashboardStats> getDashboardStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const DashboardStats();
    }

    try {
      // Carica tutte le tracce dell'utente
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks')
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        return const DashboardStats();
      }

      // Parsing tracce
      final tracks = snapshot.docs.map((doc) {
        final data = doc.data();
        return _parseTrackData(doc.id, data);
      }).toList();

      // Calcola totali
      double totalDistance = 0;
      double totalElevation = 0;
      int totalDuration = 0;
      
      // Per record
      _TrackInfo? longestTrack;
      _TrackInfo? highestElevation;
      _TrackInfo? longestDuration;
      
      // Per pie chart
      final activityCounts = <String, int>{};
      
      // Per time series
      final byDay = <String, _MutableDayData>{};
      final byWeek = <String, _MutableDayData>{};
      final byMonth = <String, _MutableDayData>{};

      for (final track in tracks) {
        // Totali
        totalDistance += track.distance;
        totalElevation += track.elevation;
        totalDuration += track.duration;

        // Record distanza
        if (longestTrack == null || track.distance > longestTrack.value) {
          longestTrack = _TrackInfo(track.name, track.id, track.distance);
        }

        // Record dislivello
        if (highestElevation == null || track.elevation > highestElevation.value) {
          highestElevation = _TrackInfo(track.name, track.id, track.elevation);
        }

        // Record durata
        if (longestDuration == null || track.duration > longestDuration.value) {
          longestDuration = _TrackInfo(track.name, track.id, track.duration.toDouble());
        }

        // Conteggio attività
        activityCounts[track.activityType] = 
            (activityCounts[track.activityType] ?? 0) + 1;

        // Time series
        if (track.date != null) {
          final dayKey = _getDayKey(track.date!);
          final weekKey = _getWeekKey(track.date!);
          final monthKey = _getMonthKey(track.date!);
          final activityKey = _normalizeActivityType(track.activityType);

          // By Day
          byDay.putIfAbsent(dayKey, () => _MutableDayData());
          byDay[dayKey]!.addDistance(activityKey, track.distance / 1000);
          byDay[dayKey]!.addElevation(activityKey, track.elevation);

          // By Week
          byWeek.putIfAbsent(weekKey, () => _MutableDayData());
          byWeek[weekKey]!.addDistance(activityKey, track.distance / 1000);
          byWeek[weekKey]!.addElevation(activityKey, track.elevation);

          // By Month
          byMonth.putIfAbsent(monthKey, () => _MutableDayData());
          byMonth[monthKey]!.addDistance(activityKey, track.distance / 1000);
          byMonth[monthKey]!.addElevation(activityKey, track.elevation);
        }
      }

      return DashboardStats(
        totalTracks: tracks.length,
        totalDistance: totalDistance,
        totalElevationGain: totalElevation,
        totalDuration: totalDuration,
        longestTrack: longestTrack != null
            ? TrackRecord(
                name: longestTrack.name,
                trackId: longestTrack.id,
                value: longestTrack.value / 1000,
                unit: 'km',
              )
            : null,
        highestElevationTrack: highestElevation != null
            ? TrackRecord(
                name: highestElevation.name,
                trackId: highestElevation.id,
                value: highestElevation.value,
                unit: 'm',
              )
            : null,
        longestDurationTrack: longestDuration != null
            ? TrackRecord(
                name: longestDuration.name,
                trackId: longestDuration.id,
                value: longestDuration.value,
                unit: 'h',
              )
            : null,
        activityTypes: activityCounts,
        timeSeries: TimeSeriesData(
          byDay: byDay.map((k, v) => MapEntry(k, v.toDayData())),
          byWeek: byWeek.map((k, v) => MapEntry(k, v.toDayData())),
          byMonth: byMonth.map((k, v) => MapEntry(k, v.toDayData())),
        ),
      );
    } catch (e) {
      print('[DashboardRepository] Errore: $e');
      return const DashboardStats();
    }
  }

  /// Parse dati traccia da Firestore
  _ParsedTrack _parseTrackData(String id, Map<String, dynamic> data) {
    // Distance
    double distance = 0;
    if (data['distance'] != null) {
      distance = (data['distance'] as num).toDouble();
    }

    // Elevation
    double elevation = 0;
    if (data['elevationGain'] != null) {
      elevation = (data['elevationGain'] as num).toDouble();
    }

    // Duration
    int duration = 0;
    if (data['duration'] != null) {
      duration = (data['duration'] as num).toInt();
    }

    // Activity type
    String activityType = 'trekking';
    if (data['activityType'] != null) {
      activityType = data['activityType'].toString();
    }

    // Date
    DateTime? date;
    if (data['recordedAt'] != null) {
      if (data['recordedAt'] is Timestamp) {
        date = (data['recordedAt'] as Timestamp).toDate();
      } else if (data['recordedAt'] is String) {
        date = DateTime.tryParse(data['recordedAt']);
      }
    } else if (data['createdAt'] != null) {
      if (data['createdAt'] is Timestamp) {
        date = (data['createdAt'] as Timestamp).toDate();
      }
    }

    return _ParsedTrack(
      id: id,
      name: data['name']?.toString() ?? 'Senza nome',
      distance: distance,
      elevation: elevation,
      duration: duration,
      activityType: activityType,
      date: date,
    );
  }

  String _getDayKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getWeekKey(DateTime date) {
    // ISO week
    final d = DateTime.utc(date.year, date.month, date.day);
    final dayOfYear = d.difference(DateTime.utc(d.year, 1, 1)).inDays;
    final weekOfYear = ((dayOfYear - d.weekday + 10) / 7).floor();
    return '${d.year}-W${weekOfYear.toString().padLeft(2, '0')}';
  }

  String _getMonthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  String _normalizeActivityType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('trek') || lower.contains('hik') || lower.contains('walk')) {
      return 'trekking';
    }
    if (lower.contains('bik') || lower.contains('cycl')) {
      return 'bike';
    }
    if (lower.contains('run') || lower.contains('trail')) {
      return 'run';
    }
    return 'trekking';
  }
}

/// Helper classes per parsing
class _ParsedTrack {
  final String id;
  final String name;
  final double distance;
  final double elevation;
  final int duration;
  final String activityType;
  final DateTime? date;

  _ParsedTrack({
    required this.id,
    required this.name,
    required this.distance,
    required this.elevation,
    required this.duration,
    required this.activityType,
    this.date,
  });
}

class _TrackInfo {
  final String name;
  final String id;
  final double value;

  _TrackInfo(this.name, this.id, this.value);
}

class _MutableDayData {
  final Map<String, double> distance = {};
  final Map<String, double> elevation = {};

  void addDistance(String activity, double value) {
    distance[activity] = (distance[activity] ?? 0) + value;
  }

  void addElevation(String activity, double value) {
    elevation[activity] = (elevation[activity] ?? 0) + value;
  }

  DayData toDayData() => DayData(distance: distance, elevation: elevation);
}
