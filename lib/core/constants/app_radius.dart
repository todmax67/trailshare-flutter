import 'package:flutter/material.dart';

/// Scala di `BorderRadius` intenzionale per dare ritmo visivo ai componenti.
///
/// Risponde alla finding F08 dell'audit UX: "ogni Card, bottone, input e
/// dialog usa `BorderRadius.circular(12)` indistintamente → uniformità
/// noiosa, tutto ha lo stesso peso tattile".
///
/// Livelli:
/// - [xs]   `8`   — chip, badge, pill compatti
/// - [sm]   `12`  — input field, bottoni, piccole tile
/// - [md]   `16`  — card di contenuto (track card, stat card)
/// - [lg]   `24`  — dialog, bottom sheet, modali
/// - [full] `9999` — pill-tag completamente arrotondato
///
/// Uso:
/// ```dart
/// decoration: BoxDecoration(borderRadius: AppRadius.md.br)
/// shape: RoundedRectangleBorder(borderRadius: AppRadius.lg.br)
/// ```
enum AppRadius {
  xs(8),
  sm(12),
  md(16),
  lg(24),
  full(9999);

  final double value;
  const AppRadius(this.value);

  /// `BorderRadius` uniforme per tutti gli angoli.
  BorderRadius get br => BorderRadius.circular(value);

  /// `BorderRadius` solo in alto (per bottom sheet / card con "tail" in basso).
  BorderRadius get brTop => BorderRadius.only(
        topLeft: Radius.circular(value),
        topRight: Radius.circular(value),
      );
}
