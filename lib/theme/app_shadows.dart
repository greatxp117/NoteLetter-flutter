import 'package:flutter/widgets.dart';

/// Shadow tokens (`spec/design-tokens.md` §Shadows, source `theme.css`).
///
/// **Warm-tinted, never harsh black.** Every shadow here is cast in ink-700 at
/// low alpha, which is what keeps the app reading as paper rather than as
/// material. A `Colors.black26` anywhere in a screen is a token violation even
/// though it looks approximately right in isolation.
class AppShadows {
  AppShadows._();

  static const Color _ink = Color(0xFF14171F);

  /// `--shadow-1` — a hairline lift. Resting state for primary buttons and
  /// timeline nodes; the hover state for a passage card.
  static const List<BoxShadow> s1 = [
    BoxShadow(color: Color(0x0A14171F), offset: Offset(0, 1), blurRadius: 0),
    BoxShadow(color: Color(0x0F14171F), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// `--shadow-2` — the **hover** elevation for cards, and the resting state
  /// for the letter sheet and the empty-state mark.
  static const List<BoxShadow> s2 = [
    BoxShadow(color: Color(0x0A14171F), offset: Offset(0, 1), blurRadius: 0),
    BoxShadow(
        color: Color(0x1A14171F),
        offset: Offset(0, 4),
        blurRadius: 14,
        spreadRadius: -4),
  ];

  /// `--shadow-3` — reserved for what floats over the page: the composer dock.
  static const List<BoxShadow> s3 = [
    BoxShadow(color: Color(0x0A14171F), offset: Offset(0, 1), blurRadius: 0),
    BoxShadow(
        color: Color(0x2E14171F),
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -8),
  ];

  /// `--letterpress` — the 1px white edge under display type that makes it read
  /// as pressed into the paper. Applied in **both** themes, as on the web
  /// reference; it is not redefined in the `.dark` block.
  static const List<Shadow> letterpress = [
    Shadow(color: Color(0x80FFFFFF), offset: Offset(0, 1), blurRadius: 0),
  ];

  /// `--shadow-inset` — the pressed well behind the utility rail's search
  /// field. Flutter cannot cast an inner box-shadow, so this is drawn as a
  /// hairline top border by the widgets that need it; see [KitSearchField].
  /// Recorded as a documented deviation in CLAUDE.md.
  static const Color insetTop = Color(0x99FFFFFF);
  static const Color insetBottom = Color(0x0F14171F);

  static Color ink(double opacity) => _ink.withValues(alpha: opacity);
}
