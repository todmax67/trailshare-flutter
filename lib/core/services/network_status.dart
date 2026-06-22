import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Stato di connettività condiviso. Due usi:
/// - cache SINCRONA (`isOnline`) per chi non può await — es. il tile provider
///   della mappa, che deve decidere all'istante se andare in rete o servire
///   la cache offline (niente più attese di 30s senza segnale);
/// - stream (`onChange`) per reagire alla riconnessione — es. Lifeline che
///   risincronizza le posizioni rimaste in coda.
///
/// Bug field #20 (giro Valbondione, zona senza segnale).
class NetworkStatus {
  NetworkStatus._();
  static final NetworkStatus instance = NetworkStatus._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true; // ottimistico finché non sappiamo
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// C'è connessione adesso? (cache sincrona, aggiornata dal listener).
  bool get isOnline => _online;
  bool get isOffline => !_online;

  /// Emette ad ogni CAMBIO di stato (true = appena riconnesso).
  Stream<bool> get onChange => _controller.stream;

  Future<void> initialize() async {
    if (_sub != null) return;
    try {
      _online = _resultsOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      // In caso di errore restiamo ottimisti (online): peggio caso, un
      // tentativo di rete fallisce — non blocchiamo nulla a priori.
    }
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final now = _resultsOnline(results);
      if (now != _online) {
        _online = now;
        _controller.add(now);
        debugPrint('[NetworkStatus] ${now ? "online" : "offline"}');
      }
    });
  }

  bool _resultsOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
