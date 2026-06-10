import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/track.dart';

/// "Firma del tracciato": miniatura del percorso disegnata client-side
/// (CustomPainter) per le card degli elenchi sentieri — stile thumbnail
/// Strava. Niente tile, niente rete, niente quota: i punti sono già in
/// memoria, il rendering è istantaneo e funziona offline.
///
/// La pagina di dettaglio continua a usare la mappa interattiva vera.
class TrailRouteThumb extends StatelessWidget {
  final List<TrackPoint> points;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const TrailRouteThumb({
    super.key,
    required this.points,
    this.width,
    this.height,
    this.borderRadius,
  });

  /// True se ci sono abbastanza punti per disegnare una linea sensata.
  static bool canRender(List<TrackPoint> points) => points.length >= 2;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEDF3EA), Color(0xFFD9E6D2)],
          ),
        ),
        child: CustomPaint(
          painter: _RoutePainter(points),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<TrackPoint> points;
  _RoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;

    // Bounding box del tracciato.
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    var latSpan = maxLat - minLat;
    var lngSpan = maxLng - minLng;
    if (latSpan == 0) latSpan = 0.0001;
    if (lngSpan == 0) lngSpan = 0.0001;

    // Compensazione approssimativa della latitudine (i gradi di longitudine
    // si accorciano verso nord): basta il coseno della latitudine media.
    final latMidRad = (minLat + maxLat) / 2 * math.pi / 180;
    final lngScaleFactor = math.cos(latMidRad);
    final effLngSpan = lngSpan * lngScaleFactor;

    const pad = 14.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;
    if (drawW <= 0 || drawH <= 0) return;

    // Scala uniforme + centratura.
    final scale = (drawW / effLngSpan) < (drawH / latSpan)
        ? (drawW / effLngSpan)
        : (drawH / latSpan);
    final usedW = effLngSpan * scale;
    final usedH = latSpan * scale;
    final offX = pad + (drawW - usedW) / 2;
    final offY = pad + (drawH - usedH) / 2;

    Offset toCanvas(TrackPoint p) => Offset(
          offX + (p.longitude - minLng) * lngScaleFactor * scale,
          offY + (maxLat - p.latitude) * scale,
        );

    final path = Path()..moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final o = toCanvas(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    // Ombra leggera sotto la linea, poi la linea brand.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.primary,
    );

    // Punto di partenza (verde) e arrivo (rosso scuro).
    final start = toCanvas(points.first);
    final end = toCanvas(points.last);
    canvas.drawCircle(start, 4, Paint()..color = Colors.white);
    canvas.drawCircle(start, 3, Paint()..color = AppColors.success);
    canvas.drawCircle(end, 4, Paint()..color = Colors.white);
    canvas.drawCircle(end, 3, Paint()..color = AppColors.danger);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      !identical(old.points, points);
}
