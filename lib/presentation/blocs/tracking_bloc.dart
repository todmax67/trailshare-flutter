import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/track.dart';
import '../../core/services/location_service.dart';
import '../../core/services/live_track_service.dart';
import '../../core/services/lifeline_service.dart';
import '../../core/services/gamification_service.dart';
import '../widgets/level_up_dialog.dart';
import '../../core/utils/elevation_processor.dart';

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

  // 4.3 — Auto-pause su inattività
  /// Timer periodico che controlla se l'utente è fermo da troppo tempo.
  Timer? _autoIdleTimer;
  /// Ultimo istante in cui l'utente ha realmente "mosso" (punto valido che
  /// ha superato il filtro [_minDistance]).
  DateTime? _lastMovementTime;
  /// True se la pausa corrente è stata avviata automaticamente dal sistema
  /// (non dall'utente). Permette il resume automatico al primo movimento.
  bool _autoPaused = false;
  /// Soglia di inattività oltre la quale scatta la pausa automatica.
  static const Duration _autoIdleTimeout = Duration(minutes: 5);
  /// Frequenza del check di inattività.
  static const Duration _autoIdleCheckInterval = Duration(seconds: 30);

  /// True se la registrazione è stata messa in pausa automaticamente.
  /// Letta dalla UI per mostrare un banner/snackbar informativo.
  bool get isAutoPaused => _autoPaused && _state.isPaused;
  /// Tracker elevazione con smoothing e isteresi (spike removal + dead band)
  ElevationTracker? _elevationTracker;

  TrackingBloc(this._locationService);

  /// Avvia registrazione
  Future<void> startRecording({ActivityType? activityType}) async {
    if (_state.isRecording) return;

    final success = await _locationService.startTracking();
    if (!success) {
      _state = _state.copyWith(
        errorMessage: 'gps_access_error',
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

      // Inizializza tracker elevazione per l'attività selezionata
      _elevationTracker = ElevationProcessor
        .forActivity((activityType ?? ActivityType.trekking).elevationProfile)
        .createTracker();

      // Ascolta i nuovi punti GPS
      _locationSubscription = _locationService.positionStream.listen(_onNewPoint);

    // Timer per aggiornare la durata ogni secondo
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });

    // 4.3 — Avvia il watchdog di inattività
    _lastMovementTime = DateTime.now();
    _startAutoIdleWatcher();
  }

  /// Metti in pausa (manualmente, dall'utente).
  Future<void> pauseRecording() async {
    if (!_state.isRecording) return;
    _autoPaused = false;
    await _doPause();
  }

  /// Pausa automatica per inattività (4.3). Differente da [pauseRecording]
  /// solo per il flag [_autoPaused] che permette il resume automatico
  /// al primo movimento successivo.
  Future<void> _autoPause() async {
    if (!_state.isRecording) return;
    debugPrint('[TrackingBloc] 🟡 Auto-pausa per inattività >5 min');
    _autoPaused = true;
    await _doPause();
  }

  /// Logica comune di pausa.
  Future<void> _doPause() async {
    await _locationService.pauseTracking();
    _pauseStartTime = DateTime.now();
    _durationTimer?.cancel();
    _autoIdleTimer?.cancel();

    _state = _state.copyWith(status: TrackingStatus.paused);
    notifyListeners();
  }

  /// Riprendi registrazione
  Future<void> resumeRecording() async {
    if (!_state.isPaused) return;

    final success = await _locationService.resumeTracking();
    if (!success) {
      _state = _state.copyWith(
        errorMessage: 'gps_resume_error',
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
    _autoPaused = false;

    _state = _state.copyWith(status: TrackingStatus.recording);
    notifyListeners();

    // Riascolta punti GPS
    _locationSubscription = _locationService.positionStream.listen(_onNewPoint);

    // Riavvia timer durata
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });

    // 4.3 — Riavvia watchdog inattività
    _lastMovementTime = DateTime.now();
    _startAutoIdleWatcher();
  }

  /// Avvia il timer periodico che controlla se l'utente è fermo da troppo
  /// tempo e in tal caso scatta [_autoPause].
  void _startAutoIdleWatcher() {
    _autoIdleTimer?.cancel();
    _autoIdleTimer = Timer.periodic(_autoIdleCheckInterval, (_) {
      if (!_state.isRecording || _lastMovementTime == null) return;
      final idleFor = DateTime.now().difference(_lastMovementTime!);
      if (idleFor >= _autoIdleTimeout) {
        _autoPause();
      }
    });
  }

  /// Ferma e restituisci la traccia
  Future<Track?> stopRecording() async {
    if (_state.isIdle) return null;
    await _locationService.stopTrackingKeepService();
    _locationSubscription?.cancel();
    _durationTimer?.cancel();
    _autoIdleTimer?.cancel();
    _pauseStartTime = null;
    _autoPaused = false;
    _lastMovementTime = null;

    if (_state.points.isEmpty) {
      _state = const TrackingState();
      _elevationTracker = null;
      notifyListeners();
      return null;
      }

      // Finalizza tracker elevazione (registra ultimo segmento pendente)
      _elevationTracker?.finalize();

      // Aggiorna stats con i valori finali del tracker
      _state = _state.copyWith(
      stats: _state.stats.copyWith(
      elevationGain: _elevationTracker?.elevationGain ?? _state.stats.elevationGain,
      elevationLoss: _elevationTracker?.elevationLoss ?? _state.stats.elevationLoss,
      maxElevation: _elevationTracker?.maxElevation ?? _state.stats.maxElevation,
      minElevation: _elevationTracker?.minElevation ?? _state.stats.minElevation,
      ),
      );

    // Crea la traccia finale
    final track = Track(
      name: _generateTrackName(),
      points: List.from(_state.points),
      activityType: _state.activityType,
      recordedAt: _state.startTime,
      createdAt: DateTime.now(),
      stats: _state.stats,
    );

    // Reset stato e tracker
      _elevationTracker = null;
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

    _elevationTracker = null;
    _state = const TrackingState();
    notifyListeners();
    }

  /// Ferma il foreground service (chiamare dopo il salvataggio completato)
  Future<void> stopForegroundService() async {
    await _locationService.stopForegroundService();
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

    // Ricrea il tracker e alimentalo con tutti i punti storici
    _elevationTracker = ElevationProcessor
    .forActivity(activityType.name)
    .createTracker();
    for (final point in points) {
    if (point.elevation != null) {
    _elevationTracker!.addPoint(point.elevation);
    }
    }

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
  double maxSpeed = 0;

  for (int i = 1; i < points.length; i++) {
  final prev = points[i - 1];
  final curr = points[i];

  // Distanza
  totalDistance += prev.distanceTo(curr);

  // Velocità massima
  if (curr.speed != null && curr.speed! > maxSpeed) {
  maxSpeed = curr.speed!;
  }
  }

  // Elevazione: usa ElevationProcessor per elaborazione batch completa
  // (spike removal + smoothing + isteresi)
  final processor = ElevationProcessor.forActivity(
      _state.activityType.elevationProfile,
  );
  final rawElevations = points.map((p) => p.elevation).toList();
  final eleResult = processor.process(rawElevations);

  // Durata basata sui timestamp
  Duration duration = Duration.zero;
  if (points.length >= 2) {
  final firstTime = points.first.timestamp;
  final lastTime = points.last.timestamp;
  duration = lastTime.difference(firstTime);
  }

  return TrackStats(
  distance: totalDistance,
  elevationGain: eleResult.elevationGain,
  elevationLoss: eleResult.elevationLoss,
  duration: duration,
  maxSpeed: maxSpeed,
  avgSpeed: duration.inSeconds > 0
  ? totalDistance / duration.inSeconds
  : 0,
  minElevation: eleResult.minElevation,
  maxElevation: eleResult.maxElevation,
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
      debugPrint('Punto ignorato: accuracy ${point.accuracy}m > $_minAccuracy m');
      return;
    }

    // Filtro velocità assurda
    if (point.speed != null && point.speed! > _maxSpeed) {
      debugPrint('Punto ignorato: speed ${point.speed}m/s > $_maxSpeed m/s');
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

    // 4.3 — Il punto ha superato il filtro distanza: l'utente si sta
    // muovendo davvero. Aggiorna il timestamp dell'ultimo movimento e,
    // se eravamo in auto-pausa, riprendi automaticamente.
    _lastMovementTime = DateTime.now();
    if (_autoPaused && _state.isPaused) {
      debugPrint('[TrackingBloc] 🟢 Auto-resume: utente in movimento');
      // Fire-and-forget: il resume è asincrono ma non vogliamo bloccare
      // l'elaborazione del punto corrente.
      unawaited(resumeRecording());
      return;
    }

    // Alimenta il tracker elevazione (incrementale, 1 punto alla volta)
      if (point.elevation != null) {
      _elevationTracker?.addPoint(point.elevation);
      }

      // Aggiungi punto e ricalcola stats
      final newPoints = [..._state.points, point];
      final newStats = _calculateStats(newPoints, point);

    LiveTrackService().updatePosition(point.latitude, point.longitude);
    // Lifeline (safety feature): aggiorna detection movimento/inattività.
    // No-op se Lifeline non è attiva.
    LifelineService().onPosition(point.latitude, point.longitude);

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
    double maxSpeed = 0;

    for (int i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];

    // Distanza
    distance += prev.distanceTo(curr);

    // Velocità max
    if (curr.speed != null && curr.speed! > maxSpeed) {
    maxSpeed = curr.speed!;
    }
    }

    // Elevazione: leggi dal tracker (smoothing + isteresi)
    // Il tracker è alimentato incrementalmente in _onNewPoint()
    final double elevationGain = _elevationTracker?.elevationGain ?? 0;
    final double elevationLoss = _elevationTracker?.elevationLoss ?? 0;
    final double maxElevation = _elevationTracker?.maxElevation ?? 0;
    final double minElevation = _elevationTracker?.minElevation ?? 0;

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
    _autoIdleTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
