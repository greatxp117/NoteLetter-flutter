/// §12 — the Notice (4.7.0, ADR-043).
///
/// A standing statement about the thing it sits in: a condition the **backend
/// measured**, which the reader can act on.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';

/// Required parts, **in this order** — a leading glyph at `--seal` · a sans
/// line of copy naming the condition and the figure it was measured from ·
/// **one** action, as a quiet button on the trailing edge. No dismiss control.
///
/// Three rules the pattern carries, each of which is a way to get it wrong:
///
///  * **It is measured, not decorative.** It states a condition the backend
///    wrote down and this only rendered; if a client had to infer or estimate
///    the condition, it is not this pattern.
///  * **It is not dismissible.** Its lifecycle belongs to the condition — it
///    leaves when the backend says the condition ended. A local dismissal
///    hides a live state and puts the surface in disagreement with the
///    notification the reader already received about the same thing.
///  * **Warning is not error.** The accent-chip roles, never `--critical`.
///    Nothing has broken; something needs doing.
///
/// Inside a Surface card (§5.1) it sits **below** the card's own content and
/// inherits the card's inner width — never a card of its own, and never with a
/// shadow of its own.
class KitNotice extends StatelessWidget {
  /// The pattern's glyph. The reference HARDCODES it (`shared/Notice.jsx`
  /// renders `IcoAlert` and takes no icon prop) because it belongs to the
  /// pattern, not the caller — and making it a parameter here is exactly how
  /// this client's two notices came to draw different glyphs. Overridable, but
  /// the default is the pattern's.
  final IconData icon;
  final String text;

  /// The one action. Omit both and the notice is a statement with no remedy,
  /// which is legitimate when there is nothing to do.
  final String? actionLabel;
  final VoidCallback? onAction;

  const KitNotice({
    super.key,
    this.icon = Icons.warning_amber_rounded,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.s3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.accentChipBg,
        borderRadius: AppRadius.smR,
        border: Border.all(color: t.accentChipBorder),
        // No shadow, deliberately: a notice is part of what it sits in, not a
        // second card laid on top of it.
      ),
      child: _body(context, t),
    );
  }

  /// The glyph is 14 and the gap 9, so the copy starts at 23 — which is also
  /// what the stacked action is indented by, so it hangs under the copy rather
  /// than under the glyph. The reference spells the same three numbers
  /// (`app-kit.css` `.kit-notice` and its `max-width: 480px` rule).
  static const double _copyInset = 14 + 9;

  Widget _body(BuildContext context, Tokens t) {
    final copy = Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 13,
        height: 19 / 13,
        color: t.accentChipFg,
      ),
    );
    final glyph = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, size: 14, color: t.seal),
    );
    final action = actionLabel == null
        ? null
        : KitButton(actionLabel!,
            variant: KitButtonVariant.ghost, onPressed: onAction);

    // On a phone the action DROPS UNDER the copy instead of squeezing it to a
    // word a line — the reference's own rule, in its own words. Beside a
    // 'Ask about upgrading' this is the difference between two lines and eight.
    // At this client's single compact breakpoint (CLAUDE.md §Composition
    // deviations), not web's 480: one breakpoint, not three.
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    if (compact && action != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [glyph, const SizedBox(width: 9), Expanded(child: copy)],
          ),
          Padding(
            padding: const EdgeInsets.only(left: _copyInset, top: 2),
            child: action,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        glyph,
        const SizedBox(width: 9),
        Expanded(child: copy),
        if (action != null) ...[const SizedBox(width: AppSpacing.s2), action],
      ],
    );
  }
}
