// The app's only theme (spec v2 §9: keep app_theme, calm tone, dark surface).
//
// Colours are used directly by screens (`AppTheme.lightOrange`, `textGrey`, …) as
// well as through ThemeData, so changing a constant here propagates to hand-styled
// widgets too. Amber/green/red are intentionally NOT in this palette: they carry
// meaning (pending / on-track / alarming) and are specified at their use sites.

import 'package:flutter/material.dart';

/// The app's palette and dark theme. Widgets use the colour constants directly as
/// well as via `ThemeData`, so a change here is global on purpose.
class AppTheme {
  // Color scheme
  static const Color darkGrey = Color(0xFF2B2B2B);
  static const Color lightOrange = Color(0xFFFF9D5C);
  static const Color backgroundGrey = Color(0xFF1A1A1A);
  static const Color cardGrey = Color(0xFF3A3A3A);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFFB0B0B0);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundGrey,
      primaryColor: lightOrange,
      colorScheme: ColorScheme.dark(
        primary: lightOrange,
        secondary: lightOrange,
        surface: darkGrey,
        onPrimary: darkGrey,
        onSecondary: darkGrey,
        onSurface: textWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkGrey,
        foregroundColor: textWhite,
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkGrey,
        selectedItemColor: lightOrange,
        unselectedItemColor: textGrey,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: cardGrey,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      iconTheme: IconThemeData(
        color: textGrey,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textWhite,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textWhite,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          color: textWhite,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: textGrey,
          fontSize: 14,
        ),
      ),
    );
  }
}
