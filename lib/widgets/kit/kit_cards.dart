import 'package:flutter/widgets.dart';
import '../../theme/app_colors.dart';
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
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.s5 : 32, vertical: 28),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: t.border),
      ),
      child: Flex(
        // The actions column sits BESIDE the content at full width and BELOW it
        // on a phone: side by side there, it squeezed the masthead until "A
        // Letter" broke across two lines and the standfirst ran four words wide.
        direction: compact ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment:
            compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _flexible(
            compact,
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
            SizedBox(
                width: compact ? 0 : AppSpacing.s6,
                height: compact ? AppSpacing.s5 : 0),
            Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.end,
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

/// `Expanded` is only valid along the flex's own axis, and the hero flips axis
/// on a phone — so the content column is expanded when the card is a row and
/// left to size itself when it is a column.
Widget _flexible(bool compact, {required Widget child}) =>
    compact ? child : Expanded(child: child);

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

/// A shelf, as a card in the library's shelves grid
/// (`screens/library.md` §Composition): a **spine stack** over the shelf name
/// in serif and a mono count.
///
/// The spines are the shelf's stored token colour at stepped opacities — the
/// one place in the app where a shelf's colour is the subject rather than a
/// marker, which is why they carry the same hairline every swatch and dot does:
/// `plum-600` and `ink-500` sit close to the dark page and vanish without it.
class KitShelfCard extends StatelessWidget {
  final String title;

  /// The shelf's `/tags.color` token name. An unrecognised value (or a legacy
  /// hex) falls back to muted rather than failing — never fail on a colour.
  final String? colorToken;

  /// Rendered under the title, e.g. `4 volumes · 213 passages`. Mono.
  final String meta;

  /// How many volumes the shelf holds — the spine count, clamped 1..9 so a
  /// large shelf stays a shelf rather than a barcode.
  final int volumes;
  final VoidCallback? onTap;

  const KitShelfCard({
    super.key,
    required this.title,
    required this.meta,
    required this.volumes,
    this.colorToken,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final spineColor = AppColors.shelfColor(colorToken) ?? t.fgSubtle;
    final n = volumes.clamp(1, 9);

    return KitCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Container(
                      width: 6,
                      height: 40 * (0.62 + ((i * 23) % 38) / 100),
                      decoration: BoxDecoration(
                        color: spineColor.withValues(
                            alpha: 0.32 + ((i * 7) % 5) * 0.14),
                        borderRadius: BorderRadius.circular(1),
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: spineColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          fontSize: 17,
                          height: 22 / 17,
                          fontWeight: FontWeight.w500,
                          color: t.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(fontSize: 11, color: t.fgSubtle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shelves grid — four columns at the Index frame, two when compact.
///
/// A fixed column count rather than a `childAspectRatio` grid: the cards size to
/// their content, and a ratio-driven grid clips a two-line shelf name at exactly
/// the widths nobody tests.
class KitCardGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final int compactColumns;
  final double gap;

  const KitCardGrid({
    super.key,
    required this.children,
    this.columns = 4,
    this.compactColumns = 2,
    this.gap = AppSpacing.s3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 560 ? compactColumns : columns;
        final width =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
