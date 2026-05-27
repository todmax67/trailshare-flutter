import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Service per lookup di altitudini dal dataset **EU-DEM 25m** via
/// opentopodata.org (API pubblica gratuita).
///
/// **Perché EU-DEM 25m**: il dataset European Digital Elevation Model
/// pubblicato dall'European Environment Agency è significativamente
/// più accurato per il territorio europeo rispetto a SRTM/Mapzen
/// (calibrato con dati nazionali, risoluzione 25m vs 30m, copertura
/// completa EU + Turchia). È la fonte usata da Strava per la sua
/// "Elevation Correction" feature nel mercato EU.
///
/// **Endpoint**: `https://api.opentopodata.org/v1/eudem25m`
///
/// **Limiti API pubblica (free tier)**:
/// - 1 richiesta/secondo per IP
/// - 100 punti per richiesta
/// - 1000 richieste/giorno per IP
///
/// Per una traccia tipica (~500-1000 punti) servono 5-10 richieste,
/// ~5-10 secondi totali. Il rate limiter interno (1.1s delay)
/// rispetta il limite con un margine di sicurezza.
///
/// **Strategia di fallimento**:
/// - 429 (rate limit) → ritorna null, il chiamante può fallback a
///   un altro DEM (es. Mapzen) o saltare la correzione
/// - 500/timeout → ritorna null
/// - Offline → ritorna null
///
/// **Privacy**: i punti GPS vengono inviati a opentopodata.org per la
/// query. Sono solo coordinate (no metadati utente). L'host non
/// loggua tracking di endpoint, vedi privacy policy del servizio.
class OpentopodataElevationService {
  OpentopodataElevationService._();

  static const String _endpoint =
      'https://api.opentopodata.org/v1/eudem25m';

  /// Massimo punti per richiesta (limite API pubblica).
  static const int _batchSize = 100;

  /// Delay tra richieste consecutive. API pubblica accetta 1 req/sec,
  /// usiamo 1100ms per avere margine di sicurezza.
  static const Duration _requestDelay = Duration(milliseconds: 1100);

  /// Timeout per singola richiesta HTTP.
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// Recupera le altitudini EU-DEM 25m per la lista di coordinate.
  ///
  /// Ritorna una lista di `double?` della stessa lunghezza di [points]:
  /// - `double` se il punto è stato risolto correttamente dal DEM
  /// - `null` se quel punto specifico è fuori grid (raro in EU) o errore
  ///
  /// Ritorna `null` (lista intera) se la chiamata fallisce
  /// catastroficamente (timeout, 429, server down). In quel caso il
  /// chiamante deve fare fallback alternativo.
  ///
  /// [onProgress] opzionale: chiamato dopo ogni batch con `(done, total)`.
  static Future<List<double?>?> getElevations(
    List<LatLng> points, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (points.isEmpty) return const [];

    final result = <double?>[];
    final batches = <List<LatLng>>[];
    for (var i = 0; i < points.length; i += _batchSize) {
      batches.add(points.skip(i).take(_batchSize).toList());
    }

    debugPrint('[Opentopodata] fetching ${points.length} punti '
        'in ${batches.length} batch...');
    final stopwatch = Stopwatch()..start();

    for (var batchIdx = 0; batchIdx < batches.length; batchIdx++) {
      final batch = batches[batchIdx];
      try {
        final batchResult = await _fetchBatch(batch);
        if (batchResult == null) {
          debugPrint('[Opentopodata] ❌ batch $batchIdx fallito, abort');
          return null;
        }
        result.addAll(batchResult);
        if (onProgress != null) {
          onProgress(result.length, points.length);
        }
      } catch (e) {
        debugPrint('[Opentopodata] ❌ batch $batchIdx exception: $e');
        return null;
      }

      // Rate limit: aspetta prima del batch successivo (non per l'ultimo).
      if (batchIdx < batches.length - 1) {
        await Future.delayed(_requestDelay);
      }
    }

    debugPrint('[Opentopodata] ✅ completato in '
        '${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  /// Esegue una singola richiesta batch (max 100 punti).
  /// Ritorna lista di elevazioni o null su errore.
  static Future<List<double?>?> _fetchBatch(List<LatLng> batch) async {
    // Formato locations: "lat1,lng1|lat2,lng2|..."
    final locations = batch
        .map((p) =>
            '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
        .join('|');

    // Usiamo POST (supporta più punti senza limite URL lunghezza).
    final uri = Uri.parse(_endpoint);
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'TrailShare/2.6 (https://trailshare.app)',
          },
          body: jsonEncode({
            'locations': locations,
            // 'interpolation': 'bilinear', // default è bilineare, ok
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 429) {
      debugPrint('[Opentopodata] ⚠️ 429 rate limit');
      return null;
    }
    if (response.statusCode != 200) {
      debugPrint('[Opentopodata] ⚠️ HTTP ${response.statusCode}: '
          '${response.body.substring(0, response.body.length.clamp(0, 200))}');
      return null;
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') {
        debugPrint('[Opentopodata] ⚠️ status=${json['status']} '
            'error=${json['error']}');
        return null;
      }
      final results = json['results'] as List;
      return results.map<double?>((r) {
        final ele = (r as Map<String, dynamic>)['elevation'];
        if (ele == null) return null;
        if (ele is num) return ele.toDouble();
        return null;
      }).toList();
    } catch (e) {
      debugPrint('[Opentopodata] ⚠️ parse error: $e');
      return null;
    }
  }
}
