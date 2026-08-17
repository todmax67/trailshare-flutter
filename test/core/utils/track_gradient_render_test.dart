import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  group('il ponte ricostruito segue il percorso dichiarato', () {
    final ricostruito = [
      TrackGap(
        startedAt: points[2].timestamp,
        endedAt: points[3].timestamp,
        cause: TrackGap.causeAppFrozen,
        reconstruction: const [
          LatLng(45.002, 9.0),
          LatLng(45.020, 9.01),
          LatLng(45.040, 9.02),
          LatLng(45.052, 9.0),
        ],
        reconstructedAt: null,
      ),
    ];

    test('il ponte usa i punti disegnati, non i due estremi', () {
      final out = solidTrackPolylines(points, ricostruito,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points, hasLength(4),
          reason: 'segue il percorso dichiarato dal proprietario');
    });

    test('resta tratteggiato: dichiarato non vuol dire misurato', () {
      final out = solidTrackPolylines(points, ricostruito,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      // Il marcatore e' la larghezza ridotta: identica al ponte in linea retta.
      expect(bridge.strokeWidth, 5 * 0.75);
    });

    test('vale anche nel ramo colorato per pendenza', () {
      final out = gapAwareSlopeGradientPolylines(points, ricostruito,
          strokeWidth: 5, fallbackColor: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points, hasLength(4));
    });

    test('senza ricostruzione il ponte resta la retta fra due punti', () {
      final out = solidTrackPolylines(points, gaps,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points, hasLength(2));
    });
  });

  group('il ponte e ancorato agli estremi misurati', () {
    // Il routing aggancia i waypoint alla via piu vicina, anche a centinaia
    // di metri: disegnando solo la ricostruzione restavano due raccordi senza
    // alcun segno sulla mappa — incertezza sparita proprio nella funzione che
    // esiste per dichiararla.
    final staccata = [
      TrackGap(
        startedAt: points[2].timestamp,
        endedAt: points[3].timestamp,
        cause: TrackGap.causeAppFrozen,
        reconstruction: const [
          LatLng(45.030, 9.05),
          LatLng(45.040, 9.06),
        ],
      ),
    ];

    test('primo e ultimo punto coincidono coi punti misurati', () {
      final out = solidTrackPolylines(points, staccata,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points.first.latitude, closeTo(points[2].latitude, 1e-9));
      expect(bridge.points.last.latitude, closeTo(points[3].latitude, 1e-9));
    });

    test('la ricostruzione sta in mezzo, non sostituisce gli estremi', () {
      final out = solidTrackPolylines(points, staccata,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points, hasLength(4),
          reason: 'estremo + 2 disegnati + estremo');
    });
  });

  group('piu buchi sullo stesso arco', () {
    // Il watchdog ne emette uno ogni 5 minuti: su un congelamento lungo sono
    // la norma. Chi disegna e chi offre devono scegliere lo STESSO buco.
    final due = [
      TrackGap(
        startedAt: points[2].timestamp.add(const Duration(seconds: 1)),
        endedAt: points[2].timestamp.add(const Duration(minutes: 5)),
        cause: TrackGap.causeStreamStalled,
      ),
      TrackGap(
        startedAt: points[2].timestamp.add(const Duration(minutes: 5)),
        endedAt: points[3].timestamp,
        cause: TrackGap.causeAppFrozen,
        reconstruction: const [
          LatLng(45.030, 9.01),
          LatLng(45.040, 9.02),
        ],
      ),
    ];

    test('vince quello ricostruito, non il primo della lista', () {
      final out = solidTrackPolylines(points, due,
          strokeWidth: 5, color: Colors.orange);
      final bridge = out.firstWhere((p) => isBridge(p, 5));
      expect(bridge.points, hasLength(4),
          reason: 'se vincesse il primo (non ricostruito) sarebbero 2: la retta');
    });

    test('un arco solo, non due ponti', () {
      final out = solidTrackPolylines(points, due,
          strokeWidth: 5, color: Colors.orange);
      expect(out.where((p) => isBridge(p, 5)), hasLength(1));
    });
  });
}
