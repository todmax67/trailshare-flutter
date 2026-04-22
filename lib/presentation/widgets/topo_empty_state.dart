import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Empty state con illustrazione topografica line-art (curve di livello
/// stilizzate + pin arancione) + titolo + messaggio + eventuale CTA.
///
/// Risponde alla finding F03 dell'audit UX: sostituisce il pattern
/// `Icon(Icons.xxx_outlined, size:80, color:grey[300]) + testo` generico
/// con qualcosa di brand-coerente.
///
/// Uso:
/// ```dart
/// TopoEmptyState(
///   title: 'Nessuna traccia',
///   message: 'Registra la tua prima uscita',
///   cta: 'Registra',
///   onCta: () => ...,
/// )
/// ```
class TopoEmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final String? cta;
  final VoidCallback? onCta;
  final double illustrationSize;

  /// Seme per la generazione delle curve — consente varianti visive
  /// diverse su pagine diverse (Dashboard vs Tracks vs Wishlist) pur
  /// mantenendo lo stesso stile.
  final int variant;

  const TopoEmptyState({
    super.key,
    required this.title,
    this.message,
    this.cta,
    this.onCta,
    this.illustrationSize = 180,
    this.variant = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: illustrationSize,
              height: illustrationSize,
              child: CustomPaint(
                painter: _TopoPainter(
                  variant: variant,
                  lineColor: scheme.onSurface.withValues(alpha: 0.18),
                  pinColor: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            if (cta != null && onCta != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onCta,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(cta!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// CustomPainter che disegna curve di livello concentriche (topografia
/// stilizzata) + un pin arancione a colpo d'occhio nella parte alta.
class _TopoPainter extends CustomPainter {
  final int variant;
  final Color lineColor;
  final Color pinColor;

  _TopoPainter({
    required this.variant,
    required this.lineColor,
    required this.pinColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Disegna 5 "curve di livello" concentriche ma non perfettamente
    // concentriche (offset casuale per variante visiva).
    final rng = math.Random(variant * 7 + 13);
    for (int i = 5; i >= 1; i--) {
      final radius = size.width * 0.12 + i * (size.width * 0.07);
      final offsetX = (rng.nextDouble() - 0.5) * 8;
      final offsetY = (rng.nextDouble() - 0.5) * 8;
      final rect = Rect.fromCenter(
        center: center.translate(offsetX, offsetY),
        width: radius * 2,
        // Curve leggermente ovali per sembrare una "collina" vista dall'alto.
        height: radius * 1.55,
      );
      canvas.drawOval(rect, linePaint);
    }

    // Pin arancione in alto-centro (fuori dalle curve).
    final pinCenter = Offset(size.width / 2, size.height * 0.18);
    final pinPath = Path()
      ..moveTo(pinCenter.dx, pinCenter.dy + 18)
      ..cubicTo(
        pinCenter.dx - 10, pinCenter.dy + 4,
        pinCenter.dx - 10, pinCenter.dy - 6,
        pinCenter.dx, pinCenter.dy - 14,
      )
      ..cubicTo(
        pinCenter.dx + 10, pinCenter.dy - 6,
        pinCenter.dx + 10, pinCenter.dy + 4,
        pinCenter.dx, pinCenter.dy + 18,
      )
      ..close();

    canvas.drawPath(
      pinPath,
      Paint()..color = pinColor,
    );
    canvas.drawCircle(
      pinCenter.translate(0, -4),
      4,
      Paint()..color = Colors.white,
    );

    // Piccolo tratteggio leggero dal pin verso la collina centrale.
    final dashPaint = Paint()
      ..color = pinColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dashPath = Path();
    final from = pinCenter + const Offset(0, 18);
    final to = center + Offset(0, -size.width * 0.07);
    const dashLen = 4.0;
    const gapLen = 4.0;
    final delta = to - from;
    final dist = delta.distance;
    final dir = delta / dist;
    double traveled = 0;
    Offset cursor = from;
    while (traveled < dist) {
      final next = cursor + dir * dashLen;
      dashPath.moveTo(cursor.dx, cursor.dy);
      dashPath.lineTo(next.dx, next.dy);
      cursor = next + dir * gapLen;
      traveled += dashLen + gapLen;
    }
    canvas.drawPath(dashPath, dashPaint);
  }

  @override
  bool shouldRepaint(covariant _TopoPainter old) =>
      old.variant != variant ||
      old.lineColor != lineColor ||
      old.pinColor != pinColor;
}
