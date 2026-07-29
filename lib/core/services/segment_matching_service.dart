import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
import 'navigation_service.dart';

/// Risultato di un match geometrico (prima del calcolo record personale/assoluto).
class SegmentMatchAttempt {
  final Segment segment;
  final int startIdx;
  final int endIdx;
  final int durationSeconds;
  final double averageSpeedKmh;

  /// Quale giro e', dentro questa uscita: 0 il primo. GEMELLO di
  /// `indicePassaggio` in functions/segment_matching.js.
  final int passIndex;

  const SegmentMatchAttempt({
    required this.segment,
    required this.startIdx,
    required this.endIdx,
    required this.durationSeconds,
    required this.averageSpeedKmh,
    this.passIndex = 0,
  });

  SegmentMatchAttempt conPassaggio(int i) => SegmentMatchAttempt(
        segment: segment,
        startIdx: startIdx,
        endIdx: endIdx,
        durationSeconds: durationSeconds,
        averageSpeedKmh: averageSpeedKmh,
        passIndex: i,
      );
}

/// Servizio puro (stateless) che, data una [Track] appena salvata e la lista
/// di tutti i [Segment] conosciuti, restituisce i segmenti attraversati e il
/// tempo impiegato da/a start ed end.
///
/// L'algoritmo è una semplice versione euristica per MVP:
/// 1. Filtra i segmenti il cui startPoint è nel bounding box della track.
/// 2. Per ogni segmento candidato:
///    - trova il primo punto della track entro [_startRadius] dal segment.start
///    - trova il primo punto dopo questo entro [_endRadius] dal segment.end
///    - verifica che i punti intermedi seguano il polyline (tolleranza generosa)
///    - calcola duration da timestamp
class SegmentMatchingService {
  static const double _startRadius = 30;
  static const double _endRadius = 30;
  static const double _avgPolylineTolerance = 40;
  static const double _maxPolylineTolerance = 80;

  /// Attività confrontabili fra loro. Un segmento di corsa non ha senso in
  /// bici: si va molto più forte e ogni passaggio diventa un primato — è il
  /// motivo per cui il founder vedeva "record personale" su qualsiasi
  /// attività. Ma corsa e trail running sulla stessa salita sono la stessa
  /// gara, e camminare è la versione lenta di correre: separarli darebbe
  /// classifiche vuote. Sci ed e-bike stanno per conto loro.
  ///
  /// GEMELLO di FAMIGLIE in functions/segment_matching.js: cambiarne uno
  /// solo fa divergere l'app dal recupero storico.
  static const _famiglie = <List<String>>[
    ['trekking', 'walking', 'running', 'trailRunning'],
    ['cycling', 'gravelBiking', 'mountainBiking'],
    ['eBike', 'eMountainBike'],
    ['skiTouring', 'alpineSkiing', 'nordicSkiing', 'snowboarding', 'snowshoeing'],
  ];

  static bool _attivitaCompatibili(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return true;
    if (a == b) return true;
    return _famiglie.any((f) => f.contains(a) && f.contains(b));
  }

  static List<SegmentMatchAttempt> match(Track track, List<Segment> segments) {
    final results = <SegmentMatchAttempt>[];
    if (track.points.length < 2 || segments.isEmpty) return results;

    // Bounding box della track
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in track.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    for (final seg in segments) {
      // Un segmento di un'altra famiglia di attività non si confronta:
      // altrimenti una pedalata entra nella classifica dei podisti.
      if (!_attivitaCompatibili(track.activityType.name, seg.activityType)) {
        continue;
      }
      // Early out: startPoint del segment deve essere nel bbox (con padding)
      const pad = 0.01; // ~1km
      if (seg.startLat < minLat - pad || seg.startLat > maxLat + pad) continue;
      if (seg.startLng < minLng - pad || seg.startLng > maxLng + pad) continue;

      results.addAll(_passaggi(track, seg));
    }

    debugPrint('[SegmentMatching] Track di ${track.points.length} punti → ${results.length} segmenti matchati su ${segments.length}');
    return results;
  }

  /// TUTTI i passaggi sul segmento dentro una traccia.
  ///
  /// Prima se ne contava uno solo: su un allenamento a ripetute — o su un
  /// anello ripercorso — i giri successivi sparivano, e proprio lì il
  /// confronto fra un giro e l'altro è l'informazione che serve. Dopo ogni
  /// arrivo la ricerca riparte dal punto successivo.
  ///
  /// GEMELLO di `passaggi` in functions/segment_matching.js.
  static List<SegmentMatchAttempt> _passaggi(Track track, Segment seg,
      {int max = 20}) {
    final out = <SegmentMatchAttempt>[];
    var da = 0;
    while (out.length < max) {
      final r = _matchSingle(track, seg, da);
      if (r == null) break;
      out.add(r.conPassaggio(out.length));
      da = r.endIdx + 1; // sempre in avanti: niente cicli infiniti
    }
    return out;
  }

  static SegmentMatchAttempt? _matchSingle(Track track, Segment seg,
      [int da = 0]) {
    final startLL = LatLng(seg.startLat, seg.startLng);
    final endLL = LatLng(seg.endLat, seg.endLng);

    // 1. Trova startIdx
    int? startIdx;
    for (var i = da; i < track.points.length; i++) {
      final p = LatLng(track.points[i].latitude, track.points[i].longitude);
      if (NavigationService.distanceMeters(p, startLL) < _startRadius) {
        startIdx = i;
        break;
      }
    }
    if (startIdx == null) return null;

    // 2. Trova endIdx dopo startIdx
    int? endIdx;
    for (var i = startIdx + 1; i < track.points.length; i++) {
      final p = LatLng(track.points[i].latitude, track.points[i].longitude);
      if (NavigationService.distanceMeters(p, endLL) < _endRadius) {
        endIdx = i;
        break;
      }
    }
    if (endIdx == null) return null;

    // 3. Verifica aderenza al polyline (tolleranza generosa MVP)
    final subPoints = track.points
        .sublist(startIdx, endIdx + 1)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    // Non e' il segmento: fra i due estremi si e' passati altrove (tipico
    // dell'andata e ritorno che aggancia la partenza dell'andata con
    // l'arrivo del ritorno). Si riprova da dopo questa falsa partenza.
    if (!_followsPolyline(subPoints, seg.polyline)) {
      return _matchSingle(track, seg, startIdx + 1);
    }

    // 4. Calcola duration
    final duration = track.points[endIdx].timestamp
        .difference(track.points[startIdx].timestamp)
        .inSeconds;
    if (duration <= 0) return _matchSingle(track, seg, startIdx + 1);

    final avgSpeedKmh = seg.distance > 0 ? (seg.distance / duration) * 3.6 : 0.0;

    return SegmentMatchAttempt(
      segment: seg,
      startIdx: startIdx,
      endIdx: endIdx,
      durationSeconds: duration,
      averageSpeedKmh: avgSpeedKmh,
    );
  }

  /// Verifica se i [trackPoints] (sub-tratto) seguono il [segmentPolyline]
  /// con tolleranza sufficiente.
  static bool _followsPolyline(
    List<LatLng> trackPoints,
    List<LatLng> segmentPolyline,
  ) {
    if (trackPoints.isEmpty || segmentPolyline.isEmpty) return false;

    double sum = 0;
    double maxD = 0;
    for (final p in trackPoints) {
      final d = NavigationService.distanceToPolyline(segmentPolyline, p);
      sum += d;
      if (d > maxD) maxD = d;
    }
    final avg = sum / trackPoints.length;

    if (avg > _avgPolylineTolerance) return false;
    if (maxD > _maxPolylineTolerance) return false;
    return true;
  }
}
