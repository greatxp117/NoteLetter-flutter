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
  static const _brick50 = Color(0xFFF6E1DC); // accent-chip fill, light
  /// Dark-mode CHIP TEXT. The accent step is a fill and a glyph colour; set as
  /// 12px copy inside its own tinted chip it is 3.16:1, so the chip text needed
  /// a lighter step of its own (4.30.0, ADR-067).
  static const _brick300 = Color(0xFFEE7B62);
  static const _brick400 = Color(0xFFD9482F); // vermilion (4.29.0, ADR-066)
  /// Ochre — --warning only. Its own family because a warning drawn from
  /// brick sits beside --critical and reads as a dimmer error (ADR-066).
  static const _ochre400 = Color(0xFFF2A63B); // dark-mode warning
  static const _ochre600 = Color(0xFF8A5A12); // light-mode warning
  static const _brick500 = Color(0xFF9D352D);
  static const _sage100 = Color(0xFFE2E8DC); // light-mode chip fill
  /// Dark-mode chip TEXT — the positive family's answer to --brick-300
  /// (4.31.0, ADR-068). Three widgets had invented `0xFFA8B894` for this by
  /// hand, which is not this colour.
  static const _sage300 = Color(0xFFA8BC8F);
  static const _sage400 = Color(0xFF93A87A); // dark-mode positive + sage tone
  static const _sage500 = Color(0xFF6F8159);
  static const _sage700 = Color(0xFF495936);
  static const _brick700 = Color(0xFF6E1F18);
  static const _ink300 = Color(0xFF8A91A4);
  /// `--ink-350` — the subtle-metadata step. `--fg-subtle` drew the 300 until
  /// 4.31.0 (ADR-068): 170 rules set it as 9–18px COPY, and a 3.15:1 step is a
  /// dot, not text. The 300 stays, for the dots and dashes it is.
  static const _ink350 = Color(0xFF686E7D);
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
  static const warning = _ochre600; // --warning (4.29.0, ADR-066)
  static const critical = _brick500; // --critical

  // ── Semantic — Dark (status) ─────────────────────────────────────────────
  // Until 4.21.0 the three status colours were shared with light mode, so an
  // error drew brick-500 on the near-black ground — about 2:1. theme.css now
  // lifts all three for dark; these mirror it.
  static const positiveDark = _sage400;
  static const warningDark = _ochre400;
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
  static const subtleForegroundLight = _ink350; // --fg-subtle
  static const subtleForegroundDark = Color(0x85FFFFFF); // --fg-subtle rgba(255,255,255,.52)

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
  static const accentHoverDark = Color(0xFFE85940); // --accent-hover (dark)
  static const accentSoftLight = Color(0x1A9D352D); // --accent-soft rgba(157,53,45,.10)
  static const accentSoftDark = Color(0x29D9482F); // --accent-soft rgba(217,72,47,.16)
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
  static const highlightDark = Color(0x3DD9482F); // --highlight rgba(217,72,47,.24)
  // `--highlight-strong` — the mark on a passage the reader is *reading*, as
  // opposed to one being listed. Contracted since the token file's first
  // version and absent from this client until 4.5.4, which is why the search
  // reading pane had nothing to mark the matched chunk with.
  static const highlightStrongLight =
      Color(0x429D352D); // --highlight-strong rgba(157,53,45,.26)
  static const highlightStrongDark =
      Color(0x66D9482F); // --highlight-strong rgba(217,72,47,.40)
  // `--seal` is the wax seal and its eight siblings — decorative, floored at
  // the 3:1 a graphic gets. It is NOT the chip text and NOT accent copy: ADR-069
  // split those roles out precisely because a token named for a seal had come
  // to carry every eyebrow, folio and verse number in the app.
  /// The family TEXT steps (4.32.0, ADR-069). Every hue the app writes copy in
  /// needs one, and it is NOT the fill: the accent and positive steps are sized
  /// to be a button, a dot or a rule, and set as 9–13px type they measure
  /// 3.16–4.23:1. No value moves — this is the dictionary catching up with what
  /// was already drawn.
  static const accentTextLight = _brick700; // --accent-text
  static const accentTextDark = _brick300; // --accent-text (dark)
  static const positiveTextLight = _sage700; // --positive-text
  static const positiveTextDark = _sage300; // --positive-text (dark)

  /// The positive chip (4.31.0, ADR-068). Structurally identical to the accent
  /// chip: a solid tint in light, a translucent wash of the page in dark. The
  /// raw steps do NOT flip, so a chip built from sage-100/sage-700 is a
  /// light-mode chip that never got a dark mode — legible in both and still
  /// wrong, which is a composition defect no contrast gate can see.
  static const positiveChipBgLight = _sage100;
  static const positiveChipBgDark = Color(0x2993A87A); // rgba(147,168,122,.16)
  static const positiveChipFgLight = _sage700;
  static const positiveChipFgDark = _sage300;
  static const positiveChipBorderLight = Color(0x386F8159); // rgba(111,129,89,.22)
  static const positiveChipBorderDark = Color(0x5293A87A); // rgba(147,168,122,.32)

  /// The seven reference tokens this mirror was missing. MIRROR printed them
  /// for a day and failed nothing — absence is not drift, because a client
  /// draws a subset of the app. What made them owed was the EIGHTH direction:
  /// LITERAL found five of the seven already being drawn, spelled out by hand
  /// one widget at a time, which is the same defect as a missing token with
  /// none of the visibility.
  static const criticalHoverLight = _brick700; // --critical-hover
  /// NOT brick-700. `--critical` flips to #E4695E in dark, so the hover has to
  /// LIFT (#EF8478); the raw step darkens it — a light button that gets darker
  /// on hover, which is exactly the defect ADR-067 fixed on the web and which
  /// `KitButton.danger` was still carrying here.
  static const criticalHoverDark = Color(0xFFEF8478);
  static const secondaryHoverLight = _plum500; // --secondary-hover
  static const secondaryHoverDark = Color(0x24FFFFFF); // rgba(255,255,255,.14)
  static const solidHoverLight = _ink800; // --solid-hover
  static const solidHoverDark = _paper200;

  /// The four event-family tones (`--tone-*`, component-kit §4.2). Semantic
  /// because the raw steps do NOT flip: plum-600 on the near-black dark page is
  /// the family colour being invisible on the one screen whose job is to be
  /// read, which is why the dark theme takes a lifted plum that belongs to no
  /// family. `KitActivityNode` had that lifted step as `0xFFB99BB6` — close to
  /// #C9A6C6 and not it, so the feed's plum node was a different plum here.
  static const toneSageLight = _sage700; // --tone-sage
  static const toneSageDark = _sage400;
  static const tonePlumLight = _plum600; // --tone-plum
  static const tonePlumDark = Color(0xFFC9A6C6);

  static const sealLight = _brick700; // --seal
  static const sealDark = _brick300; // --seal (dark)
  static const accentChipFgLight = _brick700; // --accent-chip-fg
  static const accentChipFgDark = _brick300; // --accent-chip-fg (dark)
  static const accentChipBgLight = _brick50; // --accent-chip-bg
  static const criticalFgLight = _paper50; // --critical-fg
  // `--critical-fg` (dark). paper-50 on the dark #E4695E fill is 3.10:1; ink-800
  // is 5.99 (4.30.0, ADR-067).
  static const criticalFgDark = _ink800;
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
