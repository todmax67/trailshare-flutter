import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/track_gradient_colors.dart';
import 'package:trailshare_flutter/data/models/track.dart';

/// Il disegno consapevole dei buchi, su ENTRAMBI i rami (pendenza e tinta
/// unita). Esiste perche' la prima stesura del tratteggio viveva solo nel
/// ramo a tinta unita, e sul disegno di default — la pendenza — il ponte
/// restava una linea piena: trovato dal founder al primo collaudo sul campo.
void main() {
  TrackPoint at(int seconds, double lat) => TrackPoint(
        latitude: lat,
        longitude: 9.0,
        elevation: 500 + lat * 10,
        timestamp:
            DateTime.utc(2026, 8, 16, 10).add(Duration(seconds: seconds)),
      );

  // Percorso, buco di 37 minuti, percorso.
  final points = [
    at(0, 45.000),
    at(60, 45.001),
    at(120, 45.002),
    at(120 + 2220, 45.052),
    at(120 + 2280, 45.053),
    at(120 + 2340, 45.054),
  ];
  final gaps = [
    TrackGap(
      startedAt: points[2].timestamp,
      endedAt: points[3].timestamp,
      cause: TrackGap.causeAppFrozen,
    ),
  ];

  // Il ponte si riconosce dalla larghezza ridotta (0,75x): e' il marcatore
  // piu' stabile da verificare senza confrontare pattern di tratteggio.
  bool isBridge(Polyline p, double base) => p.strokeWidth == base * 0.75;

  group('ramo pendenza (il default della scheda)', () {
    test('il ponte esce tratteggiato, non colorato per pendenza', () {
      final out = gapAwareSlopeGradientPolylines(points, gaps,
          strokeWidth: 5, fallbackColor: Colors.orange);

      final bridges = out.where((p) => isBridge(p, 5)).toList();
      expect(bridges, hasLength(1),
          reason: 'un buco = un ponte, sottile e tratteggiato');
      expect(bridges.single.points, hasLength(2),
          reason: 'il ponte unisce i soli due estremi: non e\' un percorso');
      expect(out.length, greaterThan(1),
          reason: 'i tratti percorsi restano colorati per pendenza');
    });

    test('senza buchi il disegno resta identico a prima', () {
      final before = slopeGradientPolylines(points,
          strokeWidth: 5, fallbackColor: Colors.orange);
      final after = gapAwareSlopeGradientPolylines(points, const [],
          strokeWidth: 5, fallbackColor: Colors.orange);
      expect(after.length, before.length);
      expect(after.every((p) => !isBridge(p, 5)), isTrue);
    });
  });

  group('ramo a tinta unita', () {
    test('percorso, ponte, percorso', () {
      final out = solidTrackPolylines(points, gaps,
          strokeWidth: 5, color: Colors.orange);
      expect(out, hasLength(3));
      expect(out.where((p) => isBridge(p, 5)), hasLength(1));
    });

    test('senza buchi: una polilinea sola, piena', () {
      final out = solidTrackPolylines(points, const [],
          strokeWidth: 5, color: Colors.orange);
      expect(out, hasLength(1));
      expect(isBridge(out.single, 5), isFalse);
    });
  });
}
