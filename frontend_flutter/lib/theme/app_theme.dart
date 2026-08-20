import 'package:flutter/material.dart';

class AppTheme {
  static const Color neonGreen = Color(0xFF00E676);
  static const Color yellow = Color(0xFFFFD600);
  static const Color red = Color(0xFFFF1744);

  // ─────────── FlashScore palette ───────────
  static const Color flashBg = Color(0xFF0B1519);
  static const Color flashCard = Color(0xFF132229);
  static const Color flashLine = Color(0xFF1C3039);
  static const Color flashAccent = Color(0xFF1FB453);
  static const Color flashSub = Color(0xFF7A8C95);
  static const Color flashLiveRed = Color(0xFFFF3B30);

  // ─────────── Temas legado (mantém compatibilidade) ───────────
  static const Color darkBg = flashBg;
  static const Color cardBg = flashCard;

  static ThemeData get darkTheme {
    return ThemeData(
      scaffoldBackgroundColor: flashBg,
      brightness: Brightness.dark,
      useMaterial3: true,
      cardTheme: CardTheme(
        color: flashCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: flashLine, width: 0.8),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: flashBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: yellow,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: yellow, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        titleMedium:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: flashSub),
        labelLarge: TextStyle(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonGreen,
          foregroundColor: flashBg,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(34),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: flashCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: flashLine, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: flashLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: neonGreen),
        ),
        hintStyle: const TextStyle(color: flashSub),
        labelStyle: const TextStyle(color: Colors.white70),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: flashLine,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: flashCard,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: flashLine),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      primaryColor: neonGreen,
      colorScheme: ColorScheme.dark(
        primary: neonGreen,
        secondary: yellow,
        surface: flashCard,
        error: red,
        onPrimary: flashBg,
        onSecondary: flashBg,
        surfaceTint: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: flashCard,
        selectedItemColor: neonGreen,
        unselectedItemColor: flashSub,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
