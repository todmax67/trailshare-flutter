import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/camera_orientation.dart';
import '../../core/utils/sun_moon.dart';

/// Il cammino del sole e della luna disegnato sopra l'immagine della
/// fotocamera.
///
/// Serve a due cose, e la seconda vale più della prima.
///
/// La prima è la funzione che si vende: alzi il telefono verso una cresta e
/// vedi a che ora il sole ci passerà sopra. È quello che chiede chi fotografa,
/// e chi si chiede se all'una avrà ancora ombra sul versante.
///
/// La seconda è che il sole è **l'unico oggetto in cielo di cui conosciamo la
/// posizione esatta senza sensori**. Se il disco disegnato cade sul sole vero,
/// il puntamento è giusto — e se non ci cade, si vede subito di quanto sbaglia.
/// Nessun'altra parte di questa schermata dà una verifica così: il profilo del
/// terreno richiede di riconoscere le montagne, il sole no.
class SunPathOverlay extends StatefulWidget {
  final CameraBasis basis;
  final double horizontalFovDeg;
  final double verticalFovDeg;
  final double zoom;

  /// Dove si trova chi guarda: la posizione degli astri ne dipende.
  final double observerLat;
  final double observerLng;

  const SunPathOverlay({
    super.key,
    required this.basis,
    required this.horizontalFovDeg,
    required this.verticalFovDeg,
    required this.observerLat,
    required this.observerLng,
    this.zoom = 1.0,
  });

  @override
  State<SunPathOverlay> createState() => _SunPathOverlayState();
}

class _SunPathOverlayState extends State<SunPathOverlay> {
  List<SkyTrackPoint> _sun = const [];
  List<SkyTrackPoint> _moon = const [];
  DateTime _now = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _rebuildTracks();
    // Il sole si sposta di un quarto di grado al minuto: mezzo minuto di
    // ritardo è invisibile, e ricalcolare a ogni frame della bussola sarebbe
    // sprecare batteria per niente.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final dayChanged = now.day != _now.day;
      setState(() => _now = now);
      if (dayChanged) _rebuildTracks();
    });
  }

  @override
  void didUpdateWidget(SunPathOverlay old) {
    super.didUpdateWidget(old);
    // Il cammino cambia con la posizione, ma di poco: qualche centinaio di
    // metri non sposta il sole in modo percepibile, e il GPS aggiorna di
    // continuo. Si ricalcola solo per spostamenti veri.
    if ((old.observerLat - widget.observerLat).abs() > 0.05 ||
        (old.observerLng - widget.observerLng).abs() > 0.05) {
      _rebuildTracks();
    }
  }

  void _rebuildTracks() {
    final midnight = DateTime(_now.year, _now.month, _now.day).toUtc();
    _sun = sunTrack(midnight, widget.observerLat, widget.observerLng,
        stepMinutes: 10);
    _moon = moonTrack(midnight, widget.observerLat, widget.observerLng,
        stepMinutes: 20);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SunPathPainter(
          basis: widget.basis,
          horizontalFovDeg: widget.horizontalFovDeg,
          verticalFovDeg: widget.verticalFovDeg,
          zoom: widget.zoom,
          sunTrack: _sun,
          moonTrack: _moon,
          sunNow: sunPosition(
              _now.toUtc(), widget.observerLat, widget.observerLng),
          moonNow: moonPosition(
                  _now.toUtc(), widget.observerLat, widget.observerLng)
              .position,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SunPathPainter extends CustomPainter {
  final CameraBasis basis;
  final double horizontalFovDeg;
  final double verticalFovDeg;
  final double zoom;
  final List<SkyTrackPoint> sunTrack;
  final List<SkyTrackPoint> moonTrack;
  final SkyPosition sunNow;
  final SkyPosition moonNow;

  _SunPathPainter({
    required this.basis,
    required this.horizontalFovDeg,
    required this.verticalFovDeg,
    required this.zoom,
    required this.sunTrack,
    required this.moonTrack,
    required this.sunNow,
    required this.moonNow,
  });

  static const _sunColor = Color(0xFFFFC24B);
  static const _moonColor = Color(0xFFDCE4F0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    _paintTrack(canvas, size, moonTrack, _moonColor, dashed: true);
    _paintTrack(canvas, size, sunTrack, _sunColor);
    _paintHours(canvas, size, sunTrack, _sunColor);

    _paintMoonDisc(canvas, size);
    _paintSunDisc(canvas, size);
  }

  Offset? _project(Size size, SkyPosition p) {
    final az = p.azimuthDeg * math.pi / 180;
    final el = p.elevationDeg * math.pi / 180;
    final ce = math.cos(el);
    final r = projectDirection(
      enu: [math.sin(az) * ce, math.cos(az) * ce, math.sin(el)],
      basis: basis,
      viewportWidth: size.width,
      viewportHeight: size.height,
      horizontalFovDeg: horizontalFovDeg,
      verticalFovDeg: verticalFovDeg,
      zoom: zoom,
      clipToCone: false,
    );
    if (r == null) return null;
    // Con angoli radenti la proiezione rettilinea esplode: oltre qualche
    // schermata di distanza il punto non serve piu' a niente.
    if (r.x.abs() > size.width * 4 || r.y.abs() > size.height * 4) return null;
    return Offset(r.x, r.y);
  }

  void _paintTrack(
    Canvas canvas,
    Size size,
    List<SkyTrackPoint> track,
    Color color, {
    bool dashed = false,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 2 : 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.75);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (dashed ? 2 : 3) + 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x55000000);

    Offset? prev;
    var dashOn = true;
    for (final p in track) {
      // Sotto l'orizzonte il cammino non interessa: quello che conta è dove
      // l'astro passa fra le montagne, non dov'è mentre è sotto i piedi.
      if (p.position.elevationDeg < -2) {
        prev = null;
        continue;
      }
      final cur = _project(size, p.position);
      if (cur == null) {
        prev = null;
        continue;
      }
      if (prev != null && (!dashed || dashOn)) {
        canvas.drawLine(prev, cur, halo);
        canvas.drawLine(prev, cur, paint);
      }
      dashOn = !dashOn;
      prev = cur;
    }
  }

  /// Le ore lungo l'arco. Sono la risposta alla domanda vera: non «dove passa
  /// il sole» ma «a che ora arriva lì».
  void _paintHours(
      Canvas canvas, Size size, List<SkyTrackPoint> track, Color color) {
    for (final p in track) {
      final local = p.time.toLocal();
      if (local.minute != 0) continue;
      if (p.position.elevationDeg < 0) continue;
      final c = _project(size, p.position);
      if (c == null) continue;
      if (c.dx < -40 || c.dx > size.width + 40) continue;

      canvas.drawCircle(c, 4, Paint()..color = const Color(0x77000000));
      canvas.drawCircle(c, 2.5, Paint()..color = color);

      final tp = TextPainter(
        text: TextSpan(
          text: '${local.hour}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
            shadows: const [
              Shadow(color: Color(0xCC000000), blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + 6));
    }
  }

  void _paintSunDisc(Canvas canvas, Size size) {
    if (sunNow.elevationDeg < -2) return;
    final c = _project(size, sunNow);
    if (c == null) return;

    // Il disco solare misura mezzo grado: si disegna con la dimensione vera,
    // così sovrapporlo al sole reale è una verifica onesta del puntamento e non
    // un cerchione che copre l'errore.
    final pxPerDeg = size.width / (horizontalFovDeg / zoom);
    final r = math.max(6.0, 0.53 / 2 * pxPerDeg);

    canvas.drawCircle(
        c, r * 3, Paint()..color = _sunColor.withValues(alpha: 0.16));
    canvas.drawCircle(c, r, Paint()..color = _sunColor);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x88000000),
    );
  }

  void _paintMoonDisc(Canvas canvas, Size size) {
    if (moonNow.elevationDeg < -2) return;
    final c = _project(size, moonNow);
    if (c == null) return;

    final pxPerDeg = size.width / (horizontalFovDeg / zoom);
    final r = math.max(5.0, 0.52 / 2 * pxPerDeg);

    canvas.drawCircle(c, r, Paint()..color = _moonColor.withValues(alpha: 0.9));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x88000000),
    );
  }

  @override
  bool shouldRepaint(covariant _SunPathPainter old) =>
      old.basis.azimuthDeg != basis.azimuthDeg ||
      old.basis.pitchDeg != basis.pitchDeg ||
      old.basis.rollDeg != basis.rollDeg ||
      old.zoom != zoom ||
      old.horizontalFovDeg != horizontalFovDeg ||
      old.verticalFovDeg != verticalFovDeg ||
      old.sunNow.azimuthDeg != sunNow.azimuthDeg;
}
