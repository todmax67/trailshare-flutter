import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';

class GarminSyncService {
  static final GarminSyncService _instance = GarminSyncService._();
  factory GarminSyncService() => _instance;
  GarminSyncService._();

  static const _methodChannel = MethodChannel('com.trailshare.app/garmin');
  static const _eventChannel = EventChannel('com.trailshare.app/garmin_events');

  StreamSubscription? _eventSubscription;
  final _syncController = StreamController<GarminSyncEvent>.broadcast();

  Stream<GarminSyncEvent> get syncEvents => _syncController.stream;

  Future<void> initialize() async {
    if (kIsWeb) return; // MethodChannel nativo non disponibile su web
    try {
      await _methodChannel.invokeMethod('initialize');
      debugPrint('[GarminSync] Inizializzato');

      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen(_handleEvent, onError: _handleError);
    } catch (e) {
      debugPrint('[GarminSync] Errore init: $e');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod('getStatus');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('[GarminSync] Errore status: $e');
      return {'initialized': false, 'deviceConnected': false};
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final data = Map<String, dynamic>.from(event);
    final eventType = data['event'] as String?;

    debugPrint('[GarminSync] Evento: $eventType');

    switch (eventType) {
      case 'sync_started':
        final totalPoints = data['totalPoints'] as int? ?? 0;
        _syncController.add(GarminSyncEvent.started(totalPoints));
        break;

      case 'sync_progress':
        final received = data['received'] as int? ?? 0;
        final total = data['total'] as int? ?? 1;
        final points = data['pointsReceived'] as int? ?? 0;
        _syncController.add(GarminSyncEvent.progress(received, total, points));
        break;

      case 'sync_complete':
        _handleTrackComplete(data);
        break;
    }
  }

  Future<void> _handleTrackComplete(Map<String, dynamic> data) async {
    try {
      // Estrai metadati
      final name = data['name'] as String? ?? 'TrailShare Garmin';
      final sport = data['sport'] as String? ?? 'trekking';
      final distanceM = (data['distance'] as num?)?.toDouble() ?? 0;
      final ascentM = (data['ascent'] as num?)?.toDouble() ?? 0;
      final durationMs = (data['duration'] as num?)?.toInt() ?? 0;

      // Estrai punti GPS
      final pointsList = data['points'] as List? ?? [];
      final trackPoints = <TrackPoint>[];
      final now = DateTime.now();

      for (int i = 0; i < pointsList.length; i++) {
        final p = pointsList[i];
        if (p is Map) {
          final lat = (p['latitude'] as num?)?.toDouble();
          final lon = (p['longitude'] as num?)?.toDouble();
          final alt = (p['altitude'] as num?)?.toDouble();

          if (lat != null && lon != null && lat != 0 && lon != 0) {
            trackPoints.add(TrackPoint(
              latitude: lat,
              longitude: lon,
              elevation: alt,
              timestamp: now.subtract(Duration(
                milliseconds: durationMs - (i * durationMs ~/ pointsList.length),
              )),
            ));
          }
        }
      }

      if (trackPoints.isEmpty) {
        debugPrint('[GarminSync] Nessun punto GPS valido');
        _syncController.add(GarminSyncEvent.error('Nessun punto GPS valido'));
        return;
      }

      debugPrint('[GarminSync] Importo traccia: ${trackPoints.length} punti');

      // Tipo attività
      ActivityType activityType;
      switch (sport) {
        case 'hiking':
          activityType = ActivityType.trekking;
          break;
        case 'running':
          activityType = ActivityType.trailRunning;
          break;
        case 'cycling':
          activityType = ActivityType.cycling;
          break;
        default:
          activityType = ActivityType.trekking;
      }

      // Salva traccia
      final repo = TracksRepository();
      final track = Track(
        name: 'Garmin: $name',
        points: trackPoints,
        activityType: activityType,
        createdAt: DateTime.now(),
        recordedAt: now.subtract(Duration(milliseconds: durationMs)),
        stats: TrackStats(
          distance: distanceM,
          elevationGain: ascentM,
          duration: Duration(milliseconds: durationMs),
        ),
      );

      final savedId = await repo.saveTrack(track);
      debugPrint('[GarminSync] Traccia salvata: $savedId');
      _syncController.add(GarminSyncEvent.completed(savedId, trackPoints.length));

    } catch (e) {
      debugPrint('[GarminSync] Errore import: $e');
      _syncController.add(GarminSyncEvent.error(e.toString()));
    }
  }

  void _handleError(dynamic error) {
    debugPrint('[GarminSync] Errore stream: $error');
  }

  Future<void> shutdown() async {
    await _eventSubscription?.cancel();
    await _methodChannel.invokeMethod('shutdown');
  }
}

class GarminSyncEvent {
  final String type;
  final int? totalPoints;
  final int? received;
  final int? totalChunks;
  final int? pointsReceived;
  final String? trackId;
  final String? error;

  GarminSyncEvent._({
    required this.type,
    this.totalPoints,
    this.received,
    this.totalChunks,
    this.pointsReceived,
    this.trackId,
    this.error,
  });

  factory GarminSyncEvent.started(int totalPoints) =>
      GarminSyncEvent._(type: 'started', totalPoints: totalPoints);

  factory GarminSyncEvent.progress(int received, int total, int points) =>
      GarminSyncEvent._(type: 'progress', received: received, totalChunks: total, pointsReceived: points);

  factory GarminSyncEvent.completed(String trackId, int totalPoints) =>
      GarminSyncEvent._(type: 'completed', trackId: trackId, totalPoints: totalPoints);

  factory GarminSyncEvent.error(String error) =>
      GarminSyncEvent._(type: 'error', error: error);
}
