import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/home_feed_aggregator.dart';
import '../../data/models/home_feed_data.dart';

enum HomeFeedStatus { idle, loading, ready, error }

/// Stato della Home Feed (ChangeNotifier).
///
/// **Caricamento a due fasi** (per velocità + accuratezza geo):
/// 1. `loadCore()` — sezioni non-geo (sfida, seguiti, tour): veloci,
///    mostrate appena pronte → la Home appare quasi subito.
/// 2. `resolveLocation()` + `loadGeo()` — sezioni geo (Pro, Scopri,
///    meteo): usano una posizione accurata; mentre arrivano,
///    [geoPending] è true e la UI mostra un loader per quelle sezioni.
class HomeFeedBloc extends ChangeNotifier {
  HomeFeedBloc({HomeFeedAggregator? aggregator})
      : _aggregator = aggregator ?? HomeFeedAggregator();

  final HomeFeedAggregator _aggregator;

  HomeFeedStatus _status = HomeFeedStatus.idle;
  HomeFeedData? _data;
  String? _error;
  bool _geoPending = false;

  HomeFeedStatus get status => _status;
  HomeFeedData? get data => _data;
  String? get error => _error;

  /// True mentre le sezioni geo (Pro, Scopri, meteo) stanno ancora
  /// caricando dopo che le sezioni non-geo sono già a schermo.
  bool get geoPending => _geoPending;

  /// True al primissimo load (skeleton full-page). Un refresh
  /// successivo mantiene i dati a schermo.
  bool get isInitialLoading =>
      _status == HomeFeedStatus.loading && _data == null;

  Future<void> load() => _run(keepData: false);

  /// Pull-to-refresh: ricarica senza azzerare [_data] (anti-flash).
  Future<void> refresh() => _run(keepData: true);

  Future<void> _run({required bool keepData}) async {
    if (_status == HomeFeedStatus.loading) return;
    _status = HomeFeedStatus.loading;
    _error = null;
    if (!keepData) _data = null;
    notifyListeners();

    try {
      // ── Fase 1: non-geo (veloce) ──
      final core = await _aggregator.loadCore();
      _data = core;
      _geoPending = true;
      _status = HomeFeedStatus.ready;
      notifyListeners(); // la Home appare con le sezioni non-geo

      // ── Differita: Rifugi (parsing bundle 20k POI = pesante) — NON blocca
      // il primo paint. Aggiorna _data quando pronto. ──
      unawaited(_aggregator.loadRifugi().then((rifugi) {
        final d = _data;
        if (d != null && rifugi.isNotEmpty) {
          _data = d.withRifugi(rifugi);
          notifyListeners();
        }
      }));

      // ── Fase 2: geo (posizione accurata + fetch) ──
      final loc = await _aggregator.resolveLocation();
      if (loc != null) {
        final geo = await _aggregator.loadGeo(loc);
        // Parte da _data (non da core) per non sovrascrivere i rifugi
        // eventualmente arrivati nel frattempo dal caricamento differito.
        _data = (_data ?? core).withGeo(userLocation: loc, geo: geo);
      }
      _geoPending = false;
      notifyListeners(); // le sezioni geo si riempiono
    } catch (e) {
      _error = e.toString();
      _status = HomeFeedStatus.error;
      _geoPending = false;
      notifyListeners();
    }
  }
}
