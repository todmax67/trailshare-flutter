import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../models/osm_poi.dart';

/// Repository read-only per i ~18.5k POI OSM bundlati in
/// `assets/data/pois_italy_clean.json` (rifugi, bivacchi, fontane,
/// sorgenti, panorami, croci, ometti, picnic, ripari).
///
/// **Strategia:**
/// - Asset bundle (no network al runtime, no costo Firestore)
/// - Caricato lazy alla prima chiamata di [ensureLoaded]
/// - Tenuto interamente in memoria (~3MB heap, irrilevante)
/// - Query nearby/near-polyline via linear scan + Haversine
///   - 18k POI * scan = ~5ms su mobile, accettabile per il PoC
///   - Ottimizzazione futura (geohash bucket) se cresceremo a 100k+
///
/// Singleton. L'inizializzazione è idempotente.
class OsmPoisRepository {
  OsmPoisRepository._();
  static final OsmPoisRepository _instance = OsmPoisRepository._();
  factory OsmPoisRepository() => _instance;

  List<OsmPoi> _all = const [];
  bool _loaded = false;
  Future<void>? _loadingFuture;

  bool get isLoaded => _loaded;
  int get count => _all.length;

  /// Carica e parsa l'asset una sola volta. Concorrent-safe: chiamate
  /// multiple condividono lo stesso Future.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle
          .loadString('assets/data/pois_italy_clean.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['pois'] as List?) ?? const [];
      final parsed = <OsmPoi>[];
      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final poi = OsmPoi.fromJson(entry);
          if (poi != null) parsed.add(poi);
        }
      }
      _all = parsed;
      _loaded = true;
      debugPrint('[OsmPois] Loaded ${_all.length} POI from asset');
    } catch (e, st) {
      debugPrint('[OsmPois] Errore caricamento asset: $e\n$st');
      _all = const [];
      _loaded = true;
    } finally {
      _loadingFuture = null;
    }
  }

  /// Ritorna tutti i POI, oppure subset filtrato per tipo.
  ///
  /// Costo: O(n) o O(filtered). Pensato per UI list, non per render in
  /// tempo reale di un set ampio (in quel caso usa [findNearby]).
  List<OsmPoi> all({Set<OsmPoiType>? types}) {
    if (types == null || types.isEmpty) return List.unmodifiable(_all);
    return _all.where((p) => types.contains(p.type)).toList();
  }

  /// POI entro [radiusMeters] da (lat,lng), opzionalmente filtrati per
  /// tipo. Ordinati per distanza crescente.
  ///
  /// Usato per:
  /// - "POI vicino a te" su record page
  /// - Lookup quando si tappa la mappa per mostrare un punto candidato
  List<OsmPoi> findNearby(
    double lat,
    double lng, {
    double radiusMeters = 1000,
    Set<OsmPoiType>? types,
  }) {
    final result = <_PoiWithDistance>[];
    for (final p in _all) {
      if (types != null && types.isNotEmpty && !types.contains(p.type)) {
        continue;
      }
      final d = haversine(lat, lng, p.latitude, p.longitude);
      if (d <= radiusMeters) {
        result.add(_PoiWithDistance(p, d));
      }
    }
    result.sort((a, b) => a.distance.compareTo(b.distance));
    return result.map((e) => e.poi).toList();
  }

  /// POI a distanza massima [radiusMeters] dal polyline definito da
  /// [points] (es. una traccia GPS o una route pianificata). Dedup per id.
  ///
  /// [sampleEvery] è adattivo: per polyline corte campioniamo ogni
  /// punto (così non saltiamo zone con un sentiero rappresentato da
  /// pochi vertici), per polyline lunghe campioniamo ogni N punti per
  /// evitare lavoro inutile (~ ogni 50-100m di percorso).
  ///
  /// Performance note: ~50-100ms su mobile per polyline tipiche.
  List<OsmPoi> findNearPolyline(
    List<LatLng> points, {
    double radiusMeters = 200,
    int? sampleEvery,
    Set<OsmPoiType>? types,
  }) {
    if (points.isEmpty) return const [];
    // Adattivo: cap a ~150 sample point per non bruciare CPU su tracce
    // GPS dense (1000+ punti), ma garantisce campionamento fitto su
    // tracce corte/sintetiche (≤100 punti = ogni punto).
    final step = sampleEvery ?? math.max(1, points.length ~/ 150);
    final found = <String, OsmPoi>{};
    final radiusSq = radiusMeters; // soglia, non quadrato
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      for (final poi in _all) {
        if (types != null && types.isNotEmpty && !types.contains(poi.type)) {
          continue;
        }
        // Pre-filter rapido: se il delta lat/lng è oltre la soglia in
        // gradi (~0.01 = ~1.1km), skip senza calcolare haversine.
        final dlat = (p.latitude - poi.latitude).abs();
        final dlng = (p.longitude - poi.longitude).abs();
        if (dlat > 0.01 || dlng > 0.015) continue;

        final d = haversine(p.latitude, p.longitude, poi.latitude, poi.longitude);
        if (d <= radiusSq) {
          found[poi.id] = poi;
        }
      }
    }
    return found.values.toList();
  }

  /// Distanza ortodromica in metri tra due coppie (lat,lng) WGS84.
  /// Implementazione stand-alone (no dipendenze esterne) per essere
  /// usabile in tool diagnostici/test e da widget caller.
  static double haversine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0; // raggio Terra (metri)
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  /// Reset state — solo per uso nei test.
  @visibleForTesting
  void resetForTesting() {
    _all = const [];
    _loaded = false;
    _loadingFuture = null;
  }
}

class _PoiWithDistance {
  final OsmPoi poi;
  final double distance;
  const _PoiWithDistance(this.poi, this.distance);
}
