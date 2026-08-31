import 'package:flutter/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §6.1 — the four button variants, and **the variant carries meaning**.
enum KitButtonVariant {
  /// `--accent`. The only primary CTA colour in the app.
  primary,

  /// `--secondary` — plum on paper, a white wash on ink.
  secondary,

  /// `--critical`. Destructive only.
  danger,

  /// Transparent, `--fg-muted`, fills `--hover`.
  ghost,
}

/// A kit button. Height 36, radius from its height (`0.25 × h`), sans 14/500.
///
/// Never build a button from a bare `TextButton`/`ElevatedButton`: Material's
/// defaults are a different design system, and a screen that reaches for one
/// gets Material's radius, ripple, elevation and padding — none of which appear
/// in any token file.
class KitButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final KitButtonVariant variant;

  const KitButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.variant = KitButtonVariant.primary,
  });

  const KitButton.primary(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.primary;
  const KitButton.secondary(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.secondary;
  const KitButton.danger(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.danger;
  const KitButton.ghost(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.ghost;

  @override
  State<KitButton> createState() => _KitButtonState();
}

class _KitButtonState extends State<KitButton> {
  bool _hover = false;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final disabled = widget.onPressed == null;

    late final Color bg;
    late final Color fg;
    List<BoxShadow>? shadow;

    switch (widget.variant) {
      case KitButtonVariant.primary:
        bg = _hover ? t.accentHover : t.accent;
        fg = t.accentFg;
        shadow = AppShadows.s1;
      case KitButtonVariant.secondary:
        bg = _hover ? t.secondaryHover : t.secondary;
        fg = t.secondaryFg;
      case KitButtonVariant.danger:
        // `--critical` stays brick-500 in both themes, so the label is
        // paper-50 — NOT accentFg, which flips dark and would fail contrast.
        bg = _hover ? t.criticalHover : t.critical;
        fg = t.criticalFg;
        shadow = AppShadows.s1;
      case KitButtonVariant.ghost:
        bg = _hover ? t.hover : const Color(0x00000000);
        fg = _hover ? t.fg : t.fgMuted;
    }

    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadius.controlR(_height),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 14, color: fg),
                  const SizedBox(width: AppSpacing.s2),
                ],
                // Flexible, not a bare Text: a button in a card that is a
                // quarter of the grid gets a bounded width, and a label one
                // hundredth of a pixel too wide is a striped overflow banner
                // rather than a slightly tight button.
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §6.2 — tag pill variants.
enum KitTagVariant { shelf, source, accent, ghost }

/// A pill. `3px 10px`, pill radius, sans 12/500, optional 6px leading dot.
///
/// A shelf pill takes its colour from the tag's **stored token name**. Swatches,
/// dots, plates and spines carry a hairline border in every theme — `plum-600`
/// and `ink-500` sit close to the dark-mode page and would otherwise vanish.
class KitTag extends StatelessWidget {
  final String label;
  final KitTagVariant variant;

  /// A `/tags.color` token name. Resolved via [AppColors.shelfColor]; an
  /// unrecognised value falls back to muted rather than failing.
  final String? colorToken;
  final VoidCallback? onTap;

  const KitTag(
    this.label, {
    super.key,
    this.variant = KitTagVariant.source,
    this.colorToken,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    late final Color bg;
    late final Color fg;
    Color? borderColor;

    switch (variant) {
      case KitTagVariant.shelf:
        bg = t.positiveChipBg;
        fg = t.positiveChipFg;
      case KitTagVariant.source:
        bg = t.surfaceSunken;
        fg = t.fgMuted;
      case KitTagVariant.accent:
        bg = t.accentChipBg;
        fg = t.accentChipFg;
        borderColor = t.accentChipBorder;
      case KitTagVariant.ghost:
        bg = const Color(0x00000000);
        fg = t.fgMuted;
        borderColor = t.borderStrong;
    }

    final dot = AppColors.shelfColor(colorToken);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                // The hairline that keeps plum-600 and ink-500 visible on the
                // dark page.
                border: Border.all(color: t.border, width: 0.5),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dot != null && variant == KitTagVariant.shelf ? fg : fg,
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? pill
        : GestureDetector(onTap: onTap, child: pill);
  }
}

/// §6.3 — a status pill. Mono 10 / 0.1em caps.
class KitStatusPill extends StatelessWidget {
  final String label;
  final bool positive;

  const KitStatusPill(this.label, {super.key, this.positive = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: 2),
      decoration: BoxDecoration(
        color: positive ? t.positiveChipBg : t.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: KitText.capsLabel(
          context,
          fontSize: 10,
          letterSpacing: 0.1,
          color: positive ? t.positiveChipFg : t.fgMuted,
        ),
      ),
    );
  }
}

/// §6.4 — the document plate. Portrait, tinted per type, mono 9 caps.
enum KitBadgeSize {
  /// 26×32 — inline, in a timeline row.
  inline(26, 32, 8),

  /// 36×44 — in a source row.
  row(36, 44, 9),

  /// 40×48 — in a screen header.
  header(40, 48, 10);

  final double width;
  final double height;
  final double fontSize;
  const KitBadgeSize(this.width, this.height, this.fontSize);
}

class KitFileBadge extends StatelessWidget {
  /// `pdf` · `epub` · `web` · `podcast` · `note` — anything else renders
  /// neutral. Build it from a document's `type` with [kitDocKind].
  final String kind;
  final KitBadgeSize size;

  const KitFileBadge(this.kind, {super.key, this.size = KitBadgeSize.row});

  /// The plate's own word, which is **not** the kind: an audio source's plate
  /// reads AUDIO, and an unknown kind reads DOC rather than printing whatever
  /// token was passed in. Printing the raw value is the same class of defect as
  /// showing a user the literal status `pending_upload`.
  static const _labels = <String, String>{
    'pdf': 'PDF',
    'epub': 'EPUB',
    'web': 'WEB',
    'podcast': 'AUDIO',
    'note': 'NOTE',
  };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final k = kind.toLowerCase();

    late final Color bg;
    late final Color fg;
    late final Color border;

    switch (k) {
      case 'pdf':
        bg = t.accentChipBg;
        fg = t.accentChipFg;
        border = t.accentChipBorder;
      case 'epub':
        bg = t.positiveChipBg;
        fg = t.positiveChipFg;
        border = t.positiveChipBorder;
      case 'web':
      case 'note':
      case 'podcast':
        bg = t.surfaceSunken;
        fg = t.fgMuted;
        border = t.border;
      default:
        bg = t.surfaceSunken;
        fg = t.fgMuted;
        border = t.border;
    }

    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.xsR,
        border: Border.all(color: border),
      ),
      child: Text(
        _labels[k] ?? 'DOC',
        style: AppTheme.mono(
          fontSize: size.fontSize,
          height: 1,
          letterSpacing: 0.06 * size.fontSize,
          color: fg,
        ),
      ),
    );
  }
}

/// §6.5 — a 34×34 icon button. Icon 17px.
///
/// Icon stroke weight is **1.75 everywhere**, round caps and joins. Flutter's
/// bundled Material icons have a fixed stroke, so the app uses the `_outlined`
/// set throughout — mixing filled and outlined is visible across a screen even
/// when nothing else is wrong.
class KitIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  const KitIconButton(this.icon,
      {super.key, this.onPressed, this.tooltip, this.color});

  @override
  State<KitIconButton> createState() => _KitIconButtonState();
}

class _KitIconButtonState extends State<KitIconButton> {
  bool _hover = false;
  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.hover : const Color(0x00000000),
            borderRadius: AppRadius.controlR(_size),
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: widget.color ?? (_hover ? t.fg : t.fgMuted),
          ),
        ),
      ),
    );
  }
}

/// §6.6 — the control bar (contract 4.5.2): the row of filters between a
/// screen's header and its list, **closed by a 1px `--rule`**.
///
/// The chips wrap and the trailing controls do not. A bar that lets its sort
/// control wrap puts the least important element on a line of its own.
class KitControlBar extends StatelessWidget {
  /// Filter chips. They take the leading side and wrap.
  final List<Widget> filters;

  /// Sort / view controls. They neither wrap nor shrink.
  final List<Widget> trailing;

  const KitControlBar({
    super.key,
    this.filters = const [],
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;

    final chips = Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: filters,
    );
    final tail = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < trailing.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          trailing[i],
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: compact
          // Below the compact width the bar stacks, chips first — the same
          // rule the web reference applies at 680px.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chips,
                if (trailing.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Align(alignment: Alignment.centerLeft, child: tail),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: chips),
                if (trailing.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.s4),
                  tail,
                ],
              ],
            ),
    );
  }
}

/// §6.7 — a filter chip. **Not a tag pill**: §6.2 labels an object, this
/// narrows a list and answers to a click.
///
/// Selection changes **fill, border and foreground together**, never colour
/// alone. A chip whose count is zero renders **disabled, not hidden** — the
/// chip set is a vocabulary (the document `type` enum, the event families), and
/// dropping the empty ones reshapes the bar per library, so the same filter
/// sits somewhere different for every user.
class KitFilterChip extends StatefulWidget {
  final String label;

  /// The trailing count, in the mono face. Null renders no count at all —
  /// which is not the same as `0`, and `0` is what disables the chip.
  final int? count;
  final bool selected;
  final VoidCallback? onPressed;

  const KitFilterChip(
    this.label, {
    super.key,
    this.count,
    this.selected = false,
    this.onPressed,
  });

  @override
  State<KitFilterChip> createState() => _KitFilterChipState();
}

class _KitFilterChipState extends State<KitFilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final disabled = widget.onPressed == null;

    final Color bg = widget.selected ? t.accentSoft : t.surface;
    final Color borderColor = widget.selected
        ? t.accentChipBorder
        : (_hover ? t.borderStrong : t.border);
    final Color fg = widget.selected
        ? t.accentChipFg
        : (_hover ? t.fg : t.fgMuted);

    return MouseRegion(
      cursor:
          disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Opacity(
          opacity: disabled ? 0.4 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
                if (widget.count != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    '${widget.count}',
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One position of a [KitSegmented].
class KitSegment {
  final String label;
  final IconData? icon;

  const KitSegment(this.label, {this.icon});
}

/// §6.8 — the segmented control: letter tabs, summary style, sort order.
///
/// **The selection is a raise, not a tint.** The selected segment lifts onto
/// `--surface` with `--shadow-1`, the same way the rail marks its active item.
/// Recolouring in place leaves two flat labels that differ only in shade — and
/// in dark mode, barely.
class KitSegmented extends StatelessWidget {
  final List<KitSegment> segments;
  final int selected;
  final ValueChanged<int>? onChanged;

  /// Fill the available width, segments flexing equally — what the reference
  /// does below 680px, and what a phone always wants.
  final bool expand;

  const KitSegmented({
    super.key,
    required this.segments,
    required this.selected,
    this.onChanged,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
          // Filling needs a width to fill. A segmented control also sits inside
          // a `Wrap`, an `Align` or a shrink-wrapping row — all unbounded — and
          // `Expanded` there is not a layout that looks wrong, it is an
          // assertion that takes the whole screen down. The device run caught
          // exactly this on the organization panel.
          return _build(context,
              fill: (expand || compact) && constraints.hasBoundedWidth);
        },
      );

  Widget _build(BuildContext context, {required bool fill}) {
    final t = Tokens.of(context);

    Widget segment(int i) {
      final s = segments[i];
      final on = i == selected;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
                horizontal: fill ? 8 : 14, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? t.surface : const Color(0x00000000),
              borderRadius: AppRadius.xsR,
              boxShadow: on ? AppShadows.s1 : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.icon != null) ...[
                  Icon(s.icon,
                      size: 14, color: on ? t.fg : t.fgMuted),
                  const SizedBox(width: 7),
                ],
                Text(
                  s.label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: on ? t.fg : t.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.smR,
      ),
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            fill ? Expanded(child: segment(i)) : segment(i),
          ],
        ],
      ),
    );
  }
}

/// The mono caps label that names a trailing control in a [KitControlBar]
/// ("Order by"). Sits beside the control, not above it.
class KitControlLabel extends StatelessWidget {
  final String text;

  const KitControlLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: KitText.capsLabel(context,
            fontSize: 10,
            letterSpacing: 0.1,
            color: Tokens.of(context).fgSubtle),
      );
}

/// A document `type` → the plate kind ([KitFileBadge]).
///
/// Mirrors the web reference's `docKind` exactly, including that every web-ish
/// source (article, YouTube, Instagram, TikTok) shares one plate: the plate says
/// where a source came from, not which service it came through.
String kitDocKind(String type) {
  switch (type) {
    case 'pdf':
      return 'pdf';
    case 'epub':
      return 'epub';
    // `audio` (4.10.0) shares the podcast kind: both are timestamped
    // transcripts with real audio behind them, and the badge already reads
    // AUDIO. Missing here since 4.10.0, so every uploaded voice memo badged
    // NOTE on this client while web badged it AUDIO.
    case 'podcast':
    case 'audio':
      return 'podcast';
    // `video` (4.13.0, ADR-049) gets its OWN kind rather than joining audio:
    // it is indexed from its audio track alone but it is not a recording, and
    // labelling a lecture video AUDIO is the conflation ADR-049 refused.
    case 'video':
      return 'video';
    case 'url':
    case 'article':
    case 'youtube':
    case 'instagram':
    case 'tiktok':
      return 'web';
    default:
      return 'note';
  }
}
