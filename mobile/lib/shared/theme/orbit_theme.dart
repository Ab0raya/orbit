import 'package:flutter/material.dart';
import 'orbit_colors.dart';

class OrbitTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: OrbitColors.orbitBackground,
      colorScheme: const ColorScheme.dark(
        surface: OrbitColors.orbitSurface,
        primary: OrbitColors.orbitAccent,
        secondary: OrbitColors.orbitAccentCyan,
        error: OrbitColors.orbitError,
        onSurface: OrbitColors.orbitTextPrimary,
        onPrimary: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: OrbitColors.orbitBackground,
        foregroundColor: OrbitColors.orbitTextPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: OrbitColors.orbitSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 14,
        ),
        bodyMedium: TextStyle(
          color: OrbitColors.orbitTextSecondary,
          fontSize: 13,
        ),
        labelSmall: TextStyle(
          color: OrbitColors.orbitTextTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static const TextStyle monospace = TextStyle(
    fontFamily: 'monospace',
    color: OrbitColors.orbitTextPrimary,
    fontSize: 13,
    letterSpacing: 0,
  );
}
