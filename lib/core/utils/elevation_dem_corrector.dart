import 'package:flutter/foundation.dart';

import '../../data/models/track.dart';
import '../services/terrain_tile_service.dart';

/// Corregge le quote GPS dei TrackPoint usando il DEM
/// (AWS Open Terrain Tiles, formato Mapzen terrarium).
///
/// **Motivazione**: l'altitudine GPS smartphone è notoriamente rumorosa
/// (±30-50m in cielo aperto, fino a ±100m in canyon/foresta) e spesso
/// affetta da bias sistematici. Strava/Komoot/Garmin Connect applicano
/// tutti correzione DEM automatica al save. TrailShare salvava le quote
/// GPS grezze: questo causava grafici di altimetria con shape sbagliata
/// e quota massima off by 50-100m rispetto a Strava sulla stessa traccia.
///
/// **Algoritmo**:
/// 1. Calcola bbox della traccia con margine di sicurezza (500m).
/// 2. Costruisce un [DemGrid] coprente l'area, scaricando i tile terrarium
///    da AWS S3 (zoom 12 = ~30m/pixel, equivalente Strava).
/// 3. Per ogni TrackPoint, sostituisce `elevation` con `dem.elevationAt`
///    (interpolazione bilineare).
/// 4. I punti per cui il DEM è fuori bbox o NaN restano col valore GPS.
///
/// **Performance**: per una traccia 5-30km serve scaricare 1-6 tile
/// (~250-1500 KB totali). La cache LRU in-memory + persistente di
/// [TerrainTileService] rende le correzioni successive nella stessa
/// zona praticamente istantanee.
///
/// **Costo**: zero — AWS Open Terrain Tiles è un dataset pubblico gratuito.
class ElevationDemCorrector {
  ElevationDemCorrector._();

  /// Zoom DEM per la correzione. 12 = ~30m/pixel in Italia, equivalente
  /// alla precisione che usa Strava per la sua "Elevation Correction"
  /// feature. Zoom più alto = più precisione ma più tile da scaricare.
  static const int _demZoom = 12;

  /// Margine in gradi attorno alla bbox della traccia. ~0.005° ≈ 500m
  /// di buffer per non avere bordi NaN ai punti estremi.
  static const double _bboxMargin = 0.005;

  /// Corregge le quote di tutti i punti usando il DEM. Ritorna una nuova
  /// lista con quote aggiornate (il `TrackPoint` originale non è mutato).
  ///
  /// Se il DEM non è disponibile (errore di rete, AWS down) ritorna la
  /// lista invariata senza errori — fallback silente alle quote GPS.
  ///
  /// [onProgress] opzionale: chiamato con `(corrected, total)` ogni 50 punti,
  /// utile per progress bar in UI di ricalcolo manuale.
  static Future<CorrectionResult> correct(
    List<TrackPoint> points, {
    void Function(int corrected, int total)? onProgress,
  }) async {
    if (points.isEmpty) {
      return const CorrectionResult.empty();
    }

    // Calcola bbox della traccia.
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

    // Scarica DEM coprente la bbox + margine.
    final stopwatch = Stopwatch()..start();
    final dem = await TerrainTileService().buildDemGrid(
      minLat: minLat - _bboxMargin,
      maxLat: maxLat + _bboxMargin,
      minLng: minLng - _bboxMargin,
      maxLng: maxLng + _bboxMargin,
      zoom: _demZoom,
    );
    if (dem == null) {
      debugPrint('[ElevationDem] ❌ DEM non disponibile, skip correzione');
      return CorrectionResult.skipped(points);
    }
    debugPrint('[ElevationDem] ✅ DEM costruito in ${stopwatch.elapsedMilliseconds}ms');

    // Applica la correzione punto per punto.
    final corrected = <TrackPoint>[];
    int correctedCount = 0;
    int skippedCount = 0;
    double minDeltaSeen = double.infinity;
    double maxDeltaSeen = double.negativeInfinity;
    double sumDelta = 0;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final demEle = dem.elevationAt(p.latitude, p.longitude);
      if (demEle.isNaN) {
        // Fuori bbox (non dovrebbe succedere col margine, ma safety net).
        corrected.add(p);
        skippedCount++;
      } else {
        if (p.elevation != null) {
          final delta = demEle - p.elevation!;
          if (delta < minDeltaSeen) minDeltaSeen = delta;
          if (delta > maxDeltaSeen) maxDeltaSeen = delta;
          sumDelta += delta;
        }
        corrected.add(p.copyWith(elevation: demEle));
        correctedCount++;
      }
      if (onProgress != null && i % 50 == 0) {
        onProgress(i + 1, points.length);
      }
    }
    if (onProgress != null) onProgress(points.length, points.length);

    final avgDelta = correctedCount > 0 ? sumDelta / correctedCount : 0.0;
    debugPrint('[ElevationDem] corretti $correctedCount/${points.length} punti '
        '(skip=$skippedCount). Δ avg=${avgDelta.toStringAsFixed(1)}m '
        'min=${minDeltaSeen.toStringAsFixed(1)}m max=${maxDeltaSeen.toStringAsFixed(1)}m. '
        'Totale ${stopwatch.elapsedMilliseconds}ms');

    return CorrectionResult(
      points: corrected,
      correctedCount: correctedCount,
      skippedCount: skippedCount,
      avgDeltaMeters: avgDelta,
      minDeltaMeters: minDeltaSeen.isFinite ? minDeltaSeen : 0,
      maxDeltaMeters: maxDeltaSeen.isFinite ? maxDeltaSeen : 0,
      success: true,
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

  /// `true` se il DEM è stato applicato. `false` se il DEM non era
  /// disponibile e i punti sono invariati.
  final bool success;

  const CorrectionResult({
    required this.points,
    required this.correctedCount,
    required this.skippedCount,
    required this.avgDeltaMeters,
    required this.minDeltaMeters,
    required this.maxDeltaMeters,
    required this.success,
  });

  const CorrectionResult.empty()
      : points = const [],
        correctedCount = 0,
        skippedCount = 0,
        avgDeltaMeters = 0,
        minDeltaMeters = 0,
        maxDeltaMeters = 0,
        success = false;

  factory CorrectionResult.skipped(List<TrackPoint> originalPoints) =>
      CorrectionResult(
        points: originalPoints,
        correctedCount: 0,
        skippedCount: originalPoints.length,
        avgDeltaMeters: 0,
        minDeltaMeters: 0,
        maxDeltaMeters: 0,
        success: false,
      );

  /// `true` se la correzione ha effettivamente cambiato qualcosa.
  bool get hasChanges => success && correctedCount > 0;
}
