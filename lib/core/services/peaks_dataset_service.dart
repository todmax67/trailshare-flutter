import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/models/mountain_peak.dart';

/// Servizio singleton che carica e tiene in memoria il dataset offline
/// di tutte le cime italiane (`assets/data/peaks_italy.json`, ~37k voci,
/// derivate da OpenStreetMap natural=peak).
///
/// Uso tipico:
/// ```dart
/// final service = PeaksDatasetService();
/// await service.ensureLoaded();
/// final nearby = service.findWithinRadius(lat, lng, radiusKm: 50);
/// ```
///
/// Performance:
/// - Caricamento: ~250ms al primo accesso (parse JSON 4MB)
/// - Query bbox: <5ms su dataset completo (linear scan con filtro lat
///   precedente)
class PeaksDatasetService {
  PeaksDatasetService._();
  static final PeaksDatasetService _instance = PeaksDatasetService._();
  factory PeaksDatasetService() => _instance;

  /// Path dell'asset bundled.
  static const String _assetPath = 'assets/data/peaks_italy.json';

  List<MountainPeak>? _peaks;
  bool _loading = false;
  Future<void>? _loadFuture;

  /// True se il dataset è già stato caricato in memoria.
  bool get isLoaded => _peaks != null;

  /// Numero totale di cime nel dataset (0 se non ancora caricato).
  int get totalPeaks => _peaks?.length ?? 0;

  /// Carica il dataset se non già in memoria. Idempotente: chiamate
  /// concorrenti condividono la stessa Future.
  Future<void> ensureLoaded() {
    if (_peaks != null) return Future.value();
    if (_loading && _loadFuture != null) return _loadFuture!;
    _loading = true;
    _loadFuture = _doLoad();
    return _loadFuture!;
  }

  Future<void> _doLoad() async {
    try {
      final stopwatch = Stopwatch()..start();
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final peaksJson = json['peaks'] as List<dynamic>;
      final list = peaksJson
          .map((e) => MountainPeak.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _peaks = list;
      debugPrint('[PeaksDataset] caricate ${list.length} cime in '
          '${stopwatch.elapsedMilliseconds}ms');
    } catch (e, st) {
      debugPrint('[PeaksDataset] errore load: $e\n$st');
      _peaks = const [];
    } finally {
      _loading = false;
    }
  }

  /// Ritorna le cime entro un raggio (km) dalla posizione data.
  /// Pre-filtra con bounding box approssimata, poi calcola distanze
  /// precise solo sulle candidate.
  List<MountainPeak> findWithinRadius(
    double lat,
    double lng, {
    required double radiusKm,
    int maxResults = 200,
  }) {
    final all = _peaks;
    if (all == null || all.isEmpty) return const [];

    // 1° di latitudine ≈ 111 km. 1° di longitudine ≈ 111 * cos(lat).
    final dLat = radiusKm / 111.0;
    final dLng = radiusKm / (111.0 * math.cos(lat * math.pi / 180));
    final minLat = lat - dLat;
    final maxLat = lat + dLat;
    final minLng = lng - dLng;
    final maxLng = lng + dLng;

    final radiusMeters = radiusKm * 1000;
    final results = <_ScoredPeak>[];

    for (final p in all) {
      // Bbox prefilter (sub-microsecondo per peak)
      if (p.latitude < minLat ||
          p.latitude > maxLat ||
          p.longitude < minLng ||
          p.longitude > maxLng) {
        continue;
      }
      final d = _haversine(lat, lng, p.latitude, p.longitude);
      if (d <= radiusMeters) {
        results.add(_ScoredPeak(p, d));
      }
    }

    results.sort((a, b) => a.distance.compareTo(b.distance));
    if (results.length <= maxResults) {
      return results.map((r) => r.peak).toList(growable: false);
    }
    return results
        .take(maxResults)
        .map((r) => r.peak)
        .toList(growable: false);
  }

  /// Distanza Haversine in metri.
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1R) *
            math.cos(lat2R) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _ScoredPeak {
  final MountainPeak peak;
  final double distance;
  const _ScoredPeak(this.peak, this.distance);
}
