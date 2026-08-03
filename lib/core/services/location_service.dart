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
/// Perché la registrazione ha smesso di ricevere punti.
enum GpsGapCause {
  /// Il sistema ha congelato il processo: i `Timer` di Dart non sono scattati.
  /// Durante il blocco non girava una riga di codice nostro, quindi non c'era
  /// niente da fare per evitarlo — si può solo accorgersene dopo.
  appFrozen,

  /// L'app era viva e i timer scattavano, ma lo stream di posizioni ha smesso
  /// di consegnare. Qui riagganciare serve davvero.
  streamStalled,
}

/// Un buco nella registrazione, con quanto è durato e perché lo sappiamo.
class GpsGap {
  final GpsGapCause cause;
  final Duration duration;
  final DateTime detectedAt;

  const GpsGap({
    required this.cause,
    required this.duration,
    required this.detectedAt,
  });

  @override
  String toString() =>
      'GpsGap(${cause.name}, ${duration.inSeconds}s, $detectedAt)';
}

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<TrackPoint>.broadcast();
  bool _isTracking = false;

  // ── Watchdog ───────────────────────────────────────────────────────────
  //
  // Il 2026-08-03, su un giro di 6h15, la registrazione si è fermata per 37
  // minuti senza che l'app se ne accorgesse: l'accuratezza era 3 m prima e 3 m
  // dopo, quindi non era il GPS — era il sistema che aveva congelato il
  // processo. L'utente se n'è accorto da solo un chilometro più avanti.
  //
  // La rilevazione non può basarsi solo sull'attesa di punti: con
  // `distanceFilter` a 5 m, da fermi non ne arrivano per minuti ed è del tutto
  // normale. Ma se il processo viene sospeso **anche i timer non scattano**:
  // un tick periodico che si risveglia e trova 37 minuti di orologio invece di
  // 10 secondi è la prova del congelamento, e non dà falsi allarmi durante una
  // sosta al rifugio.
  //
  // Da qui i due segnali distinti in [GpsGapCause].
  static const _tick = Duration(seconds: 10);
  static const _driftTolerance = Duration(seconds: 25);
  static const _staleAfter = Duration(minutes: 5);

  Timer? _watchdogTimer;
  DateTime? _lastPointAt;
  DateTime? _lastTickAt;
  bool _resubscribing = false;

  final _gapController = StreamController<GpsGap>.broadcast();

  /// Buchi rilevati durante la registrazione. La UI ci si aggancia per dire
  /// all'utente che ha perso del tracciato, invece di lasciarglielo scoprire
  /// a casa guardando la mappa.
  Stream<GpsGap> get gaps => _gapController.stream;

  /// Quando è arrivato l'ultimo punto. `null` se non è ancora arrivato niente.
  DateTime? get lastPointAt => _lastPointAt;

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
    // Riavvia tracking se già attivo, con le nuove settings.
    if (_isTracking) await _resubscribe();
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

    _positionSubscription = _listen();
    _isTracking = true;
    _lastPointAt = DateTime.now();
    _startWatchdog();
    debugPrint('[LocationService] Tracking avviato');
    return true;
  }

  /// Unico punto in cui ci si aggancia allo stream di geolocator.
  ///
  /// Prima esisteva in tre copie (avvio, ripresa, cambio battery saver) che
  /// col tempo avevano smesso di somigliarsi: due loggavano gli errori in modo
  /// diverso e nessuna riagganciava. Un difetto corretto in una copia sarebbe
  /// rimasto nelle altre due.
  StreamSubscription<Position> _listen() {
    return Geolocator.getPositionStream(
      locationSettings: _trackingSettings,
    ).listen(
      (Position position) {
        _lastPointAt = DateTime.now();
        _positionController.add(_positionToTrackPoint(position));
      },
      // `onError` prima si limitava a un debugPrint: lo stream restava chiuso
      // e `_isTracking` restava true, cioè l'app credeva di registrare mentre
      // non riceveva più niente. È il modo silenzioso di perdere un'uscita.
      onError: (error) {
        debugPrint('[LocationService] Errore stream: $error — riaggancio');
        _resubscribe();
      },
      onDone: () {
        debugPrint('[LocationService] Stream chiuso dal sistema — riaggancio');
        _resubscribe();
      },
      cancelOnError: false,
    );
  }

  /// Riaggancia lo stream **senza restare scoperti**: prima apre il nuovo,
  /// poi chiude il vecchio.
  ///
  /// L'ordine non è pignoleria: su Android il foreground service di geolocator
  /// vive e muore con lo stream, quindi cancellare prima di riaprire lascia
  /// l'app per un istante senza servizio — proprio la condizione che invita il
  /// sistema a congelarla, cioè il problema che stiamo cercando di risolvere.
  Future<void> _resubscribe() async {
    if (_resubscribing || !_isTracking) return;
    _resubscribing = true;
    try {
      final old = _positionSubscription;
      _positionSubscription = _listen();
      await old?.cancel();
    } catch (e) {
      debugPrint('[LocationService] Riaggancio fallito: $e');
    } finally {
      _resubscribing = false;
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _lastTickAt = DateTime.now();
    _watchdogTimer = Timer.periodic(_tick, (_) => _onWatchdogTick());
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _lastTickAt = null;
  }

  void _onWatchdogTick() {
    final now = DateTime.now();
    final prevTick = _lastTickAt;
    _lastTickAt = now;

    // 1) Il processo è stato sospeso: il tick doveva arrivare dopo 10 secondi
    //    e ne sono passati molti di più. Il buco è già avvenuto e non era
    //    evitabile — ma da qui in poi almeno lo sappiamo, e lo diciamo.
    if (prevTick != null) {
      final elapsed = now.difference(prevTick);
      if (elapsed - _tick > _driftTolerance) {
        _reportGap(GpsGapCause.appFrozen, elapsed, now);
        _lastPointAt = now;
        _resubscribe();
        return;
      }
    }

    // 2) I timer scattano regolarmente ma i punti non arrivano più: qui l'app
    //    è viva e riagganciare ha davvero effetto. La soglia è larga perché
    //    con distanceFilter a 5 m stare fermi a lungo è legittimo.
    final last = _lastPointAt;
    if (last != null && now.difference(last) > _staleAfter) {
      _reportGap(GpsGapCause.streamStalled, now.difference(last), now);
      // Riparte da adesso, altrimenti lo stesso buco verrebbe segnalato a ogni
      // tick finché non arriva un punto.
      _lastPointAt = now;
      _resubscribe();
    }
  }

  void _reportGap(GpsGapCause cause, Duration duration, DateTime at) {
    debugPrint('[LocationService] BUCO ${cause.name}: ${duration.inSeconds}s');
    if (!_gapController.isClosed) {
      _gapController.add(
        GpsGap(cause: cause, duration: duration, detectedAt: at),
      );
    }
  }

  /// Ferma tracking
  Future<void> stopTracking() async {
    _stopWatchdog();
    _isTracking = false;
    _lastPointAt = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[LocationService] Tracking fermato');
  }

  // Alias storico di [stopTracking]: quando esisteva il secondo service
  // FFT, questo fermava solo lo stream. Oggi il service di geolocator
  // vive e muore con lo stream, quindi le due funzioni coincidono.
  Future<void> stopTrackingKeepService() => stopTracking();

  /// Pausa tracking
  Future<void> pauseTracking() async {
    // Il watchdog si ferma con la pausa: in pausa l'assenza di punti è
    // esattamente ciò che l'utente ha chiesto, segnalarla sarebbe rumore.
    _stopWatchdog();
    _lastPointAt = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[LocationService] Tracking in pausa');
  }

  /// Riprendi tracking
  Future<bool> resumeTracking() async {
    _positionSubscription = _listen();
    _isTracking = true;
    _lastPointAt = DateTime.now();
    _startWatchdog();
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
    _stopWatchdog();
    _positionSubscription?.cancel();
    _positionController.close();
    _gapController.close();
  }
}
