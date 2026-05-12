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
  Future<ViewshedRunResult> computeVisible({
    required double observerLat,
    required double observerLng,
    required List<MountainPeak> candidates,
    required ViewshedTier tier,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Abilita disk cache solo per Pro (idempotente — chiamabile a ripetizione).
    if (tier.persistentCache && !_tiles.diskCacheReady) {
      await _tiles.enableDiskCache();
    }

    // Cache check (skip per free → no persistenza intra-sessione).
    if (tier.persistentCache && _cached != null) {
      final dist = _haversineMeters(
        observerLat, observerLng,
        _cached!.observerLat, _cached!.observerLng,
      );
      if (dist < _skylineInvalidationMeters && _cached!.tier.label == tier.label) {
        debugPrint('[Viewshed] cache HIT (moved ${dist.round()}m < $_skylineInvalidationMeters)');
        return _cached!.result;
      }
    }

    // Bbox: raggio in gradi (approssimazione lat ≈ 111 km/°).
    final radiusKm = tier.maxRadiusKm;
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * math.cos(observerLat * math.pi / 180));

    debugPrint(
        '[Viewshed] start lat=$observerLat lng=$observerLng radius=${radiusKm}km '
        'candidates=${candidates.length} tier=${tier.label}');

    // 1. DEM
    final dem = await _tiles.buildDemGrid(
      minLat: observerLat - latDelta,
      maxLat: observerLat + latDelta,
      minLng: observerLng - lngDelta,
      maxLng: observerLng + lngDelta,
      zoom: tier.demZoom,
    );
    if (dem == null) {
      debugPrint('[Viewshed] DEM nullo, abort');
      return const ViewshedRunResult(visible: [], elapsedMs: 0, demRows: 0, demCols: 0);
    }
    debugPrint('[Viewshed] DEM pronto: ${dem.rows}×${dem.cols} '
        '(${(stopwatch.elapsedMilliseconds)}ms)');

    // 2. Filtra candidati a quelli nel bbox (ottimizzazione: viewshed conosce
    //    solo cime dentro maxRadius).
    final inRange = candidates.where((p) {
      final d = _haversineMeters(observerLat, observerLng, p.latitude, p.longitude);
      return d <= radiusKm * 1000;
    }).toList();

    if (inRange.isEmpty) {
      debugPrint('[Viewshed] nessuna cima nel raggio');
      return ViewshedRunResult(
        visible: const [],
        elapsedMs: stopwatch.elapsedMilliseconds,
        demRows: dem.rows,
        demCols: dem.cols,
      );
    }

    // 3. Compute in isolate via `compute()`.
    final request = ViewshedRequest(
      observerLat: observerLat,
      observerLng: observerLng,
      dem: dem,
      maxRadiusKm: radiusKm.toDouble(),
      rayStepMeters: tier.rayStepMeters,
      azimuthSteps: tier.azimuthSteps,
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
        skylineAngleDeg: pr.skylineAngleDeg,
      ));
    }
    visible.sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));
    if (visible.length > tier.maxVisiblePeaks) {
      // Free: keep top-N by prominence (più "stagliate sull'orizzonte").
      final sorted = [...visible]
        ..sort((a, b) => b.prominenceOverSkylineDeg.compareTo(a.prominenceOverSkylineDeg));
      visible = sorted.take(tier.maxVisiblePeaks).toList()
        ..sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));
    }

    final out = ViewshedRunResult(
      visible: visible,
      elapsedMs: stopwatch.elapsedMilliseconds,
      demRows: dem.rows,
      demCols: dem.cols,
    );

    if (tier.persistentCache) {
      _cached = _CachedViewshed(
        observerLat: observerLat,
        observerLng: observerLng,
        tier: tier,
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
  final int demZoom;
  final int rayStepMeters;
  final int azimuthSteps;

  const ViewshedTier({
    required this.label,
    required this.maxRadiusKm,
    required this.maxVisiblePeaks,
    required this.persistentCache,
    required this.demZoom,
    required this.rayStepMeters,
    required this.azimuthSteps,
  });

  static const free = ViewshedTier(
    label: 'free',
    maxRadiusKm: 20,
    maxVisiblePeaks: 10,
    persistentCache: false,
    demZoom: 11, // tile più grossi = meno fetch
    rayStepMeters: 250,
    azimuthSteps: 180, // 2° step = sufficiente per 20 km
  );

  static const pro = ViewshedTier(
    label: 'pro',
    maxRadiusKm: 100,
    maxVisiblePeaks: 1000,
    persistentCache: true,
    demZoom: 12,
    rayStepMeters: 200,
    azimuthSteps: 360,
  );
}

class ViewshedRunResult {
  final List<VisiblePeak> visible;
  final int elapsedMs;
  final int demRows;
  final int demCols;

  const ViewshedRunResult({
    required this.visible,
    required this.elapsedMs,
    required this.demRows,
    required this.demCols,
  });
}

class _CachedViewshed {
  final double observerLat;
  final double observerLng;
  final ViewshedTier tier;
  final ViewshedRunResult result;

  _CachedViewshed({
    required this.observerLat,
    required this.observerLng,
    required this.tier,
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
