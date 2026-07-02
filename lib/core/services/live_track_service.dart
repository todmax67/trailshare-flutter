import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../../data/repositories/live_track_repository.dart';
import 'network_status.dart';

/// Servizio per gestire LiveTrack durante la registrazione
/// 
/// Permette di condividere la posizione in tempo reale con altri utenti
/// mentre si sta registrando una traccia.
class LiveTrackService {
  static final LiveTrackService _instance = LiveTrackService._internal();
  factory LiveTrackService() => _instance;
  LiveTrackService._internal();

  final LiveTrackRepository _repository = LiveTrackRepository();
  final Battery _battery = Battery();

  // Stato
  bool _isActive = false;
  String? _sessionId;
  DateTime? _lastUpdate;

  // Ultima posizione NOTA non ancora confermata inviata: alla riconnessione
  // viene spinta subito (i contatti vedono la posizione attuale, niente buco).
  double? _pendingLat;
  double? _pendingLng;
  // Ascolta la riconnessione per fare il flush.
  StreamSubscription<bool>? _connSub;

  // Configurazione
  static const Duration updateInterval = Duration(seconds: 30);

  // Stream
  final _stateController = StreamController<LiveTrackState>.broadcast();
  Stream<LiveTrackState> get stateStream => _stateController.stream;

  // Getters
  bool get isActive => _isActive;
  String? get sessionId => _sessionId;
  String? get shareUrl => _sessionId != null ? _repository.getShareUrl(_sessionId!) : null;

  /// Avvia LiveTrack e condividi il link
  Future<bool> startAndShare({required String userName}) async {
    final ok = await startSilent(userName: userName);
    if (ok) await _shareSession();
    return ok;
  }

  /// Avvia LiveTrack **senza** aprire il dialog di condivisione nativo.
  /// Usato da Lifeline: la condivisione viene gestita per-contatto con
  /// messaggi personalizzati (pre-compilati via url_launcher).
  Future<bool> startSilent({required String userName}) async {
    if (_isActive) {
      debugPrint('[LiveTrack] Già attivo');
      return true;
    }

    try {
      final batteryLevel = await _getBatteryLevel();

      final session = await _repository.createSession(
        userName: userName,
        batteryLevel: batteryLevel,
      );

      if (session == null) {
        debugPrint('[LiveTrack] Errore creazione sessione');
        return false;
      }

      _sessionId = session.id;
      _isActive = true;
      _lastUpdate = DateTime.now();

      // Alla riconnessione: aggiorna lo stato (banner) e spingi subito
      // l'ultima posizione nota (Lifeline reconnect, bug field #20).
      _connSub ??= NetworkStatus.instance.onChange.listen((online) {
        _emitState();
        if (online) _flushPending();
      });

      _emitState();
      debugPrint('[LiveTrack] Sessione silent creata: $_sessionId');
      return true;
    } catch (e) {
      debugPrint('[LiveTrack] Errore startSilent: $e');
      return false;
    }
  }

  /// Aggiorna posizione (chiamato dal LocationService durante recording)
  Future<void> updatePosition(double latitude, double longitude) async {
    if (!_isActive || _sessionId == null) return;

    // Ricorda SEMPRE l'ultima posizione: se siamo (o andiamo) offline verrà
    // inviata alla riconnessione (niente più buco / posizione persa).
    _pendingLat = latitude;
    _pendingLng = longitude;

    // Offline: non tentare la scrittura (era ~30s di attesa / fail silenzioso).
    // La posizione resta in _pending e parte al ritorno del segnale.
    if (NetworkStatus.instance.isOffline) return;

    // Throttle: aggiorna solo ogni updateInterval
    final now = DateTime.now();
    if (_lastUpdate != null && now.difference(_lastUpdate!) < updateInterval) {
      return;
    }

    await _send(latitude, longitude, now);
  }

  /// Scrive una posizione su Firestore. Su successo aggiorna il throttle e
  /// svuota il pending (se è l'ultima nota); su fallimento la lascia in coda.
  Future<void> _send(double lat, double lng, DateTime now) async {
    try {
      final batteryLevel = await _getBatteryLevel();
      final ok = await _repository.updatePosition(
        sessionId: _sessionId!,
        latitude: lat,
        longitude: lng,
        batteryLevel: batteryLevel,
      );
      if (ok) {
        _lastUpdate = now;
        if (_pendingLat == lat && _pendingLng == lng) {
          _pendingLat = null;
          _pendingLng = null;
        }
        debugPrint('[LiveTrack] Posizione aggiornata');
      } else {
        debugPrint('[LiveTrack] update fallito → resta in coda');
      }
    } catch (e) {
      debugPrint('[LiveTrack] Errore aggiornamento: $e');
    }
  }

  /// Alla riconnessione invia SUBITO l'ultima posizione nota (bypassa il
  /// throttle): i contatti vedono la posizione attuale senza attendere.
  Future<void> _flushPending() async {
    if (!_isActive || _sessionId == null) return;
    if (NetworkStatus.instance.isOffline) return;
    final lat = _pendingLat;
    final lng = _pendingLng;
    if (lat == null || lng == null) return;
    debugPrint('[LiveTrack] riconnesso → flush posizione in coda');
    await _send(lat, lng, DateTime.now());
  }

  /// Ferma LiveTrack
  Future<void> stop() async {
    if (!_isActive || _sessionId == null) return;
    final sid = _sessionId!;

    // Reset dello stato locale SUBITO: lo stop non deve dipendere dall'ack del
    // server. Offline la endSession pende all'infinito (persistenza Firestore)
    // e senza questo la sessione live resterebbe "attiva/fantasma" (i contatti
    // vedono un live fermo) fino al riavvio. Chiusura remota best-effort.
    _isActive = false;
    _sessionId = null;
    _lastUpdate = null;
    _pendingLat = null;
    _pendingLng = null;
    _connSub?.cancel();
    _connSub = null;
    _emitState();

    unawaited(
      _repository
          .endSession(sid)
          .timeout(const Duration(seconds: 5))
          .then((_) => debugPrint('[LiveTrack] Sessione terminata'))
          .catchError(
              (e) => debugPrint('[LiveTrack] endSession best-effort err: $e')),
    );
  }

  /// Condividi link sessione
  Future<void> _shareSession() async {
    if (_sessionId == null) return;

    final url = _repository.getShareUrl(_sessionId!);
    
    try {
      // Copia negli appunti per test
      await Clipboard.setData(ClipboardData(text: _sessionId!));
      debugPrint('[LiveTrack] Session ID copiato: $_sessionId');
      
      // Prova a condividere
      await SharePlus.instance.share(
        ShareParams(
          text: 'Segui la mia escursione in tempo reale! 🥾\n$url',
          subject: 'Seguimi su TrailShare',
        ),
      );
    } catch (e) {
      debugPrint('[LiveTrack] Errore share: $e');
      // Almeno l'ID è negli appunti
    }
  }

  /// Ottieni session ID (per test/debug)
  String? getSessionId() => _sessionId;

  /// Ricondividi link (per utente)
  Future<void> reshare() async {
    await _shareSession();
  }

  /// Ottieni livello batteria
  Future<int> _getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      return 100;
    }
  }

  void _emitState() {
    _stateController.add(LiveTrackState(
      isActive: _isActive,
      sessionId: _sessionId,
      shareUrl: shareUrl,
      offline: _isActive && NetworkStatus.instance.isOffline,
    ));
  }

  /// True se la sessione è attiva ma adesso siamo senza segnale (la UI può
  /// mostrare "offline, riprende al segnale" invece di un falso "attivo").
  bool get isOffline => _isActive && NetworkStatus.instance.isOffline;

  void dispose() {
    _connSub?.cancel();
    _connSub = null;
    _stateController.close();
  }
}

/// Stato del LiveTrack
class LiveTrackState {
  final bool isActive;
  final String? sessionId;
  final String? shareUrl;

  /// Sessione attiva ma temporaneamente senza segnale.
  final bool offline;

  const LiveTrackState({
    required this.isActive,
    this.sessionId,
    this.shareUrl,
    this.offline = false,
  });
}
