import 'package:flutter/widgets.dart';

/// Curvature tokens (spec/design-tokens.md §Spacing / radius, 2.16.0–2.17.0).
///
/// Three rules, and they are not interchangeable:
///
/// 1. **Controls** — anything sized by its height (buttons, inputs, chips,
///    tabs, icon buttons) take `radius = 0.25 × height` via [control]. Never a
///    named step picked by eye: a fixed radius across mixed heights over-rounds
///    small controls and pinches large ones, and the *ratio* is what makes a
///    32px chip and a 56px button read as one family.
/// 2. **Containers** are concentric, not ratio-based: `outer = inner + inset`
///    via [nest], capped at [xxl] — an editorial cap, past which the page stops
///    reading as paper. A container with no rounded children keeps a named step.
/// 3. **Named steps** ([xs]…[xxl]) are a fallback for surfaces that hold only
///    text — the letter sheet, the reader pane, the drop zone. They were snapped
///    onto the curvature grid at 2.17.0 (xs/sm/md were 4/6/10).
///
/// [pill] (0.5 × height) is the one deliberate exception to rule 1.
class AppRadius {
  AppRadius._();

  /// `--r-ratio`
  static const double ratio = 0.25;

  // ── Named steps (text-only surfaces) ──────────────────────────────────────
  static const double xs = 6;
  static const double sm = 9;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 20;
  static const double xxl = 28; // --r-2xl, also the concentric cap

  /// The authored `--r-c-*` table (theme.css). It is the authority, not the
  /// formula: the values are **not** a pure `round(0.25 × h)`. 34→9 and 46→12
  /// round the .5 up, but 58→14 rounds it down. Computing instead of looking up
  /// would silently disagree with the web reference on 58px controls — one
  /// pixel, invisible in review, and exactly the kind of drift the token table
  /// exists to prevent.
  static const Map<int, double> _controlSteps = {
    20: 5, 24: 6, 28: 7, 32: 8,
    34: 9, 36: 9, 40: 10, 44: 11,
    46: 12, 48: 12, 52: 13, 56: 14,
    58: 14,
  };

  /// A control's radius from its height (`--r-c-*`). Contracted heights come
  /// from the table; anything else falls back to the ratio, so an off-grid
  /// control is still proportionate rather than arbitrary.
  static double control(double height) =>
      _controlSteps[height.round()] ?? (height * ratio).roundToDouble();

  /// The pill exception (0.5 × height) — for a control that is deliberately a
  /// lozenge, not for picking a large radius by eye.
  static double pill(double height) => height / 2;

  /// Concentric container radius: `outer = inner + inset`, capped at [xxl].
  /// `--r-nest-8` 20 · `--r-nest-14` 26 · `--r-nest-16` 28 all fall out of this
  /// with an inner of 12 and the cap applied.
  static double nest(double innerRadius, double inset) {
    final r = innerRadius + inset;
    return r > xxl ? xxl : r;
  }

  // ── BorderRadius conveniences ─────────────────────────────────────────────
  static BorderRadius controlR(double height) =>
      BorderRadius.circular(control(height));
  static BorderRadius pillR(double height) =>
      BorderRadius.circular(pill(height));
  static BorderRadius nestR(double innerRadius, double inset) =>
      BorderRadius.circular(nest(innerRadius, inset));

  static const BorderRadius xsR = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdR = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlR = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlR = BorderRadius.all(Radius.circular(xxl));
}
