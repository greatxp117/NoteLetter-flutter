import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_radius.dart';

class AppTheme {
  AppTheme._();

  // Per design-tokens.md: serif `Source Serif 4` for display/headings/reading,
  // sans `Geist` for UI body, mono `Geist Mono` for code/caps-labels. Geist and
  // Geist Mono are bundled as OFL assets (see pubspec `fonts:` + assets/fonts/)
  // because neither ships in the google_fonts package; the serif still comes
  // from google_fonts. `Geist`/`Geist Mono` are referenced by family name.
  static const String fontSans = 'Geist';
  static const String fontMono = 'Geist Mono';

  static TextStyle _geist(double size, FontWeight weight, Color color) =>
      TextStyle(fontFamily: fontSans, fontSize: size, fontWeight: weight, color: color);

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return TextTheme(
      displayLarge: GoogleFonts.sourceSerif4(
        fontSize: 56, fontWeight: FontWeight.w400, color: displayColor),
      displayMedium: GoogleFonts.sourceSerif4(
        fontSize: 48, fontWeight: FontWeight.w400, color: displayColor),
      displaySmall: GoogleFonts.sourceSerif4(
        fontSize: 40, fontWeight: FontWeight.w400, color: displayColor),
      headlineLarge: GoogleFonts.sourceSerif4(
        fontSize: 32, fontWeight: FontWeight.w700, color: displayColor),
      headlineMedium: GoogleFonts.sourceSerif4(
        fontSize: 24, fontWeight: FontWeight.w700, color: displayColor),
      headlineSmall: GoogleFonts.sourceSerif4(
        fontSize: 20, fontWeight: FontWeight.w400, color: displayColor),
      titleLarge: _geist(18, FontWeight.w500, bodyColor),
      titleMedium: _geist(16, FontWeight.w500, bodyColor),
      titleSmall: _geist(14, FontWeight.w500, bodyColor),
      bodyLarge: _geist(16, FontWeight.w400, bodyColor),
      bodyMedium: _geist(14, FontWeight.w400, bodyColor),
      bodySmall: _geist(12, FontWeight.w400, bodyColor),
      labelLarge: _geist(14, FontWeight.w700, bodyColor),
      labelMedium: _geist(12, FontWeight.w500, bodyColor),
      labelSmall: _geist(11, FontWeight.w300, bodyColor),
    );
  }

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      surface: AppColors.backgroundLight,
      primary: AppColors.primary,
      onPrimary: AppColors.primaryForeground,
      secondary: AppColors.secondaryLight,
      onSecondary: AppColors.foregroundLight,
      onSurface: AppColors.foregroundLight,
      outline: AppColors.borderLight,
    );
    return ThemeData(
      colorScheme: colorScheme,
      textTheme: _buildTextTheme(AppColors.foregroundLight, AppColors.foregroundLight),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      cardTheme: CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdR,
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardLight,
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sidebarLight,
        elevation: 0,
        titleTextStyle: GoogleFonts.sourceSerif4(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.foregroundLight),
        iconTheme: const IconThemeData(color: AppColors.foregroundLight),
      ),
      dividerColor: AppColors.borderLight,
      useMaterial3: true,
    );
  }

  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      surface: AppColors.backgroundDark,
      primary: AppColors.primaryDark,
      onPrimary: AppColors.primaryForegroundDark,
      secondary: AppColors.secondaryDark,
      onSecondary: AppColors.foregroundDark,
      onSurface: AppColors.foregroundDark,
      outline: AppColors.borderDark,
    );
    return ThemeData(
      colorScheme: colorScheme,
      textTheme: _buildTextTheme(AppColors.foregroundDark, AppColors.foregroundDark),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdR,
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlR(56),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sidebarDark,
        elevation: 0,
        titleTextStyle: GoogleFonts.sourceSerif4(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.foregroundDark),
        iconTheme: const IconThemeData(color: AppColors.foregroundDark),
      ),
      dividerColor: AppColors.borderDark,
      useMaterial3: true,
    );
  }
}
