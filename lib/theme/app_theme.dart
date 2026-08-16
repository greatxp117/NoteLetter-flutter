import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';

class AppTheme {
  AppTheme._();

  // Per design-tokens.md: serif `Source Serif 4` for display/headings/reading,
  // sans `Geist` for UI body, mono `Geist Mono` for code/caps-labels. All three
  // are bundled as OFL assets (see pubspec `fonts:` + assets/fonts/) and
  // referenced by family name — nothing is fetched at runtime.
  static const String fontSans = 'Geist';
  static const String fontMono = 'Geist Mono';
  static const String fontSerif = 'Source Serif 4';

  static TextStyle _geist(double size, FontWeight weight, Color color) =>
      TextStyle(fontFamily: fontSans, fontSize: size, fontWeight: weight, color: color);

  /// Serif (`Source Serif 4`) — display, headings and reading text.
  ///
  /// Use this, never `GoogleFonts.sourceSerif4`. The font is bundled, so this
  /// resolves from the app package with no network and no silent fallback to
  /// the platform serif — which is exactly what the google_fonts path did when
  /// a fetch failed, invisibly, on every heading in the app.
  ///
  /// It is a VARIABLE font: one asset covers the weight axis, so the weight has
  /// to be driven through `fontVariations`. `fontWeight` is passed as well —
  /// it is what the engine falls back to for synthetic bolding, and what any
  /// style-merging code reads.
  static TextStyle serif({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    FontStyle? fontStyle,
    double? letterSpacing,
  }) {
    final w = fontWeight ?? FontWeight.w400;
    return TextStyle(
      fontFamily: fontSerif,
      fontSize: fontSize,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: color,
      height: height,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
    );
  }

  /// Mono (`Geist Mono`) — code and caps-labels.
  ///
  /// design-tokens.md names Geist Mono; this app had been calling
  /// `GoogleFonts.robotoMono`, which is both a different typeface from the one
  /// the tokens specify and a second runtime fetch.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return TextTheme(
      displayLarge: serif(
        fontSize: 56, fontWeight: FontWeight.w400, color: displayColor),
      displayMedium: serif(
        fontSize: 48, fontWeight: FontWeight.w400, color: displayColor),
      displaySmall: serif(
        fontSize: 40, fontWeight: FontWeight.w400, color: displayColor),
      headlineLarge: serif(
        fontSize: 32, fontWeight: FontWeight.w700, color: displayColor),
      headlineMedium: serif(
        fontSize: 24, fontWeight: FontWeight.w700, color: displayColor),
      headlineSmall: serif(
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

  /// The light scheme, **written out from the semantic tokens** rather than
  /// generated.
  ///
  /// This app previously built its live scheme with
  /// `ColorScheme.fromSeed(seedColor: brick-500)`. That takes ONE token and
  /// derives a whole tonal palette from it by algorithm, so almost every
  /// Material surface, chip, switch and button drew a colour that appears
  /// nowhere in `design-tokens.md` — the token file was correct and largely
  /// unread. Nothing failed, because a generated palette is always
  /// self-consistent; it was simply a different design.
  ///
  /// Every role below therefore names the token it carries. Roles the token
  /// layer has no opinion about are given the nearest semantic surface rather
  /// than left to a default, because a default here means "seeded again".
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary, // --accent
    onPrimary: AppColors.primaryForeground, // --accent-fg
    primaryContainer: AppColors.accentSoftLight, // --accent-soft
    onPrimaryContainer: AppColors.foregroundLight,
    secondary: AppColors.secondaryFillLight, // --secondary
    onSecondary: AppColors.secondaryFg, // --secondary-fg
    secondaryContainer: AppColors.surfaceRaisedLight, // --surface-raised
    onSecondaryContainer: AppColors.foregroundLight,
    tertiary: AppColors.positive, // --positive
    onTertiary: AppColors.primaryForeground,
    error: AppColors.critical, // --critical
    onError: AppColors.primaryForeground,
    surface: AppColors.cardLight, // --surface (the sheet, not the page)
    onSurface: AppColors.foregroundLight, // --fg
    surfaceContainerLowest: AppColors.cardLight,
    surfaceContainerLow: AppColors.backgroundLight, // --bg
    surfaceContainer: AppColors.surfaceRaisedLight,
    surfaceContainerHigh: AppColors.surfaceRaisedLight,
    surfaceContainerHighest: AppColors.surfaceSunkenLight, // --surface-sunken
    onSurfaceVariant: AppColors.mutedForeground, // --fg-muted
    outline: AppColors.borderStrongLight, // --border-strong
    outlineVariant: AppColors.borderLight, // --border
    inverseSurface: AppColors.foregroundLight,
    onInverseSurface: AppColors.backgroundLight,
    inversePrimary: AppColors.primaryDark,
    // M3 tints every elevated surface with `surfaceTint` (primary by default),
    // which would quietly reintroduce a generated hue over the card colours we
    // just pinned. The design has no elevation tint — a card is a clean sheet
    // laid on the checkered ground.
    surfaceTint: Colors.transparent,
  );

  static ThemeData get light {
    const colorScheme = lightScheme;
    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: fontSans,
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
        titleTextStyle: serif(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.foregroundLight),
        iconTheme: const IconThemeData(color: AppColors.foregroundLight),
      ),
      dividerColor: AppColors.borderLight,
      hoverColor: AppColors.hoverLight, // --hover
      filledButtonTheme: _filled(colorScheme),
      outlinedButtonTheme: _outlined(colorScheme),
      textButtonTheme: _text(colorScheme),
      chipTheme: _chip(colorScheme, AppColors.borderLight),
      useMaterial3: true,
    );
  }

  // ── Component themes ──────────────────────────────────────────────────────
  // Controls take `radius = 0.25 x height` from their own height (AppRadius),
  // never a named step picked by eye. Material's default heights are the ones
  // used here: 40 for buttons, 32 for chips.

  static FilledButtonThemeData _filled(ColorScheme cs) => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlR(40)),
          textStyle: _geist(14, FontWeight.w600, cs.onPrimary),
        ),
      );

  static OutlinedButtonThemeData _outlined(ColorScheme cs) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlR(40)),
          textStyle: _geist(14, FontWeight.w500, cs.onSurface),
        ),
      );

  static TextButtonThemeData _text(ColorScheme cs) => TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlR(40)),
          textStyle: _geist(14, FontWeight.w500, cs.primary),
        ),
      );

  static ChipThemeData _chip(ColorScheme cs, Color border) => ChipThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.primary,
        side: BorderSide(color: border),
        labelStyle: _geist(12, FontWeight.w500, cs.onSurface),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlR(32)),
      );

  /// The dark scheme — the SAME semantic layer resolved for dark, never a
  /// second palette. Clients implement light and dark from one token API
  /// (design-tokens.md); mixing a semantic token with a raw step is how
  /// white-on-white once shipped while every element was individually correct.
  ///
  /// `--positive` and `--critical` deliberately do NOT flip: theme.css leaves
  /// both at sage-500 / brick-500 in dark.
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryDark, // --accent (dark)
    onPrimary: AppColors.primaryForegroundDark, // --accent-fg (dark)
    primaryContainer: AppColors.accentSoftDark, // --accent-soft (dark)
    onPrimaryContainer: AppColors.foregroundDark,
    secondary: AppColors.secondaryFillDark, // --secondary (dark)
    onSecondary: AppColors.secondaryFg, // --secondary-fg
    secondaryContainer: AppColors.surfaceRaisedDark, // --surface-raised (dark)
    onSecondaryContainer: AppColors.foregroundDark,
    tertiary: AppColors.positive, // --positive (does not flip)
    onTertiary: AppColors.foregroundDark,
    error: AppColors.critical, // --critical (does not flip)
    onError: AppColors.foregroundDark,
    surface: AppColors.cardDark, // --surface (dark)
    onSurface: AppColors.foregroundDark, // --fg (dark)
    surfaceContainerLowest: AppColors.surfaceSunkenDark,
    surfaceContainerLow: AppColors.backgroundDark, // --bg (dark)
    surfaceContainer: AppColors.cardDark,
    surfaceContainerHigh: AppColors.surfaceRaisedDark,
    surfaceContainerHighest: AppColors.surfaceRaisedDark,
    onSurfaceVariant: AppColors.mutedForegroundDark, // --fg-muted (dark)
    outline: AppColors.borderStrongDark, // --border-strong (dark)
    outlineVariant: AppColors.borderDark, // --border (dark)
    inverseSurface: AppColors.foregroundDark,
    onInverseSurface: AppColors.backgroundDark,
    inversePrimary: AppColors.primary,
    surfaceTint: Colors.transparent,
  );

  static ThemeData get dark {
    const colorScheme = darkScheme;
    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: fontSans,
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
        titleTextStyle: serif(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.foregroundDark),
        iconTheme: const IconThemeData(color: AppColors.foregroundDark),
      ),
      dividerColor: AppColors.borderDark,
      hoverColor: AppColors.hoverDark, // --hover (dark)
      filledButtonTheme: _filled(colorScheme),
      outlinedButtonTheme: _outlined(colorScheme),
      textButtonTheme: _text(colorScheme),
      chipTheme: _chip(colorScheme, AppColors.borderDark),
      useMaterial3: true,
    );
  }
}
