import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/camera_fov.dart';

/// Il campo visivo era l'ultimo numero indovinato della catena AR, e sbagliarlo
/// di un grado sposta le etichette dell'1,7% della larghezza dello schermo.
/// Qui si verifica con numeri quello che altrimenti si potrebbe controllare solo
/// puntando il telefono verso una montagna.
void main() {
  // Sensore tipico: 4:3, campo orizzontale 70°.
  const sensorH = 70.0;
  final sensorV = 2 *
      math.atan(math.tan(sensorH / 2 * math.pi / 180) * 3 / 4) *
      180 /
      math.pi; // ~56,3°

  test('senza ritaglio il campo resta quello del sensore', () {
    // Viewport con lo stesso rapporto d'aspetto del buffer: cover non taglia.
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: sensorH,
      sensorVerticalDeg: sensorV,
      bufferWidth: 4000,
      bufferHeight: 3000,
      viewportWidth: 800,
      viewportHeight: 600,
    )!;
    expect(fov.horizontalDeg, closeTo(sensorH, 0.01));
    expect(fov.verticalDeg, closeTo(sensorV, 0.01));
  });

  test('in portrait i due campi si scambiano', () {
    // Schermo alto e stretto: il lato orizzontale mostra il lato CORTO del
    // sensore. Senza questo scambio si userebbe il campo largo su un lato
    // stretto, cioè l'errore più grosso possibile.
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: sensorH,
      sensorVerticalDeg: sensorV,
      bufferWidth: 4000,
      bufferHeight: 3000,
      viewportWidth: 600,
      viewportHeight: 800,
    )!;
    expect(fov.horizontalDeg, closeTo(sensorV, 0.01));
    expect(fov.verticalDeg, closeTo(sensorH, 0.01));
  });

  test('il ritaglio si applica alla tangente, non ai gradi', () {
    // Viewport 16:9 su buffer 4:3, in landscape: cover riempie la larghezza e
    // taglia l'altezza a 3/4. Il campo verticale che resta NON è i tre quarti
    // dei gradi: tenendo la parte centrale dell'immagine si conserva più campo
    // di quanto la proporzione suggerisca, perché al centro un pixel copre più
    // gradi che ai bordi. Con 55,4° di partenza restano 43,0° e non 41,6°.
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: sensorH,
      sensorVerticalDeg: sensorV,
      bufferWidth: 4000,
      bufferHeight: 3000,
      viewportWidth: 800,
      viewportHeight: 450,
    )!;
    final expected = 2 *
        math.atan(math.tan(sensorV / 2 * math.pi / 180) * 0.75) *
        180 /
        math.pi;
    expect(fov.verticalDeg, closeTo(expected, 0.01));
    expect(fov.verticalDeg, greaterThan(sensorV * 0.75),
        reason: 'la proporzione lineare sottostima il campo residuo');
    expect(fov.horizontalDeg, closeTo(sensorH, 0.01),
        reason: 'la larghezza è coperta per intero, non si taglia');
  });

  test('un telefono reale in portrait: campo stretto, non largo', () {
    // Buffer 1920×1080 (16:9) su uno schermo 1080×2400.
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: 70,
      sensorVerticalDeg: 42,
      bufferWidth: 1920,
      bufferHeight: 1080,
      viewportWidth: 1080,
      viewportHeight: 2400,
    )!;
    // Orizzontale = lato corto del sensore, ulteriormente ritagliato.
    expect(fov.horizontalDeg, lessThan(42));
    expect(fov.verticalDeg, closeTo(70, 0.01));
    expect(fov.horizontalDeg, greaterThan(10));
  });

  test('una preview 16:9 e\' un ritaglio del sensore 4:3, non il sensore intero',
      () {
    // Numeri veri di un Motorola edge 60 pro: sensore 8,192x6,144 mm, campo
    // dichiarato 72,8x57,8°. Ma la preview e' 16:9, cioe' l'array 4:3 tagliato
    // sopra e sotto: la larghezza resta, l'altezza no. Prendere per buono il
    // 57,8° verticale su un buffer 16:9 sovrastima il campo di 12 gradi.
    const sH = 72.8, sV = 57.8;
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: sH,
      sensorVerticalDeg: sV,
      bufferWidth: 1280,
      bufferHeight: 720,
      // Viewport landscape con lo stesso rapporto: nessun ritaglio ulteriore,
      // cosi' si isola l'effetto del buffer.
      viewportWidth: 1280,
      viewportHeight: 720,
    )!;
    final expectedV = 2 *
        math.atan(math.tan(sH / 2 * math.pi / 180) * 720 / 1280) *
        180 /
        math.pi; // ~45,3°
    expect(fov.horizontalDeg, closeTo(sH, 0.01));
    expect(fov.verticalDeg, closeTo(expectedV, 0.01));
    expect(fov.verticalDeg, lessThan(sV - 10),
        reason: 'il verticale del sensore pieno non vale per un buffer 16:9');
  });

  test('una preview 4:3 usa il sensore per intero', () {
    const sH = 72.8, sV = 57.8;
    final fov = screenFovFromSensor(
      sensorHorizontalDeg: sH,
      sensorVerticalDeg: sV,
      bufferWidth: 1440,
      bufferHeight: 1080,
      viewportWidth: 1440,
      viewportHeight: 1080,
    )!;
    expect(fov.horizontalDeg, closeTo(sH, 0.01));
    expect(fov.verticalDeg, closeTo(sV, 0.2));
  });

  test('valori assurdi o mancanti → null invece di numeri inventati', () {
    expect(
      screenFovFromSensor(
        sensorHorizontalDeg: 0,
        sensorVerticalDeg: 40,
        bufferWidth: 100,
        bufferHeight: 100,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      isNull,
    );
    expect(
      screenFovFromSensor(
        sensorHorizontalDeg: 200,
        sensorVerticalDeg: 40,
        bufferWidth: 100,
        bufferHeight: 100,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      isNull,
    );
    expect(
      screenFovFromSensor(
        sensorHorizontalDeg: 70,
        sensorVerticalDeg: 40,
        bufferWidth: 0,
        bufferHeight: 100,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      isNull,
    );
  });
}
