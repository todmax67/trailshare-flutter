import 'package:flutter/material.dart';

/// SnackBar animata per mostrare XP guadagnati dopo un'azione.
class XpSnackBar {
  /// Mostra una snackbar con gli XP guadagnati.
  ///
  /// [context] - BuildContext per ScaffoldMessenger
  /// [xpGained] - Quantità di XP guadagnati
  /// [reason] - Motivo dell'assegnazione (per messaggi personalizzati)
  static void show(
    BuildContext context, {
    required int xpGained,
    String reason = 'track_completed',
  }) {
    if (!context.mounted) return;

    final message = _getReasonMessage(reason, xpGained);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Text(
                '⭐',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '+$xpGained XP',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32), // verde scuro
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Restituisce il messaggio in base al motivo dell'XP.
  static String _getReasonMessage(String reason, int xp) {
    switch (reason) {
      case 'track_completed':
        return 'Traccia completata!';
      case 'first_track':
        return 'Prima traccia registrata! 🎉';
      case 'badge_unlocked':
        return 'Badge sbloccato!';
      case 'challenge_completed':
        return 'Sfida completata!';
      default:
        return 'Punti esperienza guadagnati';
    }
  }
}
