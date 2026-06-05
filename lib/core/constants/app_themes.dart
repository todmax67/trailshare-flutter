import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Definizione dei temi dell'app
class AppThemes {
  // Colori brand (allineati con AppColors - Arancione TrailShare)
  static const Color primaryColor = Color(0xFFE07B4C);    // Arancione TrailShare
  static const Color primaryLight = Color(0xFFF5A67E);    // Arancione chiaro
  static const Color primaryDark = Color(0xFFC4683F);     // Arancione scuro

  /// TextTheme con Outfit per titoli, sistema per body.
  ///
  /// Gerarchia "moderna": titoli grassi con tracking negativo (le lettere si
  /// stringono ai corpi grandi → look premium/editoriale, non Material default).
  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      // Display - titoli molto grandi: bold + tracking molto stretto
      displayLarge: GoogleFonts.outfit(
          textStyle: base.displayLarge,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0),
      displayMedium: GoogleFonts.outfit(
          textStyle: base.displayMedium,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5),
      displaySmall: GoogleFonts.outfit(
          textStyle: base.displaySmall,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5),
      // Headline - titoli sezioni: bold + tracking stretto
      headlineLarge: GoogleFonts.outfit(
          textStyle: base.headlineLarge,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5),
      headlineMedium: GoogleFonts.outfit(
          textStyle: base.headlineMedium,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3),
      headlineSmall: GoogleFonts.outfit(
          textStyle: base.headlineSmall,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3),
      // Title - AppBar, card titles, ecc.: semibold
      titleLarge: GoogleFonts.outfit(
          textStyle: base.titleLarge,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2),
      titleMedium: GoogleFonts.outfit(
          textStyle: base.titleMedium, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.outfit(
          textStyle: base.titleSmall, fontWeight: FontWeight.w600),
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

      // Colori principali — scala tonale calda (sabbia/pietra), non bianco piatto.
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        primaryContainer: primaryLight,
        secondary: const Color(0xFF2E7D32),           // Verde - accento successo
        secondaryContainer: const Color(0xFFC8E6C9),
        // Scala superfici calde (chiaro → profondo):
        surface: const Color(0xFFFBF9F5),             // card: bianco caldo
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF7F3EC),
        surfaceContainer: const Color(0xFFE7E9D9),    // = sfondo pagina (sabbia-salvia)
        surfaceContainerHigh: const Color(0xFFECE6DD), // input well, field fill
        surfaceContainerHighest: const Color(0xFFE6DFD4), // bubble, placeholder
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF2D3436),
        onSurfaceVariant: const Color(0xFF6E665C),    // testo secondario caldo
        outlineVariant: const Color(0xFFE8E3DD),      // hairline border caldo
        onError: Colors.white,
      ),

      // Scaffold — sabbia-salvia (più profondo delle card, così galleggiano per tono)
      scaffoldBackgroundColor: const Color(0xFFE7E9D9),

      // Feedback al tocco: ripple tinto col brand (non il grigio Material di default).
      // Vale per InkWell/ListTile/Card/tab in tutta l'app.
      splashFactory: InkRipple.splashFactory,
      splashColor: primaryColor.withValues(alpha: 0.10),
      highlightColor: primaryColor.withValues(alpha: 0.04),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFF1A1A1A),
        iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
      ),

      // Card — piatte con bordo a filo di capello (look editoriale, niente ombra).
      cardTheme: CardThemeData(
        color: const Color(0xFFFBF9F5),   // bianco caldo, non bianco clinico
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8E3DD), width: 1),
        ),
      ),

      // Bottoni — piatti (stile FilledButton M3): nessuna ombra "galleggiante".
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),

      // FilledButton allineato a ElevatedButton: stesso aspetto, così i due
      // tipi di bottone convivono senza incoerenza visiva.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
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

      // Input — well caldo incassato (non bianco)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFECE6DD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0DACF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0DACF)),
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
        backgroundColor: const Color(0xFFFBF9F5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFFBF9F5),
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

      // Colori principali — scala superfici scure deterministica (no default lavanda M3).
      colorScheme: ColorScheme.dark(
        primary: primaryLight,                          // Arancione chiaro su sfondo scuro
        primaryContainer: primaryColor,
        secondary: const Color(0xFF81C784),             // Verde chiaro - accento successo
        secondaryContainer: const Color(0xFF2E7D32),
        // Scala superfici (profondo → chiaro):
        surface: const Color(0xFF1E1E1E),             // card
        surfaceContainerLowest: const Color(0xFF161616),
        surfaceContainerLow: const Color(0xFF1E1E1E),
        surfaceContainer: const Color(0xFF222222),
        surfaceContainerHigh: const Color(0xFF2A2A2A), // input well, field fill
        surfaceContainerHighest: const Color(0xFF333333), // bubble, placeholder
        error: const Color(0xFFEF5350),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: const Color(0xFFE0E0E0),
        onSurfaceVariant: const Color(0xFFB0A99F),    // testo secondario leggermente caldo
        outlineVariant: const Color(0xFF333333),      // hairline border
        onError: Colors.black,
      ),

      // Scaffold
      scaffoldBackgroundColor: const Color(0xFF121212),

      // Feedback al tocco: ripple tinto col brand (non il grigio Material di default).
      // Vale per InkWell/ListTile/Card/tab in tutta l'app.
      splashFactory: InkRipple.splashFactory,
      splashColor: primaryLight.withValues(alpha: 0.12),
      highlightColor: primaryLight.withValues(alpha: 0.05),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFFE0E0E0),
        iconTheme: IconThemeData(color: Color(0xFFE0E0E0)),
      ),

      // Card — piatte con bordo a filo di capello (look editoriale, niente ombra).
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
      ),

      // Bottoni — piatti (stile FilledButton M3): nessuna ombra "galleggiante".
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),

      // FilledButton allineato a ElevatedButton: stesso aspetto, così i due
      // tipi di bottone convivono senza incoerenza visiva.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: const BorderSide(color: primaryLight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
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
