import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/utils/camera_orientation.dart';
import '../../core/utils/viewshed_compute.dart' show TerrainProfiles;

/// Profilo dell'orizzonte calcolato dal DEM, disegnato sopra l'immagine della
/// fotocamera.
///
/// È il riferimento visivo che mancava. Finché l'app si limita a mettere dei
/// nomi in mezzo al cielo, l'utente non ha modo di capire se il puntamento è
/// giusto: se un'etichetta è fuori posto se ne accorge solo per le cime che già
/// riconosce. Con il profilo del terreno sovrapposto invece lo vede subito —
/// la linea o combacia con le montagne vere o no — ed è quello che rende
/// sensato il trascinamento per allineare.
///
/// È anche il motivo per cui i concorrenti migliori disegnano il panorama
/// invece di limitarsi a etichettarlo.
class SkylineOverlay extends StatelessWidget {
  /// Angolo di elevazione massimo del terreno per ogni direzione, dall'azimut
  /// 0 (nord) in senso orario. NaN dove il DEM non sa rispondere.
  final List<double> skylineAngles;

  /// Il terreno per fasce di distanza. Quando c'è, invece di una sola linea si
  /// disegnano i crinali intermedi, che è ciò che dà profondità al paesaggio.
  ///
  /// **Qui non si riempie.** Nel panorama le fasce sono superfici colorate; sopra
  /// la fotocamera devono restare linee, perché una superficie piena coprirebbe
  /// l'immagine, cioè l'unica cosa che l'AR ha da mostrare.
  final TerrainProfiles profiles;

  final CameraBasis basis;
  final double horizontalFovDeg;
  final double verticalFovDeg;
  final double zoom;
  final Color color;

  const SkylineOverlay({
    super.key,
    required this.skylineAngles,
    this.profiles = TerrainProfiles.empty,
    required this.basis,
    required this.horizontalFovDeg,
    required this.verticalFovDeg,
    this.zoom = 1.0,
    this.color = const Color(0xFF7CE0FF),
  });

  @override
  Widget build(BuildContext context) {
    if (skylineAngles.length < 8) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _SkylinePainter(
          skylineAngles: skylineAngles,
          profiles: profiles,
          basis: basis,
          horizontalFovDeg: horizontalFovDeg,
          verticalFovDeg: verticalFovDeg,
          zoom: zoom,
          color: color,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  final List<double> skylineAngles;
  final TerrainProfiles profiles;
  final CameraBasis basis;
  final double horizontalFovDeg;
  final double verticalFovDeg;
  final double zoom;
  final Color color;

  _SkylinePainter({
    required this.skylineAngles,
    required this.profiles,
    required this.basis,
    required this.horizontalFovDeg,
    required this.verticalFovDeg,
    required this.zoom,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bande = profiles.isEmpty ? null : profiles.byBand;
    if (bande == null || bande.isEmpty) {
      _paintProfile(canvas, size, skylineAngles, 1.6, 0.85);
      return;
    }

    // Dalla più lontana alla più vicina, come nel panorama: qui non c'è
    // riempimento a coprire, ma l'ordine conta lo stesso perché la linea vicina
    // deve passare sopra a quelle dietro dove si incrociano.
    for (var b = bande.length - 1; b >= 0; b--) {
      final t = bande.length == 1 ? 0.0 : b / (bande.length - 1);
      // Le creste lontane si assottigliano e sbiadiscono: senza questa scala il
      // disegno diventa un groviglio di righe tutte uguali, e si perde proprio
      // l'informazione che le fasce servono a dare.
      _paintProfile(canvas, size, bande[b], 1.7 - 1.0 * t, 0.85 - 0.45 * t);
    }
  }

  /// Disegna un singolo profilo (una fascia, o lo skyline intero).
  void _paintProfile(
    Canvas canvas,
    Size size,
    List<double> profile,
    double strokeWidth,
    double alpha,
  ) {
    final steps = profile.length;
    if (steps < 8) return;

    // Si disegna solo il settore inquadrato, più un margine: proiettare tutti i
    // 720 azimut quando se ne vedono sessanta sarebbe lavoro buttato a ogni
    // frame. Il margine serve a far entrare e uscire la linea dai bordi.
    final centerAz = basis.azimuthDeg;
    final halfSpanDeg = horizontalFovDeg / 2 / zoom + 12;
    final halfSpanSteps = (halfSpanDeg / 360 * steps).ceil();
    final centerIdx = (centerAz / 360 * steps).round();

    final path = Path();
    bool penDown = false;

    for (var k = -halfSpanSteps; k <= halfSpanSteps; k++) {
      final idx = (centerIdx + k) % steps;
      final elevation = profile[idx < 0 ? idx + steps : idx];
      if (elevation.isNaN) {
        // Terreno sconosciuto in quella direzione: si stacca la penna invece di
        // tirare una riga dritta attraverso il buco, che sarebbe una bugia.
        penDown = false;
        continue;
      }
      final az = (idx < 0 ? idx + steps : idx) * 360.0 / steps;
      final p = projectDirection(
        enu: _directionEnu(az, elevation),
        basis: basis,
        viewportWidth: size.width,
        viewportHeight: size.height,
        horizontalFovDeg: horizontalFovDeg,
        verticalFovDeg: verticalFovDeg,
        zoom: zoom,
        // La linea deve poter uscire dallo schermo, non essere troncata.
        clipToCone: false,
      );
      if (p == null) {
        penDown = false; // direzione alle spalle
        continue;
      }
      // Fuori di molto: inutile tenerne traccia, e con angoli radenti i valori
      // proiettati esplodono.
      if (p.x.abs() > size.width * 4 || p.y.abs() > size.height * 4) {
        penDown = false;
        continue;
      }
      if (penDown) {
        path.lineTo(p.x, p.y);
      } else {
        path.moveTo(p.x, p.y);
        penDown = true;
      }
    }

    // Alone scuro sotto, così la linea resta leggibile anche contro il cielo
    // chiaro o la neve.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = Color.fromRGBO(0, 0, 0, 0.4 * alpha)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: alpha),
    );
  }

  /// Versore ENU di una direzione data azimut ed elevazione, in gradi.
  List<double> _directionEnu(double azDeg, double elevationDeg) {
    final az = azDeg * math.pi / 180;
    final el = elevationDeg * math.pi / 180;
    final ce = math.cos(el);
    return [math.sin(az) * ce, math.cos(az) * ce, math.sin(el)];
  }

  @override
  bool shouldRepaint(covariant _SkylinePainter old) =>
      old.skylineAngles != skylineAngles ||
      old.profiles != profiles ||
      old.basis.azimuthDeg != basis.azimuthDeg ||
      old.basis.pitchDeg != basis.pitchDeg ||
      old.basis.rollDeg != basis.rollDeg ||
      old.zoom != zoom ||
      old.horizontalFovDeg != horizontalFovDeg ||
      old.verticalFovDeg != verticalFovDeg ||
      old.color != color;
}
