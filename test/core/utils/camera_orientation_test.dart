import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/camera_orientation.dart';

/// Matrice device→ENU (row-major) costruita dalle colonne, cioè dagli assi del
/// device espressi in ENU. Scriverla così è molto più leggibile che allineare
/// nove numeri a mano.
List<double> _matrixFromDeviceAxes({
  required List<double> deviceX,
  required List<double> deviceY,
  required List<double> deviceZ,
}) =>
    [
      deviceX[0], deviceY[0], deviceZ[0], //
      deviceX[1], deviceY[1], deviceZ[1], //
      deviceX[2], deviceY[2], deviceZ[2], //
    ];

/// Telefono in portrait tenuto verticale, obiettivo posteriore verso nord.
/// X del device = est, Y del device (bordo alto) = su, Z (verso l'utente) = sud.
final _uprightFacingNorth = _matrixFromDeviceAxes(
  deviceX: [1, 0, 0],
  deviceY: [0, 0, 1],
  deviceZ: [0, -1, 0],
);

void main() {
  group('CameraBasis.fromAngles', () {
    test('azimut, pitch e roll fanno round-trip', () {
      for (final az in [0.0, 37.0, 180.0, 271.5, 359.0]) {
        for (final pitch in [-40.0, -5.0, 0.0, 12.0, 55.0]) {
          for (final roll in [-90.0, -12.0, 0.0, 33.0, 90.0]) {
            final b = CameraBasis.fromAngles(
              azimuthDeg: az,
              pitchDeg: pitch,
              rollDeg: roll,
            );
            expect(b.azimuthDeg, closeTo(az % 360, 1e-6),
                reason: 'az=$az pitch=$pitch roll=$roll');
            expect(b.pitchDeg, closeTo(pitch, 1e-6),
                reason: 'az=$az pitch=$pitch roll=$roll');
            expect(b.rollDeg, closeTo(roll, 1e-6),
                reason: 'az=$az pitch=$pitch roll=$roll');
          }
        }
      }
    });

    test('la terna è ortonormale', () {
      final b = CameraBasis.fromAngles(
        azimuthDeg: 123,
        pitchDeg: -17,
        rollDeg: 44,
      );
      double dot(List<double> a, List<double> c) =>
          a[0] * c[0] + a[1] * c[1] + a[2] * c[2];
      final f = [b.fE, b.fN, b.fU];
      final u = [b.uE, b.uN, b.uU];
      final r = [b.rE, b.rN, b.rU];
      expect(dot(f, f), closeTo(1, 1e-9));
      expect(dot(u, u), closeTo(1, 1e-9));
      expect(dot(r, r), closeTo(1, 1e-9));
      expect(dot(f, u), closeTo(0, 1e-9));
      expect(dot(f, r), closeTo(0, 1e-9));
      expect(dot(u, r), closeTo(0, 1e-9));
    });
  });

  group('CameraBasis.fromDeviceToEnu', () {
    test('telefono verticale in portrait verso nord', () {
      final b = CameraBasis.fromDeviceToEnu(_uprightFacingNorth);
      expect(b.azimuthDeg, closeTo(0, 1e-6));
      expect(b.pitchDeg, closeTo(0, 1e-6));
      expect(b.rollDeg, closeTo(0, 1e-6));
    });

    test('obiettivo inclinato verso l\'alto', () {
      // Ruotiamo di 30° attorno all'asse X del device (est): l'obiettivo si
      // alza di 30°, il bordo alto si inclina all'indietro.
      const a = 30 * math.pi / 180;
      final b = CameraBasis.fromDeviceToEnu(_matrixFromDeviceAxes(
        deviceX: [1, 0, 0],
        deviceY: [0, -math.sin(a), math.cos(a)],
        deviceZ: [0, -math.cos(a), -math.sin(a)],
      ));
      expect(b.azimuthDeg, closeTo(0, 1e-6));
      expect(b.pitchDeg, closeTo(30, 1e-6));
      expect(b.rollDeg, closeTo(0, 1e-6));
    });

    test('in landscape la destra dello schermo non è più l\'asse X', () {
      // Stessa posa fisica, ma la UI è ruotata di 90°: l'asse ottico non
      // cambia, cambia solo quale asse del device è "destra" sullo schermo.
      final portrait = CameraBasis.fromDeviceToEnu(_uprightFacingNorth);
      final landscape = CameraBasis.fromDeviceToEnu(
        _uprightFacingNorth,
        screenRotationDeg: 90,
      );
      expect(landscape.azimuthDeg, closeTo(portrait.azimuthDeg, 1e-6));
      expect(landscape.pitchDeg, closeTo(portrait.pitchDeg, 1e-6));
      // Roll di 90°: rispetto allo schermo il mondo è coricato.
      expect(landscape.rollDeg.abs(), closeTo(90, 1e-6));
      // I due landscape devono essere opposti fra loro, non identici: è
      // esattamente l'errore che si otteneva ignorando la rotazione UI.
      final other = CameraBasis.fromDeviceToEnu(
        _uprightFacingNorth,
        screenRotationDeg: 270,
      );
      expect(landscape.rollDeg, closeTo(-other.rollDeg, 1e-6));
    });

    test('rinormalizza una matrice con rumore in virgola mobile', () {
      final noisy = [..._uprightFacingNorth];
      noisy[0] = 1.0004; // versore lungo 1.0004
      final b = CameraBasis.fromDeviceToEnu(noisy);
      final len = math.sqrt(b.rE * b.rE + b.rN * b.rN + b.rU * b.rU);
      expect(len, closeTo(1, 1e-9));
    });
  });

  group('projectDirection', () {
    const w = 1000.0;
    const h = 2000.0;
    final north = CameraBasis.fromAngles(azimuthDeg: 0, pitchDeg: 0);

    ScreenProjection? project(List<double> enu,
            {CameraBasis? basis, double zoom = 1.0}) =>
        projectDirection(
          enu: enu,
          basis: basis ?? north,
          viewportWidth: w,
          viewportHeight: h,
          horizontalFovDeg: 90,
          verticalFovDeg: 90,
          zoom: zoom,
        );

    test('bersaglio sull\'asse ottico → centro esatto', () {
      final p = project([0, 1000, 0])!;
      expect(p.x, closeTo(w / 2, 1e-6));
      expect(p.y, closeTo(h / 2, 1e-6));
      expect(p.relativeBearingDeg, closeTo(0, 1e-6));
      expect(p.relativePitchDeg, closeTo(0, 1e-6));
    });

    test('la mappatura è in tangente, non lineare', () {
      // FOV 90° → semiangolo 45° → tan = 1. Un bersaglio a 45° cade sul bordo,
      // uno a 26,565° (tangente 0,5) cade a metà semilarghezza — non a 0,59
      // come darebbe la vecchia mappatura lineare 26,565/45.
      final edge = project([1000, 1000, 0])!;
      expect(edge.x, closeTo(w, 1e-6));

      final half = project([500, 1000, 0])!;
      expect(half.x, closeTo(w / 2 + w / 4, 1e-6));
      expect(half.relativeBearingDeg, closeTo(26.565, 1e-3));

      // Quanto sbagliava la mappatura lineare in quel punto, in pixel.
      final linearX = w / 2 + (26.565 / 45) * (w / 2);
      expect((linearX - half.x).abs(), greaterThan(45));
    });

    test('sopra il centro significa Y più piccola', () {
      final up = project([0, 1000, 300])!;
      expect(up.y, lessThan(h / 2));
      expect(up.relativePitchDeg, greaterThan(0));
    });

    test('fuori dal cono e dietro la fotocamera → null', () {
      expect(project([1000, 500, 0]), isNull); // oltre 45° a destra
      expect(project([0, -1000, 0]), isNull); // alle spalle
    });

    test('lo zoom restringe il cono per tangente', () {
      // A 2× il semiangolo non è 45/2 ma atan(tan(45°)/2) = 26,565°: un
      // bersaglio a 26,565° finisce esattamente sul bordo.
      final p = project([500, 1000, 0], zoom: 2)!;
      expect(p.x, closeTo(w, 1e-6));
      // E uno a 45° esce dal campo.
      expect(project([1000, 1000, 0], zoom: 2), isNull);
    });

    test('il roll ruota l\'immagine, non solo le etichette', () {
      // Bersaglio in alto sull'asse ottico. Con roll +90° deve spostarsi
      // sull'asse orizzontale dello schermo.
      final rolled = CameraBasis.fromAngles(
        azimuthDeg: 0,
        pitchDeg: 0,
        rollDeg: 90,
      );
      final upright = project([0, 1000, 300])!;
      final tilted = project([0, 1000, 300], basis: rolled)!;
      expect(upright.x, closeTo(w / 2, 1e-6));
      expect(tilted.y, closeTo(h / 2, 1e-6));
      expect((tilted.x - w / 2).abs(), greaterThan(w / 10));
    });
  });

  group('geometria terrestre', () {
    test('abbassamento per curvatura e rifrazione', () {
      expect(earthDropMeters(10000), closeTo(6.8, 0.2));
      expect(earthDropMeters(50000), closeTo(170.6, 1));
      expect(earthDropMeters(100000), closeTo(682.4, 2));
    });

    test('enuOffsetMeters: nord, est e quota', () {
      // Un grado di latitudine più a nord ≈ 111 km, nessuno spostamento a est.
      final enu = enuOffsetMeters(
        observerLat: 45.0,
        observerLng: 9.0,
        observerElevationM: 1000,
        targetLat: 46.0,
        targetLng: 9.0,
        targetElevationM: 3000,
      );
      expect(enu[0].abs(), lessThan(1)); // est
      expect(enu[1], closeTo(111195, 500)); // nord
      // 2000 m di dislivello meno l'abbassamento per curvatura a ~111 km.
      expect(enu[2], closeTo(2000 - earthDropMeters(111195), 1));
    });

    test('la curvatura conta: a 100 km una cima si abbassa di 0,4°', () {
      final flat = math.atan2(2000.0, 100000.0) * 180 / math.pi;
      final withDrop =
          math.atan2(2000.0 - earthDropMeters(100000), 100000.0) * 180 / math.pi;
      expect(flat - withDrop, closeTo(0.39, 0.05));
    });
  });
}
