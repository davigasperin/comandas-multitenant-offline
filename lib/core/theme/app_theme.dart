import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Cores Baseadas no Design System "Real-Time / Operations" (Teal/Amber)
  static const Color primary = Color(0xFF0D9488); // Teal
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF0F766E); // Teal 700 para contraste WCAG AA
  static const Color accent = Color(0xFFD97706); // Amber
  static const Color background = Color(0xFFF0FDFA);
  static const Color danger = Color(0xFFDC2626);
  static const Color cardBg = Color(0xFFFFFFFF);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        error: danger,
        surface: cardBg,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
    );

    // Tipografia Fira Sans (leitura)
    final textTheme = GoogleFonts.firaSansTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2, // Maior elevação para separação de block
        shadowColor: Colors.black26,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(88, 48), // Touch target mínimo
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8), // Mais sharp (block-based)
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF5EEAD4)), // Borda do design system
        ),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onPrimary,
        unselectedLabelColor: onPrimary.withAlpha(153),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
    );
  }
}

