import 'package:flutter/material.dart';

import '../../core/utils/difficulty_calculator.dart';
import '../../data/models/track.dart';

/// Badge "T1..T5" colorato per mostrare la difficoltà di una traccia.
///
/// Risoluzione del livello in cascata:
/// 1. Se [manualDifficultyKey] è valorizzato (override utente), lo usa
///    e mostra un piccolo indicatore ✏️ per segnalare che è manuale.
/// 2. Altrimenti usa [difficultyKey] (computedDifficulty).
/// 3. Se entrambi null ma [fallbackStats] + [fallbackActivity] sono
///    valorizzati (es. tracce legacy), calcola al volo per il display.
/// 4. Se nessuna delle sopra, ritorna `SizedBox.shrink()`.
///
/// Varianti UI:
/// - `compact: true` → pill stretta con solo codice ("T3"), per liste
/// - `compact: false` → chip con codice + label ("T3 · Impegnativo"),
///   per scheda di dettaglio
class DifficultyBadge extends StatelessWidget {
  /// Difficoltà calcolata automaticamente. Usata se [manualDifficultyKey]
  /// è null/invalido.
  final String? difficultyKey;

  /// Override manuale impostato dall'utente. Se presente, ha priorità
  /// e fa apparire l'indicatore ✏️.
  final String? manualDifficultyKey;

  final bool compact;

  /// Komoot K1a — fallback per tracce legacy senza computedDifficulty
  /// persistito. Se [difficultyKey] è null ma [fallbackStats] +
  /// [fallbackActivity] sono valorizzati, calcola la difficoltà al
  /// volo per il display (no write su Firestore — quello avviene
  /// quando l'utente modifica/salva la traccia).
  final TrackStats? fallbackStats;
  final ActivityType? fallbackActivity;

  const DifficultyBadge({
    super.key,
    required this.difficultyKey,
    this.manualDifficultyKey,
    this.compact = false,
    this.fallbackStats,
    this.fallbackActivity,
  });

  @override
  Widget build(BuildContext context) {
    // Risoluzione cascata.
    final manualLevel = ComputedDifficulty.fromKey(manualDifficultyKey);
    var level = manualLevel ?? ComputedDifficulty.fromKey(difficultyKey);
    if (level == null &&
        fallbackStats != null &&
        fallbackActivity != null) {
      level = DifficultyCalculator.compute(
        stats: fallbackStats!,
        activityType: fallbackActivity!,
      );
    }
    if (level == null) return const SizedBox.shrink();

    final isManual = manualLevel != null;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: level.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: level.color.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              level.code,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: level.color,
                height: 1.1,
              ),
            ),
            if (isManual) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 9, color: level.color),
            ],
          ],
        ),
      );
    }

    return Tooltip(
      message: isManual
          ? 'Difficoltà impostata manualmente'
          : 'Difficoltà calcolata automaticamente',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: level.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: level.color.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terrain, size: 14, color: level.color),
            const SizedBox(width: 5),
            Text(
              '${level.code} · ${level.label}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: level.color,
                height: 1.1,
              ),
            ),
            if (isManual) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 11, color: level.color),
            ],
          ],
        ),
      ),
    );
  }
}
