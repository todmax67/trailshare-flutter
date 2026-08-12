import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/models/mountain_peak.dart';
import '../../data/models/visible_peak.dart';
import '../utils/viewshed_compute.dart';
import 'terrain_tile_service.dart';

/// Orchestrator del calcolo "solo cime visibili" (Viewshed Peak Filter).
///
/// Flusso:
/// 1. Costruisce bbox intorno alla posizione utente, raggio max secondo tier.
/// 2. Scarica + decodifica i DEM tile (in-memory cache).
/// 3. Run [computeViewshed] in Isolate via [compute].
/// 4. Mappa il risultato a [VisiblePeak] (model UI).
///
/// Pro/Free tiering qui dentro: solo parametri (raggio, max peaks). La logica
/// di gating "is user pro" la decide il chiamante e passa un [ViewshedTier].
class ViewshedService {
  ViewshedService._();
  static final ViewshedService _instance = ViewshedService._();
  factory ViewshedService() => _instance;

  final _tiles = TerrainTileService();

  /// Skyline cache: key = (latRounded, lngRounded, tier). Invalida dopo
  /// movimento > _skylineInvalidationMeters.
  _CachedViewshed? _cached;
  static const double _skylineInvalidationMeters = 500;

  /// Compute. Restituisce le cime visibili ordinate per azimut, troncate a
  /// `tier.maxVisiblePeaks`. Se la cache è valida per la posizione richiesta,
  /// ritorna senza ricalcolare (Pro only).
  /// [radiusKm] è il raggio effettivo da usare: normalmente il minore fra
  /// quello scelto dall'utente e quello consentito dal tier. Se omesso si usa
  /// il massimo del tier.
  Future<ViewshedRunResult> computeVisible({
    required double observerLat,
    required double observerLng,
    required List<MountainPeak> candidates,
    required ViewshedTier tier,
    double? radiusKm,
    bool computeSkyline = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Abilita disk cache solo per Pro (idempotente — chiamabile a ripetizione).
    if (tier.persistentCache && !_tiles.diskCacheReady) {
      await _tiles.enableDiskCache();
    }

    final effectiveRadiusKm = math.min(
      radiusKm ?? tier.maxRadiusKm.toDouble(),
      tier.maxRadiusKm.toDouble(),
    );

    // Cache check (skip per free → no persistenza intra-sessione).
    //
    // La chiave comprende **raggio e skyline**, non solo la posizione: il
    // risultato dipende da entrambi, e con la chiave incompleta spostare lo
    // slider della distanza non produceva alcun effetto finché l'utente non
    // camminava per mezzo chilometro — lo slider sembrava rotto.
    if (tier.persistentCache && _cached != null) {
      final dist = _haversineMeters(
        observerLat, observerLng,
        _cached!.observerLat, _cached!.observerLng,
      );
      if (dist < _skylineInvalidationMeters &&
          _cached!.tier.label == tier.label &&
          (_cached!.radiusKm - effectiveRadiusKm).abs() < 0.5 &&
          _cached!.withSkyline == computeSkyline) {
        debugPrint('[Viewshed] cache HIT (moved ${dist.round()}m < $_skylineInvalidationMeters)');
        return _cached!.result;
      }
    }

    debugPrint(
        '[Viewshed] start lat=$observerLat lng=$observerLng '
        'radius=${effectiveRadiusKm.toStringAsFixed(0)}km '
        'candidates=${candidates.length} tier=${tier.label}');

    // 1. Terreno a due risoluzioni: fitto vicino (dove si decidono le
    //    occlusioni), largo lontano (dove la risoluzione non conta).
    final dem = await _tiles.buildLayeredDem(
      observerLat: observerLat,
      observerLng: observerLng,
      radiusKm: effectiveRadiusKm,
      coarseZoom: tier.demZoom,
      fineZoom: tier.fineDemZoom,
      fineRadiusKm: tier.fineRadiusKm,
    );
    if (dem == null) {
      debugPrint('[Viewshed] DEM nullo, abort');
      return ViewshedRunResult(
        visible: const [],
        elapsedMs: stopwatch.elapsedMilliseconds,
        demRows: 0,
        demCols: 0,
        status: ViewshedStatus.demUnavailable,
      );
    }
    debugPrint('[Viewshed] DEM pronto: ${dem.coarse.rows}×${dem.coarse.cols} '
        '(${(stopwatch.elapsedMilliseconds)}ms)');

    // Quota del terreno sotto l'osservatore. Se qui il DEM non sa rispondere
    // (tile mancante proprio dove siamo) ogni confronto diventa NaN e il
    // risultato sarebbe "nessuna cima visibile" — indistinguibile da "sei in
    // una conca". Meglio dichiararlo: chi chiama mostra lo stato invece di far
    // sparire le cime in silenzio.
    final observerGroundM = dem.elevationAt(observerLat, observerLng);
    if (!observerGroundM.isFinite) {
      debugPrint('[Viewshed] DEM senza copertura sulla posizione utente');
      return ViewshedRunResult(
        visible: const [],
        elapsedMs: stopwatch.elapsedMilliseconds,
        demRows: dem.coarse.rows,
        demCols: dem.coarse.cols,
        status: ViewshedStatus.observerOutsideDem,
      );
    }

    // 2. Filtra candidati a quelli nel raggio del tier.
    final inRange = candidates.where((p) {
      final d = _haversineMeters(observerLat, observerLng, p.latitude, p.longitude);
      return d <= effectiveRadiusKm * 1000;
    }).toList();

    if (inRange.isEmpty) {
      debugPrint('[Viewshed] nessuna cima nel raggio');
      return ViewshedRunResult(
        visible: const [],
        elapsedMs: stopwatch.elapsedMilliseconds,
        demRows: dem.coarse.rows,
        demCols: dem.coarse.cols,
        observerGroundElevationM: observerGroundM,
        status: ViewshedStatus.noPeaksInRange,
      );
    }

    // 3. Compute in isolate via `compute()`.
    final request = ViewshedRequest(
      observerLat: observerLat,
      observerLng: observerLng,
      dem: dem,
      visibilityToleranceDeg: tier.visibilityToleranceDeg,
      // Il profilo dell'orizzonte si calcola solo se qualcuno lo disegna:
      // sono 720 raggi in più, che raddoppiano il tempo del calcolo. Costa
      // poco solo perché riusa il DEM già scaricato, non perché sia gratis.
      computeSkyline: computeSkyline,
      skylineRadiusM: effectiveRadiusKm * 1000,
      candidatePeaks: inRange
          .map((p) => {
                'id': p.id,
                'lat': p.latitude,
                'lng': p.longitude,
                'ele': p.elevation ?? 0,
              })
          .toList(),
    );
    final result = await compute(computeViewshed, request);
    debugPrint('[Viewshed] compute done in ${stopwatch.elapsedMilliseconds}ms');

    // 4. Map → VisiblePeak. Tiene solo i visibili, ordinati per azimut.
    final byId = {for (final p in inRange) p.id: p};
    var visible = <VisiblePeak>[];
    for (final pr in result.peaks) {
      if (!pr.visible) continue;
      final peak = byId[pr.id];
      if (peak == null) continue;
      visible.add(VisiblePeak(
        peak: peak,
        azimuthDeg: pr.azimuthDeg,
        distanceMeters: pr.distanceMeters,
        elevationAngleDeg: pr.elevationAngleDeg,
        clearanceDeg: pr.clearanceDeg,
        uncertain: pr.uncertain,
      ));
    }
    visible.sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));
    if (visible.length > tier.maxVisiblePeaks) {
      // Free: si tengono le più **imponenti nella scena**, cioè quelle che
      // sottendono l'angolo maggiore. Prima si usava lo stacco dallo skyline,
      // che premiava chi sporgeva di più da un crinale anche se in cielo era un
      // puntino: non è quello che l'utente chiama "le cime che vedo".
      final sorted = [...visible]
        ..sort((a, b) => b.elevationAngleDeg.compareTo(a.elevationAngleDeg));
      visible = sorted.take(tier.maxVisiblePeaks).toList()
        ..sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));
    }

    final out = ViewshedRunResult(
      visible: visible,
      elapsedMs: stopwatch.elapsedMilliseconds,
      demRows: dem.coarse.rows,
      demCols: dem.coarse.cols,
      observerGroundElevationM: observerGroundM,
      status: ViewshedStatus.ok,
      skylineAngles: result.skylineAngles,
    );

    if (tier.persistentCache) {
      _cached = _CachedViewshed(
        observerLat: observerLat,
        observerLng: observerLng,
        tier: tier,
        radiusKm: effectiveRadiusKm,
        withSkyline: computeSkyline,
        result: out,
      );
    }

    debugPrint('[Viewshed] DONE: ${visible.length} visible peaks in ${out.elapsedMs}ms');
    return out;
  }

  void invalidateCache() => _cached = null;
}

/// Parametrizzazione tier (free vs pro). Niente if "isPro" qui dentro: lo
/// fa il chiamante.
class ViewshedTier {
  final String label;
  final int maxRadiusKm;
  final int maxVisiblePeaks;
  final bool persistentCache;

  /// Zoom della griglia larga, che copre tutto il raggio.
  final int demZoom;

  /// Zoom della griglia fitta nel campo vicino, dove si decidono le occlusioni.
  final int fineDemZoom;

  /// Raggio della griglia fitta, in km.
  final double fineRadiusKm;

  /// Tolleranza angolare per dichiarare occlusa una cima radente, in gradi.
  final double visibilityToleranceDeg;

  const ViewshedTier({
    required this.label,
    required this.maxRadiusKm,
    required this.maxVisiblePeaks,
    required this.persistentCache,
    required this.demZoom,
    this.fineDemZoom = 12,
    this.fineRadiusKm = 10,
    this.visibilityToleranceDeg = 0.05,
  });

  static const free = ViewshedTier(
    label: 'free',
    maxRadiusKm: 20,
    maxVisiblePeaks: 10,
    persistentCache: false,
    demZoom: 10, // ~110 m/pixel alle nostre latitudini
    fineDemZoom: 12, // ~27 m/pixel nel campo vicino
    fineRadiusKm: 8,
  );

  static const pro = ViewshedTier(
    label: 'pro',
    maxRadiusKm: 100,
    maxVisiblePeaks: 1000,
    persistentCache: true,
    // Zoom 10 sul raggio pieno: ~110 m/pixel, e tiene il conto dei tile sotto
    // il cap. Zoom 12 su 100 km darebbe centinaia di tile e una griglia
    // ingestibile — per quello il dettaglio si aggiunge solo dove serve, con la
    // griglia fitta del campo vicino.
    demZoom: 10,
    fineDemZoom: 12,
    fineRadiusKm: 12,
  );
}

/// Esito di un calcolo viewshed. Serve a distinguere "non vedi nessuna cima"
/// da "non ho potuto calcolarlo": prima erano la stessa cosa, e la funzione
/// degradava in silenzio a "mostra tutte le cime" senza dirlo a nessuno.
enum ViewshedStatus {
  /// Calcolo completato.
  ok,

  /// Nessun tile DEM disponibile: tipicamente si è offline.
  demUnavailable,

  /// Il DEM non copre la posizione dell'utente (tile mancante proprio lì).
  observerOutsideDem,

  /// Nessuna cima candidata dentro il raggio.
  noPeaksInRange,
}

class ViewshedRunResult {
  final List<VisiblePeak> visible;
  final int elapsedMs;
  final int demRows;
  final int demCols;

  /// Quota del terreno sotto l'osservatore secondo il DEM, in metri.
  /// `null` quando non è stato possibile calcolarla.
  final double? observerGroundElevationM;

  final ViewshedStatus status;

  /// Profilo dell'orizzonte: angolo di elevazione massimo del terreno per ogni
  /// direzione, dall'azimut 0 (nord) in senso orario. Vuoto se non calcolato,
  /// NaN dove il DEM non sa rispondere.
  final List<double> skylineAngles;

  const ViewshedRunResult({
    required this.visible,
    required this.elapsedMs,
    required this.demRows,
    required this.demCols,
    this.observerGroundElevationM,
    this.status = ViewshedStatus.ok,
    this.skylineAngles = const [],
  });

  /// True se il filtro ha davvero girato: solo allora ha senso fidarsi
  /// dell'elenco delle cime visibili.
  bool get isReliable => status == ViewshedStatus.ok;

  /// Quante delle cime mostrate lo sono senza certezza, perché il DEM non
  /// copre tutto il terreno che sta in mezzo.
  int get uncertainCount => visible.where((v) => v.uncertain).length;

  /// True quando la copertura del terreno è così lacunosa che l'elenco va
  /// preso con le pinze: più di un quarto delle cime è incerto.
  bool get hasPatchyTerrain =>
      visible.isNotEmpty && uncertainCount * 4 > visible.length;
}

class _CachedViewshed {
  final double observerLat;
  final double observerLng;
  final ViewshedTier tier;

  /// Raggio con cui è stato calcolato: fa parte della chiave, perché il
  /// risultato cambia se cambia.
  final double radiusKm;

  /// Se il risultato in cache contiene anche il profilo dell'orizzonte.
  final bool withSkyline;

  final ViewshedRunResult result;

  _CachedViewshed({
    required this.observerLat,
    required this.observerLng,
    required this.tier,
    required this.radiusKm,
    required this.withSkyline,
    required this.result,
  });
}

const double _earthRadiusM = 6371000.0;
double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(a));
}
