import 'dart:async';
import 'package:flutter/foundation.dart';
import 'background_geolocation_service.dart';
import '../../data/models/track.dart';

/// Servizio per la registrazione delle tracce
/// 
/// Gestisce la raccolta dei punti GPS durante una registrazione,
/// applicando filtri per qualità e distanza minima.
class TrackRecordingService {
  static final TrackRecordingService _instance = TrackRecordingService._internal();
  factory TrackRecordingService() => _instance;
  TrackRecordingService._internal();

  final BackgroundGeolocationService _geoService = BackgroundGeolocationService();

  // Configurazione
  static const double MIN_ACCURACY = 50.0; // metri
  static const double MIN_DISTANCE = 5.0;  // metri tra punti
  static const double STATIONARY_RADIUS = 8.0; // metri per considerare fermo

  // Stato registrazione
  bool _isRecording = false;
  bool _isPaused = false;
  DateTime? _startTime;
  DateTime? _pauseTime;
  Duration _pausedDuration = Duration.zero;
  
  // Dati traccia
  final List<TrackPoint> _points = [];
  double _totalDistance = 0;
  double _elevationGain = 0;
  double _elevationLoss = 0;
  double? _lastElevation;
  LocationData? _lastLocation;

  // Stream
  final _recordingStateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get recordingStateStream => _recordingStateController.stream;

  final _statsController = StreamController<RecordingStats>.broadcast();
  Stream<RecordingStats> get statsStream => _statsController.stream;

  StreamSubscription<LocationData>? _locationSubscription;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  List<TrackPoint> get points => List.unmodifiable(_points);
  double get totalDistance => _totalDistance;
  double get elevationGain => _elevationGain;
  Duration get elapsedTime {
    if (_startTime == null) return Duration.zero;
    final now = _isPaused ? (_pauseTime ?? DateTime.now()) : DateTime.now();
    return now.difference(_startTime!) - _pausedDuration;
  }

  /// Inizializza il servizio
  Future<bool> initialize() async {
    return await _geoService.initialize();
  }

  /// Imposta il tipo di attività
  void setActivityType(String type) {
    _geoService.setActivityType(type);
  }

  /// Avvia la registrazione
  Future<bool> startRecording({String activityType = 'walking'}) async {
    if (_isRecording) {
      debugPrint('[Recording] Registrazione già in corso');
      return true;
    }

    // Reset stato
    _points.clear();
    _totalDistance = 0;
    _elevationGain = 0;
    _elevationLoss = 0;
    _lastElevation = null;
    _lastLocation = null;
    _pausedDuration = Duration.zero;
    _pauseTime = null;

    // Imposta tipo attività
    setActivityType(activityType);

    // Avvia tracking GPS
    final started = await _geoService.startTracking();
    if (!started) {
      debugPrint('[Recording] Impossibile avviare GPS');
      return false;
    }

    // Ascolta le posizioni
    _locationSubscription = _geoService.locationStream.listen(_onLocationUpdate);

    _isRecording = true;
    _isPaused = false;
    _startTime = DateTime.now();

    _emitState();
    debugPrint('[Recording] Registrazione avviata');
    
    return true;
  }

  /// Mette in pausa la registrazione
  void pauseRecording() {
    if (!_isRecording || _isPaused) return;

    _isPaused = true;
    _pauseTime = DateTime.now();
    
    _emitState();
    debugPrint('[Recording] Registrazione in pausa');
  }

  /// Riprende la registrazione
  void resumeRecording() {
    if (!_isRecording || !_isPaused) return;

    if (_pauseTime != null) {
      _pausedDuration += DateTime.now().difference(_pauseTime!);
    }
    
    _isPaused = false;
    _pauseTime = null;
    
    _emitState();
    debugPrint('[Recording] Registrazione ripresa');
  }

  /// Ferma la registrazione e ritorna i dati
  Future<RecordingResult> stopRecording() async {
    if (!_isRecording) {
      return RecordingResult(success: false, error: 'Nessuna registrazione attiva');
    }

    // Ferma GPS
    await _geoService.stopTracking();
    _locationSubscription?.cancel();
    _locationSubscription = null;

    final result = RecordingResult(
      success: true,
      points: List.from(_points),
      totalDistance: _totalDistance,
      elevationGain: _elevationGain,
      elevationLoss: _elevationLoss,
      duration: elapsedTime,
      startTime: _startTime,
      endTime: DateTime.now(),
    );

    // Reset stato
    _isRecording = false;
    _isPaused = false;
    _startTime = null;

    _emitState();
    debugPrint('[Recording] Registrazione fermata: ${_points.length} punti, ${(_totalDistance/1000).toStringAsFixed(2)} km');

    return result;
  }

  /// Annulla la registrazione senza salvare
  Future<void> discardRecording() async {
    await _geoService.stopTracking();
    _locationSubscription?.cancel();
    _locationSubscription = null;

    _points.clear();
    _isRecording = false;
    _isPaused = false;
    _startTime = null;

    _emitState();
    debugPrint('[Recording] Registrazione annullata');
  }

  /// Callback per nuove posizioni GPS
  void _onLocationUpdate(LocationData location) {
    if (!_isRecording || _isPaused) return;

    // Filtro accuratezza
    if (location.accuracy > MIN_ACCURACY) {
      debugPrint('[Recording] Punto scartato: accuratezza ${location.accuracy.toStringAsFixed(0)}m > $MIN_ACCURACY m');
      return;
    }

    // Filtro distanza minima
    if (_lastLocation != null) {
      final distance = _calculateDistance(
        _lastLocation!.latitude, _lastLocation!.longitude,
        location.latitude, location.longitude,
      );
      
      if (distance < MIN_DISTANCE) {
        debugPrint('[Recording] Punto scartato: distanza ${distance.toStringAsFixed(1)}m < $MIN_DISTANCE m');
        return;
      }

      _totalDistance += distance;
    }

    // Calcola dislivello
    if (_lastElevation != null && location.altitude > 0) {
      final elevDiff = location.altitude - _lastElevation!;
      if (elevDiff > 0) {
        _elevationGain += elevDiff;
      } else {
        _elevationLoss += elevDiff.abs();
      }
    }
    if (location.altitude > 0) {
      _lastElevation = location.altitude;
    }

    // Aggiungi punto
    final point = TrackPoint(
      latitude: location.latitude,
      longitude: location.longitude,
      elevation: location.altitude,
      timestamp: location.timestamp,
    );
    _points.add(point);
    _lastLocation = location;

    // Emetti statistiche aggiornate
    _emitStats();
    
    debugPrint('[Recording] Punto #${_points.length}: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}');
  }

  /// Calcola distanza tra due coordinate (formula Haversine)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // metri
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = 
        (Math.sin(dLat / 2) * Math.sin(dLat / 2)) +
        (Math.cos(_toRadians(lat1)) * Math.cos(_toRadians(lat2)) *
         Math.sin(dLon / 2) * Math.sin(dLon / 2));
    
    final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (Math.pi / 180);

  void _emitState() {
    _recordingStateController.add(RecordingState(
      isRecording: _isRecording,
      isPaused: _isPaused,
      pointsCount: _points.length,
    ));
  }

  void _emitStats() {
    _statsController.add(RecordingStats(
      pointsCount: _points.length,
      distance: _totalDistance,
      elevationGain: _elevationGain,
      duration: elapsedTime,
      currentPosition: _lastLocation,
    ));
  }

  void dispose() {
    _locationSubscription?.cancel();
    _recordingStateController.close();
    _statsController.close();
  }
}

// Helper per Math
class Math {
  static double sin(double x) => _sin(x);
  static double cos(double x) => _cos(x);
  static double sqrt(double x) => _sqrt(x);
  static double atan2(double y, double x) => _atan2(y, x);
  static const double pi = 3.141592653589793;
  
  static double _sin(double x) {
    return _nativeSin(x);
  }
  static double _cos(double x) {
    return _nativeCos(x);
  }
  static double _sqrt(double x) {
    return _nativeSqrt(x);
  }
  static double _atan2(double y, double x) {
    return _nativeAtan2(y, x);
  }
}

// Import dart:math per le funzioni native
import 'dart:math' as dart_math;
double _nativeSin(double x) => dart_math.sin(x);
double _nativeCos(double x) => dart_math.cos(x);
double _nativeSqrt(double x) => dart_math.sqrt(x);
double _nativeAtan2(double y, double x) => dart_math.atan2(y, x);

/// Stato della registrazione
class RecordingState {
  final bool isRecording;
  final bool isPaused;
  final int pointsCount;

  const RecordingState({
    required this.isRecording,
    required this.isPaused,
    required this.pointsCount,
  });
}

/// Statistiche in tempo reale
class RecordingStats {
  final int pointsCount;
  final double distance;
  final double elevationGain;
  final Duration duration;
  final LocationData? currentPosition;

  const RecordingStats({
    required this.pointsCount,
    required this.distance,
    required this.elevationGain,
    required this.duration,
    this.currentPosition,
  });

  String get distanceFormatted {
    if (distance < 1000) return '${distance.toStringAsFixed(0)} m';
    return '${(distance / 1000).toStringAsFixed(2)} km';
  }

  String get durationFormatted {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Risultato della registrazione
class RecordingResult {
  final bool success;
  final String? error;
  final List<TrackPoint> points;
  final double totalDistance;
  final double elevationGain;
  final double elevationLoss;
  final Duration duration;
  final DateTime? startTime;
  final DateTime? endTime;

  const RecordingResult({
    required this.success,
    this.error,
    this.points = const [],
    this.totalDistance = 0,
    this.elevationGain = 0,
    this.elevationLoss = 0,
    this.duration = Duration.zero,
    this.startTime,
    this.endTime,
  });
}
