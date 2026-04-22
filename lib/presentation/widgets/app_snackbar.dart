import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// SnackBar helper con icona Material + fondo colorato semantico, allineato
/// al design system TrailShare. Sostituisce gli emoji inline usati in giro
/// per l'app (⌚, ✅, ❌, ⚠️) — che nei messaggi di sistema rompono il tono
/// "strumento serio" e non sono accessibili agli screen reader.
///
/// Uso:
/// ```dart
/// AppSnackBar.success(context, 'Traccia salvata');
/// AppSnackBar.error(context, 'Errore di caricamento');
/// AppSnackBar.info(context, 'Caricamento in corso…');
/// AppSnackBar.warning(context, 'Batteria bassa');
/// ```
class AppSnackBar {
  AppSnackBar._();

  /// Messaggio di successo — verde.
  static void success(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      color: AppColors.success,
      duration: duration,
    );
  }

  /// Messaggio di errore — rosso.
  static void error(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      color: AppColors.danger,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  /// Messaggio informativo neutro — azzurro.
  static void info(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline,
      color: AppColors.info,
      duration: duration,
    );
  }

  /// Warning non critico — ambra.
  static void warning(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      icon: Icons.warning_amber_rounded,
      color: AppColors.warning,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color color,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }
}
