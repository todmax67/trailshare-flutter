import 'package:flutter/material.dart';

/// Voce della [TrackStatsBar]: icona colorata + valore + unità + etichetta.
class TrackStat {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  final String label;

  const TrackStat({
    required this.icon,
    required this.color,
    required this.value,
    this.unit = '',
    required this.label,
  });
}

/// Stat bar raggruppata dell'header traccia (design system, "Variante A"):
/// i dati chiave del giro in un unico blocco contenuto con divisori
/// verticali — in evidenza, invece di tre card-isola sparse.
///
/// Usa colori espliciti (non `colorScheme.surface`) perché le pagine
/// traccia avvolgono il contenuto in `SageSurface`, che rende trasparenti
/// le superfici del tema: questa striscia deve invece restare un blocco
/// solido, è l'eccezione voluta al frameless.
class TrackStatsBar extends StatelessWidget {
  final List<TrackStat> stats;
  const TrackStatsBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1E1E1E) : const Color(0xFFFBF9F5);
    final hairline = dark ? const Color(0xFF333333) : const Color(0xFFE8E3DD);
    final valueColor = dark ? const Color(0xFFE0E0E0) : const Color(0xFF2D3436);
    final labelColor = dark ? const Color(0xFFB0A99F) : const Color(0xFF6E665C);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, thickness: 1, color: hairline),
              Expanded(
                child: _StatCell(
                  stat: stats[i],
                  valueColor: valueColor,
                  labelColor: labelColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final TrackStat stat;
  final Color valueColor;
  final Color labelColor;

  const _StatCell({
    required this.stat,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stat.icon, size: 15, color: stat.color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                stat.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ),
            if (stat.unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                stat.unit,
                style: TextStyle(fontSize: 11, color: labelColor),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
      ],
    );
  }
}
