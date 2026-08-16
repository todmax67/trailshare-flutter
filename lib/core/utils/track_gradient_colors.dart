import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/track.dart';
import 'track_gap_segments.dart';

/// Colorazione tracce per pendenza — logica condivisa tra la mappa fullscreen
/// (`TrackMapPage`) e la mappa inline (`InteractiveTrackMap`).
///
/// È l'elemento-firma del prodotto: la traccia colorata verde(piano) →
/// rosso(salita) → blu(discesa). Vedi `docs/design-system.md`.

/// Pendenza % tra due punti (positivo = salita). 0 se manca la quota.
double slopeBetween(TrackPoint p1, TrackPoint p2) {
  if (p1.elevation == null || p2.elevation == null) return 0;
  final distance = const Distance().as(
    LengthUnit.Meter,
    LatLng(p1.latitude, p1.longitude),
    LatLng(p2.latitude, p2.longitude),
  );
  if (distance < 1) return 0; // evita divisione per zero
  return ((p2.elevation! - p1.elevation!) / distance) * 100;
}

/// Colore per fascia di pendenza (8 fasce discrete).
Color slopeColor(double gradient) {
  if (gradient > 15) return const Color(0xFFB71C1C); // salita ripida
  if (gradient > 10) return const Color(0xFFD32F2F); // salita forte
  if (gradient > 6) return const Color(0xFFFF5722); // salita moderata
  if (gradient > 3) return const Color(0xFFFF9800); // salita leggera
  if (gradient > -3) return const Color(0xFF4CAF50); // piano
  if (gradient > -6) return const Color(0xFF00BCD4); // discesa leggera
  if (gradient > -10) return const Color(0xFF2196F3); // discesa moderata
  if (gradient > -15) return const Color(0xFF1976D2); // discesa forte
  return const Color(0xFF0D47A1); // discesa ripida
}

/// True se almeno un punto ha la quota (serve per decidere se ha senso
/// colorare per pendenza o mostrare la legenda).
bool trackHasElevation(List<TrackPoint> points) =>
    points.any((p) => p.elevation != null);

/// Polyline a segmenti colorati per pendenza. Raggruppa segmenti con lo
/// stesso colore per ridurne il numero. Fallback a polyline singola
/// [fallbackColor] se mancano dati (pochi punti o nessuna quota).
List<Polyline> slopeGradientPolylines(
  List<TrackPoint> points, {
  double strokeWidth = 5,
  required Color fallbackColor,
}) {
  final latLng =
      points.map((p) => LatLng(p.latitude, p.longitude)).toList();

  if (points.length < 2 || !trackHasElevation(points)) {
    return [
      Polyline(points: latLng, strokeWidth: strokeWidth, color: fallbackColor),
    ];
  }

  final polylines = <Polyline>[];
  int startIndex = 0;
  Color? currentColor;

  for (int i = 0; i < points.length - 1; i++) {
    final color = slopeColor(slopeBetween(points[i], points[i + 1]));
    if (currentColor == null) {
      currentColor = color;
      startIndex = i;
    } else if (color != currentColor || i == points.length - 2) {
      final endIndex = (i == points.length - 2) ? i + 2 : i + 1;
      polylines.add(Polyline(
        points: latLng.sublist(startIndex, endIndex),
        strokeWidth: strokeWidth,
        color: currentColor,
      ));
      currentColor = color;
      startIndex = i;
    }
  }
  return polylines;
}

/// Legenda compatta della pendenza (discesa → salita), per overlay mappa.
class SlopeLegend extends StatelessWidget {
  const SlopeLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_down, size: 13, color: Color(0xFF1976D2)),
          const SizedBox(width: 5),
          Container(
            width: 48,
            height: 6,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(3)),
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0D47A1), // discesa ripida
                  Color(0xFF2196F3),
                  Color(0xFF4CAF50), // piano
                  Color(0xFFFF9800),
                  Color(0xFFB71C1C), // salita ripida
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.trending_up, size: 13, color: Color(0xFFB71C1C)),
        ],
      ),
    );
  }
}

// ─── Disegno consapevole dei buchi di registrazione ─────────────────────────

/// Il ponte sopra un buco: tratteggiato, piu' sottile e piu' chiaro del
/// percorso. Si legge come "qui siamo meno sicuri" senza bisogno di legenda.
Polyline gapBridgePolyline(
  TrackSegment bridge, {
  required double strokeWidth,
  required Color color,
}) =>
    Polyline(
      points: bridge.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(),
      strokeWidth: strokeWidth * 0.75,
      color: color.withValues(alpha: 0.45),
      pattern: StrokePattern.dashed(segments: const [8, 8]),
    );

/// Come [slopeGradientPolylines], ma i ponti sopra i buchi di registrazione
/// escono tratteggiati invece che colorati per pendenza.
///
/// Esiste perche' la colorazione per pendenza e' il disegno di DEFAULT della
/// scheda traccia, e la prima stesura del tratteggio (2.11.3) viveva solo nel
/// ramo a tinta unita: sulla mappa che gli utenti vedono davvero il ponte
/// restava una linea piena — colorata, per giunta, con la "pendenza" di un
/// tratto mai percorso. Trovato dal founder al primo collaudo sul campo.
List<Polyline> gapAwareSlopeGradientPolylines(
  List<TrackPoint> points,
  List<TrackGap> gaps, {
  double strokeWidth = 5,
  required Color fallbackColor,
}) {
  if (gaps.isEmpty) {
    return slopeGradientPolylines(points,
        strokeWidth: strokeWidth, fallbackColor: fallbackColor);
  }
  final out = <Polyline>[];
  for (final seg in splitTrackOnGaps(points, gaps)) {
    if (seg.points.length < 2) continue;
    if (seg.isGap) {
      out.add(gapBridgePolyline(seg,
          strokeWidth: strokeWidth, color: fallbackColor));
    } else {
      out.addAll(slopeGradientPolylines(seg.points,
          strokeWidth: strokeWidth, fallbackColor: fallbackColor));
    }
  }
  return out;
}

/// Traccia a tinta unita, con i ponti sopra i buchi tratteggiati. E' il
/// gemello non-gradiente di [gapAwareSlopeGradientPolylines]; la logica di
/// divisione sta in track_gap_segments.dart ed e' verificata dai suoi test.
List<Polyline> solidTrackPolylines(
  List<TrackPoint> points,
  List<TrackGap> gaps, {
  double strokeWidth = 5,
  required Color color,
}) {
  final segments = splitTrackOnGaps(points, gaps);
  final out = <Polyline>[];
  for (final seg in segments) {
    if (seg.points.length < 2) continue;
    if (seg.isGap) {
      out.add(gapBridgePolyline(seg, strokeWidth: strokeWidth, color: color));
    } else {
      out.add(Polyline(
        points:
            seg.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        strokeWidth: strokeWidth,
        color: color,
      ));
    }
  }
  return out;
}
