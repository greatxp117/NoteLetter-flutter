/// Spacing and layout tokens (`spec/design-tokens.md` §Spacing / layout,
/// source `NoteLetter-web/src/styles/theme.css`).
///
/// The 4px base is not a suggestion: every gap, pad and inset in the app comes
/// from this scale. A one-off `EdgeInsets.all(13)` is invisible in review and
/// is exactly what makes a screen stop sitting on the same grid as the rest.
class AppSpacing {
  AppSpacing._();

  // `--s-1` … `--s-32`.
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;
  static const double s20 = 80;
  static const double s24 = 96;
  static const double s32 = 128;

  // ── Layout (`component-kit.md` §1.5) ─────────────────────────────────────

  /// The four page-frame ceilings. Chosen by what the screen is FOR, never by
  /// eye — see [KitFrame].
  static const double frameWide = 1100; // search: the only two-pane screen
  static const double frameIndex = 980; // anything that lists
  static const double frameReading = 760; // prose, and long forms
  static const double frameSheet = 640; // the letter paper

  /// The inline gutter is **constant across all four frames**; only the ceiling
  /// moves. A screen that changes its gutter to fit its content has left the
  /// grid.
  static const double frameGutter = 56;
  static const double frameGutterTop = 36;

  /// Narrow-viewport gutter. The 56px reference gutter is wrong on a phone —
  /// this is the one documented scale-down, applied below [compactWidth].
  /// Recorded in CLAUDE.md §Composition deviations.
  static const double frameGutterCompact = 20;
  static const double compactWidth = 768;

  /// `--measure` 68ch. Flutter has no `ch` unit; at the reading face's average
  /// advance this is the em-based equivalent used by the reading surfaces.
  static const double measure = 660;

  /// Chrome rail width (`component-kit.md` §1.1) and the main pane's inset.
  static const double railWidth = 260;
  static const double shellInset = 8;
}
