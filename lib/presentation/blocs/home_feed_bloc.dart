import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/home_feed_aggregator.dart';
import '../../core/utils/perf_trace.dart';
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

  /// Spostamento (m) oltre il quale il fix GPS accurato invalida i dati
  /// geo già caricati con l'ultima posizione nota → secondo loadGeo.
  static const double _geoRefreshThresholdMeters = 1000;
  static const Distance _distance = Distance();

  Future<void> _run({required bool keepData}) async {
    if (_status == HomeFeedStatus.loading) return;
    _status = HomeFeedStatus.loading;
    _error = null;
    if (!keepData) _data = null;
    notifyListeners();

    try {
      // ── GPS avviato SUBITO, in parallelo a loadCore: il fix accurato è
      // la voce più lenta della Home (6,4s misurati su Android) e prima
      // partiva solo DOPO il core, sommandosi. Entrambe le future non
      // lanciano mai (gestiscono gli errori internamente → null). ──
      final lastKnownFuture = PerfTrace.track(
        'homeFeed.lastKnownLocation',
        () => _aggregator.resolveLastKnownLocation(),
      );
      final accurateFuture = PerfTrace.track(
        'homeFeed.resolveLocation (GPS)',
        () => _aggregator.resolveLocation(),
      );

      // ── Fase 1: non-geo (veloce) ──
      final core = await PerfTrace.track(
        'homeFeed.loadCore',
        () => _aggregator.loadCore(),
      );
      _data = core;
      _geoPending = true;
      _status = HomeFeedStatus.ready;
      notifyListeners(); // la Home appare con le sezioni non-geo
      PerfTrace.mark('homeFeed.firstPaint (sezioni non-geo a schermo)');

      // ── Differita: Rifugi (parsing bundle 20k POI = pesante) — NON blocca
      // il primo paint. Aggiorna _data quando pronto. ──
      unawaited(PerfTrace.track(
        'homeFeed.loadRifugi (differita)',
        () => _aggregator.loadRifugi(),
        describe: (r) => '${r.length} rifugi',
      ).then((rifugi) {
        final d = _data;
        if (d != null && rifugi.isNotEmpty) {
          _data = d.withRifugi(rifugi);
          notifyListeners();
        }
      }));

      // ── Fase 2: geo in DUE passate. Prima con l'ultima posizione nota
      // (istantanea) → le sezioni geo si riempiono senza aspettare il GPS.
      // Poi col fix accurato, ma solo se l'utente risulta spostato oltre
      // ~1 km: altrimenti i dati geo già a schermo restano validi. ──
      final lastKnown = await lastKnownFuture;
      if (lastKnown != null) {
        final geo = await PerfTrace.track(
          'homeFeed.loadGeo (last-known)',
          () => _aggregator.loadGeo(lastKnown),
        );
        // Parte da _data (non da core) per non sovrascrivere i rifugi
        // eventualmente arrivati nel frattempo dal caricamento differito.
        _data = (_data ?? core).withGeo(userLocation: lastKnown, geo: geo);
        _geoPending = false;
        notifyListeners(); // Home completa con posizione cache
        PerfTrace.mark('homeFeed.geoComplete (last-known, Home completa)');
      }

      final loc = await accurateFuture;
      final movedFar = lastKnown == null ||
          (loc != null &&
              _distance.as(LengthUnit.Meter, lastKnown, loc) >
                  _geoRefreshThresholdMeters);
      if (loc != null && movedFar) {
        // Raffinamento silenzioso: niente _geoPending, i contenuti geo
        // eventualmente già a schermo vengono solo sostituiti.
        final geo = await PerfTrace.track(
          'homeFeed.loadGeo',
          () => _aggregator.loadGeo(loc),
        );
        _data = (_data ?? core).withGeo(userLocation: loc, geo: geo);
      }
      _geoPending = false;
      notifyListeners(); // le sezioni geo si riempiono/raffinano
      PerfTrace.mark('homeFeed.geoComplete (fix accurato, Home completa)');
    } catch (e) {
      _error = e.toString();
      _status = HomeFeedStatus.error;
      _geoPending = false;
      notifyListeners();
    }
  }
}
