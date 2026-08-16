import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/track.dart';
import '../../core/services/location_service.dart';
import '../../core/services/live_track_service.dart';
import '../../core/services/lifeline_service.dart';
import '../../core/services/recording_status_service.dart';
import '../../core/utils/elevation_processor.dart';
import '../../core/utils/moving_time.dart';

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

  /// Quante volte la registrazione ha smesso di ricevere punti, e per quanto
  /// tempo in totale.
  ///
  /// Serve a non far scoprire i buchi a casa guardando la mappa: durante il
  /// giro si può avvisare, e a fine giro si può dire con onestà che il
  /// tracciato non è completo invece di presentarlo come se lo fosse.
  final int gapCount;
  final Duration lostTime;

  /// I buchi con i loro estremi, non solo contati. Servono a finire sulla
  /// traccia salvata: senza, l'informazione muore con questa schermata e chi
  /// riapre il giro domani vede una retta che sembra strada percorsa.
  final List<TrackGap> gaps;

  const TrackingState({
    this.status = TrackingStatus.idle,
    this.points = const [],
    this.stats = const TrackStats(),
    this.startTime,
    this.pausedDuration = Duration.zero,
    this.errorMessage,
    this.activityType = ActivityType.trekking,
    this.gapCount = 0,
    this.lostTime = Duration.zero,
    this.gaps = const [],
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
    int? gapCount,
    Duration? lostTime,
    List<TrackGap>? gaps,
  }) {
    return TrackingState(
      status: status ?? this.status,
      points: points ?? this.points,
      stats: stats ?? this.stats,
      startTime: startTime ?? this.startTime,
      pausedDuration: pausedDuration ?? this.pausedDuration,
      errorMessage: errorMessage,
      activityType: activityType ?? this.activityType,
      gapCount: gapCount ?? this.gapCount,
      lostTime: lostTime ?? this.lostTime,
      gaps: gaps ?? this.gaps,
    );
  }
}

/// BLoC per gestire il tracking GPS
class TrackingBloc extends ChangeNotifier {
  final LocationService _locationService;
  
  TrackingState _state = const TrackingState();
  TrackingState get state => _state;

  StreamSubscription<TrackPoint>? _locationSubscription;
  StreamSubscription<GpsGap>? _gapSubscription;
  Timer? _durationTimer;

  /// Tempo in movimento, accumulato su finestre mentre i punti arrivano.
  /// Vedi [MovingTimeAccumulator] per il perche' non si giudichi il singolo
  /// campione.
  final MovingTimeAccumulator _moving = MovingTimeAccumulator();
  DateTime? _pauseStartTime;

  // Soglie per il filtro
  static const double _minAccuracy = 50.0;     // Ignora punti con accuracy > 50m
  static const double _maxSpeed = 50.0;        // Ignora speed > 180 km/h (50 m/s)
  static const double _minDistance = 3.0;      // Distanza minima tra punti (3m)

  // ⚠️ AUTO-PAUSA RIMOSSA (2026-07-13, decisione founder su bug di campo).
  // Il rilevamento "utente fermo" usava i punti che superano il filtro
  // accuracy ≤ 50m: in zona SENZA rete il fused provider perde l'assistenza
  // A-GPS, l'accuratezza sale sopra soglia e (a) la pausa scattava anche in
  // cammino, (b) una volta in pausa l'unico segnale di ripresa era un punto
  // "valido" che senza rete non arrivava mai → registrazione congelata fino
  // al ritorno del segnale (linea dritta sulla traccia). Non esiste un modo
  // affidabile per distinguere "utente fermo" da "GPS degradato" col solo
  // GPS → resta SOLO la pausa manuale (bottone).
  /// Tracker elevazione con smoothing e isteresi (spike removal + dead band)
  ElevationTracker? _elevationTracker;

  TrackingBloc(this._locationService);

  /// Avvia registrazione
  Future<void> startRecording({ActivityType? activityType}) async {
    if (_state.isRecording) return;

    // Gate GLOBALE anti doppia-sessione: la RecordPage può essere pushata
    // (trail detail, planner, "segui percorso" community) mentre la TAB
    // Registra ha già una registrazione attiva. Ogni istanza ha il SUO
    // bloc, quindi il check _state.isRecording qui sopra non basta: il
    // mirror RecordingStatusService dice se QUALSIASI istanza sta
    // registrando (o è in pausa) — in quel caso non avviare un secondo
    // stream GPS parallelo.
    if (_state.isIdle && !RecordingStatusService().isIdle) {
      debugPrint('[TrackingBloc] start bloccato: registrazione già attiva '
          'in un\'altra istanza');
      _state = _state.copyWith(errorMessage: 'recording_already_active');
      notifyListeners();
      return;
    }

    final success = await _locationService.startTracking();
    if (!success) {
      _state = _state.copyWith(
        errorMessage: 'gps_access_error',
      );
      notifyListeners();
      return;
    }

    _moving.reset();
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
      _gapSubscription = _locationService.gaps.listen(_onGap);

    // Timer per aggiornare la durata ogni secondo
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
  }

  /// La registrazione ha perso un pezzo. Non c'è niente da riparare — i punti
  /// di quei minuti non esistono — ma tacerlo significa consegnare all'utente
  /// una traccia incompleta presentata come completa.
  void _onGap(GpsGap gap) {
    // Il watchdog dice quando se n'e' accorto e quanto e' durato: l'inizio si
    // ricava all'indietro. Sono estremi precisi al tick, non al secondo — ed e'
    // il motivo per cui la scheda dira' "circa dodici minuti" e non "12:04".
    _state = _state.copyWith(
      gapCount: _state.gapCount + 1,
      lostTime: _state.lostTime + gap.duration,
      gaps: [
        ..._state.gaps,
        TrackGap(
          startedAt: gap.detectedAt.subtract(gap.duration),
          endedAt: gap.detectedAt,
          cause: gap.cause.name,
        ),
      ],
      errorMessage: gap.cause == GpsGapCause.appFrozen
          ? 'gps_gap_frozen'
          : 'gps_gap_stalled',
    );
    notifyListeners();
  }

  /// Metti in pausa (manualmente, dall'utente).
  Future<void> pauseRecording() async {
    if (!_state.isRecording) return;
    await _doPause();
  }

  /// Logica comune di pausa.
  Future<void> _doPause() async {
    await _locationService.pauseTracking();
    // Cancella anche la subscription del bloc: resumeRecording() ne crea
    // una nuova con .listen() — senza questo cancel ogni ciclo pausa/riprendi
    // aggiungeva un listener duplicato di _onNewPoint sul broadcast stream.
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _gapSubscription?.cancel();
    _gapSubscription = null;
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

    _state = _state.copyWith(status: TrackingStatus.recording);
    notifyListeners();

    // Riascolta punti GPS
    _locationSubscription = _locationService.positionStream.listen(_onNewPoint);
    _gapSubscription = _locationService.gaps.listen(_onGap);

    // Riavvia timer durata
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
  }

  /// Ferma e restituisci la traccia
  Future<Track?> stopRecording() async {
    if (_state.isIdle) return null;
    await _locationService.stopTrackingKeepService();
    _locationSubscription?.cancel();
    _gapSubscription?.cancel();
    _gapSubscription = null;
    _durationTimer?.cancel();
    _pauseStartTime = null;

    if (_state.points.isEmpty) {
      _moving.reset();
      _state = const TrackingState();
      _elevationTracker = null;
      notifyListeners();
      return null;
      }

      // Finalizza tracker elevazione (registra ultimo segmento pendente)
      _elevationTracker?.finalize();
      // Stessa ragione: l'ultima finestra di movimento e' ancora aperta, e su
      // una registrazione breve puo' essere tutto il tempo in movimento.
      _moving.finish();

      // Aggiorna stats con i valori finali del tracker
      _state = _state.copyWith(
      stats: _state.stats.copyWith(
      movingTime: _moving.value,
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
      // I buchi seguono la traccia invece di morire con la schermata: e' l'unico
      // modo perche' domani, riaprendo il giro, si sappia che quella retta non
      // e' strada percorsa.
      gaps: List.from(_state.gaps),
    );

    // Reset stato e tracker
      _elevationTracker = null;
      _moving.reset();
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

    // Alimenta il tracker elevazione (incrementale, 1 punto alla volta)
      if (point.elevation != null) {
      _elevationTracker?.addPoint(point.elevation);
      }

      // Aggiungi punto e ricalcola stats
      final newPoints = [..._state.points, point];
      // Il tempo in movimento si accumula sull'ultimo tratto: ricalcolarlo
      // sull'intera lista a ogni punto sarebbe quadratico sulla durata.
      if (_state.points.isNotEmpty) {
        _moving.add(_state.points.last, point);
      }
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
      movingTime: _moving.value,
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
    _gapSubscription?.cancel();
    _durationTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
