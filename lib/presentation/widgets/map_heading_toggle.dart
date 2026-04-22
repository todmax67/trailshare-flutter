import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/extensions/l10n_extension.dart';
import '../../core/services/heading_service.dart';

/// Pulsante circolare che mostra una bussola stilizzata sopra la mappa.
///
/// - Tap: cicla tra modalità `north-up` (default) e `heading-up` (mappa
///   ruota secondo direzione di movimento).
/// - La bussola interna ruota **sempre** per indicare dov'è il nord,
///   fornendo all'utente orientamento indipendente dallo stato del toggle.
///
/// Ascolta [HeadingService] per reagire in tempo reale sia al cambio di
/// preferenza utente sia ai nuovi valori di heading.
class MapHeadingToggle extends StatefulWidget {
  /// Dimensione del pulsante (default 40).
  final double size;

  const MapHeadingToggle({super.key, this.size = 40});

  @override
  State<MapHeadingToggle> createState() => _MapHeadingToggleState();
}

class _MapHeadingToggleState extends State<MapHeadingToggle> {
  final _service = HeadingService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
    _service.loadPreference();
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final heading = _service.currentHeading ?? 0;
    final active = _service.isHeadingUp;

    // In modalità heading-up la mappa ruota: il "nord" rispetto al viewport
    // diventa (-heading). In north-up invece il nord è sempre verso l'alto,
    // quindi l'ago punta sempre su (0°) — ma se l'utente è diretto a sud
    // l'ago resta su, mostrando comunque dove è nord.
    final needleAngle = active ? -heading * math.pi / 180 : 0.0;

    return Tooltip(
      message: active
          ? context.l10n.compassHeadingUp
          : context.l10n.compassNorthUp,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          onTap: _service.toggle,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: AnimatedRotation(
                turns: needleAngle / (2 * math.pi),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _CompassIcon(
                  size: widget.size * 0.6,
                  active: active,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bussola stilizzata: "N" rosso in cima, stelo grigio verso sud.
class _CompassIcon extends StatelessWidget {
  final double size;
  final bool active;

  const _CompassIcon({required this.size, required this.active});

  @override
  Widget build(BuildContext context) {
    final needleColor = active
        ? const Color(0xFFE53935) // rosso quando heading-up attivo
        : const Color(0xFF636E72); // grigio scuro default

    return CustomPaint(
      size: Size(size, size),
      painter: _CompassPainter(
        needleNorthColor: needleColor,
        needleSouthColor: const Color(0xFFB2BEC3),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Color needleNorthColor;
  final Color needleSouthColor;

  _CompassPainter({
    required this.needleNorthColor,
    required this.needleSouthColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final width = size.width * 0.22;
    final length = size.height * 0.48;

    // Ago nord (triangolo che punta in su)
    final north = Path()
      ..moveTo(center.dx, center.dy - length)
      ..lineTo(center.dx - width / 2, center.dy)
      ..lineTo(center.dx + width / 2, center.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = needleNorthColor);

    // Ago sud (triangolo che punta in giù, più chiaro)
    final south = Path()
      ..moveTo(center.dx, center.dy + length)
      ..lineTo(center.dx - width / 2, center.dy)
      ..lineTo(center.dx + width / 2, center.dy)
      ..close();
    canvas.drawPath(south, Paint()..color = needleSouthColor);

    // Cerchio perno centrale
    canvas.drawCircle(
      center,
      width * 0.35,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      width * 0.35,
      Paint()
        ..color = needleNorthColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.needleNorthColor != needleNorthColor ||
      old.needleSouthColor != needleSouthColor;
}
