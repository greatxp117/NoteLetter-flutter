// Parts the ported D pages share (F-145: Deep study, Activity, For your
// review; web `pages/StudyView.jsx`, `ActivityView.jsx`, `ReviewView.jsx` over
// `styles/app-redesign-d.css` `.d-peek-*` and `app-d-pages.css`): the running
// head's text mark and the measured rule along its foot, the ruled register a D page lists in, and the D form of the group
// heads a ported page keeps. A page file never styles its own type or spacing
// (ADR-041), so these live here.

import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart';

/// The running head's leading mark in text (web `.d-peek-x`): a session's
/// `№ 2` — or `§` once nothing is left to answer — in accent serif 600 16.5,
/// for [KitLibPeek.mark].
class KitPeekMark extends StatelessWidget {
  final String text;
  const KitPeekMark(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.serif(
      fontSize: 16.5,
      height: 22 / 16.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.06 * 16.5,
      color: Tokens.of(context).accentText,
      opsz: 24,
    ),
  );
}

/// The 2px accent rule along the running head's foot that fills by a
/// MEASURED fraction (web `.dp-peek-bar`): the session's answered questions
/// over its questions — never the scroll (the source page's
/// [KitReadProgress] follows the scroll). No track under it. Its width eases
/// over `--dur-base`, and not at all under reduced motion. Placed by
/// `KitDSheet.foot`.
class KitPeekBar extends StatelessWidget {
  final double fraction;
  const KitPeekBar(this.fraction, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction.clamp(0.0, 1.0)),
          duration: KitD.dur(context, AppMotion.durBase),
          curve: AppMotion.easeOut,
          builder: (context, f, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              key: const ValueKey('d-peek-bar'),
              widthFactor: f,
              heightFactor: 1,
              child: ColoredBox(color: t.accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// A D page's ruled register: its entries under a 1px `--fg` rule, each
/// entry drawing its own `--rule` beneath it — Study's programs (`.st-list`),
/// its sessions (`.st-hist`) and the empty state's moves (`.st-moves`), where
/// before D each was a card or a pile of cards.
class KitRuledRegister extends StatelessWidget {
  final List<Widget> children;
  const KitRuledRegister({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).fg)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// Asks the section headers inside it for a ported D page's **group head**
/// (For your review's groups, `screens/review.md` §Composition; web
/// `.dp-review .d-main .lib-section-h`): a 1px `--fg` rule, padding 12, the
/// eyebrow set as a serif 600 22px title (its glyph dropped), the head's
/// actions pushed right; [gap] between groups, and none above the [first]
/// group that draws anything. The groups keep their own components — the
/// Library's import and suggestion queues among them — so the head changes
/// only where this scope says, never on the screen the group came from.
class KitDGroupHeads extends InheritedWidget {
  final bool first;
  final double gap;

  const KitDGroupHeads({
    super.key,
    this.first = false,
    this.gap = 56,
    required super.child,
  });

  static KitDGroupHeads? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitDGroupHeads>();

  @override
  bool updateShouldNotify(KitDGroupHeads old) =>
      old.first != first || old.gap != gap;
}

/// The head [KitDGroupHeads] asks for — and the program editor's groups
/// (`.dp-study .d-main .st-sec`, 48 apart, the eyebrow `margin: 0 0 6px`):
/// one line of title and, pushed to the trailing edge (wrapping under it when
/// they do not fit), the head's [trailing] parts.
class KitDGroupHead extends StatelessWidget {
  final String title;
  final List<Widget> trailing;
  final double top;
  final double bottom;

  const KitDGroupHead(
    this.title, {
    super.key,
    this.trailing = const [],
    this.top = 56,
    this.bottom = 18,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final head = Semantics(
      header: true,
      child: Text(
        title,
        style: AppTheme.serif(
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01 * 22,
          color: t.fg,
          opsz: 24,
        ).copyWith(shadows: AppShadows.letterpress),
      ),
    );
    return Container(
      margin: EdgeInsets.only(top: top, bottom: bottom),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg)),
      ),
      child: trailing.isEmpty
          ? Align(alignment: Alignment.centerLeft, child: head)
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                head,
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: trailing,
                ),
              ],
            ),
    );
  }
}

/// A group's standing sentence on a ported D page (For your review's *Dismissing
/// only clears it from here…*; web `.dp-review .review-standing`): serif
/// italic 14/21 in `--fg-lede`, 14 above the group's rows.
class KitDStanding extends StatelessWidget {
  final String text;
  const KitDStanding(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: AppTheme.serif(
        fontSize: 14,
        height: 21 / 14,
        fontStyle: FontStyle.italic,
        color: Tokens.of(context).fgLede,
      ),
    ),
  );
}
