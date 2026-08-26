import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  // The full ThemeData is constructible in a plain unit test because all three
  // token fonts are bundled assets referenced by family name. While the serif
  // resolved through google_fonts this test could not build the theme at all —
  // it reached the network.
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.backgroundLight);
      expect(AppTheme.light.scaffoldBackgroundColor,
          isNot(AppTheme.lightScheme.surface));
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.backgroundDark);
      expect(AppTheme.dark.scaffoldBackgroundColor,
          isNot(AppTheme.darkScheme.surface));
    });

    test('--link is a SEMANTIC token and flips; --link-decor is the accent', () {
      // theme.css: --link is ink-700 in light and paper-50 in dark. It is
      // deliberately near-black rather than coloured, which is exactly why the
      // support footer's control must carry an underline (component-kit.md
      // §13) — a link distinguished only by this colour is invisible as a
      // control. A raw palette step used in its place would not flip, and the
      // footer would render paper-on-paper in one theme while every element in
      // it stayed individually correct.
      expect(AppColors.linkLight, isNot(AppColors.linkDark));
      expect(AppColors.linkLight, AppColors.foregroundLight);
      expect(AppColors.linkDark, AppColors.foregroundDark);
      expect(AppColors.linkDecorLight, AppColors.primary);
    });
  });

  group('type tokens', () {
    // design-tokens.md §Type: serif Source Serif 4, sans Geist, mono Geist Mono.
    // The serif used to come from google_fonts, which fetches at runtime and
    // falls back to the platform serif when that fails — silently, on every
    // heading. The mono was RobotoMono, which is not the token font at all.
    test('the three families are the token families', () {
      expect(AppTheme.fontSerif, 'Source Serif 4');
      expect(AppTheme.fontSans, 'Geist');
      expect(AppTheme.fontMono, 'Geist Mono');
      expect(AppTheme.serif(fontSize: 16).fontFamily, 'Source Serif 4');
      expect(AppTheme.mono(fontSize: 11).fontFamily, 'Geist Mono');
    });

    test('serif weight drives the variable wght axis', () {
      // One asset covers the axis, so a plain `fontWeight` would render every
      // heading at the default instance.
      final bold = AppTheme.serif(fontSize: 24, fontWeight: FontWeight.w700);
      expect(bold.fontWeight, FontWeight.w700);
      expect(bold.fontVariations, contains(const FontVariation('wght', 700)));
      final regular = AppTheme.serif(fontSize: 16);
      expect(regular.fontVariations, contains(const FontVariation('wght', 400)));
    });

    test('every bundled family is declared in pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final family in [AppTheme.fontSans, AppTheme.fontMono, AppTheme.fontSerif]) {
        expect(pubspec, contains('family: $family'),
            reason: '$family must be a bundled asset, not a runtime fetch');
      }
      // The italic cut is a separate asset; without it `fontStyle: italic`
      // synthesises a slant instead of using the real italic design.
      expect(pubspec, contains('SourceSerif4-Italic-Variable.ttf'));
    });

    test('nothing in lib/ reaches google_fonts', () {
      // The regression that matters: one reintroduced call puts a network fetch
      // back on a heading, and a silent fallback looks fine in review.
      // Matched on the IMPORT, not the bare word — app_theme.dart's own doc
      // comment names GoogleFonts in order to say "never use it", and a check
      // that flags its own warning is a check people delete.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          if (f.readAsStringSync().contains("import 'package:google_fonts")) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty);
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
