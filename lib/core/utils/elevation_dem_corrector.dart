import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/track.dart';
import '../services/opentopodata_elevation_service.dart';
import '../services/terrain_tile_service.dart';

/// Corregge le quote GPS dei TrackPoint usando un DEM (Digital Elevation
/// Model).
///
/// **Motivazione**: l'altitudine GPS smartphone è notoriamente rumorosa
/// (±30-50m in cielo aperto, fino a ±100m in canyon/foresta) e spesso
/// affetta da bias sistematici. Strava/Komoot/Garmin applicano tutti
/// correzione DEM automatica al save. TrailShare salvava le quote GPS
/// grezze: causava grafici altimetria con shape sbagliata e quota
/// massima off by 50-150m rispetto a Strava sulla stessa traccia.
///
/// **Strategia ibrida con fallback** (2026-05-27):
/// 1. **Primario**: EU-DEM 25m via opentopodata.org — dataset European
///    Environment Agency, calibrato per il territorio europeo, ~25m
///    precisione. È la fonte equivalente a quella usata da Strava per
///    il mercato EU. Più accurata per le Alpi italiane.
/// 2. **Fallback**: AWS Open Terrain Tiles (Mapzen Terrarium) — usato
///    se l'API opentopodata fallisce (offline, 429 rate limit, errore).
///    Risoluzione ~30m basata su SRTM, accuratezza media globale ma
///    bias verso il basso (-50/-150m) in alcune zone alpine italiane.
///
/// Il fallback garantisce che, in caso di rete giù, una correzione
/// "imperfetta ma migliore del GPS grezzo" venga comunque applicata.
///
/// **Performance**:
/// - EU-DEM: ~1.1s/100 punti (rate-limited a 1 req/sec). Una traccia
///   da 500-1000 punti = 5-10 secondi.
/// - Mapzen fallback: ~1s totali grazie a cache LRU + persistente Hive.
///
/// **Costo**: zero per entrambe le fonti (opentopodata.org è API
/// pubblica gratuita, AWS Open Terrain è dataset pubblico).
class ElevationDemCorrector {
  ElevationDemCorrector._();

  /// Zoom DEM per Mapzen fallback. 12 = ~30m/pixel in Italia.
  static const int _fallbackDemZoom = 12;

  /// Margine in gradi attorno alla bbox per il Mapzen fallback.
  static const double _bboxMargin = 0.005;

  /// Corregge le quote di tutti i punti usando EU-DEM (primario) o
  /// Mapzen (fallback). Ritorna una nuova lista con quote aggiornate.
  ///
  /// [onProgress] opzionale: chiamato con `(done, total)` durante il
  /// processing. Per opentopodata, l'avanzamento è batch-by-batch.
  static Future<CorrectionResult> correct(
    List<TrackPoint> points, {
    void Function(int corrected, int total)? onProgress,
  }) async {
    if (points.isEmpty) {
      return const CorrectionResult.empty();
    }

    // ── Tentativo 1: EU-DEM 25m via opentopodata.org ──────────────────
    final stopwatch = Stopwatch()..start();
    final latlngs = points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);
    final eudem = await OpentopodataElevationService.getElevations(
      latlngs,
      onProgress: onProgress,
    );
    if (eudem != null && eudem.length == points.length) {
      debugPrint('[ElevationDem] ✅ EU-DEM 25m corretto in '
          '${stopwatch.elapsedMilliseconds}ms');
      return _buildResult(points, eudem, source: 'eudem25m');
    }
    debugPrint('[ElevationDem] EU-DEM non disponibile, fallback a Mapzen');

    // ── Fallback: Mapzen Terrarium (AWS Open Terrain Tiles) ──────────
    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final dem = await TerrainTileService().buildDemGrid(
      minLat: minLat - _bboxMargin,
      maxLat: maxLat + _bboxMargin,
      minLng: minLng - _bboxMargin,
      maxLng: maxLng + _bboxMargin,
      zoom: _fallbackDemZoom,
    );
    if (dem == null) {
      debugPrint('[ElevationDem] ❌ anche Mapzen non disponibile, skip');
      return CorrectionResult.skipped(points);
    }

    final mapzenElevations = <double?>[];
    for (final p in points) {
      final demEle = dem.elevationAt(p.latitude, p.longitude);
      mapzenElevations.add(demEle.isNaN ? null : demEle);
    }
    debugPrint('[ElevationDem] ⚠️ Mapzen fallback applicato in '
        '${stopwatch.elapsedMilliseconds}ms');
    return _buildResult(points, mapzenElevations, source: 'mapzen');
  }

  /// Costruisce il CorrectionResult dal mapping originale-corretto.
  /// I punti con elevazione null nel DEM restano col valore GPS.
  static CorrectionResult _buildResult(
    List<TrackPoint> originalPoints,
    List<double?> demElevations, {
    required String source,
  }) {
    final corrected = <TrackPoint>[];
    int correctedCount = 0;
    int skippedCount = 0;
    double minDelta = double.infinity;
    double maxDelta = double.negativeInfinity;
    double sumDelta = 0;

    for (var i = 0; i < originalPoints.length; i++) {
      final p = originalPoints[i];
      final demEle = demElevations[i];
      if (demEle == null) {
        corrected.add(p);
        skippedCount++;
        continue;
      }
      if (p.elevation != null) {
        final delta = demEle - p.elevation!;
        if (delta < minDelta) minDelta = delta;
        if (delta > maxDelta) maxDelta = delta;
        sumDelta += delta;
      }
      corrected.add(p.copyWith(elevation: demEle));
      correctedCount++;
    }

    final avgDelta = correctedCount > 0 ? sumDelta / correctedCount : 0.0;
    debugPrint('[ElevationDem] source=$source corretti '
        '$correctedCount/${originalPoints.length} (skip=$skippedCount). '
        'Δ avg=${avgDelta.toStringAsFixed(1)}m '
        'min=${minDelta.isFinite ? minDelta.toStringAsFixed(1) : "n/a"}m '
        'max=${maxDelta.isFinite ? maxDelta.toStringAsFixed(1) : "n/a"}m');

    return CorrectionResult(
      points: corrected,
      correctedCount: correctedCount,
      skippedCount: skippedCount,
      avgDeltaMeters: avgDelta,
      minDeltaMeters: minDelta.isFinite ? minDelta : 0,
      maxDeltaMeters: maxDelta.isFinite ? maxDelta : 0,
      success: correctedCount > 0,
      source: source,
    );
  }
}

/// Esito della correzione DEM. Include statistiche utili per UI
/// (dialog di conferma "delta medio +X m, max +Y m").
class CorrectionResult {
  /// Lista di TrackPoint con quote corrette (o quote GPS originali se
  /// `success=false`).
  final List<TrackPoint> points;

  /// Quanti punti hanno ricevuto una quota DEM valida.
  final int correctedCount;

  /// Quanti punti sono rimasti col valore GPS (NaN dal DEM).
  final int skippedCount;

  /// Differenza media (DEM - GPS) in metri. Positivo = il DEM è più alto.
  final double avgDeltaMeters;

  /// Differenza minima rilevata.
  final double minDeltaMeters;

  /// Differenza massima rilevata.
  final double maxDeltaMeters;

  /// `true` se la correzione ha portato qualche valore valido.
  final bool success;

  /// Fonte DEM effettivamente usata: `'eudem25m'`, `'mapzen'`, o `''`
  /// se nessuna correzione applicata.
  final String source;

  const CorrectionResult({
    required this.points,
    required this.correctedCount,
    required this.skippedCount,
    required this.avgDeltaMeters,
    required this.minDeltaMeters,
    required this.maxDeltaMeters,
    required this.success,
    this.source = '',
  });

  const CorrectionResult.empty()
      : points = const [],
        correctedCount = 0,
        skippedCount = 0,
        avgDeltaMeters = 0,
        minDeltaMeters = 0,
        maxDeltaMeters = 0,
        success = false,
        source = '';

  factory CorrectionResult.skipped(List<TrackPoint> originalPoints) =>
      CorrectionResult(
        points: originalPoints,
        correctedCount: 0,
        skippedCount: originalPoints.length,
        avgDeltaMeters: 0,
        minDeltaMeters: 0,
        maxDeltaMeters: 0,
        success: false,
        source: '',
      );

  /// `true` se la correzione ha effettivamente cambiato qualcosa.
  bool get hasChanges => success && correctedCount > 0;

  /// Etichetta user-friendly della fonte usata.
  String get sourceLabel {
    switch (source) {
      case 'eudem25m':
        return 'EU-DEM 25m';
      case 'mapzen':
        return 'AWS Mapzen';
      default:
        return '';
    }
  }
}
