import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_shell.dart' show KitGlyph;
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

/// §5.1 variant — the **connect card** (contract 4.5.2).
///
/// A surface card whose contents are fixed: **iconbox → title → subtitle →
/// status pill**. One per cloud provider on Sources, in a four-column grid.
///
/// The whole card is the affordance — a connect card with a trailing button is
/// a row wearing a card's border.
class KitConnectCard extends StatelessWidget {
  final IconData icon;
  final String title;

  /// The account when connected, the invitation when not.
  final String subtitle;

  /// Rendered as the card's [KitStatusPill].
  final String status;
  final bool connected;
  final VoidCallback? onTap;

  /// Actions that only exist once a provider is connected (browse, sync,
  /// disconnect). They sit under the pill, inside the card.
  final List<Widget> actions;

  /// A warning rendered between the subtitle and the pill — the
  /// `reconnect_required` banner (`screens/sources.md` §Trust & feedback).
  final Widget? notice;

  /// A line under the actions that says why one of them is unavailable, or
  /// what the last one answered — the sync-now 400/429 sentence
  /// (`screens/sources.md` §Sync control: "Disabled with the 400
  /// explanation"). Visible text, never a tooltip: a tooltip reaches neither a
  /// finger nor a screen reader.
  final Widget? footnote;

  const KitConnectCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.connected = false,
    this.onTap,
    this.actions = const [],
    this.notice,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // The kit's one sanctioned raw colour: the iconbox is a plate
              // holding a VENDOR's mark, and vendor artwork is tuned for light
              // surfaces. A `--surface` fill flips near-black in dark mode and
              // swallows half of them (component-kit.md §5.1).
              // literal-ok: a vendor brand-mark plate, fixed white in both
              // themes — the same class as `.connect-card .iconbox` on the web
              color: const Color(0xFFFFFFFF),
              borderRadius: AppRadius.smR,
              border: Border.all(color: t.border),
            ),
            child: Icon(icon, size: 19, color: AppColors.chrome),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 12,
              height: 1.35,
              color: t.fgMuted,
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 10),
            notice!,
          ],
          const SizedBox(height: 10),
          KitStatusPill(status, positive: connected),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s2,
              children: actions,
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: 8),
            footnote!,
          ],
        ],
      ),
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
                  // The HERO form (§8): 24px numerals, no separators. It is a
                  // form, not the absence of the `--ruled` modifier — the two
                  // were one flag here until 4.46.0, which is why every caller
                  // that wanted the reader/shelf header's separated row got the
                  // hero's metrics instead (ADR-084).
                  KitStatCluster(stats: stats, form: KitStatForm.hero),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            SizedBox(
                width: compact ? 0 : AppSpacing.s6,
                height: compact ? AppSpacing.s5 : 0),
            // On a phone the actions are a ROW that wraps, each at its own
            // width — `.letter-hero .actions { flex-direction: row;
            // flex-wrap: wrap }` (web 9a84288). A stretched column put every
            // action on its own full-width line; a nowrap row sheared the
            // last one off a 320 card.
            if (compact)
              KitActionFlow(children: actions)
            else
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

/// `Expanded` is only valid along the flex's own axis, and the hero flips axis
/// on a phone — so the content column is expanded when the card is a row and
/// left to size itself when it is a column.
Widget _flexible(bool compact, {required Widget child}) =>
    compact ? child : Expanded(child: child);

/// The unmeasured figure (component-kit §8, 4.75.0, ADR-109).
const kitUnmeasured = '—';

/// **The rule, in one place for this client** — web's `figure()` in
/// `shared/Stat.jsx`. A figure is a measurement: `value == null` is how a call
/// site says it has none (the read failed, or has not completed), and it draws
/// the em dash, never a number. `'0'` is a measurement and keeps its figure —
/// an empty library really holds zero volumes. §8's [KitStatCluster] and
/// §1.2's [KitRailCard] both call this; neither decides the dash for itself.
///
/// Every state a pattern derives from a value (a highlight, a level tint, a
/// denominator) branches on `measured`, so none of them fires on a dash.
({bool measured, String text}) kitFigure(String? value) => value == null
    ? (measured: false, text: kitUnmeasured)
    : (measured: true, text: value);

/// One figure in a [KitStatCluster].
class KitStat {
  /// Null means NOT MEASURED (ADR-109) — never pass `?? '0'` for it: a zero
  /// nothing read is the defect this type exists to make unspellable.
  final String? value;
  final String label;

  /// The `/ 12` of a `4 / 12` — **context, not a second figure**, so it sits
  /// beside the numeral at 14px `--fg-subtle` and never reads as loud as the
  /// count it qualifies (3.1.0, ADR-039).
  final String? denominator;

  const KitStat(this.value, this.label, {this.denominator});
}

/// The two forms of §8. **Which stats appear is the screen's business; how one
/// is drawn is this file's**, and the two were entangled in a single `ruled`
/// bool until 4.46.0.
enum KitStatForm {
  /// The default — serif 18/500 numerals, gap 14, each stat closed by a 1px
  /// `--rule` at 18px right padding, the last unseparated. The reader header,
  /// the source header and a shelf header all draw this.
  separated,

  /// Inside a [KitHeroCard] — gap 22, serif 24/500 numerals at line-height 1,
  /// **no separators**.
  hero,
}

/// §8 — a row of figures: a **serif numeral** over a **mono caps label**.
/// Never the reverse order, never both in the same face.
///
/// Figures shown here must be **measured**. The design prototype's numbers are
/// mock data and its progress bar is a simulated timer; a stat needs a real
/// backing signal before it gets a slot.
///
/// **[ruled] is a modifier, not a form** (4.46.0, ADR-084). §8 named the 18px
/// separated row "rule-bounded form (reader header)" and gave it top and bottom
/// rules, transcribed from `.reader-meta` — a web class that was already dead
/// when this kit was written. The reader header has never drawn them. The rules
/// are a **report** treatment, for a full-width band across the measure (admin
/// metrics, the recipe body); a header inside a screen frame does not take it.
class KitStatCluster extends StatelessWidget {
  final List<KitStat> stats;

  /// Separated row (default) or the hero card's row.
  final KitStatForm form;

  /// The `--ruled` modifier: the row additionally wrapped top and bottom by a
  /// 1px `--rule` with 12px of vertical padding. Independent of [form].
  final bool ruled;

  const KitStatCluster({
    super.key,
    required this.stats,
    this.form = KitStatForm.separated,
    this.ruled = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final hero = form == KitStatForm.hero;
    final numeralSize = hero ? 24.0 : 18.0;

    Widget one(KitStat s, bool last) => Container(
          padding: !hero && !last
              ? const EdgeInsets.only(right: 18)
              : EdgeInsets.zero,
          decoration: !hero && !last
              ? BoxDecoration(
                  border: Border(right: BorderSide(color: t.rule)))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: kitFigure(s.value).text),
                  // Dropped with the value it qualifies: "— / 12" would be a
                  // claim about a total nothing read.
                  if (s.denominator != null && kitFigure(s.value).measured)
                    TextSpan(
                      text: ' / ${s.denominator}',
                      style: AppTheme.serif(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: t.fgSubtle,
                      ),
                    ),
                ]),
                style: AppTheme.serif(
                  fontSize: numeralSize,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: kitFigure(s.value).measured ? t.fg : t.fgSubtle,
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

    final row = Wrap(
      spacing: hero ? 22 : 14,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (var i = 0; i < stats.length; i++)
          one(stats[i], i == stats.length - 1),
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

/// A shelf, as a card in the shelves grid (`screens/library.md` §Composition):
/// a **spine band** over the shelf name in serif, a mono count, and the first
/// few volume titles.
///
/// Required parts, in order: the spine band · a colour dot · the serif name ·
/// an optional provenance badge (`auto`, `split`) · the mono meta · the volume
/// lines, which say `Empty shelf` when there are none rather than leaving the
/// card short.
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

  /// The first few volume titles, as the reference shows them. Empty renders
  /// the italic `Empty shelf` line: a shelf with nothing on it is a fact about
  /// the shelf, and ADR-025 calls it a defect worth seeing, not a blank.
  final List<String> volumeTitles;

  /// Volumes beyond [volumeTitles] — `+3 more`. Zero renders nothing.
  final int moreCount;

  /// `auto` for an auto-created shelf, `split` for one split from another.
  /// **A label and nothing more** (ADR-025): provenance never rolls counts up
  /// to a parent and never nests one shelf under another.
  final String? badge;

  final VoidCallback? onTap;

  const KitShelfCard({
    super.key,
    required this.title,
    required this.meta,
    required this.volumes,
    this.volumeTitles = const [],
    this.moreCount = 0,
    this.badge,
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
          // The band is `--surface-sunken` under a `--rule`: the shelf the
          // spines stand on. Without it the bars float in the card and the
          // card stops reading as a shelf at all.
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
              ),
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Container(
                    width: 7,
                    height: 44 * (0.62 + ((i * 23) % 38) / 100),
                    decoration: BoxDecoration(
                      color: spineColor.withValues(
                          alpha: 0.32 + ((i * 7) % 5) * 0.14),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        topRight: Radius.circular(2),
                      ),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: spineColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          fontSize: 19,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: t.fg,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 9),
                      _ProvenanceBadge(badge!),
                    ],
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(fontSize: 11, color: t.fgSubtle),
                ),
                const SizedBox(height: 9),
                if (volumeTitles.isEmpty)
                  Text('Empty shelf',
                      style: AppTheme.serif(
                        fontSize: 12,
                        height: 16 / 12,
                        fontStyle: FontStyle.italic,
                        color: t.fgSubtle,
                      ))
                else
                  for (final v in volumeTitles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        v,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 13,
                          color: t.fgMuted,
                        ),
                      ),
                    ),
                if (moreCount > 0)
                  Text('+$moreCount more',
                      style: AppTheme.serif(
                        fontSize: 12,
                        height: 16 / 12,
                        fontStyle: FontStyle.italic,
                        color: t.fgSubtle,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The `auto` / `split` badge on a shelf card (`.shelf-auto-badge`) — mono 9
/// caps in a hairline box. Not a §6.3 status pill: it states where the shelf
/// came from, not what condition it is in.
class _ProvenanceBadge extends StatelessWidget {
  final String label;

  const _ProvenanceBadge(this.label);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: AppRadius.xsR,
        border: Border.all(color: t.border),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.mono(
          fontSize: 9,
          letterSpacing: 0.08 * 9,
          color: t.fgSubtle,
        ),
      ),
    );
  }
}

/// The dashed **make one** card that closes a grid (`.shelf-new`) — a plus in
/// an accent-chip disc, a serif title and a sans subtitle.
///
/// §7's posture at card scale: the offer is a place to put something, not a
/// sentence saying there is nothing here. It is dashed `--border-strong` on the
/// page ground rather than a `--surface` sheet, so it reads as a slot beside
/// the real cards instead of an eleventh shelf.
class KitNewCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const KitNewCard({
    super.key,
    this.icon = Icons.add,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  State<KitNewCard> createState() => _KitNewCardState();
}

class _KitNewCardState extends State<KitNewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 200),
          padding: const EdgeInsets.all(AppSpacing.s6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.hover : null,
            borderRadius: AppRadius.mdR,
            border: Border.all(
              color: _hover ? t.accentChipBorder : t.borderStrong,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentChipBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 20, color: t.seal),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                widget.title,
                style: AppTheme.serif(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12,
                  color: t.fgSubtle,
                ),
              ),
            ],
          ),
        ),
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

/// §5.2 at **reduced emphasis** — one message of a conversation
/// (`screens/support.md` §Composition). A variant of the passage card, not a
/// new card: the same `--r-md` sheet with a 1px border, tightened to
/// `11px 14px`, no hover shadow, and its meta row lifted **outside** the sheet
/// as the message's own mono caps timestamp+sender line.
///
/// The two sides are told apart by surface, never by alignment alone: a
/// support message takes the accent-chip roles, a user message
/// `--surface-raised`. Body sans 14/24 — this is the reader's own words to a
/// person, not a quotation from a document, so it does not take the reading
/// serif.
class KitMessageCard extends StatelessWidget {
  /// The mono caps line above the sheet: `You · 9:41 AM · /activity`.
  final List<String> meta;
  final String body;

  /// `true` for the reader's own message (trailing edge, `--surface-raised`).
  final bool mine;

  const KitMessageCard({
    super.key,
    this.meta = const [],
    required this.body,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (meta.isNotEmpty) ...[
              Text(
                meta.where((s) => s.isNotEmpty).join(' · ').toUpperCase(),
                textAlign: mine ? TextAlign.right : TextAlign.left,
                style: KitText.capsLabel(context,
                    fontSize: 10, letterSpacing: 0.12, color: t.fgSubtle),
              ),
              const SizedBox(height: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: mine ? t.surfaceRaised : t.accentChipBg,
                borderRadius: AppRadius.mdR,
                border: Border.all(color: mine ? t.border : t.accentChipBorder),
              ),
              child: Text(
                body,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 14,
                  height: 24 / 14,
                  color: mine ? t.fg : t.accentChipFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one-line note that closes a thread awaiting an answer — sans 12/17 at
/// `--fg-subtle`, on the trailing edge like the message it follows.
class KitThreadNote extends StatelessWidget {
  final String text;

  const KitThreadNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontFamily: AppTheme.fontSans,
            fontSize: 12,
            height: 17 / 12,
            color: Tokens.of(context).fgSubtle,
          ),
        ),
      );
}

/// §5.2's action-bar action: sans 12 at `--fg-lede` with a 13px icon.
///
/// It lived in `pages/search/result_card.dart` until 4.63.0, which is the
/// reference's own defect ported: `.pact` was scoped to `.passage` there, so
/// Ask's three uses of the same control rendered as unstyled browser buttons.
/// A pattern that lives in a page is a pattern the next screen re-invents —
/// Ask's citations and Search's results draw one control, and it is this one.
class KitPassageAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const KitPassageAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<KitPassageAction> createState() => _KitPassageActionState();
}

class _KitPassageActionState extends State<KitPassageAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = _hover ? t.fg : t.fgLede;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // The card itself is tappable, so this action must claim its own tap
        // rather than letting it fall through and toggle the selection too.
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A **feature card** (`.set-feature`, Settings › Setup): one offer that is a
/// place to go rather than a setting to change — a 52px `--chrome` tile with
/// the brand glyph, a serif 19/600 title over a sans 13.5/1.5 `--fg-muted`
/// line, and its one control. `--surface`, `--border`, `--r-md`, `--shadow-1`,
/// `22px 24px`. Side by side on a wide pane; below the compact width it
/// stacks, left-aligned, 14px apart — the reference's own `max-width: 640px`
/// rule. Drawn as an icon-plate setting row, the replay read as one more
/// preference among the toggles.
class KitFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  const KitFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final mark = Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.chrome,
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s1,
      ),
      child: KitGlyph(icon, size: 24, color: t.chromeFg),
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: AppTheme.serif(
                fontSize: 19, fontWeight: FontWeight.w600, color: t.fg)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 46 * 7.5),
          child: Text(description,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 13.5,
                height: 1.5,
                color: t.fgMuted,
              )),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
        boxShadow: AppShadows.s1,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark,
                const SizedBox(height: 14),
                main,
                const SizedBox(height: 14),
                action,
              ],
            )
          : Row(
              children: [
                mark,
                const SizedBox(width: 20),
                Expanded(child: main),
                const SizedBox(width: 20),
                action,
              ],
            ),
    );
  }
}
