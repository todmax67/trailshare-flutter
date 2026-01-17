import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/models/track.dart';

/// Servizio per il tracking GPS con supporto background
/// 
/// Usa flutter_foreground_task per mantenere il GPS attivo
/// anche quando l'app è in background o lo schermo è bloccato.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<TrackPoint>.broadcast();
  bool _isTracking = false;
  
  /// Stream dei punti GPS
  Stream<TrackPoint> get positionStream => _positionController.stream;
  
  /// Stato tracking
  bool get isTracking => _isTracking;
  
  /// Configurazione location settings per tracking preciso
  LocationSettings get _trackingSettings => const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5, // Aggiorna ogni 5 metri
  );

  /// Inizializza il servizio (chiamare una volta all'avvio app)
  static Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'trailshare_tracking',
        channelName: 'TrailShare GPS',
        channelDescription: 'Registrazione percorso in corso',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    debugPrint('[LocationService] Inizializzato');
  }

  /// Verifica e richiede permessi
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] GPS disabilitato');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Permesso negato');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Permesso negato permanentemente');
      return false;
    }

    return true;
  }

  /// Ottieni posizione corrente
  Future<TrackPoint?> getCurrentPosition() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return _positionToTrackPoint(position);
    } catch (e) {
      debugPrint('[LocationService] Errore getCurrentPosition: $e');
      return null;
    }
  }

  /// Avvia tracking continuo con foreground service
  Future<bool> startTracking() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return false;

    // Ferma eventuale tracking precedente
    await stopTracking();

    // Avvia foreground service per background tracking
    await _startForegroundService();

    // Avvia stream posizioni
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _trackingSettings,
    ).listen(
      (Position position) {
        final trackPoint = _positionToTrackPoint(position);
        _positionController.add(trackPoint);
        debugPrint('[LocationService] Punto: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');
      },
      onError: (error) {
        debugPrint('[LocationService] Errore stream: $error');
      },
    );

    _isTracking = true;
    debugPrint('[LocationService] Tracking avviato');
    return true;
  }

  /// Ferma tracking
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    
    // Ferma foreground service
    await _stopForegroundService();
    
    _isTracking = false;
    debugPrint('[LocationService] Tracking fermato');
  }

  /// Pausa tracking
  Future<void> pauseTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    
    // Aggiorna notifica
    await _updateNotification('In pausa');
    
    debugPrint('[LocationService] Tracking in pausa');
  }

  /// Riprendi tracking
  Future<bool> resumeTracking() async {
    // Aggiorna notifica
    await _updateNotification('Registrazione in corso...');
    
    // Riavvia stream
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _trackingSettings,
    ).listen(
      (Position position) {
        final trackPoint = _positionToTrackPoint(position);
        _positionController.add(trackPoint);
      },
      onError: (error) {
        debugPrint('[LocationService] Errore stream: $error');
      },
    );
    
    debugPrint('[LocationService] Tracking ripreso');
    return true;
  }

  /// Aggiorna testo notifica (es. con distanza/tempo)
  Future<void> updateNotificationText(String text) async {
    await _updateNotification(text);
  }

  /// Avvia foreground service
  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[LocationService] Foreground service già attivo');
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'TrailShare',
      notificationText: 'Registrazione in corso...',
      callback: _foregroundTaskCallback,
    );
    debugPrint('[LocationService] Foreground service avviato');
  }

  /// Ferma foreground service
  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      debugPrint('[LocationService] Foreground service fermato');
    }
  }

  /// Aggiorna notifica
  Future<void> _updateNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'TrailShare',
        notificationText: text,
      );
    }
  }

  /// Converte Position di Geolocator in TrackPoint
  TrackPoint _positionToTrackPoint(Position position) {
    return TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude > 0 ? position.altitude : null,
      timestamp: position.timestamp,
      speed: position.speed > 0 ? position.speed : null,
      accuracy: position.accuracy,
      heading: position.heading > 0 ? position.heading : null,
    );
  }

  /// Cleanup
  void dispose() {
    _positionSubscription?.cancel();
    _positionController.close();
    _stopForegroundService();
  }
}

// Callback per il foreground task (deve essere top-level function)
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

/// Handler per il foreground task (API v9.x)
class _LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] Avviato');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive - viene chiamato ogni 5 secondi
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] Fermato (timeout: $isTimeout)');
  }

  @override
  void onNotificationPressed() {
    // L'utente ha toccato la notifica - torna all'app
    FlutterForegroundTask.launchApp();
  }
}
