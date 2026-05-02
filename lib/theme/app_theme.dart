import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return TextTheme(
      displayLarge: GoogleFonts.libreBaskerville(
        fontSize: 56, fontWeight: FontWeight.w400, color: displayColor),
      displayMedium: GoogleFonts.libreBaskerville(
        fontSize: 48, fontWeight: FontWeight.w400, color: displayColor),
      displaySmall: GoogleFonts.libreBaskerville(
        fontSize: 40, fontWeight: FontWeight.w400, color: displayColor),
      headlineLarge: GoogleFonts.libreBaskerville(
        fontSize: 32, fontWeight: FontWeight.w700, color: displayColor),
      headlineMedium: GoogleFonts.libreBaskerville(
        fontSize: 24, fontWeight: FontWeight.w700, color: displayColor),
      headlineSmall: GoogleFonts.libreBaskerville(
        fontSize: 20, fontWeight: FontWeight.w400, color: displayColor),
      titleLarge: GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w500, color: bodyColor),
      titleMedium: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w500, color: bodyColor),
      titleSmall: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w500, color: bodyColor),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w400, color: bodyColor),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400, color: bodyColor),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400, color: bodyColor),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w700, color: bodyColor),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500, color: bodyColor),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w300, color: bodyColor),
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
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sidebarLight,
        elevation: 0,
        titleTextStyle: GoogleFonts.libreBaskerville(
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
      onPrimary: AppColors.primaryForeground,
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
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sidebarDark,
        elevation: 0,
        titleTextStyle: GoogleFonts.libreBaskerville(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.foregroundDark),
        iconTheme: const IconThemeData(color: AppColors.foregroundDark),
      ),
      dividerColor: AppColors.borderDark,
      useMaterial3: true,
    );
  }
}
