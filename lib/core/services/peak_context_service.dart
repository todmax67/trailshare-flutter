import 'package:cloud_firestore/cloud_firestore.dart' show Source;
import 'package:flutter/foundation.dart';

import '../../data/models/mountain_peak.dart';
import '../../data/models/osm_poi.dart';
import '../../data/models/hut_opening.dart';
import '../../data/repositories/osm_pois_repository.dart';
import '../../data/repositories/public_trails_repository.dart';
import 'hut_openings_service.dart';

/// Quello che TrailShare sa di una cima, e che i concorrenti non possono sapere.
///
/// Finora la scheda di una vetta mostrava quota, distanza, coordinate e un link
/// a OpenStreetMap: le stesse informazioni che ha chiunque abbia scaricato lo
/// stesso dataset. Ma questa app conosce i sentieri che ci salgono e i rifugi
/// intorno, con le loro aperture stagionali — ed è l'unica cosa del Peak Finder
/// che PeakFinder non può copiare.
class PeakContextService {
  PeakContextService._();
  static final PeakContextService _instance = PeakContextService._();
  factory PeakContextService() => _instance;

  final _pois = OsmPoisRepository();
  final _huts = HutOpeningsService();
  final _trails = PublicTrailsRepository();

  /// Rifugi, bivacchi e ripari attorno alla vetta, con lo stato di apertura
  /// quando lo conosciamo.
  ///
  /// Tutto locale: i POI sono un asset in memoria e le aperture pure, quindi
  /// funziona **anche senza rete** — che per una funzione da usare in quota non
  /// è un dettaglio.
  Future<List<PeakShelter>> sheltersNear(
    MountainPeak peak, {
    double radiusMeters = 3000,
    int limit = 4,
  }) async {
    try {
      if (!_pois.isLoaded) await _pois.ensureLoaded();
      await _huts.ensureLoaded();

      final found = _pois.findNearby(
        peak.latitude,
        peak.longitude,
        radiusMeters: radiusMeters,
        types: const {
          OsmPoiType.alpineHut,
          OsmPoiType.wildernessHut,
          OsmPoiType.shelter,
        },
      );

      final out = <PeakShelter>[];
      for (final poi in found.take(limit)) {
        out.add(PeakShelter(
          poi: poi,
          distanceMeters: OsmPoisRepository.haversine(
            peak.latitude,
            peak.longitude,
            poi.latitude,
            poi.longitude,
          ),
          opening: _huts.forPoi(poi.id)?.resolve(),
        ));
      }
      return out;
    } catch (e) {
      debugPrint('[PeakContext] rifugi non disponibili: $e');
      return const [];
    }
  }

  /// Sentieri che passano vicino alla vetta.
  ///
  /// **Con un'onestà sulla precisione.** Il catalogo indicizza ogni sentiero con
  /// un solo punto — quello mediano del tracciato — quindi una ricerca stretta
  /// attorno alla cima non troverebbe il sentiero che parte a valle e ci sale.
  /// Si prende allora una finestra larga e si filtra in locale sulla geometria
  /// semplificata che arriva già col documento.
  ///
  /// Quella geometria ha una trentina di punti: su un sentiero di 10 km sono
  /// distanti ~330 m l'uno dall'altro. Per questo la soglia è di qualche
  /// centinaio di metri e non di cinquanta: dire "passa dalla vetta" con una
  /// precisione che non abbiamo sarebbe un'affermazione inventata.
  Future<List<PeakTrail>> trailsNear(
    MountainPeak peak, {
    double thresholdMeters = 400,
    int limit = 4,
  }) async {
    try {
      // Finestra larga (~11 km): deve contenere il punto mediano di sentieri
      // che salgono da fondovalle.
      const delta = 0.1;
      final trails = await _trails.getTrailsInBounds(
        minLat: peak.latitude - delta,
        maxLat: peak.latitude + delta,
        minLng: peak.longitude - delta,
        maxLng: peak.longitude + delta,
        limit: 120,
        // La cache prima della rete: la scheda si apre in montagna.
        source: Source.cache,
      );

      final scored = <PeakTrail>[];
      for (final t in trails) {
        if (t.points.isEmpty) continue;
        var best = double.infinity;
        for (final p in t.points) {
          final d = OsmPoisRepository.haversine(
            peak.latitude,
            peak.longitude,
            p.latitude,
            p.longitude,
          );
          if (d < best) best = d;
        }
        if (best <= thresholdMeters) {
          scored.add(PeakTrail(trail: t, closestMeters: best));
        }
      }
      scored.sort((a, b) => a.closestMeters.compareTo(b.closestMeters));
      return scored.take(limit).toList();
    } catch (e) {
      debugPrint('[PeakContext] sentieri non disponibili: $e');
      return const [];
    }
  }
}

/// Un rifugio vicino a una cima, con lo stato di apertura se lo conosciamo.
class PeakShelter {
  final OsmPoi poi;
  final double distanceMeters;

  /// `null` quando del rifugio non sappiamo le aperture. È diverso da
  /// "chiuso": non sapere e sapere che è chiuso non vanno mai confusi.
  final OpeningStatus? opening;

  const PeakShelter({
    required this.poi,
    required this.distanceMeters,
    this.opening,
  });

  /// Dislivello dalla vetta al rifugio, se entrambe le quote sono note.
  /// Negativo = il rifugio sta più in basso, che è il caso normale.
  double? elevationDeltaFrom(MountainPeak peak) {
    final hut = poi.elevation;
    final top = peak.elevation;
    if (hut == null || top == null) return null;
    return hut - top;
  }
}

/// Un sentiero che passa vicino a una cima.
class PeakTrail {
  final PublicTrail trail;

  /// Quanto il tracciato si avvicina davvero alla vetta, in metri. Misurato
  /// sulla geometria semplificata, quindi va letto come ordine di grandezza.
  final double closestMeters;

  const PeakTrail({required this.trail, required this.closestMeters});

  /// True quando il tracciato tocca la vetta, non solo le passa vicino.
  bool get reachesSummit => closestMeters <= 150;

  /// Dislivello arrotondato alle decine, per non fingere una precisione che il
  /// catalogo non ha.
  int? get elevationGainRounded {
    final g = trail.elevationGain;
    if (g == null || g <= 0) return null;
    return (g / 10).round() * 10;
  }

  /// Lunghezza in km con una cifra decimale sotto i 10 km.
  String? get lengthLabel {
    final l = trail.length;
    if (l == null || l <= 0) return null;
    final km = l / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }
}

/// Formattazione di una distanza breve, per le schede.
String formatShortDistance(double meters) {
  if (meters < 950) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// Etichetta leggibile per lo stato di apertura, o `null` se non c'è niente da
/// dire. Non inventa: quando il dato riguarda solo stagioni passate, tace.
String? openingLabel(OpeningStatus? status) {
  if (status == null) return null;
  switch (status.verdict) {
    case OpeningVerdict.sempreAccessibile:
      return 'sempre accessibile';
    case OpeningVerdict.aperto:
      return 'aperto';
    case OpeningVerdict.chiuso:
      return 'chiuso';
    case OpeningVerdict.probabilmenteAperto:
      return 'di solito aperto';
    case OpeningVerdict.probabilmenteChiuso:
      return 'di solito chiuso';
    case OpeningVerdict.soloStagioniPassate:
    case OpeningVerdict.ignoto:
      return null;
  }
}

/// Dislivello formattato con il segno, per dire "300 m più in basso".
String formatElevationDelta(double delta) {
  final m = delta.abs().round();
  return delta < 0 ? '$m m più in basso' : '$m m più in alto';
}
