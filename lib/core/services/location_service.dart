import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import '../../data/models/track.dart' hide ActivityType;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servizio per il tracking GPS con supporto background.
///
/// Il background su Android è garantito dal foreground service INTERNO di
/// geolocator (ForegroundNotificationConfig nelle AndroidSettings, notifica
/// persistente inclusa); su iOS da AppleSettings.allowBackgroundLocationUpdates.
///
/// NOTA STORICA (Fase B audit 2026-07-13): qui c'era anche un secondo
/// service flutter_foreground_task, ma la sua init() era stata rimossa da
/// main.dart a feb 2026 (commit 6f6d525) e non partiva più: startService
/// falliva in silenzio e tutte le chiamate erano no-op. L'app ha sempre
/// funzionato col solo service di geolocator → macchinario FFT rimosso.
/// Il pacchetto flutter_foreground_task resta in pubspec SOLO per le API
/// di battery optimization usate in record_page.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<TrackPoint>.broadcast();
  bool _isTracking = false;
  
  /// Stream dei punti GPS
  Stream<TrackPoint> get positionStream => _positionController.stream;
  
  /// Stato tracking
  bool get isTracking => _isTracking;
  
  /// Flag battery saver. Quando true il tracking usa frequenze/precisione
  /// ridotte per risparmiare batteria (utile per escursioni lunghe o con
  /// batteria bassa). Può essere attivato/disattivato anche durante la
  /// registrazione: il service si riavvia con le nuove settings.
  bool _batterySaverMode = false;
  bool get isBatterySaverMode => _batterySaverMode;

  /// Configurazione location settings per tracking preciso
  /// iOS richiede AppleSettings con allowBackgroundLocationUpdates
  /// per continuare il tracking con schermo bloccato
  LocationSettings get _trackingSettings {
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: _batterySaverMode
            ? LocationAccuracy.medium
            : LocationAccuracy.bestForNavigation,
        distanceFilter: _batterySaverMode ? 15 : 5,
        activityType: ActivityType.fitness, // Geolocator ActivityType
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      return AndroidSettings(
        accuracy: _batterySaverMode
            ? LocationAccuracy.medium
            : LocationAccuracy.bestForNavigation,
        distanceFilter: _batterySaverMode ? 15 : 5,
        forceLocationManager: false,
        intervalDuration: Duration(seconds: _batterySaverMode ? 10 : 2),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'TrailShare',
          notificationText: _batterySaverMode
              ? 'Registrazione GPS attiva (battery saver)'
              : 'Registrazione GPS attiva',
          enableWakeLock: true,
        ),
      );
    }
  }

  /// Attiva/disattiva la modalità battery saver. Se il tracking è già
  /// in corso, lo riavvia con i nuovi settings (piccolo gap di qualche
  /// secondo durante il riavvio, ma niente perdita di dati già raccolti).
  Future<void> setBatterySaverMode(bool enabled) async {
    if (_batterySaverMode == enabled) return;
    debugPrint('[LocationService] Battery saver: $enabled');
    _batterySaverMode = enabled;
    // Riavvia tracking se già attivo
    if (_isTracking) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _trackingSettings,
      ).listen(
        (Position position) {
          final trackPoint = _positionToTrackPoint(position);
          _positionController.add(trackPoint);
        },
        onError: (e) {
          debugPrint('[LocationService] Errore stream (saver): $e');
        },
      );
    }
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
          if (!context.mounted) {
            _resolveAllPending(false);
            return false;
          }
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
        // Apple guideline 5.1.1(iv): il pre-prompt non deve avere
        // un'uscita che salti il system permission dialog. Single
        // CTA "Continua" che porta sempre al sistema; l'utente
        // decide lì se concedere o negare.
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continua'),
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

  /// Ultima posizione nota all'OS (istantanea: nessuna attesa di fix GPS).
  ///
  /// Serve al pattern "parti subito, raffina dopo": Home/mappe la usano per
  /// caricare le sezioni geo immediatamente, poi correggono col fix accurato
  /// di [getCurrentPosition] se l'utente si è spostato. NON mostra prompt
  /// permessi: se mancano, o l'OS non ha una posizione in cache, torna null
  /// e ci pensa il percorso accurato.
  Future<TrackPoint?> getLastKnownPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return _positionToTrackPoint(position);
    } catch (e) {
      // Es. web: getLastKnownPosition non supportato dal plugin.
      debugPrint('[LocationService] Errore getLastKnownPosition: $e');
      return null;
    }
  }

  /// Avvia tracking continuo (il foreground service di geolocator parte
  /// insieme allo stream, via ForegroundNotificationConfig nelle settings)
  Future<bool> startTracking() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return false;

    // Ferma eventuale tracking precedente
    await stopTracking();

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
    _isTracking = false;
    debugPrint('[LocationService] Tracking fermato');
  }

  // Alias storico di [stopTracking]: quando esisteva il secondo service
  // FFT, questo fermava solo lo stream. Oggi il service di geolocator
  // vive e muore con lo stream, quindi le due funzioni coincidono.
  Future<void> stopTrackingKeepService() => stopTracking();

  /// Pausa tracking
  Future<void> pauseTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[LocationService] Tracking in pausa');
  }

  /// Riprendi tracking
  Future<bool> resumeTracking() async {
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
  Future<void> dispose() async {
    _positionSubscription?.cancel();
    _positionController.close();
  }
}
