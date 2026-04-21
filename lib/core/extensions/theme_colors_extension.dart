import 'package:flutter/material.dart';

/// Estensione su [BuildContext] che espone i colori "semantici" dell'app
/// come valori theme-aware (light/dark).
///
/// Sostituisce le costanti di `AppColors` (textPrimary, textSecondary,
/// textMuted, surface, background, border) per quei widget che devono
/// adattarsi al tema corrente.
///
/// Uso:
/// ```dart
/// color: context.textSecondary  // invece di AppColors.textSecondary
/// ```
extension ThemeColorsExtension on BuildContext {
  ColorScheme get _cs => Theme.of(this).colorScheme;

  /// Testo principale — mappato su colorScheme.onSurface.
  Color get textPrimary => _cs.onSurface;

  /// Testo secondario (subtitle, metadata) — onSurfaceVariant.
  Color get textSecondary => _cs.onSurfaceVariant;

  /// Testo attenuato (hint, disabled) — 60% onSurface.
  Color get textMuted => _cs.onSurface.withValues(alpha: 0.55);

  /// Sfondo card / contenitori rialzati.
  Color get themedSurface => _cs.surface;

  /// Sfondo pagina (uguale a surface nel sistema Material 3).
  Color get themedBackground => _cs.surface;

  /// Bordo default / separatore sottile.
  Color get themedBorder => _cs.outlineVariant;
}
