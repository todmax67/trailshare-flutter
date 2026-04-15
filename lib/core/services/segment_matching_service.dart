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

  const SegmentMatchAttempt({
    required this.segment,
    required this.startIdx,
    required this.endIdx,
    required this.durationSeconds,
    required this.averageSpeedKmh,
  });
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
      // Early out: startPoint del segment deve essere nel bbox (con padding)
      const pad = 0.01; // ~1km
      if (seg.startLat < minLat - pad || seg.startLat > maxLat + pad) continue;
      if (seg.startLng < minLng - pad || seg.startLng > maxLng + pad) continue;

      final attempt = _matchSingle(track, seg);
      if (attempt != null) {
        results.add(attempt);
      }
    }

    debugPrint('[SegmentMatching] Track di ${track.points.length} punti → ${results.length} segmenti matchati su ${segments.length}');
    return results;
  }

  static SegmentMatchAttempt? _matchSingle(Track track, Segment seg) {
    final startLL = LatLng(seg.startLat, seg.startLng);
    final endLL = LatLng(seg.endLat, seg.endLng);

    // 1. Trova startIdx
    int? startIdx;
    for (var i = 0; i < track.points.length; i++) {
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
    if (!_followsPolyline(subPoints, seg.polyline)) return null;

    // 4. Calcola duration
    final duration = track.points[endIdx].timestamp
        .difference(track.points[startIdx].timestamp)
        .inSeconds;
    if (duration <= 0) return null;

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
