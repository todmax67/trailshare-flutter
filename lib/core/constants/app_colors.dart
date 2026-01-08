import 'package:flutter/material.dart';

/// Colori dell'app TrailShare (portati da style.css)
class AppColors {
  // Colori primari
  static const Color primary = Color(0xFFE07B4C);      // Arancione TrailShare
  static const Color primaryDark = Color(0xFFC4683F);
  static const Color primaryLight = Color(0xFFF5A67E);

  // Colori semantici
  static const Color success = Color(0xFF4CAF50);      // Verde
  static const Color danger = Color(0xFFE53935);       // Rosso
  static const Color warning = Color(0xFFFFA726);      // Arancione warning
  static const Color info = Color(0xFF29B6F6);         // Azzurro

  // Grigi e neutri
  static const Color background = Color(0xFFFAF9F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textMuted = Color(0xFFB2BEC3);
  static const Color border = Color(0xFFDFE6E9);

  // Colori per mappe e tracce
  static const Color trackDefault = Color(0xFFE07B4C);
  static const Color trackRecording = Color(0xFF4CAF50);
  static const Color trackFollowing = Color(0xFF2196F3);
  
  // Gradiente velocità (lento → veloce)
  static const List<Color> speedGradient = [
    Color(0xFF4CAF50),  // Verde - lento
    Color(0xFFFFEB3B),  // Giallo
    Color(0xFFFFA726),  // Arancione
    Color(0xFFE53935),  // Rosso - veloce
  ];

  // Gradiente pendenza (discesa → salita)
  static const List<Color> slopeGradient = [
    Color(0xFF2196F3),  // Blu - discesa
    Color(0xFF4CAF50),  // Verde - piano
    Color(0xFFFFEB3B),  // Giallo - leggera salita
    Color(0xFFFFA726),  // Arancione - salita
    Color(0xFFE53935),  // Rosso - salita ripida
  ];
}
