import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/segment.dart';

/// Dialog mostrato dopo il salvataggio di una traccia che ha attraversato
/// uno o più segmenti cronometrati.
///
/// Per ogni risultato mostra:
/// - 🏆 "Nuovo record del segmento!" se ha battuto il primatista assoluto
/// - ⭐ "Nuovo personal best!" se ha migliorato il proprio PB (ma non il record)
/// - "Segmento completato" se è un tempo più lento del proprio PB
Future<void> showSegmentResultsDialog(
  BuildContext context,
  List<SegmentMatchResult> results,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _SegmentResultsDialog(results: results),
  );
}

class _SegmentResultsDialog extends StatelessWidget {
  final List<SegmentMatchResult> results;

  const _SegmentResultsDialog({required this.results});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: AppColors.primary, size: 28),
                const SizedBox(width: 10),
                Text(
                  results.length == 1
                      ? 'Segmento completato'
                      : '${results.length} segmenti completati',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  children: results.map((r) => _resultTile(r)).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(SegmentMatchResult r) {
    // Determina stile e titolo in base al risultato
    Color accent;
    IconData icon;
    String badgeLabel;
    if (r.isNewRecord) {
      accent = Colors.amber;
      icon = Icons.emoji_events;
      badgeLabel = 'Nuovo record!';
    } else if (r.isNewPB) {
      accent = AppColors.primary;
      icon = Icons.star;
      badgeLabel = 'Personal best!';
    } else {
      accent = AppColors.textMuted;
      icon = Icons.check_circle_outline;
      badgeLabel = 'Completato';
    }

    final improvement = (r.isNewPB && r.previousPBSeconds != null)
        ? (r.previousPBSeconds! - r.durationSeconds)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.segment.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                r.durationFormatted,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                '${(r.distance / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (improvement != null && improvement > 0) ...[
            const SizedBox(height: 4),
            Text(
              '− $improvement s rispetto al tuo miglior tempo',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
