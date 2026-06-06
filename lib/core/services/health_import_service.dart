import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import 'health_service.dart';

/// Importa attività registrate sull'orologio (Apple Watch via HealthKit /
/// Garmin & co. via Health Connect) come tracce TrailShare, **senza bisogno di
/// un'app nativa sul polso**: legge il workout + la sua rotta GPS da Health e
/// costruisce una traccia con stats e battito.
class HealthImportService {
  final HealthService _health = HealthService();
  final TracksRepository _repo = TracksRepository();

  ActivityType _mapType(String t) {
    final s = t.toUpperCase();
    if (s.contains('HIK')) return ActivityType.trekking;
    if (s.contains('RUN')) return ActivityType.trailRunning;
    if (s.contains('WALK')) return ActivityType.walking;
    if (s.contains('CYCL') || s.contains('BIK')) return ActivityType.cycling;
    return ActivityType.trekking;
  }

  String _trackName(HealthWorkout w) {
    final src = w.sourceName.trim().isNotEmpty ? w.sourceName.trim() : 'Orologio';
    final d = w.startTime;
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return '$src · $date';
  }

  /// Importa un workout (con rotta GPS) come traccia. Ritorna il trackId,
  /// oppure `null` se il workout non ha una rotta GPS (es. attività indoor).
  Future<String?> importWorkout(HealthWorkout w) async {
    final route = await _health.getWorkoutRoute(
      start: w.startTime,
      end: w.endTime,
      workoutUuid: w.uuid,
    );
    if (route.length < 2) {
      debugPrint('[HealthImport] Workout senza rotta GPS → non importabile');
      return null;
    }

    final points = <TrackPoint>[];
    double dist = 0, gain = 0, loss = 0;
    double? prevLat, prevLng, prevEle;
    for (final loc in route) {
      points.add(TrackPoint(
        latitude: loc.latitude,
        longitude: loc.longitude,
        elevation: loc.altitude,
        timestamp: loc.timestamp,
      ));
      if (prevLat != null) {
        dist += Geolocator.distanceBetween(
            prevLat, prevLng!, loc.latitude, loc.longitude);
      }
      if (loc.altitude != null && prevEle != null) {
        final d = loc.altitude! - prevEle;
        if (d > 0) {
          gain += d;
        } else {
          loss += -d;
        }
      }
      prevLat = loc.latitude;
      prevLng = loc.longitude;
      if (loc.altitude != null) prevEle = loc.altitude;
    }

    // Battito per la finestra dell'attività (se autorizzato).
    Map<DateTime, int>? hr;
    try {
      final h = await _health.getHeartRateForTimeRange(
        start: w.startTime,
        end: w.endTime,
      );
      if (h.isNotEmpty) hr = h;
    } catch (_) {}

    final track = Track(
      name: _trackName(w),
      points: points,
      activityType: _mapType(w.type),
      createdAt: DateTime.now(),
      recordedAt: w.startTime,
      stats: TrackStats(
        distance: (w.totalDistance != null && w.totalDistance! > 0)
            ? w.totalDistance!
            : dist,
        elevationGain: gain,
        elevationLoss: loss,
        duration: w.endTime.difference(w.startTime),
      ),
      heartRateData: hr,
      healthCalories: w.totalCalories,
    );

    final id = await _repo.saveTrack(track);
    debugPrint('[HealthImport] Importato → traccia $id '
        '(${points.length} punti, HR ${hr?.length ?? 0})');
    return id;
  }
}
