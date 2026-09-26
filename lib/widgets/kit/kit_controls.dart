import 'package:flutter/material.dart'
    show
        Checkbox,
        CircularProgressIndicator,
        DropdownButton,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        Icons,
        InputBorder,
        InputDecoration,
        LinearProgressIndicator,
        TextField,
        TextInputType,
        Tooltip;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

part 'kit_proc.dart';

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

  /// The QUIET destructive control (`.ss-delete`): no fill, no padding, sans
  /// 13 at `--critical-text` behind a 14px glyph, underlined on hover. A
  /// destructive action at rest in a settings panel is a sentence, not a
  /// filled button — the §18 confirm it opens carries the filled one.
  dangerText,
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

  /// The glyph after the label, not before it — an advance control
  /// (onboarding's `Begin →`, `IcoArrowR` after the text on the reference).
  final bool iconTrailing;

  /// Centre the label when the button is given more width than it needs —
  /// `.nl-actions .btn { justify-content: center }`, a button a
  /// [KitActionFlow] grows across its line. `.btn` itself starts its content
  /// at the left, so this is opt-in, never the default.
  final bool center;

  const KitButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.variant = KitButtonVariant.primary,
    this.iconTrailing = false,
    this.center = false,
  });

  const KitButton.primary(this.label,
      {super.key, this.icon, this.onPressed, this.iconTrailing = false})
      : variant = KitButtonVariant.primary,
        center = false;
  const KitButton.secondary(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.secondary,
        iconTrailing = false,
        center = false;
  const KitButton.danger(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.danger,
        iconTrailing = false,
        center = false;
  const KitButton.dangerText(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.dangerText,
        iconTrailing = false,
        center = false;
  const KitButton.ghost(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.ghost,
        iconTrailing = false,
        center = false;

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
      case KitButtonVariant.dangerText:
        bg = const Color(0x00000000);
        fg = t.criticalText;
    }
    final quiet = widget.variant == KitButtonVariant.dangerText;
    final glyph = widget.icon == null
        ? null
        : Icon(widget.icon, size: 14, color: fg);

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
            height: quiet ? null : _height,
            padding: quiet
                ? const EdgeInsets.symmetric(vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadius.controlR(_height),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: widget.center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (glyph != null && !widget.iconTrailing) ...[
                  glyph,
                  SizedBox(width: quiet ? 7 : AppSpacing.s2),
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
                      fontSize: quiet ? 13 : 14,
                      height: 1,
                      fontWeight: quiet ? FontWeight.w400 : FontWeight.w500,
                      color: fg,
                      decoration: quiet && _hover
                          ? TextDecoration.underline
                          : null,
                      decorationColor: fg,
                    ),
                  ),
                ),
                if (glyph != null && widget.iconTrailing) ...[
                  const SizedBox(width: AppSpacing.s2),
                  glyph,
                ],
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

  /// A trailing `×` inside the pill — a chip that stands for one member of a
  /// set the reader can shrink (the sync-folder scope, `sources.md` §Sync
  /// control: "chips with remove affordances"). Null draws no control, and a
  /// set that cannot shrink right now passes null rather than a dead `×`.
  final VoidCallback? onRemove;

  /// What the `×` does, for a screen reader — the glyph alone says nothing
  /// about WHICH member it removes.
  final String? removeLabel;

  const KitTag(
    this.label, {
    super.key,
    this.variant = KitTagVariant.source,
    this.colorToken,
    this.onTap,
    this.onRemove,
    this.removeLabel,
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
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: removeLabel ?? 'Remove $label',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Icon(Icons.close, size: 12, color: fg),
                ),
              ),
            ),
          ],
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

  /// 34×42, mono 9 — a chapter opening's **lead** (component-kit §6.4 at
  /// 4.98.0: `.ch-folio-row .filebadge`, the reader's header). It was 40×48
  /// from `.reader-head .filebadge`, a dead class the reader never mounts
  /// (ADR-131).
  header(34, 42, 9),

  /// 30×38 — on a source card (`.src-card .filebadge`).
  card(30, 38, 9),

  /// 32×40 — on a processing card (`.proc-row .filebadge`).
  proc(32, 40, 9),

  /// Content-sized — the plate is its label and a hairline, no fixed box: a
  /// readings-day passage card's head (`.sc-p-h .filebadge`, which sets no
  /// width or height), where a 36×44 row plate made each quoted passage read
  /// as a source row.
  chip(null, null, 9);

  /// `null` for [chip]: the plate sizes to its label.
  final double? width;
  final double? height;
  final double fontSize;
  const KitBadgeSize(this.width, this.height, this.fontSize);
}

class KitFileBadge extends StatelessWidget {
  /// `pdf` · `epub` · `web` · `youtube` · `instagram` · `tiktok` · `podcast` · `note` — anything else renders
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
    // Platform plates abbreviate (4.84.0): a plate is too narrow for a brand
    // name; every surface with room spells it.
    'youtube': 'YT',
    'instagram': 'IG',
    'tiktok': 'TT',
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
      case 'youtube':
      case 'instagram':
      case 'tiktok':
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
      alignment: size.width == null ? null : Alignment.center,
      // A chip's hairline sits a breath off its glyphs; the reference's
      // content-sized plate has none, and its border touches the letters.
      padding: size.width == null
          ? const EdgeInsets.symmetric(horizontal: 3, vertical: 2)
          : null,
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

/// §6.5 — a 34×34 icon button. Icon 17px. [tooltip] is web's `title` +
/// `aria-label`: shown on hover (long-press on touch) and read as the label.
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
    final button = _button(context);
    final tip = widget.tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }

  Widget _button(BuildContext context) {
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

/// A row of actions that **wraps rather than overflows** — CSS
/// `display: flex; flex-wrap: wrap; gap` over the children, with [grow] as
/// `flex: 1` on each of them.
///
/// Each child keeps at least its natural (max-intrinsic) width; a child that
/// cannot fit beside the ones already on a line starts the next. With [grow],
/// the children on each line then share that line — equally, except where a
/// natural width beats the equal share (a flex item never shrinks below its
/// min-content) — which is `.nl-actions { flex-wrap: wrap } .btn { flex: 1 }`
/// on the Letters card. Without it they stay at their natural width,
/// `.letter-hero .actions { flex-direction: row; flex-wrap: wrap }`.
///
/// Why not `Wrap`: a `Wrap` cannot grow its children, and a `Row` of
/// `Expanded` cannot wrap. At 320 the Letters card's three actions held a
/// nowrap line open past the card (web `9a84288`, gate:phone); a child wider
/// than the whole line is given the line and left to ellipsise its label.
class KitActionFlow extends MultiChildRenderObjectWidget {
  final bool grow;
  final double spacing;
  final double runSpacing;

  const KitActionFlow({
    super.key,
    required super.children,
    this.grow = false,
    this.spacing = AppSpacing.s2,
    this.runSpacing = AppSpacing.s2,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderActionFlow(grow: grow, spacing: spacing, runSpacing: runSpacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderActionFlow)
      ..grow = grow
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _FlowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderActionFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FlowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FlowParentData> {
  _RenderActionFlow(
      {required bool grow, required double spacing, required double runSpacing})
      : _grow = grow,
        _spacing = spacing,
        _runSpacing = runSpacing;

  bool _grow;
  set grow(bool v) {
    if (v == _grow) return;
    _grow = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FlowParentData) {
      child.parentData = _FlowParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = childAfter(c);
    }
    return out;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _kids.fold(0.0, (m, c) {
        final w = c.getMinIntrinsicWidth(height);
        return w > m ? w : m;
      });

  @override
  double computeMaxIntrinsicWidth(double height) {
    final kids = _kids;
    if (kids.isEmpty) return 0;
    return kids.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height)) +
        _spacing * (kids.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _layout(width, dry: true).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _layout(width, dry: true).height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_layout(constraints.maxWidth, dry: true));

  @override
  void performLayout() {
    size = constraints.constrain(_layout(constraints.maxWidth, dry: false));
  }

  /// Lines by natural width, then each child's width on its line, then (when
  /// not [dry]) the real layout and the offsets.
  Size _layout(double avail, {required bool dry}) {
    final kids = _kids;
    if (kids.isEmpty) return Size.zero;
    final natural = [
      for (final c in kids)
        (avail.isFinite
                ? c.getMaxIntrinsicWidth(double.infinity).clamp(0.0, avail)
                : c.getMaxIntrinsicWidth(double.infinity))
            .toDouble(),
    ];
    final lines = <List<int>>[];
    var line = <int>[];
    var used = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final need = natural[i] + (line.isEmpty ? 0 : _spacing);
      if (line.isNotEmpty && avail.isFinite && used + need > avail) {
        lines.add(line);
        line = <int>[];
        used = 0;
      }
      used += natural[i] + (line.isEmpty ? 0 : _spacing);
      line.add(i);
    }
    lines.add(line);

    final widths = List<double>.from(natural);
    if (_grow && avail.isFinite) {
      for (final l in lines) {
        final space = avail - _spacing * (l.length - 1);
        final frozen = <int, double>{};
        while (true) {
          final free = l.where((i) => !frozen.containsKey(i)).toList();
          if (free.isEmpty) break;
          final left = space - frozen.values.fold(0.0, (a, b) => a + b);
          final share = left / free.length;
          final over = free.where((i) => natural[i] > share).toList();
          if (over.isEmpty) {
            for (final i in free) {
              frozen[i] = share;
            }
            break;
          }
          for (final i in over) {
            frozen[i] = natural[i];
          }
        }
        for (final i in l) {
          widths[i] = frozen[i]!.floorToDouble();
        }
      }
    }

    var y = 0.0;
    var maxW = 0.0;
    for (var li = 0; li < lines.length; li++) {
      final l = lines[li];
      final sizes = <Size>[];
      for (final i in l) {
        final cons = _grow && avail.isFinite
            ? BoxConstraints.tightFor(width: widths[i])
            : BoxConstraints(maxWidth: widths[i]);
        if (dry) {
          sizes.add(kids[i].getDryLayout(cons));
        } else {
          kids[i].layout(cons, parentUsesSize: true);
          sizes.add(kids[i].size);
        }
      }
      final lineH = sizes.fold(0.0, (m, s) => s.height > m ? s.height : m);
      var x = 0.0;
      for (var k = 0; k < l.length; k++) {
        if (!dry) {
          (kids[l[k]].parentData! as _FlowParentData).offset =
              Offset(x, y + (lineH - sizes[k].height) / 2);
        }
        x += sizes[k].width + (k < l.length - 1 ? _spacing : 0);
      }
      if (x > maxW) maxW = x;
      y += lineH + (li < lines.length - 1 ? _runSpacing : 0);
    }
    return Size(_grow && avail.isFinite ? avail : maxW, y);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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

  /// The bar's own width below which it stacks even on a wide window — the
  /// width the reference's `.browse-controls` gives up its one line at
  /// (720, web 9a84288). A wide window with the rail beside the page can hand
  /// the bar less than that, and a trailing slot that neither wraps nor
  /// shrinks then left the chips a few pixels once Sources' view toggle
  /// joined the sort (F-65).
  static const double _stackBelow = 720;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => _build(
          context,
          compact: MediaQuery.sizeOf(context).width < AppSpacing.compactWidth ||
              (c.hasBoundedWidth && c.maxWidth < _stackBelow),
        ),
      );

  Widget _build(BuildContext context, {required bool compact}) {
    final t = Tokens.of(context);

    final chips = Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: filters,
    );
    // §6.6: the trailing slot neither wraps nor shrinks — at the width the
    // reference bar is drawn at. Below the compact breakpoint the bar has
    // already stacked, and the slot wraps BETWEEN its items rather than
    // overflowing: a Row that cannot fit does not shrink, it paints the
    // striped bar and clips whatever is last, which on search was the measured
    // count sitting beside two segmented controls. Each control stays whole —
    // what wraps is the boundary between them, never a track (§6.8).
    final tail = compact
        ? Wrap(
            spacing: 10,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: trailing,
          )
        : Row(
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
                // Flexible (4.84.0): a chip wider than the whole chip column
                // (a brand label at a narrow bar) ellipsises instead of
                // painting the overflow stripe.
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
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

  /// Draw the icon alone in a 32×30 cell — the reference's `.view-toggle
  /// .vt-btn` (list / cards / shelf), which is this same sunken track with the
  /// same raised selection, holding glyphs instead of words. [label] is then
  /// the segment's accessible name, never drawn.
  final bool iconOnly;

  const KitSegment(this.label, {this.icon}) : iconOnly = false;

  const KitSegment.icon(IconData this.icon, this.label) : iconOnly = true;
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
          // A view toggle keeps its cells' own width at every size: the
          // reference's `.vt-btn` is 32px on a phone too.
          final glyphs = segments.every((s) => s.iconOnly);
          return _build(context,
              fill: !glyphs &&
                  (expand || compact) &&
                  constraints.hasBoundedWidth);
        },
      );

  Widget _build(BuildContext context, {required bool fill}) => _segTrack(
        context,
        segments: segments,
        fill: fill,
        isOn: (i) => i == selected,
        onTap: onChanged,
      );
}

/// §6.8 — the same track, holding a **set** of raised segments.
///
/// The notifications editor's level picker (`screens/notifications.md` §The
/// editor — "a multiselect over error · warning · success · info") is drawn
/// by the reference with the segmented control's own class: one sunken track,
/// every chosen level raised. Same anatomy, same raise, same metrics — only
/// the arity of the selection differs, so it shares the track rather than
/// re-deriving it (the `Wrap` of `FilterChip`s it replaced was inline
/// composition by definition).
class KitSegmentedMulti extends StatelessWidget {
  final List<KitSegment> segments;
  final Set<int> selected;
  final ValueChanged<int>? onToggle;
  final bool expand;

  const KitSegmentedMulti({
    super.key,
    required this.segments,
    required this.selected,
    this.onToggle,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
          return _segTrack(
            context,
            segments: segments,
            fill: (expand || compact) && constraints.hasBoundedWidth,
            isOn: selected.contains,
            onTap: onToggle,
          );
        },
      );
}

/// The §6.8 track, drawn once for both arities.
Widget _segTrack(
  BuildContext context, {
  required List<KitSegment> segments,
  required bool fill,
  required bool Function(int) isOn,
  required ValueChanged<int>? onTap,
}) {
  final t = Tokens.of(context);

  Widget segment(int i) {
    final s = segments[i];
    final on = isOn(i);
    if (s.iconOnly) {
      // `.vt-btn`: 32×30, radius 4, the glyph 16 in --fg-muted, --fg when on.
      return Semantics(
        button: true,
        selected: on,
        label: s.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 32,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? t.surface : const Color(0x00000000),
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                boxShadow: on ? AppShadows.s1 : null,
              ),
              child: Icon(s.icon, size: 16, color: on ? t.fg : t.fgMuted),
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          // `.seg button { padding: 7px 10px }`. Filling no longer shares the
          // track EQUALLY (which ellipsised "Successes" on a 390pt phone,
          // F-46): [_segLines] gives each segment at least its label, the way
          // flex:1 with a min-content floor does, and wraps when they cannot.
          padding: EdgeInsets.symmetric(
              horizontal: fill ? _segPadX : 14, vertical: 7),
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
                Icon(s.icon, size: 14, color: on ? t.fg : t.fgMuted),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: on ? t.fg : t.fgMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final decoration = BoxDecoration(
    color: t.surfaceSunken,
    borderRadius: AppRadius.smR,
  );
  if (!fill) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: _segGap),
            segment(i),
          ],
        ],
      ),
    );
  }
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: decoration,
    child: LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final base = DefaultTextStyle.of(context).style;
      final natural = [
        for (final s in segments) _segNaturalWidth(s, base, scaler),
      ];
      final lines = _segLines(natural, constraints.maxWidth);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var l = 0; l < lines.length; l++) ...[
            if (l > 0) const SizedBox(height: _segGap),
            Row(children: [
              for (var k = 0; k < lines[l].length; k++) ...[
                if (k > 0) const SizedBox(width: _segGap),
                SizedBox(
                  width: lines[l][k].width,
                  child: segment(lines[l][k].index),
                ),
              ],
            ]),
          ],
        ],
      );
    }),
  );
}

const double _segGap = 2;
const double _segPadX = 10;

/// A segment's max-content width: its label (and icon) plus `.seg button`'s
/// inline padding — what CSS floors a `flex: 1` item at.
double _segNaturalWidth(KitSegment s, TextStyle base, TextScaler scaler) {
  // Measured in the style the label is DRAWN in — the ambient style merged
  // with the segment's own, since a Text inherits whatever it does not set.
  final tp = TextPainter(
    text: TextSpan(
      text: s.label,
      style: base.merge(const TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      )),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final icon = s.icon != null ? 14 + 7 : 0;
  return (tp.width + icon + 2 * _segPadX).ceilToDouble();
}

/// `.seg { flex-wrap: wrap; gap: 2px }` over `button { flex: 1 }`: segments
/// fill their line in shares that are equal except where a label needs more
/// (a flex item never shrinks below its min-content), and a segment that
/// cannot fit on the current line starts the next one. Returns, per line,
/// each segment's index and resolved width.
List<List<({int index, double width})>> _segLines(
    List<double> natural, double avail) {
  final lines = <List<int>>[];
  var line = <int>[];
  var used = 0.0;
  for (var i = 0; i < natural.length; i++) {
    final need = natural[i] + (line.isEmpty ? 0 : _segGap);
    if (line.isNotEmpty && used + need > avail) {
      lines.add(line);
      line = <int>[];
      used = 0;
    }
    used += natural[i] + (line.isEmpty ? 0 : _segGap);
    line.add(i);
  }
  if (line.isNotEmpty) lines.add(line);

  return [
    for (final l in lines) _segResolve(l, natural, avail),
  ];
}

List<({int index, double width})> _segResolve(
    List<int> line, List<double> natural, double avail) {
  final space = (avail - _segGap * (line.length - 1)).clamp(0.0, avail);
  // Freeze every item whose floor beats the equal share, then re-share what
  // is left among the rest — the flex algorithm's min-violation loop.
  final frozen = <int, double>{};
  while (true) {
    final free = line.where((i) => !frozen.containsKey(i)).toList();
    if (free.isEmpty) break;
    final left = space - frozen.values.fold(0.0, (a, b) => a + b);
    final share = left / free.length;
    final over = free.where((i) => natural[i] > share).toList();
    if (over.isEmpty) {
      for (final i in free) {
        frozen[i] = share;
      }
      break;
    }
    for (final i in over) {
      frozen[i] = natural[i];
    }
  }
  return [
    for (final i in line) (index: i, width: frozen[i]!.floorToDouble()),
  ];
}

/// The switch (`.switch`, app-responsive.css): a 38×22 pill, `--surface-sunken`
/// with a 1px `--border` at rest and the accent fill when on, a 16px knob that
/// travels 2 → 18. Used by every setting row that is a yes/no.
///
/// **Write before move.** This widget has no state of its own: it draws
/// [value] and reports [onChanged]. The screen awaits its request and only
/// then re-renders with the new value — a switch that flips first hides the
/// failure until reload (component-kit.md §Rules, ADR-022).
class KitSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  const KitSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.tooltip,
  });

  static const double _w = 38;
  static const double _h = 22;
  static const double _knob = 16;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      toggled: value,
      label: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _w,
            height: _h,
            decoration: BoxDecoration(
              color: value ? t.accent : t.surfaceSunken,
              borderRadius: AppRadius.pillR(_h),
              border: Border.all(
                color: value ? const Color(0x00000000) : t.border,
              ),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  top: 2,
                  left: value ? _w - _knob - 4 : 2,
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: const BoxDecoration(
                      // literal-ok: a switch knob is white on both of its
                      // grounds — the accent fill when on, --surface-sunken
                      // when off — which is the control's convention, not a
                      // surface that flips (`.switch i` on the web).
                      color: Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.s1,
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

/// The bordered text field (`.timefield`): 1px `--border`, `--r-sm`,
/// `--surface`, padding `10px 14px`, an optional 16px leading icon at
/// `--fg-muted`, and the value in the **mono** face at 15 — an address, a time,
/// a label are all data the reader typed, and the reference sets them mono.
///
/// [face] picks the typeface role for the value and its placeholder — mono by
/// default, because that is the data-field case above. A field whose value is
/// a *name* or a *sentence* is not data: web's shelf form sets the name in
/// `.ss-input` (serif 15) and "What belongs here?" in `.sf-desc` (sans 13/1.45),
/// and drawing either in mono read as a different form. The frame is the same
/// for every face; only the type changes.
class KitTextField extends StatefulWidget {
  final TextEditingController controller;
  final KitFieldFace face;
  final String? placeholder;
  final IconData? icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  /// More than one line makes a note field; the frame is unchanged.
  final int minLines;
  final int maxLines;

  /// False while the write the field feeds is in flight (write before move).
  final bool enabled;

  /// The server's own bound, enforced as the reader types — no counter is
  /// drawn: a refusal past it is still the server's sentence (§14.2).
  final int? maxLength;
  final bool autofocus;

  const KitTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.icon,
    this.keyboardType,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.maxLength,
    this.autofocus = false,
    this.face = KitFieldFace.mono,
  });

  @override
  State<KitTextField> createState() => _KitTextFieldState();
}

class _KitTextFieldState extends State<KitTextField> {
  // `.ss-input:focus` draws the accent border and a 4px `--accent-soft` ring;
  // `.timefield` (the mono data field) draws no focus state at all, so the
  // ring belongs to the serif and sans faces only.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  // Tracking is pinned to 0 on EVERY face: a TextField merges its style over
  // the Material 3 `bodyLarge`, whose 0.5 letter-spacing otherwise leaks in —
  // F-38 found it on the serif and sans faces and pinned those; the mono
  // `.timefield` kept it, so every data field (an address, a time) drew ~8%
  // wider than web's for as long as the kit had one (F-49).
  TextStyle _style(Color color) => switch (widget.face) {
        // `.timefield input`
        KitFieldFace.mono =>
          AppTheme.mono(fontSize: 15, color: color, letterSpacing: 0),
        // `.ss-input`
        KitFieldFace.serif =>
          AppTheme.serif(fontSize: 15, color: color, letterSpacing: 0),
        // `.sf-desc`
        KitFieldFace.sans => TextStyle(
            fontFamily: AppTheme.fontSans,
            fontSize: 13,
            height: 1.45,
            letterSpacing: 0,
            color: color,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ring = widget.face != KitFieldFace.mono && _focus.hasFocus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.smR,
        border: Border.all(color: ring ? t.accent : t.border),
        boxShadow: ring
            ? [BoxShadow(color: t.accentSoft, spreadRadius: 4)]
            : null,
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 16, color: t.fgMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              inputFormatters: widget.maxLength == null
                  ? null
                  : [LengthLimitingTextInputFormatter(widget.maxLength)],
              style: _style(t.fg),
              cursorColor: t.accent,
              // The frame above IS the field. `InputDecoration.collapsed`
              // clears `border` and nothing else, so `app_theme`'s
              // `inputDecorationTheme.enabledBorder` went on applying — every
              // kit field drew a SECOND rounded field inside the first, on
              // every screen that has one, and each piece was individually
              // correct. Each border state is suppressed by name (4.54.x,
              // F-08).
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: _style(t.fgSubtle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The typeface role of a [KitTextField]'s value (design-tokens.md §Type:
/// serif for reading and names, sans for UI sentences, mono for data).
enum KitFieldFace {
  /// Geist Mono 15 — data the reader typed: an address, a time, a label.
  mono,

  /// Source Serif 15 (`.ss-input`) — a name: a shelf's title.
  serif,

  /// Geist 13/1.45 (`.sf-desc`) — a sentence: a shelf's description.
  sans,
}

/// A labelled field group (`.cfg-group` + `.cfg-label`): a mono caps label,
/// with an optional trailing note in the accent text role ("optional"), over
/// the control; groups stack with a 1px `--rule` between them, none above the
/// first. The settings-form rhythm — the same block letter settings uses.
class KitFieldGroup extends StatelessWidget {
  final String label;
  final String? note;
  final Widget child;
  final bool first;

  /// `.cfg-second` — letter settings' readings-letter group: 20px of top
  /// padding and a 4px gap above, because it opens a second letter rather
  /// than another field of the first.
  final bool second;

  const KitFieldGroup({
    super.key,
    required this.label,
    this.note,
    required this.child,
    this.first = false,
    this.second = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: EdgeInsets.only(top: second ? 4 : 0),
      padding: EdgeInsets.only(top: second ? 20 : 18, bottom: 18),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: t.rule, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: KitText.capsLabel(context,
                    fontSize: 10, letterSpacing: 0.12),
              ),
              if (note != null)
                Text(
                  note!,
                  style: AppTheme.mono(fontSize: 11, color: t.accentText),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          child,
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

/// The document-kind vocabulary (component-kit.md §6.4.1) — **one
/// declaration, read in both directions**, exactly as the web reference
/// declares it (`src/shared/FileBadge.jsx` `KIND_BY_TYPE`).
///
/// [kitDocKind] maps a backend `type` to its coarse kind for the plate;
/// [kitTypesForKind] inverts the same table into the `sourceTypes` a chip
/// sends. It was a `switch` until 4.40.0, which cannot be inverted — and a
/// hand-written inverse beside it would be a second copy of the vocabulary,
/// which is how `podcast` and `video` came to have a chip on one screen of
/// three (ADR-064). The table is what `doc_kind_check.py` reads.
const Map<String, String> kKindByType = <String, String>{
  'pdf': 'pdf',

  // `epub` is a PENDING kind (§6.4.1 rule 3): rendered, never advertised, and
  // no document can carry it until EPUB ingestion exists.
  'epub': 'epub',

  // The default bucket, named explicitly rather than left to the fallthrough —
  // an exhaustive table is what the gate can check, and it is what makes the
  // inverse able to answer for `note` at all.
  'plain': 'note',
  'docx': 'note',
  'pptx': 'note',
  'image': 'note',
  'image_set': 'note',

  // A web page shares one plate with its legacy alias.
  'article': 'web',
  // Legacy alias of `article`, kept so pre-2.0 documents render (§6.4.1).
  'url': 'web',

  // The platforms are their OWN kinds (4.84.0, ADR-118), named by brand. They
  // were `web` until then, so a reel filed beside an essay under "Web" and the
  // Web chip returned both. The brand IS the kind.
  'youtube': 'youtube',
  'instagram': 'instagram',
  'tiktok': 'tiktok',

  // `audio` (4.10.0) shares the podcast kind: both are timestamped transcripts
  // with real audio behind them, and the badge already reads AUDIO.
  'podcast': 'podcast',
  'audio': 'podcast',

  // `video` (4.13.0, ADR-049) gets its OWN kind rather than joining audio: it
  // is indexed from its audio track alone but it is not a recording, and
  // labelling a lecture video AUDIO is the conflation ADR-049 refused.
  'video': 'video',
};

/// The source-shape vocabulary (component-kit.md §6.4.2, 4.37.0 ADR-075) —
/// the **second** vocabulary over the same `type` column, and the reason it is
/// a table: what a document *renders as* (§6.4.1 above) is not what its source
/// *is*, and every call site used to infer the second from `gcs_path != null`.
///
/// That is a two-value test over a three-value world, and it files an
/// `image_set` — many objects, no single `gcs_path` — in the `link` branch,
/// which draws **Open the link** over a null.
///
/// `epub` is deliberately absent, as in the reference: it is a pending KIND
/// with no writable `type`, so shaping it would be a branch with no subject.
const Map<String, String> kShapeByType = <String, String>{
  // `file` — one stored object, signable by `fn_get_raw_document_url`. Written
  // by `fn_create_upload_session` BEFORE a byte is uploaded, so the shape
  // holds in every status, `error` and `pending_upload` included.
  'pdf': 'file',
  'docx': 'file',
  'pptx': 'file',
  'image': 'file',
  'plain': 'file',
  'audio': 'file',
  'video': 'file',

  // `link` — no stored object at all; `source_url` is the whole source. It
  // never calls the endpoint: there is nothing to sign.
  'article': 'link',
  'youtube': 'link',
  'instagram': 'link',
  'tiktok': 'link',
  'podcast': 'link',
  'url': 'link',

  // `set` — many objects (`gcs_paths[]`), no single one. The endpoint signs
  // one `gcs_path`, so it answers `signed_url: null` here by construction and
  // carries the pages in `members` instead.
  'image_set': 'set',
};

/// A document's source shape, from its `type`.
///
/// The field fallbacks are defensive only, for a `type` no release has heard
/// of — `doc_kind_check.py`'s SHAPE direction fails on any writable type the
/// table misses, so they are never load-bearing.
String kitSourceShape({String? type, String? gcsPath, String? sourceUrl}) {
  final declared = kShapeByType[type];
  if (declared != null) return declared;
  if (gcsPath != null && gcsPath.isNotEmpty) return 'file';
  if (sourceUrl != null && sourceUrl.isNotEmpty) return 'link';
  return 'set';
}

/// A document `type` → the plate kind ([KitFileBadge]).
String kitDocKind(String type) => kKindByType[type] ?? 'note';

/// Every backend `type` a kind renders — the `sourceTypes` a chip should send.
///
/// Empty for a kind no type maps to (a pending kind), which correctly sends no
/// filter rather than a filter that can match nothing.
List<String> kitTypesForKind(String kind) =>
    kKindByType.keys.where((t) => kKindByType[t] == kind).toList();


/// The reference's `select` inside a `.timefield` frame: the same bordered
/// surface as [KitTextField], holding one chosen value and opening a list.
/// Drawn from tokens — Material's dropdown chrome is replaced, not themed.
class KitSelect<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;
  final IconData? icon;

  /// The chosen value's face. A select is not a typed field: web's
  /// `.timefield select` sets it in the SANS at 14 — a zone is a choice from a
  /// list, not data the reader typed — and that is the default here. It drew
  /// mono 15 (the text field's data face) until F-51 put the letter-settings
  /// zone beside the reference. The re-shelve picker is `.ss-input`, a shelf
  /// NAME, and passes [KitFieldFace.serif].
  final KitFieldFace? face;

  const KitSelect({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    this.onChanged,
    this.icon,
    this.face,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.smR,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: t.fgMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                dropdownColor: t.surface,
                iconEnabledColor: t.fgMuted,
                style: face == KitFieldFace.serif
                    ? AppTheme.serif(fontSize: 15, color: t.fg)
                    : face == KitFieldFace.mono
                        ? AppTheme.mono(fontSize: 15, color: t.fg)
                        : TextStyle(
                            fontFamily: AppTheme.fontSans,
                            fontSize: 14,
                            color: t.fg,
                          ),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o, child: Text(label(o))),
                ],
                onChanged: onChanged == null
                    ? null
                    : (v) {
                        if (v != null) onChanged!(v);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reference's `.sf-check` / `.bf-row`: a checkbox, a sans 14/500 title
/// and a sub line at `--fg-muted`. The whole row toggles. Used where a form
/// offers a follow-on step (a shelf's backfill, a delete's re-shelve).
class KitCheckRow extends StatelessWidget {
  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;

  /// A row in a list the reader is choosing FROM (the backfill review's
  /// `.bf-row.off`): unchecked, its text drops to half — the row stays, so it
  /// can be taken back.
  final bool dimWhenOff;

  const KitCheckRow({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.onChanged,
    this.dimWhenOff = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final change = onChanged;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: change == null ? null : () => change(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: change == null ? null : (v) => change(v ?? false),
              activeColor: t.accent,
            ),
          ),
          const SizedBox(width: 10),
          // `.sf-check-title`/`.bf-title` sans 14/500 at `--fg`; the line
          // beneath (`.sf-check-sub`/`.bf-reason`) at `--fg-muted` — a reason
          // is read, not skimmed past as metadata.
          Expanded(
            child: Opacity(
              opacity: dimWhenOff && !value ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: KitText.meta(context)
                          .copyWith(color: t.fg, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: KitText.small(context, height: 18)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reference's `.stepper`: `−` · the number in the mono face · `+` · a
/// unit line in the description role. The bounds are the caller's — the
/// control never invents a range.
class KitStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String? unit;

  const KitStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.unit,
  });

  Widget _button(BuildContext context, String glyph, VoidCallback? onTap) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: glyph == '+' ? 'Increase' : 'Decrease',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.controlR(32),
            border: Border.all(color: t.border),
          ),
          child: Text(glyph,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 16,
                color: onTap == null ? t.fgSubtle : t.fg,
              )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final canDown = onChanged != null && value > min;
    final canUp = onChanged != null && value < max;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        _button(context, '−', canDown ? () => onChanged!(value - 1) : null),
        Text('$value', style: AppTheme.mono(fontSize: 15, color: t.fg)),
        _button(context, '+', canUp ? () => onChanged!(value + 1) : null),
        if (unit != null)
          Text(unit!,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 13,
                height: 1.45,
                color: t.fgMuted,
              )),
      ],
    );
  }
}

/// §6.2's shelf swatch — the control that PICKS a shelf's colour, and the one
/// place in the app where a raw palette step is the subject rather than a
/// marker.
///
/// **The hairline is not decoration.** `plum-600` and `ink-500` sit within a
/// step or two of the dark-mode page, so a bare disc of either is an invisible
/// option in a row of ten (`screens/library.md` §Shelf color). Selection is a
/// 2px `--fg` ring OUTSIDE that hairline — a swatch cannot mark itself with a
/// tint, because the tint is the thing being chosen.
///
/// [label] is the colour's reader-facing NAME (`Moss`, `Deep plum`), never its
/// token: a swatch announced as `sage-500` names a variable.
class KitSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;

  /// Null while a write is in flight — write-before-move, so the row cannot be
  /// re-picked before the request it is waiting on answers.
  final VoidCallback? onTap;

  const KitSwatch({
    super.key,
    required this.color,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Container(
              width: _size + 4,
              height: _size + 4,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.fg : const Color(0x00000000),
                  width: 2,
                ),
              ),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.border),
                  boxShadow: AppShadows.s1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shelf plate (`.shelf-plate`) — a 30×36 spine-shaped block in a shelf's
/// stored colour, used as the §2.1 **lead** on a shelf's own chapter opening
/// the way a file badge leads a document's.
///
/// Carries the same hairline every swatch, dot and spine does, for the same
/// reason.
class KitShelfPlate extends StatelessWidget {
  /// A `/tags.color` token name; an unrecognised value (or a legacy hex)
  /// resolves muted rather than failing.
  final String? colorToken;

  const KitShelfPlate(this.colorToken, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: 30,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.shelfColor(colorToken) ?? t.fgSubtle,
        borderRadius: AppRadius.xsR,
        border: Border.all(color: t.border),
        boxShadow: AppShadows.s1,
      ),
    );
  }
}

/// The sunken settings panel (`.shelf-settings`) — a disclosure a screen opens
/// under its header: `--surface-sunken`, 1px `--border`, `--r-md`, holding a
/// stack of [KitPanelRow]s.
///
/// A panel, not a card: §5.1 is a sheet laid **on** the page and reads as
/// lifted, and a settings disclosure is the opposite gesture — it is cut into
/// the page, which is what `--surface-sunken` is for.
class KitPanel extends StatelessWidget {
  final List<Widget> children;

  const KitPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row of a [KitPanel] (`.ss-row`): a fixed-width mono caps label naming
/// the control beside it. The label column is fixed so the controls of a panel
/// line up with each other rather than with their own labels.
///
/// `.ss-row` is `flex-wrap: wrap` (gap 16, row-gap 8), and which controls wrap
/// is decided by their flex basis: a `flex: 1` control (the name field, the
/// split body) has a zero basis, always fits, and shrinks beside the label; a
/// control sized by its content (the swatches) wraps WHOLE onto its own line
/// under the label when its natural width does not fit beside it — on a phone
/// the ten swatches (312px) drop under COLOR as one row of ten instead of
/// wrapping 7 + 3 inside the column (F-56). [sizedByContent] is that basis.
class KitPanelRow extends StatelessWidget {
  final String label;
  final Widget child;

  /// A row whose control is taller than its label (a split proposal) aligns
  /// to the top instead of the centre.
  final bool alignTop;

  /// The control is sized by its content (no `flex: 1`), so the row wraps it
  /// whole under the label when it does not fit beside it.
  final bool sizedByContent;

  const KitPanelRow({
    super.key,
    required this.label,
    required this.child,
    this.alignTop = false,
    this.sizedByContent = false,
  });

  static const double _labelWidth = 64;

  @override
  Widget build(BuildContext context) {
    final labelBox = SizedBox(
      width: _labelWidth,
      child: Padding(
        padding: EdgeInsets.only(top: alignTop ? 6 : 0),
        child: KitControlLabel(label),
      ),
    );
    if (sizedByContent) {
      return Wrap(
        spacing: AppSpacing.s4,
        runSpacing: 8,
        crossAxisAlignment:
            alignTop ? WrapCrossAlignment.start : WrapCrossAlignment.center,
        children: [labelBox, child],
      );
    }
    return Row(
      crossAxisAlignment:
          alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        labelBox,
        const SizedBox(width: AppSpacing.s4),
        Expanded(child: child),
      ],
    );
  }
}
