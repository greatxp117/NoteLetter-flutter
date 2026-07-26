import 'package:flutter/material.dart';

/// Values pulled from `NoteLetter-contracts/spec/design-tokens.md`, source of
/// truth `NoteLetter-web/src/styles/theme.css`. Field names are kept stable
/// (existing widgets reference them) but values now come from the semantic
/// token layer instead of the old amber/navy palette.
class AppColors {
  AppColors._();

  // ── Raw palette (subset used directly) ──────────────────────────────────
  static const _paper50 = Color(0xFFFAFAF7);
  static const _paper100 = Color(0xFFF3F2EC);
  static const _ink500 = Color(0xFF2C3142);
  static const _ink600 = Color(0xFF1F2330);
  static const _ink700 = Color(0xFF14171F);
  static const _ink800 = Color(0xFF0B0D13);
  static const _brick400 = Color(0xFFE97D39);
  static const _brick500 = Color(0xFF9D352D);
  static const _sage500 = Color(0xFF6F8159);
  static const _plum500 = Color(0xFF3F2C3E);
  static const _plum600 = Color(0xFF2D1F2E);

  // ── Semantic — Light ─────────────────────────────────────────────────────
  static const backgroundLight = _paper50; // --bg
  static const foregroundLight = _ink700; // --fg
  static const primary = _brick500; // --accent
  static const primaryForeground = _paper50; // --accent-fg
  static const secondaryLight = _paper100; // --surface-raised
  static const cardLight = Colors.white; // --surface
  static const borderLight = Color(0x1A14171F); // --border rgba(20,23,31,.10)
  static const sidebarLight = _paper100; // raised chrome area, light
  static const mutedForeground = _ink500; // --fg-muted
  static const positive = _sage500; // --positive
  static const critical = _brick500; // --critical
  static const secondaryAccent = _plum500; // plum-500 — chrome + secondary CTA only

  // ── Chrome (sidebar/footer) — plum, identical in light & dark ────────────
  // Web `--chrome: var(--plum-600)` with `color: var(--paper-50)`; the plum
  // chrome "stays warm either way" (app-kit.css .sb). Foregrounds are white at
  // token alphas over the plum surface, NOT the page fg.
  static const chrome = _plum600; // --chrome (both themes)
  static const chromeForeground = _paper50; // --chrome-fg / --paper-50
  static const chromeMuted = Color(0x9EFFFFFF); // idle nav rgba(255,255,255,.62)
  static const chromeSubtle = Color(0x66FFFFFF); // group labels/meta rgba(...,.40)
  static const chromeHover = Color(0x0DFFFFFF); // hover fill rgba(255,255,255,.05)
  static const chromeActive = Color(0x14FFFFFF); // active fill rgba(255,255,255,.08)
  static const chromeBorder = Color(0x1AFFFFFF); // rules on plum rgba(255,255,255,.10)
  static const chromeAccentBar = _brick400; // active left bar --brick-400

  // ── Semantic — Dark ──────────────────────────────────────────────────────
  static const backgroundDark = _ink700; // --bg (dark)
  static const foregroundDark = _paper50; // --fg (dark)
  static const primaryDark = _brick400; // --accent (dark)
  static const primaryForegroundDark = _ink800; // --accent-fg (dark)
  static const cardDark = _ink600; // --surface (dark)
  static const sidebarDark = _ink500; // --surface-raised (dark)
  static const borderDark = Color(0x1AFFFFFF); // --border rgba(255,255,255,.10)
  static const secondaryDark = Color(0x14FFFFFF); // --secondary rgba(255,255,255,.08)
  static const mutedForegroundDark = Color(0xA6FFFFFF); // --fg-muted rgba(255,255,255,.65)
}
