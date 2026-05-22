import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';

/// Unit test puri sulla math di [computeViewshed] — niente network, niente
/// I/O. Usano un [DemGrid] sintetico per verificare i comportamenti chiave:
///   1. Cima dietro un crinale è OCCLUSA
///   2. Cima libera in linea diretta è VISIBILE
///   3. Distanza, azimut e elevation angle sono calcolati correttamente
///   4. La curvatura terrestre abbassa cime molto lontane
void main() {
  group('computeViewshed — terreno piatto', () {
    // DEM piatto a 0m, 0.5° × 0.5° intorno all'osservatore (~55 km lato).
    final flatDem = DemGrid(
      minLat: 44.5, maxLat: 45.0,
      minLng: 8.5, maxLng: 9.0,
      rows: 50, cols: 50,
      elevations: List<double>.filled(50 * 50, 0.0),
    );

    test('skyline ~0° su terreno piatto', () {
      final res = computeViewshed(ViewshedRequest(
        observerLat: 44.75,
        observerLng: 8.75,
        dem: flatDem,
        maxRadiusKm: 20,
        azimuthSteps: 36,
        candidatePeaks: const [],
      ));
      // Su terreno piatto + osservatore alto 1.7m → skyline angles tutti
      // negativi piccoli (l'orizzonte è sotto la linea di vista).
      for (final a in res.skylineAngles) {
        expect(a, lessThan(0.01));
        expect(a, greaterThan(-5));
      }
    });

    test('cima isolata in pianura è visibile', () {
      final res = computeViewshed(ViewshedRequest(
        observerLat: 44.75,
        observerLng: 8.75,
        dem: flatDem,
        maxRadiusKm: 30,
        azimuthSteps: 36,
        candidatePeaks: const [
          {'id': 'p1', 'lat': 44.85, 'lng': 8.85, 'ele': 1000.0},
        ],
      ));
      expect(res.peaks, hasLength(1));
      expect(res.peaks.first.visible, isTrue);
      // Distanza ~ 13.6km (0.1° lat + 0.1° lng @ 45°)
      expect(res.peaks.first.distanceMeters, inInclusiveRange(12000, 15000));
      // Azimut NE-ish: 0.1° lat = 11.1km, 0.1° lng = ~7.9km a lat 44.7
      // → bearing = atan2(7.9, 11.1) ≈ 35°. Allarghiamo il range.
      expect(res.peaks.first.azimuthDeg, inInclusiveRange(30, 50));
    });
  });

  group('computeViewshed — crinale che occlude', () {
    // DEM con un "muro" di quota 2000m che taglia diagonalmente la griglia.
    // L'osservatore al centro guarda verso una cima oltre il muro.
    DemGrid wallDem() {
      const rows = 50, cols = 50;
      final ele = List<double>.filled(rows * cols, 0.0);
      // Muro: riga centrale di altezza alta nel range lat~44.78
      for (int c = 10; c < 40; c++) {
        for (int r = 22; r < 28; r++) {
          ele[r * cols + c] = 2000;
        }
      }
      return DemGrid(
        minLat: 44.5, maxLat: 45.0,
        minLng: 8.5, maxLng: 9.0,
        rows: rows, cols: cols,
        elevations: ele,
      );
    }

    test('cima dietro il muro è occlusa', () {
      // Muro a ~7km dall'osservatore, alto 2000m → skyline angle ~16°.
      // Cima a ~33km dietro: ele 1500m → angle ~2.6° → CHIARAMENTE occlusa.
      final res = computeViewshed(ViewshedRequest(
        observerLat: 44.65,
        observerLng: 8.75,
        dem: wallDem(),
        maxRadiusKm: 30,
        azimuthSteps: 90,
        rayStepMeters: 100,
        candidatePeaks: const [
          {'id': 'occluded', 'lat': 44.95, 'lng': 8.75, 'ele': 1500.0},
        ],
      ));
      expect(res.peaks.first.visible, isFalse,
          reason: 'cima 1500m a 33km vs muro 2000m a 7km → occlusa');
    });

    test('cima molto più alta del muro è visibile', () {
      // Per essere visibile da 33km dietro un muro 2000m a 7km, il peak
      // angle deve > muro angle. Muro angle ≈ atan(2000/7000) ≈ 16°.
      // Peak a 33km deve avere angle > 16° → ele > tan(16°)*33000 ≈ 9500m.
      // Quindi mettiamo cima a 12000m (esagerata ma valida il pathway).
      final res = computeViewshed(ViewshedRequest(
        observerLat: 44.65,
        observerLng: 8.75,
        dem: wallDem(),
        maxRadiusKm: 30,
        azimuthSteps: 90,
        rayStepMeters: 100,
        candidatePeaks: const [
          {'id': 'visible', 'lat': 44.95, 'lng': 8.75, 'ele': 12000.0},
        ],
      ));
      expect(res.peaks.first.visible, isTrue,
          reason: 'cima 12000m a 33km supera angolarmente muro 2000m a 7km');
    });
  });

  group('curvatura + rifrazione', () {
    final flatDem = DemGrid(
      minLat: 44.0, maxLat: 46.0,
      minLng: 8.0, maxLng: 10.0,
      rows: 100, cols: 100,
      elevations: List<double>.filled(100 * 100, 0.0),
    );

    test('cima 100km via mare a 100m sparisce sotto l\'orizzonte', () {
      // A 100km, earth drop ≈ 683m (con k=0.13). Cima a 100m è sotto l'orizzonte.
      final res = computeViewshed(ViewshedRequest(
        observerLat: 44.0,
        observerLng: 9.0,
        dem: flatDem,
        maxRadiusKm: 110,
        azimuthSteps: 36,
        candidatePeaks: const [
          {'id': 'far_low', 'lat': 44.9, 'lng': 9.0, 'ele': 100.0},
        ],
      ));
      final pr = res.peaks.first;
      expect(pr.elevationAngleDeg, lessThan(0),
          reason: 'cima oltre orizzonte → elevation angle negativo');
    });
  });
}
