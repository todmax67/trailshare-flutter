import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/models/track.dart' hide ActivityType;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// iOS richiede AppleSettings con allowBackgroundLocationUpdates
  /// per continuare il tracking con schermo bloccato
  LocationSettings get _trackingSettings {
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.fitness, // Geolocator ActivityType
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TrailShare',
          notificationText: 'Registrazione GPS attiva',
          enableWakeLock: true,
        ),
      );
    }
  }

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

  /// Verifica e richiede permessi con Prominent Disclosure
  /// Flag per evitare richieste multiple simultanee
  static bool _disclosureShown = false;
  static bool _permissionRequesting = false;
  static final List<Completer<bool>> _pendingRequests = [];

  /// Verifica e richiede permessi con Prominent Disclosure
  Future<bool> checkAndRequestPermission({BuildContext? context}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] GPS disabilitato');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    
    // Se già concesso, ritorna subito
    if (permission == LocationPermission.always || 
        permission == LocationPermission.whileInUse) {
      return true;
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Permesso negato permanentemente');
      return false;
    }

    // Se un'altra richiesta è in corso, aspetta il risultato
    if (_permissionRequesting) {
      final completer = Completer<bool>();
      _pendingRequests.add(completer);
      return completer.future;
    }

    _permissionRequesting = true;

    try {
      // ⚠️ Prominent Disclosure: mostra dialog prima della richiesta
      if (!_disclosureShown && context != null && context.mounted) {
        final prefs = await SharedPreferences.getInstance();
        final alreadyShown = prefs.getBool('location_disclosure_shown') ?? false;
        
        if (!alreadyShown) {
          final accepted = await _showLocationDisclosure(context);
          if (!accepted) {
            debugPrint('[LocationService] Utente ha rifiutato il disclosure');
            _resolveAllPending(false);
            return false;
          }
          await prefs.setBool('location_disclosure_shown', true);
        }
        _disclosureShown = true;
      }

      permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Permesso negato');
        _resolveAllPending(false);
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[LocationService] Permesso negato permanentemente');
        _resolveAllPending(false);
        return false;
      }

      // Su iOS, richiedi "Always" per il background tracking
      if (Platform.isIOS && permission == LocationPermission.whileInUse) {
        debugPrint('[LocationService] iOS: richiedo permesso Always per background');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse) {
          debugPrint('[LocationService] iOS: solo WhileInUse - background limitato');
        }
      }

      _resolveAllPending(true);
      return true;
    } catch (e) {
      debugPrint('[LocationService] Errore permessi: $e');
      _resolveAllPending(false);
      return false;
    } finally {
      _permissionRequesting = false;
    }
  }

  /// Risolve tutte le richieste in attesa
  void _resolveAllPending(bool result) {
    for (final completer in _pendingRequests) {
      completer.complete(result);
    }
    _pendingRequests.clear();
  }

  /// Dialog Prominent Disclosure richiesto da Google Play
  Future<bool> _showLocationDisclosure(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('Accesso alla posizione')),
          ],
        ),
        content: const Text(
          'TrailShare utilizza la tua posizione per:\n\n'
          '• Registrare le tracce GPS delle tue attività outdoor '
          '(escursioni, corsa, ciclismo)\n'
          '• Mostrarti i sentieri e i punti di interesse vicini a te\n'
          '• Fornire statistiche accurate su distanza, velocità e percorso\n'
          '• Permettere il tracciamento in background durante la registrazione '
          'per garantire la continuità del percorso anche con lo schermo spento\n\n'
          'La tua posizione non viene condivisa con terze parti, '
          'salvo quando scegli volontariamente di pubblicare una traccia nella community.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non ora'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ho capito, continua'),
          ),
        ],
      ),
    );
    return result ?? false;
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
    await stopForegroundService();
    
    _isTracking = false;
    debugPrint('[LocationService] Tracking fermato');
  }

  // NUOVO: Ferma solo lo stream GPS, senza toccare il foreground service.
  // Usato durante il salvataggio per evitare il flash nero causato
  // dalla distruzione del secondo Flutter engine.
  Future<void> stopTrackingKeepService() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    debugPrint('[LocationService] Tracking fermato (service attivo)');
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
  Future<void> stopForegroundService() async {
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
    stopForegroundService();
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
