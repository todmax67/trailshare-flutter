import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';

/// Test della visibilità delle cime su terreni sintetici. Niente rete, niente
/// I/O: si costruisce il DEM da una funzione della posizione e si verifica che
/// l'algoritmo concluda quello che si vede a occhio sulla geometria.

const double _obsLat = 45.0;
const double _obsLng = 9.0;

/// Metri di latitudine per grado, per posizionare le cose a distanze note.
const double _mPerDegLat = 111320.0;

double _latAtNorth(double meters) => _obsLat + meters / _mPerDegLat;

/// Costruisce una griglia riempita da [terrain], usando i metodi della griglia
/// stessa per la corrispondenza riga↔latitudine — cioè lo stesso contratto che
/// deve seguire il mosaico dei tile.
DemGrid buildGrid({
  required double minLat,
  required double maxLat,
  required double minLng,
  required double maxLng,
  required int rows,
  required int cols,
  required double Function(double lat, double lng) terrain,
}) {
  final ele = Float32List(rows * cols);
  final grid = DemGrid(
    minLat: minLat,
    maxLat: maxLat,
    minLng: minLng,
    maxLng: maxLng,
    rows: rows,
    cols: cols,
    elevations: ele,
  );
  for (var r = 0; r < rows; r++) {
    final lat = grid.latForRow(r);
    for (var c = 0; c < cols; c++) {
      ele[r * cols + c] = terrain(lat, grid.lngForCol(c));
    }
  }
  return grid;
}

/// Griglia larga standard: mezzo grado attorno all'osservatore, celle ~100 m.
DemGrid wideGrid(double Function(double lat, double lng) terrain) => buildGrid(
      minLat: 44.8,
      maxLat: 45.4,
      minLng: 8.7,
      maxLng: 9.3,
      rows: 668, // ~100 m
      cols: 472, // ~100 m
      terrain: terrain,
    );

PeakResult runOne({
  required DemGrid coarse,
  DemGrid? fine,
  required double peakLat,
  required double peakEle,
  double toleranceDeg = 0.05,
}) {
  final res = computeViewshed(ViewshedRequest(
    observerLat: _obsLat,
    observerLng: _obsLng,
    dem: LayeredDem(coarse: coarse, fine: fine),
    visibilityToleranceDeg: toleranceDeg,
    candidatePeaks: [
      {'id': 'p', 'lat': peakLat, 'lng': _obsLng, 'ele': peakEle},
    ],
  ));
  return res.peaks.single;
}

void main() {
  group('convenzione delle righe della griglia', () {
    // Il mosaico dei tile e elevationAt avevano convenzioni opposte e il DEM
    // veniva riletto specchiato nord-sud. Questi test bloccano il contratto.
    test('riga 0 = bordo sud, ultima riga = bordo nord', () {
      final g = buildGrid(
        minLat: 45, maxLat: 46, minLng: 9, maxLng: 10,
        rows: 5, cols: 5, terrain: (_, _) => 0,
      );
      expect(g.latForRow(0), closeTo(45.0, 1e-9));
      expect(g.latForRow(4), closeTo(46.0, 1e-9));
      expect(g.lngForCol(0), closeTo(9.0, 1e-9));
      expect(g.lngForCol(4), closeTo(10.0, 1e-9));
    });

    test('un terreno che sale verso nord si rilegge in salita verso nord', () {
      final g = buildGrid(
        minLat: 45, maxLat: 46, minLng: 9, maxLng: 10,
        rows: 101, cols: 3,
        terrain: (lat, _) => 1000 * (lat - 45),
      );
      expect(g.elevationAt(45.05, 9.5), closeTo(50, 12));
      expect(g.elevationAt(45.50, 9.5), closeTo(500, 12));
      expect(g.elevationAt(45.95, 9.5), closeTo(950, 12));
    });

    test('scrivere e rileggere la stessa cella dà lo stesso valore', () {
      const rows = 7, cols = 5;
      final g = buildGrid(
        minLat: 45, maxLat: 46, minLng: 9, maxLng: 10,
        rows: rows, cols: cols,
        terrain: (_, _) => 0,
      );
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          g.elevations[r * cols + c] = r * 100.0 + c;
        }
      }
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          expect(g.elevationAt(g.latForRow(r), g.lngForCol(c)),
              closeTo(r * 100.0 + c, 1e-3),
              reason: 'cella ($r,$c) riletta da un\'altra posizione');
        }
      }
    });
  });

  group('linea di vista', () {
    test('cima isolata in pianura è visibile', () {
      final dem = wideGrid((_, _) => 500);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 2000,
      );
      expect(pr.visible, isTrue);
      expect(pr.distanceMeters, closeTo(15000, 200));
      expect(pr.azimuthDeg, closeTo(0, 0.5));
      expect(pr.clearanceDeg, greaterThan(1));
    });

    test('un crinale davanti la occlude', () {
      // Muro a 2500 m dall'osservatore, 300 m più alto della pianura.
      final ridgeLat = _latAtNorth(2500);
      final dem = wideGrid((lat, _) =>
          (lat - ridgeLat).abs() < 0.003 ? 1400.0 : 500.0);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 1500,
      );
      expect(pr.visible, isFalse);
      expect(pr.clearanceDeg, lessThan(0));
    });

    test('una cima molto più alta del crinale lo scavalca', () {
      final ridgeLat = _latAtNorth(2500);
      final dem = wideGrid((lat, _) =>
          (lat - ridgeLat).abs() < 0.003 ? 1400.0 : 500.0);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 8000,
      );
      expect(pr.visible, isTrue);
    });

    test('la vetta non viene occlusa dal proprio pendio', () {
      // Cono: il terreno sale fino alla vetta. Senza il taglio prima della
      // cima, gli ultimi campioni — che sono la cima stessa — la nasconderebbero.
      final peakLat = _latAtNorth(8000);
      final dem = wideGrid((lat, _) {
        final dLat = (lat - peakLat).abs();
        if (dLat > 0.02) return 500.0;
        return 500 + 1500 * (1 - dLat / 0.02);
      });
      final pr = runOne(coarse: dem, peakLat: peakLat, peakEle: 2000);
      expect(pr.visible, isTrue);
    });
  });

  group('il margine non deve nascondere le cime che si vedono', () {
    // Geometria alpina realistica: una dorsale a 2150 m distante 25 km e una
    // cima a 2600 m dietro, a 30 km. La linea di vista passa ~90 m sopra la
    // dorsale, quindi la cima si vede.
    //
    // Il vecchio criterio pretendeva 0,5° di stacco *angolare*, che a 30 km
    // significa 260 m di quota: la differenza qui è 0,21° e la cima veniva
    // dichiarata invisibile. E' il motivo per cui il filtro nascondeva troppo.
    DemGrid demWithRidge() {
      final ridgeLat = _latAtNorth(25000);
      return wideGrid(
          (lat, _) => (lat - ridgeLat).abs() < 0.0025 ? 2150.0 : 500.0);
    }

    test('una cima che sporge di ~90 m dietro una dorsale è visibile', () {
      final pr = runOne(
        coarse: demWithRidge(),
        peakLat: _latAtNorth(30000),
        peakEle: 2600,
      );
      expect(pr.visible, isTrue);
      expect(pr.clearanceDeg, inInclusiveRange(0.1, 0.4));
    });

    test('lo stacco angolare qui è sotto il vecchio margine di 0,5°', () {
      // Verifica che il caso sopra sarebbe davvero stato scartato prima:
      // e' la ragione per cui il test ha senso.
      final pr = runOne(
        coarse: demWithRidge(),
        peakLat: _latAtNorth(30000),
        peakEle: 2600,
      );
      final ridgeAngle = math.atan2(2150 - 42.7 - 501.7, 25000) * 180 / math.pi;
      expect(pr.elevationAngleDeg - ridgeAngle, lessThan(0.5));
    });

    test('ma se passa sotto la dorsale resta nascosta', () {
      final pr = runOne(
        coarse: demWithRidge(),
        peakLat: _latAtNorth(30000),
        peakEle: 2350,
      );
      expect(pr.visible, isFalse);
    });
  });

  group('campo vicino e risoluzione del DEM', () {
    // Un dosso di 60 m ampio 200 m, appena 400 metri davanti, nasconde una
    // cima a 20 km. Ma un DEM a bassa risoluzione non lo vede come un dosso:
    // lo **media** col terreno intorno e ne restituisce un rialzo di una
    // ventina di metri, che non basta a occludere. È il motivo per cui il
    // terreno vicino si scarica a zoom maggiore.
    final moundLat = _latAtNorth(400);

    /// Terreno vero: dosso netto.
    double sharp(double lat, double _) =>
        (lat - moundLat).abs() < 0.0009 ? 660.0 : 600.0;

    /// Come lo vede una griglia con celle da ~450 m: il dosso è più stretto
    /// della cella, quindi si spalma su una base più larga e molto più bassa.
    double smoothed(double lat, double _) {
      final t = 1 - ((lat - moundLat).abs() / 0.0027);
      return t <= 0 ? 600.0 : 600.0 + 27.0 * t;
    }

    test('la griglia fitta vede il dosso vicino e occlude', () {
      final fine = buildGrid(
        minLat: _obsLat - 0.02, maxLat: _obsLat + 0.02,
        minLng: _obsLng - 0.03, maxLng: _obsLng + 0.03,
        rows: 178, cols: 178, // ~25 m
        terrain: sharp,
      );
      final pr = runOne(
        coarse: wideGrid(smoothed),
        fine: fine,
        peakLat: _latAtNorth(20000),
        peakEle: 2000,
      );
      expect(pr.visible, isFalse,
          reason: 'un dosso a 400 m nasconde una cima a 20 km');
    });

    test('con le sole celle grosse lo stesso dosso non occlude più', () {
      final pr = runOne(
        coarse: wideGrid(smoothed),
        peakLat: _latAtNorth(20000),
        peakEle: 2000,
      );
      expect(pr.visible, isTrue,
          reason: 'il dosso mediato non arriva alla linea di vista');
    });
  });

  group('curvatura terrestre', () {
    test('una cima bassa oltre l\'orizzonte marino è nascosta', () {
      // A 100 km l'abbassamento vale 683 m: una cima di 100 m sul mare non si
      // vede, ed e' il mare stesso a occluderla.
      final dem = buildGrid(
        minLat: 44.0, maxLat: 46.0, minLng: 8.0, maxLng: 10.0,
        rows: 500, cols: 500,
        terrain: (_, _) => 0,
      );
      final pr = computeViewshed(ViewshedRequest(
        observerLat: 44.0,
        observerLng: 9.0,
        dem: LayeredDem(coarse: dem),
        candidatePeaks: [
          {'id': 'far', 'lat': 44.9, 'lng': 9.0, 'ele': 100.0},
        ],
      )).peaks.single;
      expect(pr.elevationAngleDeg, lessThan(0));
      expect(pr.visible, isFalse);
    });
  });

  group('terreno sconosciuto', () {
    test('cima oltre un buco: mostrata ma dichiarata incerta', () {
      final holeLat = _latAtNorth(5000);
      final dem = wideGrid((lat, _) =>
          (lat - holeLat).abs() < 0.005 ? double.nan : 500.0);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 2000,
      );
      expect(pr.visible, isTrue);
      expect(pr.uncertain, isTrue,
          reason: 'non possiamo dimostrare che sia libera');
    });

    test('senza buchi non c\'è incertezza', () {
      final pr = runOne(
        coarse: wideGrid((_, _) => 500),
        peakLat: _latAtNorth(15000),
        peakEle: 2000,
      );
      expect(pr.uncertain, isFalse);
    });

    test('un buco oltre la cima non la rende incerta', () {
      final holeLat = _latAtNorth(25000);
      final dem = wideGrid((lat, _) =>
          (lat - holeLat).abs() < 0.005 ? double.nan : 500.0);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 2000,
      );
      expect(pr.uncertain, isFalse);
    });

    test('osservatore fuori dal DEM: tutto incerto, non tutto invisibile', () {
      final dem = wideGrid((_, _) => double.nan);
      final pr = runOne(
        coarse: dem,
        peakLat: _latAtNorth(15000),
        peakEle: 2000,
      );
      expect(pr.visible, isTrue);
      expect(pr.uncertain, isTrue);
    });
  });

  group('passo di campionamento', () {
    test('vicino è fine, lontano si allarga', () {
      final coarse = wideGrid((_, _) => 500);
      final fine = buildGrid(
        minLat: _obsLat - 0.02, maxLat: _obsLat + 0.02,
        minLng: _obsLng - 0.03, maxLng: _obsLng + 0.03,
        rows: 178, cols: 178,
        terrain: (_, _) => 500,
      );
      final dem = LayeredDem(coarse: coarse, fine: fine);
      final near = dem.stepAt(500);
      final far = dem.stepAt(40000);
      expect(near, lessThan(40));
      expect(far, greaterThan(near));
      expect(far, lessThan(200));
    });
  });
}
