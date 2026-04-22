import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Widget riutilizzabile per mostrare un numero di statistica (km, m, h, #)
/// con coerenza tipografica: **Outfit** + **tabular figures**.
///
/// Le `tabular figures` fissano la larghezza di ogni cifra così che quando
/// i valori cambiano rapidamente (es. tracking live) il testo non "balla"
/// orizzontalmente — tutte le cifre occupano lo stesso spazio.
///
/// Varianti predefinite via factory:
/// - `StatNumber.hero(...)`   — 56px, per hero stat dashboard
/// - `StatNumber.large(...)`  — 28px, per stats primarie (card media)
/// - `StatNumber.medium(...)` — 20px, per stat card classica
/// - `StatNumber.small(...)`  — 15px, per statistiche inline (cards elenco)
class StatNumber extends StatelessWidget {
  /// Il valore principale (es. "12.4").
  final String value;

  /// Unità di misura opzionale (es. "km", "m", "h"). Stampata in font
  /// più piccolo a lato del valore.
  final String? unit;

  /// Dimensione del valore in pixel.
  final double size;

  /// Colore del valore. Default: onSurface del tema corrente.
  final Color? color;

  /// Colore dell'unità. Default: onSurfaceVariant, 60% size.
  final Color? unitColor;

  /// Weight del valore. Default: FontWeight.w700.
  final FontWeight fontWeight;

  const StatNumber({
    super.key,
    required this.value,
    this.unit,
    required this.size,
    this.color,
    this.unitColor,
    this.fontWeight = FontWeight.w700,
  });

  /// Hero: 56px. Per il valore dominante di una pagina (Dashboard hero).
  const StatNumber.hero(
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.unitColor,
    this.fontWeight = FontWeight.w800,
  }) : size = 56;

  /// Large: 28px. Profilo / card medio-grandi.
  const StatNumber.large(
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.unitColor,
    this.fontWeight = FontWeight.w700,
  }) : size = 28;

  /// Medium: 20px. Default per stat card standard.
  const StatNumber.medium(
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.unitColor,
    this.fontWeight = FontWeight.w700,
  }) : size = 20;

  /// Small: 15px. Per stat inline (card elenco tracce, tour).
  const StatNumber.small(
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.unitColor,
    this.fontWeight = FontWeight.w600,
  }) : size = 15;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = color ?? scheme.onSurface;
    final uColor = unitColor ??
        scheme.onSurfaceVariant.withValues(alpha: 0.85);

    final features = const [FontFeature.tabularFigures()];

    final valueStyle = GoogleFonts.outfit(
      fontSize: size,
      fontWeight: fontWeight,
      color: valueColor,
      height: 1.0,
      letterSpacing: -0.4,
      fontFeatures: features,
    );

    if (unit == null || unit!.isEmpty) {
      return Text(value, style: valueStyle);
    }

    // Unità a 60% della size del valore, baseline allineato sulla linea di
    // riferimento (l'unità "appoggia" sul piano del numero).
    final unitStyle = GoogleFonts.outfit(
      fontSize: (size * 0.45).clamp(10.0, 22.0),
      fontWeight: FontWeight.w600,
      color: uColor,
      letterSpacing: 0,
      fontFeatures: features,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: valueStyle),
        const SizedBox(width: 4),
        Padding(
          // Piccolo offset per allineare l'unità visivamente alla baseline
          // del numero (che ha height: 1.0 quindi touch-bottom).
          padding: EdgeInsets.only(bottom: size * 0.08),
          child: Text(unit!, style: unitStyle),
        ),
      ],
    );
  }
}
