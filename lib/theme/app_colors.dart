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
  static const _paper200 = Color(0xFFE9E7DF);
  static const _ink500 = Color(0xFF2C3142);
  static const _ink600 = Color(0xFF1F2330);
  static const _ink700 = Color(0xFF14171F);
  static const _ink800 = Color(0xFF0B0D13);
  static const _brick400 = Color(0xFFE97D39);
  static const _brick500 = Color(0xFF9D352D);
  static const _sage500 = Color(0xFF6F8159);
  static const _sage700 = Color(0xFF495936);
  static const _brick700 = Color(0xFF6E1F18);
  static const _brick450 = Color(0xFFB4551A); // marigold darkened for paper
  static const _ink300 = Color(0xFF8A91A4);
  static const _ink400 = Color(0xFF4E5566);
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
  static const warning = _brick450; // --warning (4.21.0, ADR-057)
  static const critical = _brick500; // --critical

  // ── Semantic — Dark (status) ─────────────────────────────────────────────
  // Until 4.21.0 the three status colours were shared with light mode, so an
  // error drew brick-500 on the near-black ground — about 2:1. theme.css now
  // lifts all three for dark; these mirror it.
  static const positiveDark = Color(0xFF93A87A);
  static const warningDark = _brick400;
  static const criticalDark = Color(0xFFE4695E);
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

  // ── Sunken surfaces, rules and subtle text ───────────────────────────────
  // Semantic, so each flips with the theme (never a raw step picked once and
  // reused in both — that is how white-on-white shipped in dark mode while
  // every element was individually correct).
  static const surfaceSunkenLight = _paper200; // --surface-sunken
  static const surfaceSunkenDark = _ink800; // --surface-sunken (dark)
  static const ruleLight = Color(0x0F14171F); // --rule rgba(20,23,31,.06)
  static const ruleDark = Color(0x0FFFFFFF); // --rule rgba(255,255,255,.06)
  static const subtleForegroundLight = _ink300; // --fg-subtle
  static const subtleForegroundDark = Color(0x73FFFFFF); // --fg-subtle rgba(255,255,255,.45)

  // ── The rest of the semantic layer (needed to build a real ColorScheme) ──
  // Every one of these is a token that FLIPS with the theme, which is why each
  // is a light/dark pair rather than one value used twice.
  static const surfaceRaisedLight = _paper100; // --surface-raised
  static const surfaceRaisedDark = _ink500; // --surface-raised (dark)
  static const borderStrongLight = Color(0x2E14171F); // --border-strong rgba(20,23,31,.18)
  static const borderStrongDark = Color(0x2EFFFFFF); // --border-strong rgba(255,255,255,.18)
  static const hoverLight = Color(0x0A14171F); // --hover rgba(20,23,31,.04)
  static const hoverDark = Color(0x0FFFFFFF); // --hover rgba(255,255,255,.06)
  static const hoverStrongLight = Color(0x1414171F); // --hover-strong rgba(20,23,31,.08)
  static const hoverStrongDark = Color(0x1FFFFFFF); // --hover-strong rgba(255,255,255,.12)
  static const accentHoverLight = _brick700; // --accent-hover
  static const accentHoverDark = Color(0xFFD16A28); // --accent-hover (dark)
  static const accentSoftLight = Color(0x1A9D352D); // --accent-soft rgba(157,53,45,.10)
  static const accentSoftDark = Color(0x29E97D39); // --accent-soft rgba(233,125,57,.16)
  static const fgLedeLight = _ink400; // --fg-lede
  static const fgLedeDark = Color(0xB8FFFFFF); // --fg-lede rgba(255,255,255,.72)

  /// `--secondary` is the secondary BUTTON FILL, and it is one of the few
  /// tokens whose two themes are not the same kind of colour at all: solid plum
  /// on paper, a white wash on ink. Distinct from [secondaryLight], which this
  /// file has always used for `--surface-raised` — the two names predate the
  /// semantic layer and are deliberately left alone, because widgets reference
  /// them.
  static const secondaryFillLight = _plum600; // --secondary
  static const secondaryFillDark = Color(0x14FFFFFF); // --secondary rgba(255,255,255,.08)
  static const secondaryFg = _paper50; // --secondary-fg (both themes)

  /// `--solid` — the neutral control. Inverts between themes.
  static const solidLight = _ink700;
  static const solidDark = _paper50;
  static const solidFgLight = _paper50;
  static const solidFgDark = _ink700;

  // Decorative.
  static const highlightLight = Color(0x269D352D); // --highlight rgba(157,53,45,.15)
  static const highlightDark = Color(0x3DE97D39); // --highlight rgba(233,125,57,.24)
  // `--highlight-strong` — the mark on a passage the reader is *reading*, as
  // opposed to one being listed. Contracted since the token file's first
  // version and absent from this client until 4.5.4, which is why the search
  // reading pane had nothing to mark the matched chunk with.
  static const highlightStrongLight =
      Color(0x429D352D); // --highlight-strong rgba(157,53,45,.26)
  static const highlightStrongDark =
      Color(0x66E97D39); // --highlight-strong rgba(233,125,57,.40)
  static const sealLight = _brick700; // --seal
  static const sealDark = _brick400; // --seal (dark)
  static const linkLight = _ink700; // --link (theme.css: var(--ink-700))
  static const linkDark = _paper50; // --link (dark: var(--paper-50))
  static const linkDecorLight = _brick500; // --link-decor
  static const linkDecorDark = _brick400; // --link-decor (dark)

  // ── Shelf colours (2.15.0, ADR-022) ──────────────────────────────────────
  // `/tags.color` stores a design-token NAME, not a colour value — the one
  // place a token name crosses the wire as data. A hex literal cannot be
  // themed by a client that renders light and dark, and a CSS `var()` string
  // means nothing off the web; what every client can act on is WHICH token.
  //
  // Raw steps only, never semantic tokens: semantics flip between themes, so a
  // shelf coloured `--seal` would change hue when the user toggles the theme.
  // All ten already exist in the palette above — this adds no token.
  //
  // CLOSED FOR WRITING, TOLERANT ON READING. Legacy 6-digit hex stays valid
  // forever (every auto-created tag holds the `#6B7280` default and there is no
  // backfill), and an unrecognised value renders muted rather than failing.
  static const shelfColors = <String, Color>{
    'sage-500': _sage500,
    'sage-700': _sage700,
    'brick-400': _brick400,
    'brick-500': _brick500,
    'brick-700': _brick700,
    'plum-500': _plum500,
    'plum-600': _plum600,
    'ink-300': _ink300,
    'ink-400': _ink400,
    'ink-500': _ink500,
  };

  /// Resolve a `/tags.color` value. Returns null for anything unrecognised so
  /// the caller can fall back to its own muted colour — never an error.
  static Color? shelfColor(String? value) {
    if (value == null) return null;
    final v = value.trim();
    final token = shelfColors[v];
    if (token != null) return token;
    // Legacy hex, permanently valid.
    var h = v.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final n = int.tryParse(h, radix: 16);
    return n == null ? null : Color(n);
  }
}
