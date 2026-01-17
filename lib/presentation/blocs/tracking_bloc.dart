import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/track.dart';
import '../../core/services/location_service.dart';
import '../../core/services/live_track_service.dart';
import '../../core/services/gamification_service.dart';
import '../widgets/level_up_dialog.dart';

/// Stati possibili del tracking
enum TrackingStatus {
  idle,       // Non sta registrando
  recording,  // Registrazione attiva
  paused,     // In pausa
}

/// Stato del tracking
class TrackingState {
  final TrackingStatus status;
  final List<TrackPoint> points;
  final TrackStats stats;
  final DateTime? startTime;
  final Duration pausedDuration;
  final String? errorMessage;
  final ActivityType activityType;

  const TrackingState({
    this.status = TrackingStatus.idle,
    this.points = const [],
    this.stats = const TrackStats(),
    this.startTime,
    this.pausedDuration = Duration.zero,
    this.errorMessage,
    this.activityType = ActivityType.trekking,
  });

  bool get isRecording => status == TrackingStatus.recording;
  bool get isPaused => status == TrackingStatus.paused;
  bool get isIdle => status == TrackingStatus.idle;
  bool get hasPoints => points.isNotEmpty;

  TrackingState copyWith({
    TrackingStatus? status,
    List<TrackPoint>? points,
    TrackStats? stats,
    DateTime? startTime,
    Duration? pausedDuration,
    String? errorMessage,
    ActivityType? activityType,
  }) {
    return TrackingState(
      status: status ?? this.status,
      points: points ?? this.points,
      stats: stats ?? this.stats,
      startTime: startTime ?? this.startTime,
      pausedDuration: pausedDuration ?? this.pausedDuration,
      errorMessage: errorMessage,
      activityType: activityType ?? this.activityType,
    );
  }
}

/// BLoC per gestire il tracking GPS
class TrackingBloc extends ChangeNotifier {
  final LocationService _locationService;
  
  TrackingState _state = const TrackingState();
  TrackingState get state => _state;

  StreamSubscription<TrackPoint>? _locationSubscription;
  Timer? _durationTimer;
  DateTime? _pauseStartTime;

  // Soglie per il filtro
  static const double _minAccuracy = 50.0;     // Ignora punti con accuracy > 50m
  static const double _maxSpeed = 50.0;        // Ignora speed > 180 km/h (50 m/s)
  static const double _minDistance = 3.0;      // Distanza minima tra punti (3m)

  TrackingBloc(this._locationService);

  /// Avvia registrazione
  Future<void> startRecording({ActivityType? activityType}) async {
    if (_state.isRecording) return;

    final success = await _locationService.startTracking();
    if (!success) {
      _state = _state.copyWith(
        errorMessage: 'Impossibile accedere al GPS. Verifica i permessi.',
      );
      notifyListeners();
      return;
    }

    _state = TrackingState(
      status: TrackingStatus.recording,
      startTime: DateTime.now(),
      activityType: activityType ?? ActivityType.trekking,
    );
    notifyListeners();

    // Ascolta i nuovi punti GPS
    _locationSubscription = _locationService.positionStream.listen(_onNewPoint);

    // Timer per aggiornare la durata ogni secondo
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
  }

  /// Metti in pausa
  Future<void> pauseRecording() async {
    if (!_state.isRecording) return;

    await _locationService.pauseTracking();
    _pauseStartTime = DateTime.now();
    _durationTimer?.cancel();

    _state = _state.copyWith(status: TrackingStatus.paused);
    notifyListeners();
  }

  /// Riprendi registrazione
  Future<void> resumeRecording() async {
    if (!_state.isPaused) return;

    final success = await _locationService.resumeTracking();
    if (!success) {
      _state = _state.copyWith(
        errorMessage: 'Impossibile riprendere il GPS.',
      );
      notifyListeners();
      return;
    }

    // Calcola tempo in pausa
    if (_pauseStartTime != null) {
      final pauseDuration = DateTime.now().difference(_pauseStartTime!);
      _state = _state.copyWith(
        pausedDuration: _state.pausedDuration + pauseDuration,
      );
    }
    _pauseStartTime = null;

    _state = _state.copyWith(status: TrackingStatus.recording);
    notifyListeners();

    // Riascolta punti GPS
    _locationSubscription = _locationService.positionStream.listen(_onNewPoint);

    // Riavvia timer durata
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
  }

  /// Ferma e restituisci la traccia
  Future<Track?> stopRecording() async {
    if (_state.isIdle) return null;

    await _locationService.stopTracking();
    _locationSubscription?.cancel();
    _durationTimer?.cancel();
    _pauseStartTime = null;

    if (_state.points.isEmpty) {
      _state = const TrackingState();
      notifyListeners();
      return null;
    }

    // Crea la traccia finale
    final track = Track(
      name: _generateTrackName(),
      points: List.from(_state.points),
      activityType: _state.activityType,
      recordedAt: _state.startTime,
      createdAt: DateTime.now(),
      stats: _state.stats,
    );

    // Reset stato
    _state = const TrackingState();
    notifyListeners();

    return track;
  }

  /// Annulla registrazione senza salvare
  Future<void> cancelRecording() async {
    await _locationService.stopTracking();
    _locationSubscription?.cancel();
    _durationTimer?.cancel();
    _pauseStartTime = null;

    _state = const TrackingState();
    notifyListeners();
  }

  /// FIX: Ripristina lo stato da un backup
  /// Chiamato quando l'app si riavvia dopo un crash
  Future<void> restoreFromBackup({
    required List<TrackPoint> points,
    required DateTime startTime,
    required Duration pausedDuration,
    required ActivityType activityType,
  }) async {
    if (_state.isRecording) {
      debugPrint('[TrackingBloc] Già in registrazione, ignoro restore');
      return;
    }

    debugPrint('[TrackingBloc] Ripristino da backup: ${points.length} punti');

    // Calcola le statistiche dai punti esistenti
    final stats = _calculateStatsFromPoints(points);

    // Ripristina lo stato in pausa (l'utente deve decidere se continuare)
    _state = TrackingState(
      status: TrackingStatus.paused,
      points: List.from(points),
      stats: stats,
      startTime: startTime,
      pausedDuration: pausedDuration,
      activityType: activityType,
    );

    _pauseStartTime = DateTime.now();
    notifyListeners();

    debugPrint('[TrackingBloc] Stato ripristinato in pausa');
  }

  /// Calcola le statistiche da una lista di punti esistenti
  TrackStats _calculateStatsFromPoints(List<TrackPoint> points) {
    if (points.isEmpty) return const TrackStats();

    double totalDistance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    double maxSpeed = 0;
    double? minElevation;
    double? maxElevation;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // Distanza
      totalDistance += prev.distanceTo(curr);

      // Velocità massima
      if (curr.speed != null && curr.speed! > maxSpeed) {
        maxSpeed = curr.speed!;
      }

      // Elevazione
      if (prev.elevation != null && curr.elevation != null) {
        final elevDiff = curr.elevation! - prev.elevation!;
        if (elevDiff > 0) {
          elevationGain += elevDiff;
        } else {
          elevationLoss += elevDiff.abs();
        }
      }

      if (curr.elevation != null) {
        minElevation = minElevation == null 
            ? curr.elevation 
            : (curr.elevation! < minElevation ? curr.elevation : minElevation);
        maxElevation = maxElevation == null 
            ? curr.elevation 
            : (curr.elevation! > maxElevation ? curr.elevation : maxElevation);
      }
    }

    // Durata basata sui timestamp
    Duration duration = Duration.zero;
    if (points.length >= 2) {
      final firstTime = points.first.timestamp;
      final lastTime = points.last.timestamp;
      if (firstTime != null && lastTime != null) {
        duration = lastTime.difference(firstTime);
      }
    }

    return TrackStats(
      distance: totalDistance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      duration: duration,
      maxSpeed: maxSpeed,
      avgSpeed: duration.inSeconds > 0 
          ? totalDistance / duration.inSeconds 
          : 0,
      minElevation: minElevation ?? 0,
      maxElevation: maxElevation ?? 0,
    );
  }

  /// Cambia tipo attività
  void setActivityType(ActivityType type) {
    _state = _state.copyWith(activityType: type);
    notifyListeners();
  }

  /// Gestisce nuovo punto GPS
  void _onNewPoint(TrackPoint point) {
    // Filtro accuracy
    if (point.accuracy != null && point.accuracy! > _minAccuracy) {
      print('Punto ignorato: accuracy ${point.accuracy}m > $_minAccuracy m');
      return;
    }

    // Filtro velocità assurda
    if (point.speed != null && point.speed! > _maxSpeed) {
      print('Punto ignorato: speed ${point.speed}m/s > $_maxSpeed m/s');
      return;
    }

    // Filtro distanza minima dal punto precedente
    if (_state.points.isNotEmpty) {
      final lastPoint = _state.points.last;
      final distance = lastPoint.distanceTo(point);
      if (distance < _minDistance) {
        // Aggiorna solo la velocità corrente
        _state = _state.copyWith(
          stats: _state.stats.copyWith(currentSpeed: point.speed ?? 0),
        );
        notifyListeners();
        return;
      }
    }

    // Aggiungi punto e ricalcola stats
    final newPoints = [..._state.points, point];
    final newStats = _calculateStats(newPoints, point);

    LiveTrackService().updatePosition(point.latitude, point.longitude);

    _state = _state.copyWith(
      points: newPoints,
      stats: newStats,
    );
    notifyListeners();
  }

  /// Calcola statistiche aggiornate
  TrackStats _calculateStats(List<TrackPoint> points, TrackPoint currentPoint) {
    if (points.length < 2) {
      return TrackStats(currentSpeed: currentPoint.speed ?? 0);
    }

    double distance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    double maxElevation = double.negativeInfinity;
    double minElevation = double.infinity;
    double maxSpeed = 0;

    double? lastElevation;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // Distanza
      distance += prev.distanceTo(curr);

      // Elevazione
      if (curr.elevation != null) {
        if (curr.elevation! > maxElevation) maxElevation = curr.elevation!;
        if (curr.elevation! < minElevation) minElevation = curr.elevation!;

        if (lastElevation != null) {
          final diff = curr.elevation! - lastElevation;
          if (diff > 1) {  // Soglia minima 1m per evitare rumore
            elevationGain += diff;
          } else if (diff < -1) {
            elevationLoss += diff.abs();
          }
        }
        lastElevation = curr.elevation;
      }

      // Velocità max
      if (curr.speed != null && curr.speed! > maxSpeed) {
        maxSpeed = curr.speed!;
      }
    }

    // Durata e velocità media
    final duration = _state.startTime != null
        ? DateTime.now().difference(_state.startTime!) - _state.pausedDuration
        : Duration.zero;

    final avgSpeed = duration.inSeconds > 0
        ? distance / duration.inSeconds
        : 0.0;

    return TrackStats(
      distance: distance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      maxElevation: maxElevation.isFinite ? maxElevation : 0,
      minElevation: minElevation.isFinite ? minElevation : 0,
      duration: duration,
      movingTime: duration, // Per ora uguale, poi miglioreremo
      currentSpeed: currentPoint.speed ?? 0,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
    );
  }

  /// Aggiorna durata ogni secondo
  void _updateDuration() {
    if (_state.startTime == null) return;

    final duration = DateTime.now().difference(_state.startTime!) - _state.pausedDuration;
    
    // Ricalcola velocità media con nuova durata
    final avgSpeed = duration.inSeconds > 0
        ? _state.stats.distance / duration.inSeconds
        : 0.0;

    _state = _state.copyWith(
      stats: _state.stats.copyWith(
        duration: duration,
        avgSpeed: avgSpeed,
      ),
    );
    notifyListeners();
  }

  /// Genera nome traccia automatico
  String _generateTrackName() {
    final now = DateTime.now();
    final months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 
                    'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
    return 'Escursione del ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _durationTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
