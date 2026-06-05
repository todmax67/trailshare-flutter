import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/track_gradient_colors.dart';
import '../../data/models/track.dart';

/// Miniatura del percorso disegnata con un `CustomPainter` — niente mappa né
/// tile, quindi **leggerissima** anche in liste lunghe.
///
/// È la "copertina universale" dell'app: quando una traccia non ha foto,
/// invece di un box grigio mostriamo la forma del percorso colorata per
/// pendenza (l'elemento-firma). Ogni traccia ha la geometria → sempre
/// disponibile, sempre on-brand.
class RouteThumbnail extends StatelessWidget {
  final List<TrackPoint> points;
  final double? width;
  final double? height;
  final double strokeWidth;
  final BorderRadius borderRadius;

  const RouteThumbnail({
    super.key,
    required this.points,
    this.width,
    this.height,
    this.strokeWidth = 3,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFFEFEDE3), // sabbia chiaro tonale
        child: points.length < 2
            ? Center(
                child: Icon(Icons.route_outlined,
                    color: AppColors.primary.withValues(alpha: 0.5), size: 28),
              )
            : CustomPaint(
                painter: _RoutePainter(points, strokeWidth),
                size: Size.infinite,
              ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<TrackPoint> points;
  final double strokeWidth;
  final bool _hasElevation;

  _RoutePainter(this.points, this.strokeWidth)
      : _hasElevation = trackHasElevation(points);

  @override
  void paint(Canvas canvas, Size size) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    const pad = 10.0;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;

    // Correzione longitudine: alle nostre latitudini 1° lng < 1° lat.
    final midLat = (minLat + maxLat) / 2;
    final lngCorr = math.cos(midLat * math.pi / 180).abs();

    final geoW = (maxLng - minLng).abs() * lngCorr;
    final geoH = (maxLat - minLat).abs();
    final scale = math.min(
      w / (geoW == 0 ? 1 : geoW),
      h / (geoH == 0 ? 1 : geoH),
    );
    final drawW = geoW * scale;
    final drawH = geoH * scale;
    final ox = pad + (w - drawW) / 2;
    final oy = pad + (h - drawH) / 2;

    Offset project(TrackPoint p) => Offset(
          ox + (p.longitude - minLng) * lngCorr * scale,
          oy + (maxLat - p.latitude) * scale, // y invertita (lat cresce verso l'alto)
        );

    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      paint.color = _hasElevation
          ? slopeColor(slopeBetween(points[i], points[i + 1]))
          : AppColors.primary;
      canvas.drawLine(project(points[i]), project(points[i + 1]), paint);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.points != points || old.strokeWidth != strokeWidth;
}
