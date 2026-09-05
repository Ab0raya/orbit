import 'package:flutter/material.dart';

class OrbitColors {
  // Pure / Near-Black Layered Foundation
  static const Color orbitBackground = Color(0xFF000000);
  static const Color orbitSurface = Color(0xFF070707);
  static const Color orbitSurfaceElevated = Color(0xFF121212);
  static const Color orbitCard = Color(0xFF0A0A0A);

  // Translucent Silver Borders
  static const Color orbitBorder = Color(0x1AFFFFFF); // rgba(255, 255, 255, 0.10)
  static const Color orbitBorderLight = Color(0x33FFFFFF); // rgba(255, 255, 255, 0.20)
  static const Color orbitBorderSubtle = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)

  // Monochromatic White & Silver Accents
  static const Color orbitAccent = Color(0xFFFFFFFF);
  static const Color orbitAccentCyan = Color(0xFFD4D4D8);
  static const Color orbitSilver = Color(0xFFE4E4E7);

  // Clean Typography Hierarchy
  static const Color orbitTextPrimary = Color(0xFFFFFFFF);
  static const Color orbitTextSecondary = Color(0xFFA1A1AA);
  static const Color orbitTextTertiary = Color(0xFF71717A);
  static const Color orbitTextMuted = Color(0xFF71717A);

  // Status Indicators
  static const Color orbitSuccess = Color(0xFF10B981);
  static const Color orbitWarning = Color(0xFFF59E0B);
  static const Color orbitError = Color(0xFFEF4444);

  // Convenient aliases
  static const Color backgroundDark = orbitBackground;
  static const Color surfaceDark = orbitSurface;
  static const Color surfaceHighlight = orbitSurfaceElevated;
  static const Color borderSubtle = orbitBorderSubtle;
  static const Color primary = orbitAccent;
  static const Color accentCyan = orbitAccentCyan;
  static const Color textPrimary = orbitTextPrimary;
  static const Color textSecondary = orbitTextSecondary;
  static const Color textMuted = orbitTextMuted;
  static const Color warning = orbitWarning;
  static const Color error = orbitError;
}
