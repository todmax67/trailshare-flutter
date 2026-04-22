import 'package:flutter/material.dart';

/// Capsula bianca con ombra leggera per stat mobili sopra una mappa.
///
/// Sulle tile di mappa (OSM / satellite) il testo nero su sfondo chiaro e
/// variabile perde contrasto. Questa capsula garantisce leggibilità in
/// qualunque condizione — soluzione standard usata da Gaia/Komoot.
class MapCapsuleChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;

  const MapCapsuleChip({
    super.key,
    this.icon,
    required this.label,
    this.iconColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? const Color(0xFF2D3436)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3436),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrim verticale (gradient nero→trasparente) da mettere sopra o sotto i
/// tile della mappa per proteggere la leggibilità dei controlli fissi
/// (FAB, pulsanti REC, etichette).
///
/// Dir può essere [ScrimDirection.top] (scrim dal top) o
/// [ScrimDirection.bottom] (scrim dal bottom).
class MapScrimGradient extends StatelessWidget {
  final ScrimDirection direction;
  final double height;
  final double maxOpacity;

  const MapScrimGradient({
    super.key,
    this.direction = ScrimDirection.bottom,
    this.height = 80,
    this.maxOpacity = 0.40,
  });

  @override
  Widget build(BuildContext context) {
    final isTop = direction == ScrimDirection.top;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: maxOpacity),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

enum ScrimDirection { top, bottom }
