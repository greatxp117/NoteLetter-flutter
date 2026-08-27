import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'app_colors.dart';

/// The semantic token layer, resolved for the current theme.
///
/// `Tokens.of(context)` hands back every semantic colour already switched for
/// light or dark, so a widget writes `t.fgMuted` instead of
/// `isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground`.
///
/// That is not only ergonomics. The inline-ternary style is how a widget ends
/// up reaching for a **raw** step when the pair it wants has no name yet —
/// and raw steps do not flip with the theme. Mixing the two shipped
/// white-on-white in dark mode while every element was individually correct.
/// Everything a screen may consume is on this object; if a token is missing
/// here, add it here rather than reaching past it.
///
/// **Chrome is deliberately not part of the pair.** `chrome`/`chromeFg` and the
/// alphas beside them are identical in both themes — the plum chrome "stays
/// warm either way" — so a foreground taken from `fg` instead of `chromeFg`
/// turns near-black in light mode and disappears.
@immutable
class Tokens {
  final Brightness brightness;

  const Tokens._(this.brightness);

  static const Tokens light = Tokens._(Brightness.light);
  static const Tokens dark = Tokens._(Brightness.dark);

  /// Resolve against the **app's** brightness, never the platform's: the app
  /// owns a theme toggle, and once the user has chosen, following the OS would
  /// render a screen in the theme they just turned off.
  static Tokens of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_TokenScope>();
    final b = scope?.brightness ?? Theme.of(context).brightness;
    return b == Brightness.dark ? dark : light;
  }

  bool get isDark => brightness == Brightness.dark;

  T _p<T>(T lightValue, T darkValue) => isDark ? darkValue : lightValue;

  // ── Surfaces ─────────────────────────────────────────────────────────────
  Color get bg => _p(AppColors.backgroundLight, AppColors.backgroundDark);
  Color get surface => _p(AppColors.cardLight, AppColors.cardDark);
  Color get surfaceRaised =>
      _p(AppColors.surfaceRaisedLight, AppColors.surfaceRaisedDark);
  Color get surfaceSunken =>
      _p(AppColors.surfaceSunkenLight, AppColors.surfaceSunkenDark);

  // ── Text ─────────────────────────────────────────────────────────────────
  Color get fg => _p(AppColors.foregroundLight, AppColors.foregroundDark);
  Color get fgMuted =>
      _p(AppColors.mutedForeground, AppColors.mutedForegroundDark);
  Color get fgSubtle =>
      _p(AppColors.subtleForegroundLight, AppColors.subtleForegroundDark);
  Color get fgLede => _p(AppColors.fgLedeLight, AppColors.fgLedeDark);

  // ── Lines ────────────────────────────────────────────────────────────────
  Color get border => _p(AppColors.borderLight, AppColors.borderDark);
  Color get borderStrong =>
      _p(AppColors.borderStrongLight, AppColors.borderStrongDark);
  Color get rule => _p(AppColors.ruleLight, AppColors.ruleDark);

  // ── Interaction ──────────────────────────────────────────────────────────
  Color get hover => _p(AppColors.hoverLight, AppColors.hoverDark);
  Color get hoverStrong =>
      _p(AppColors.hoverStrongLight, AppColors.hoverStrongDark);

  // ── Primary CTA (brick) ──────────────────────────────────────────────────
  Color get accent => _p(AppColors.primary, AppColors.primaryDark);
  Color get accentHover =>
      _p(AppColors.accentHoverLight, AppColors.accentHoverDark);
  Color get accentFg =>
      _p(AppColors.primaryForeground, AppColors.primaryForegroundDark);
  Color get accentSoft =>
      _p(AppColors.accentSoftLight, AppColors.accentSoftDark);

  // ── Secondary CTA (plum on paper, a white wash on ink) ───────────────────
  Color get secondary =>
      _p(AppColors.secondaryFillLight, AppColors.secondaryFillDark);
  Color get secondaryFg => AppColors.secondaryFg;

  // ── Solid neutral control (inverts) ──────────────────────────────────────
  Color get solid => _p(AppColors.solidLight, AppColors.solidDark);
  Color get solidFg => _p(AppColors.solidFgLight, AppColors.solidFgDark);

  // ── Decorative ───────────────────────────────────────────────────────────
  Color get highlight =>
      _p(AppColors.highlightLight, AppColors.highlightDark);
  /// The stronger mark: the passage being read, not one being listed.
  Color get highlightStrong =>
      _p(AppColors.highlightStrongLight, AppColors.highlightStrongDark);
  Color get seal => _p(AppColors.sealLight, AppColors.sealDark);
  /// `--link` — near-black ink in light, paper in dark. It is deliberately
  /// NOT the accent: a link in this design is distinguished by its
  /// **underline** ([linkDecor]), which is why a control that drops the
  /// underline is invisible as a control (component-kit.md §13).
  Color get link => _p(AppColors.linkLight, AppColors.linkDark);
  Color get linkDecor =>
      _p(AppColors.linkDecorLight, AppColors.linkDecorDark);

  /// The accent chip triple (`--accent-chip-*`) — eyebrow chips, cite pills,
  /// the folio seal.
  Color get accentChipBg => accentSoft;
  Color get accentChipFg => _p(AppColors.sealLight, AppColors.sealDark);
  Color get accentChipBorder => _p(
        const Color(0x389D352D), // rgba(157,53,45,.22)
        const Color(0x52D9482F), // rgba(217,72,47,.32)
      );

  // ── Status ───────────────────────────────────────────────────────────────
  // The three severities `level` carries (data-model.md /activity_events). All
  // three now FLIP (4.21.0, ADR-057): they used to be shared with light mode,
  // so an error node drew brick-500 on the near-black dark ground at about 2:1
  // — the severity a feed exists to surface was the least legible thing on it.
  Color get positive => _p(AppColors.positive, AppColors.positiveDark);

  /// `warning` had no token at all until 4.21.0. It has been a `level` value
  /// since 2.5.0 (ADR-014); the web asked for `var(--gold-600, var(--accent))`
  /// and every warning has been drawing in the accent colour ever since.
  Color get warning => _p(AppColors.warning, AppColors.warningDark);

  /// Anything ON critical is labelled `paper-50` and never [accentFg] — that
  /// flips dark and would fail contrast.
  Color get critical => _p(AppColors.critical, AppColors.criticalDark);
  Color get criticalFg => const Color(0xFFFAFAF7);

  // ── Chrome — identical in both themes ────────────────────────────────────
  Color get chrome => AppColors.chrome;
  Color get chromeFg => AppColors.chromeForeground;
  Color get chromeMuted => AppColors.chromeMuted;
  Color get chromeSubtle => AppColors.chromeSubtle;
  Color get chromeHover => AppColors.chromeHover;
  Color get chromeActive => AppColors.chromeActive;
  Color get chromeBorder => AppColors.chromeBorder;
  Color get chromeAccentBar => AppColors.chromeAccentBar;
}

/// Publishes the app's chosen brightness to [Tokens.of], so token resolution
/// follows the in-app theme toggle rather than the OS.
class TokenScope extends StatelessWidget {
  final Brightness brightness;
  final Widget child;

  const TokenScope({super.key, required this.brightness, required this.child});

  @override
  Widget build(BuildContext context) =>
      _TokenScope(brightness: brightness, child: child);
}

class _TokenScope extends InheritedWidget {
  final Brightness brightness;

  const _TokenScope({required this.brightness, required super.child});

  @override
  bool updateShouldNotify(_TokenScope old) => old.brightness != brightness;
}
