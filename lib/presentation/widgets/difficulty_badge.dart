import 'package:flutter/material.dart';

import '../../core/utils/difficulty_calculator.dart';
import '../../data/models/track.dart';

/// Badge "T1..T5" colorato per mostrare la difficoltà computata di una
/// traccia. Si adatta a due varianti:
/// - `compact: true` → pill stretta con solo codice ("T3"), per liste
/// - `compact: false` → chip con codice + label ("T3 · Impegnativo"),
///   per scheda di dettaglio
///
/// Se [difficultyKey] è null o non valido, ritorna un widget vuoto
/// (SizedBox.shrink) per restare safe quando la traccia non ha ancora
/// la difficoltà computata (es. legacy data).
class DifficultyBadge extends StatelessWidget {
  final String? difficultyKey;
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
    this.compact = false,
    this.fallbackStats,
    this.fallbackActivity,
  });

  @override
  Widget build(BuildContext context) {
    var level = ComputedDifficulty.fromKey(difficultyKey);
    if (level == null &&
        fallbackStats != null &&
        fallbackActivity != null) {
      level = DifficultyCalculator.compute(
        stats: fallbackStats!,
        activityType: fallbackActivity!,
      );
    }
    if (level == null) return const SizedBox.shrink();

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
        child: Text(
          level.code,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: level.color,
            height: 1.1,
          ),
        ),
      );
    }

    return Container(
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
        ],
      ),
    );
  }
}
