import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_app/theme/app_colors.dart';
import 'package:flutter_app/theme/app_radius.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Design-token fidelity (design-tokens.md: "UI colors/type/spacing come from
/// tokens, never hardcoded values").
///
/// This exists because the app shipped for months with its live `ColorScheme`
/// built by `ColorScheme.fromSeed(seedColor: brick-500)`. A generated tonal
/// palette is always internally consistent, so **nothing looked broken and no
/// test could fail** — the token file was simply not what most widgets drew.
/// These assertions make that class of regression visible: reseed the scheme
/// and the role/token equalities below break immediately.
void main() {
  // Building the full ThemeData reaches GoogleFonts for the serif ramp, which
  // needs a binding — and, left alone, tries to FETCH the font over the
  // network. (Worth knowing beyond the test: Source Serif 4 is not bundled the
  // way Geist is, so the app resolves it at runtime.)
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('ColorScheme is built from the semantic tokens', () {
    test('light roles carry their tokens', () {
      const cs = AppTheme.lightScheme;
      expect(cs.brightness, Brightness.light);
      expect(cs.primary, AppColors.primary); // --accent
      expect(cs.onPrimary, AppColors.primaryForeground); // --accent-fg
      expect(cs.primaryContainer, AppColors.accentSoftLight); // --accent-soft
      expect(cs.secondary, AppColors.secondaryFillLight); // --secondary
      expect(cs.surface, AppColors.cardLight); // --surface
      expect(cs.onSurface, AppColors.foregroundLight); // --fg
      expect(cs.onSurfaceVariant, AppColors.mutedForeground); // --fg-muted
      expect(cs.outline, AppColors.borderStrongLight); // --border-strong
      expect(cs.outlineVariant, AppColors.borderLight); // --border
      expect(cs.error, AppColors.critical); // --critical
    });

    test('dark roles carry their tokens', () {
      const cs = AppTheme.darkScheme;
      expect(cs.brightness, Brightness.dark);
      expect(cs.primary, AppColors.primaryDark);
      expect(cs.onPrimary, AppColors.primaryForegroundDark);
      expect(cs.primaryContainer, AppColors.accentSoftDark);
      expect(cs.secondary, AppColors.secondaryFillDark);
      expect(cs.surface, AppColors.cardDark);
      expect(cs.onSurface, AppColors.foregroundDark);
      expect(cs.onSurfaceVariant, AppColors.mutedForegroundDark);
      expect(cs.outline, AppColors.borderStrongDark);
      expect(cs.outlineVariant, AppColors.borderDark);
    });

    test('status tokens do NOT flip between themes', () {
      // theme.css leaves --positive and --critical at sage-500 / brick-500 in
      // dark. Flipping them here would be inventing a token.
      expect(AppTheme.lightScheme.tertiary, AppTheme.darkScheme.tertiary);
      expect(AppTheme.lightScheme.error, AppTheme.darkScheme.error);
      expect(AppTheme.lightScheme.error, AppColors.critical);
    });

    test('surfaces and text DO flip between themes', () {
      // The counterpart assertion: a token that must flip and does not is the
      // white-on-white failure, where every element is individually correct.
      const l = AppTheme.lightScheme, d = AppTheme.darkScheme;
      expect(l.surface, isNot(d.surface));
      expect(l.onSurface, isNot(d.onSurface));
      expect(l.primary, isNot(d.primary));
      expect(l.outlineVariant, isNot(d.outlineVariant));
    });

    test('no elevation tint', () {
      // M3 tints elevated surfaces with `surfaceTint` (primary by default),
      // which reintroduces a generated hue over pinned card colours.
      expect(AppTheme.lightScheme.surfaceTint, Colors.transparent);
      expect(AppTheme.darkScheme.surfaceTint, Colors.transparent);
    });

    test('the page and the sheet are different surfaces', () {
      // --bg is the page, --surface is the card laid on it. Collapsing them
      // loses the contrast that makes a card read as lifted.
      //
      // Asserted on the TOKENS, not on `AppTheme.light.scaffoldBackgroundColor`
      // — constructing the ThemeData pulls Source Serif 4 through google_fonts,
      // which is not bundled (unlike Geist) and so is fetched at runtime. That
      // is a real gap in its own right and is filed in ../TODO.md; it is not
      // something this test should paper over by mocking the bundle.
      expect(AppColors.backgroundLight, isNot(AppTheme.lightScheme.surface));
      expect(AppColors.backgroundDark, isNot(AppTheme.darkScheme.surface));
    });
  });

  group('curvature tokens', () {
    test('control radius follows the authored --r-c-* table', () {
      // NOT a pure round(0.25 x h): 34 and 46 round the half UP, 58 rounds it
      // DOWN. Computing instead of looking up disagrees with web by a pixel.
      const expected = {
        20: 5.0, 24: 6.0, 28: 7.0, 32: 8.0, 34: 9.0, 36: 9.0, 40: 10.0,
        44: 11.0, 46: 12.0, 48: 12.0, 52: 13.0, 56: 14.0, 58: 14.0,
      };
      expected.forEach((h, r) {
        expect(AppRadius.control(h.toDouble()), r, reason: '--r-c-$h');
      });
    });

    test('containers are concentric and capped', () {
      // outer = inner + inset, capped at --r-2xl (28) — an editorial cap, past
      // which the page stops reading as paper.
      expect(AppRadius.nest(12, 8), 20); // --r-nest-8
      expect(AppRadius.nest(12, 14), 26); // --r-nest-14
      expect(AppRadius.nest(12, 16), 28); // --r-nest-16, at the cap
      expect(AppRadius.nest(12, 40), AppRadius.xxl); // capped, not 52
    });

    test('pill is the one deliberate exception', () {
      expect(AppRadius.pill(32), 16);
      expect(AppRadius.pill(4), 2);
    });
  });
}
