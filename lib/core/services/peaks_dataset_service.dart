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
  ///
  /// Quando le cime nel raggio superano [maxResults] si tengono le più
  /// **imponenti nella scena**, non le più vicine.
  ///
  /// Tenere le più vicine sembra ragionevole ed è invece l'opposto di ciò che
  /// serve: in un raggio di 60 km sulle Alpi ci sono migliaia di cime, e le 200
  /// più vicine sono tutte cimette dietro casa, mentre spariscono le montagne
  /// che uno vuole riconoscere guardando l'orizzonte. Misurato sul campo: con il
  /// vecchio criterio il raggio di 100 km del tier Pro non serviva a nulla,
  /// perché nessuna cima oltre i 60 km entrava mai nell'insieme.
  ///
  /// Il criterio è l'angolo di elevazione apparente — quanto la cima si alza nel
  /// cielo vista da qui — che è esattamente ciò che la rende notevole: premia sia
  /// il monte vicino sia il gigante lontano e scarta la collinetta.
  /// [observerElevationM] serve a calcolarlo; senza, si assume il livello del
  /// mare e il criterio degrada in "alta e vicina prima".
  List<MountainPeak> findWithinRadius(
    double lat,
    double lng, {
    required double radiusKm,
    int maxResults = 1200,
    double observerElevationM = 0,
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

    // Sotto la soglia si restituisce tutto, ordinato per distanza: è l'ordine
    // che si aspetta chi legge la lista.
    if (results.length <= maxResults) {
      results.sort((a, b) => a.distance.compareTo(b.distance));
      return results.map((r) => r.peak).toList(growable: false);
    }

    // Sopra la soglia il taglio si fa per imponenza apparente, poi si
    // riordina per distanza.
    results.sort((a, b) =>
        b.apparentElevationAngle(observerElevationM)
            .compareTo(a.apparentElevationAngle(observerElevationM)));
    final kept = results.take(maxResults).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    return kept.map((r) => r.peak).toList(growable: false);
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

  /// Angolo sotto cui la cima si alza sull'orizzonte dell'osservatore, in
  /// gradi. Include l'abbassamento per curvatura terrestre, altrimenti a 100 km
  /// una cima risulterebbe 683 m più alta di come appare davvero.
  double apparentElevationAngle(double observerElevationM) {
    if (distance < 1) return 90;
    const earthRadiusM = 6371000.0;
    const refractionK = 0.13;
    final drop = (1 - refractionK) * distance * distance / (2 * earthRadiusM);
    final dh = (peak.elevation ?? 0) - drop - observerElevationM;
    return math.atan2(dh, distance) * 180 / math.pi;
  }
}
