import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../../data/repositories/live_track_repository.dart';

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
  
  // Configurazione
  static const Duration UPDATE_INTERVAL = Duration(seconds: 30);

  // Stream
  final _stateController = StreamController<LiveTrackState>.broadcast();
  Stream<LiveTrackState> get stateStream => _stateController.stream;

  // Getters
  bool get isActive => _isActive;
  String? get sessionId => _sessionId;
  String? get shareUrl => _sessionId != null ? _repository.getShareUrl(_sessionId!) : null;

  /// Avvia LiveTrack e condividi il link
  Future<bool> startAndShare({required String userName}) async {
    if (_isActive) {
      debugPrint('[LiveTrack] Già attivo');
      return true;
    }

    try {
      // Ottieni livello batteria
      final batteryLevel = await _getBatteryLevel();

      // Crea sessione su Firestore
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

      _emitState();
      debugPrint('[LiveTrack] Sessione creata: $_sessionId');

      // Apri dialog condivisione
      await _shareSession();

      return true;
    } catch (e) {
      debugPrint('[LiveTrack] Errore start: $e');
      return false;
    }
  }

  /// Aggiorna posizione (chiamato dal LocationService durante recording)
  Future<void> updatePosition(double latitude, double longitude) async {
    if (!_isActive || _sessionId == null) return;

    // Throttle: aggiorna solo ogni UPDATE_INTERVAL
    final now = DateTime.now();
    if (_lastUpdate != null && now.difference(_lastUpdate!) < UPDATE_INTERVAL) {
      return;
    }

    try {
      final batteryLevel = await _getBatteryLevel();

      await _repository.updatePosition(
        sessionId: _sessionId!,
        latitude: latitude,
        longitude: longitude,
        batteryLevel: batteryLevel,
      );

      _lastUpdate = now;
      debugPrint('[LiveTrack] Posizione aggiornata');
    } catch (e) {
      debugPrint('[LiveTrack] Errore aggiornamento: $e');
    }
  }

  /// Ferma LiveTrack
  Future<void> stop() async {
    if (!_isActive || _sessionId == null) return;

    try {
      await _repository.endSession(_sessionId!);
      debugPrint('[LiveTrack] Sessione terminata');
    } catch (e) {
      debugPrint('[LiveTrack] Errore stop: $e');
    }

    _isActive = false;
    _sessionId = null;
    _lastUpdate = null;

    _emitState();
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
      await Share.share(
        'Segui la mia escursione in tempo reale! 🥾\n$url',
        subject: 'Seguimi su TrailShare',
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
    ));
  }

  void dispose() {
    _stateController.close();
  }
}

/// Stato del LiveTrack
class LiveTrackState {
  final bool isActive;
  final String? sessionId;
  final String? shareUrl;

  const LiveTrackState({
    required this.isActive,
    this.sessionId,
    this.shareUrl,
  });
}
