import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §5.1 — the base card: `--surface`, 1px `--border`, `--r-md`, and **shadow on
/// hover, not at rest**.
///
/// **Never put the checker on a card.** The halftone belongs to background
/// fields only — the card is a clean sheet laid *on* the checkered ground, and
/// that contrast is the whole reason it reads as lifted.
class KitCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Use `--bg` instead of `--surface` — for a card that sits *on* a surface
  /// rather than on the page (the hero card does this).
  final bool onSurface;

  const KitCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.onTap,
    this.onSurface = false,
  });

  @override
  State<KitCard> createState() => _KitCardState();
}

class _KitCardState extends State<KitCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.onSurface ? t.bg : t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
        boxShadow: _hover && widget.onTap != null ? AppShadows.s2 : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

/// §5.2 — a quoted span of a document.
///
/// Meta row → **serif quote at reading size** → action bar behind a top rule.
class KitPassageCard extends StatefulWidget {
  /// Mono page-ref and any dot-separated siblings.
  final List<String> meta;
  final Widget quote;
  final List<Widget> actions;

  const KitPassageCard({
    super.key,
    this.meta = const [],
    required this.quote,
    this.actions = const [],
  });

  @override
  State<KitPassageCard> createState() => _KitPassageCardState();
}

class _KitPassageCardState extends State<KitPassageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: t.border),
          boxShadow: _hover ? AppShadows.s1 : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.meta.isNotEmpty) ...[
              Row(
                children: [
                  for (var i = 0; i < widget.meta.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: t.fgSubtle,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(widget.meta[i],
                        style: AppTheme.mono(
                            fontSize: 11, color: t.fgSubtle)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
            widget.quote,
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: t.rule),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < widget.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.s4),
                    widget.actions[i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// §5.3 — the card that leads a screen: content column plus an actions column.
///
/// Masthead (**title + trailing issue marker**, baseline-aligned) → standfirst
/// → [KitStatCluster] → actions, bottom-aligned.
class KitHeroCard extends StatelessWidget {
  /// Accent clause written as `*clause*`.
  final String title;
  final String? marker;
  final String? standfirst;
  final List<KitStat> stats;
  final List<Widget> actions;

  const KitHeroCard({
    super.key,
    required this.title,
    this.marker,
    this.standfirst,
    this.stats = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: AccentTitle(
                        title,
                        style: AppTheme.serif(
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.018 * 24,
                          color: t.fg,
                        ),
                      ),
                    ),
                    if (marker != null) ...[
                      const SizedBox(width: AppSpacing.s3),
                      Text(marker!.toUpperCase(),
                          style: KitText.capsLabel(context, fontSize: 11)),
                    ],
                  ],
                ),
                if (standfirst != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Lede(standfirst!, fontSize: 16, height: 24),
                ],
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  KitStatCluster(stats: stats),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.s6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.s2),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One figure in a [KitStatCluster].
class KitStat {
  final String value;
  final String label;

  const KitStat(this.value, this.label);
}

/// §8 — a row of figures: a **serif numeral** over a **mono caps label**.
/// Never the reverse order, never both in the same face.
///
/// Figures shown here must be **measured**. The design prototype's numbers are
/// mock data and its progress bar is a simulated timer; a stat needs a real
/// backing signal before it gets a slot.
class KitStatCluster extends StatelessWidget {
  final List<KitStat> stats;

  /// The reader-header form: wrapped top and bottom by a `--rule`, with each
  /// stat separated by a vertical rule.
  final bool ruled;

  const KitStatCluster({super.key, required this.stats, this.ruled = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final numeralSize = ruled ? 18.0 : 24.0;

    Widget one(KitStat s, bool last) => Container(
          padding: ruled && !last
              ? const EdgeInsets.only(right: 18)
              : EdgeInsets.zero,
          decoration: ruled && !last
              ? BoxDecoration(
                  border: Border(right: BorderSide(color: t.rule)))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.value,
                style: AppTheme.serif(
                  fontSize: numeralSize,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: t.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(s.label.toUpperCase(),
                  style: KitText.capsLabel(context,
                      fontSize: 10,
                      letterSpacing: 0.1,
                      color: t.fgSubtle)),
            ],
          ),
        );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) SizedBox(width: ruled ? 14 : 22),
          one(stats[i], i == stats.length - 1),
        ],
      ],
    );

    if (!ruled) return row;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.rule),
          bottom: BorderSide(color: t.rule),
        ),
      ),
      child: row,
    );
  }
}
