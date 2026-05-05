import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Definizione dei temi dell'app
class AppThemes {
  // Colori brand (allineati con AppColors - Arancione TrailShare)
  static const Color primaryColor = Color(0xFFE07B4C);    // Arancione TrailShare
  static const Color primaryLight = Color(0xFFF5A67E);    // Arancione chiaro
  static const Color primaryDark = Color(0xFFC4683F);     // Arancione scuro

  /// TextTheme con Outfit per titoli, sistema per body
  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      // Display - titoli molto grandi
      displayLarge: GoogleFonts.outfit(textStyle: base.displayLarge),
      displayMedium: GoogleFonts.outfit(textStyle: base.displayMedium),
      displaySmall: GoogleFonts.outfit(textStyle: base.displaySmall),
      // Headline - titoli sezioni
      headlineLarge: GoogleFonts.outfit(textStyle: base.headlineLarge),
      headlineMedium: GoogleFonts.outfit(textStyle: base.headlineMedium),
      headlineSmall: GoogleFonts.outfit(textStyle: base.headlineSmall),
      // Title - AppBar, card titles, ecc.
      titleLarge: GoogleFonts.outfit(textStyle: base.titleLarge),
      titleMedium: GoogleFonts.outfit(textStyle: base.titleMedium),
      titleSmall: GoogleFonts.outfit(textStyle: base.titleSmall),
      // Body e Label - restano font di sistema per leggibilità
    );
  }

  // ============================================
  // TEMA CHIARO
  // ============================================
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Tipografia: Outfit per titoli, sistema per body
      textTheme: _buildTextTheme(ThemeData.light().textTheme),

      // Colori principali
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        primaryContainer: primaryLight,
        secondary: const Color(0xFF2E7D32),           // Verde - accento successo
        secondaryContainer: const Color(0xFFC8E6C9),
        surface: Colors.white,          // Sfondo caldo (da AppColors)
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF2D3436),
        onError: Colors.white,
      ),

      // Scaffold
      scaffoldBackgroundColor: const Color(0xFFFAF9F7),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFF1A1A1A),
        iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
      ),

      // Card
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Bottoni
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ListTile
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFF666666),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE0E0E0),
        thickness: 1,
      ),

      // BottomNav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  // ============================================
  // TEMA SCURO
  // ============================================
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Tipografia: Outfit per titoli, sistema per body
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),

      // Colori principali
      colorScheme: ColorScheme.dark(
        primary: primaryLight,                          // Arancione chiaro su sfondo scuro
        primaryContainer: primaryColor,
        secondary: const Color(0xFF81C784),             // Verde chiaro - accento successo
        secondaryContainer: const Color(0xFF2E7D32),
        surface: const Color(0xFF1E1E1E),
        error: const Color(0xFFEF5350),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: const Color(0xFFE0E0E0),
        onError: Colors.black,
      ),

      // Scaffold
      scaffoldBackgroundColor: const Color(0xFF121212),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFFE0E0E0),
        iconTheme: IconThemeData(color: Color(0xFFE0E0E0)),
      ),

      // Card
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Bottoni
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.black,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: const BorderSide(color: primaryLight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryLight,
        foregroundColor: Colors.black,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF404040)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF404040)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ListTile
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFFB0B0B0),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFF404040),
        thickness: 1,
      ),

      // BottomNav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: primaryLight,
        unselectedItemColor: Color(0xFF757575),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF404040),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
