import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, TextField, TextInputAction;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../shared/local_flags.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_shell.dart' show KitGlyph;
import 'kit_source_link.dart';

// ── Direction D's small shared parts (component-kit §31–§39) ────────────────
//
// One place for every part a D page composes besides its frame (the frame is
// kit_d_frame.dart, the chrome kit_d_chrome.dart, the covers kit_d_covers.dart).
// Web's equivalents are `src/kit/d/` — each class names its web part.

/// Direction D's breakpoints and small rules, read off the WINDOW where web
/// reads `@media` and off a container where web reads `@container`.
class KitD {
  KitD._();

  /// §30: at 680 or less the sheet becomes the running head.
  static const double phoneMax = 680;

  /// §30: at 1024 or less the app header and tab bar carry the page's tools.
  static const double chromeMax = 1024;

  /// §29: a page container this narrow stacks the sheet above the column.
  static const double stackMax = 860;

  /// §32: a column this narrow drops a register row's author and shelf.
  static const double regNarrow = 760;

  static bool phone(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= phoneMax;

  static bool chrome(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= chromeMax;

  /// §40: all of D's motion is off when the platform asks for reduced motion.
  static bool still(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or nothing under reduced motion.
  static Duration dur(BuildContext context, Duration d) =>
      still(context) ? Duration.zero : d;

  /// The italic numerals D numbers sections with (web `ROMAN`).
  static const List<String> roman = [
    'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', //
    'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI',
  ];

  static String numeral(int i) =>
      i >= 0 && i < roman.length ? roman[i] : '${i + 1}';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Web's `fmt.short` (`Oct 30`), on this device's calendar.
  static String shortDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_months[d.month - 1]} ${d.day}';
  }
}

/// Marks a subtree as a D page (web `.hx-d`), so a shared component that takes
/// D's form there — §37's empty state — can ask. [KitDPage] provides it.
class KitDScope extends InheritedWidget {
  const KitDScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitDScope>() != null;

  @override
  bool updateShouldNotify(KitDScope oldWidget) => false;
}

/// Marks the inside of a §28 settings panel (web `.d-pnl`). A Settings
/// section reused there — the source page's *Summary style*, the Library's
/// own — drops its section header and its rows' icon plates, and its row list
/// goes flat: no card, border, shadow or row inset (web `.d-pnl .set-section
/// .lib-section-h, .d-pnl .set-row-ico {display: none}` and `.d-pnl
/// :is(.set-rows, .set-row)`). The panel's own [KitDLabel] names the group.
class KitPanelScope extends InheritedWidget {
  const KitPanelScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitPanelScope>() != null;

  @override
  bool updateShouldNotify(KitPanelScope oldWidget) => false;
}

/// A pressable D part: hover (a fine pointer only), keyboard focus and
/// activation in one place, so every part draws its states from the same two
/// booleans. [label] replaces the subtree's semantics when given.
class KitDTap extends StatefulWidget {
  final Widget Function(BuildContext context, bool hover, bool focus) builder;
  final VoidCallback? onTap;
  final String? label;
  final bool? selected;
  final bool? expanded;
  final bool enabled;

  const KitDTap({
    super.key,
    required this.builder,
    this.onTap,
    this.label,
    this.selected,
    this.expanded,
    this.enabled = true,
  });

  @override
  State<KitDTap> createState() => _KitDTapState();
}

class _KitDTapState extends State<KitDTap> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    final child = FocusableActionDetector(
      enabled: on,
      mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? widget.onTap : null,
        child: widget.builder(context, _hover && on, _focus && on),
      ),
    );
    return Semantics(
      button: true,
      enabled: on,
      selected: widget.selected,
      expanded: widget.expanded,
      label: widget.label,
      excludeSemantics: widget.label != null,
      child: child,
    );
  }
}

/// `.hx-label.d-l` — a mono caps label over a part of the sheet or a panel's
/// group: 11/500/0.16em in `--fg-muted`, 26 above (none when [first]), 8 under.
class KitDLabel extends StatelessWidget {
  final String text;
  final bool first;
  final double top;

  const KitDLabel(this.text, {super.key, this.first = false, this.top = 26});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : top, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: AppTheme.mono(
          fontSize: 11,
          height: 14 / 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.16 * 11,
          color: Tokens.of(context).fgMuted,
        ),
      ),
    ),
  );
}

/// §1.2's attention pill on the PAGE (the support footer's unread, §13 in D):
/// mono 11/16, min-width 16, `0 6px`, `--r-pill`, `--accent` under
/// `--accent-fg`, tabular, `999+` past 999. Nothing at zero.
class KitAttentionPill extends StatelessWidget {
  final int count;
  final String label;

  const KitAttentionPill(this.count, {super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final t = Tokens.of(context);
    return Semantics(
      label: '$count $label',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          count > 999 ? '999+' : '$count',
          textAlign: TextAlign.center,
          style: AppTheme.mono(
            fontSize: 11,
            height: 16 / 11,
            color: t.accentFg,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// §39 — the crumb's way back: a leading chevron and a label naming WHERE it
/// returns, never just "Back"; mono 11/0.14em caps in `--fg-muted`, `--fg` on
/// hover, a 2px accent focus ring. Its hit area is 44 tall with 8 to each side
/// — the masthead takes the 14 above and below back out of its own spacing, so
/// the text sits where web's negative margins put it.
class KitDBackControl extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// The `/` after it in a crumb (dropped on a phone).
  final bool separator;

  /// Further links after it in the crumb — a shelf's ancestors, outermost
  /// first (`screens/library.md` §Nested shelves; web `.dp-crumb`): each the
  /// same mono caps link, no chevron, each followed by the `/` too.
  final List<(String, VoidCallback)> trail;

  const KitDBackControl(
    this.label, {
    super.key,
    required this.onTap,
    this.separator = false,
    this.trail = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (trail.isEmpty) return _link(context, label, onTap, chevron: true);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // Each link keeps 8px either side, so two of them stand web's 16 apart.
      spacing: 0,
      children: [
        _link(context, label, onTap, chevron: true),
        for (final (l, go) in trail) _link(context, l, go, chevron: false),
      ],
    );
  }

  Widget _link(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    required bool chevron,
  }) {
    final t = Tokens.of(context);
    return KitDTap(
      onTap: onTap,
      label: label,
      builder: (context, hover, focus) {
        final fg = hover ? t.fg : t.fgMuted;
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: focus
              ? BoxDecoration(
                  border: Border.all(color: t.accent, width: 2),
                  borderRadius: AppRadius.smR,
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chevron) ...[
                Icon(Icons.chevron_left, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    fontSize: 11,
                    letterSpacing: 0.14 * 11,
                    color: fg,
                  ),
                ),
              ),
              if (separator) ...[
                const SizedBox(width: 12),
                Transform.rotate(
                  angle: 20 * math.pi / 180,
                  child: Container(width: 1, height: 12, color: t.borderStrong),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// §31 — **SectionHead**, the edition's head for listing pages: a rule on top,
/// a letterpressed serif title, an optional mono caps meta, and the head's
/// actions at the trailing edge (they wrap under the title when they do not
/// fit). [small]: a 1px rule and a 22px title (Home's *Recently added*). A meta
/// that states a figure is a measurement: pass null while its read is out.
class KitSectionHead extends StatelessWidget {
  final String title;
  final String? meta;
  final bool small;
  final List<Widget> actions;

  /// A ported page's first head in its column has no top margin.
  final bool flushTop;

  const KitSectionHead(
    this.title, {
    super.key,
    this.meta,
    this.small = false,
    this.actions = const [],
    this.flushTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    final top = flushTop || small ? 0.0 : (phone ? 56.0 : 76.0);
    final size = small ? 22.0 : 32.0;
    final titleBlock = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 8,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTheme.serif(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.018 * size,
              color: t.fg,
              opsz: small ? 24 : 40,
            ).copyWith(shadows: AppShadows.letterpress),
          ),
        ),
        if (meta != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              meta!.toUpperCase(),
              style: AppTheme.mono(
                fontSize: 11,
                letterSpacing: 0.14 * 11,
                color: t.fgSubtle,
              ),
            ),
          ),
      ],
    );
    return Container(
      margin: EdgeInsets.only(top: top, bottom: small ? 10 : 30),
      padding: EdgeInsets.only(top: small ? 12 : 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.fg, width: small ? 1 : 2),
        ),
      ),
      child: actions.isEmpty
          ? Align(alignment: Alignment.centerLeft, child: titleBlock)
          : _HeadFlow(
              title: titleBlock,
              actions: Wrap(
                spacing: 20,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
    );
  }
}

/// §31's SectionHead line (web `.hx-sh`: `flex-wrap: wrap; gap: 8px 16px`,
/// the actions `margin-left: auto`): the title and its meta keep their line,
/// and the actions sit at its trailing edge when they fit beside them, else
/// they wrap under, still at the trailing edge — never the title squeezed so
/// the actions can stay beside it (the chapter opening's rule, which put a
/// phone's meta under the title and the List / Grid toggle beside it).
class _HeadFlow extends MultiChildRenderObjectWidget {
  _HeadFlow({required Widget title, required Widget actions})
    : super(children: [title, actions]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeadFlow();
}

class _HeadFlowData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeadFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeadFlowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeadFlowData> {
  static const double _gapX = 16;
  static const double _gapY = 8;

  /// Beside the title, the actions sit a little below its top (the head's
  /// letterpressed title is taller than the toggle).
  static const double _actionsTop = 6;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeadFlowData) {
      child.parentData = _HeadFlowData();
    }
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final actions = childAfter(title)!;
    final bounded = constraints.hasBoundedWidth;
    final width = bounded ? constraints.maxWidth : double.infinity;
    actions.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    title.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final t = title.parentData! as _HeadFlowData;
    final a = actions.parentData! as _HeadFlowData;
    t.offset = Offset.zero;
    if (!bounded ||
        title.size.width + _gapX + actions.size.width <= width) {
      final w = bounded
          ? width
          : title.size.width + _gapX + actions.size.width;
      a.offset = Offset(w - actions.size.width, _actionsTop);
      size = constraints.constrain(
        Size(
          w,
          math.max(title.size.height, actions.size.height + _actionsTop),
        ),
      );
      return;
    }
    a.offset = Offset(width - actions.size.width, title.size.height + _gapY);
    size = constraints.constrain(
      Size(width, title.size.height + _gapY + actions.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// §31 — **SecHead**, the numbered head of a page whose sheet carries Contents:
/// `§ {Roman}` in the accent italic serif beside the serif title, optional
/// actions at the trailing edge, a hairline above every section after the
/// first. It stands BEFORE its section's content. [n] is zero-based; give it
/// the section's key from [KitSections.keyOf] so Contents can follow it.
class KitSecHead extends StatelessWidget {
  final int n;
  final String title;
  final List<Widget> actions;

  /// False when the caller places the 72 (56 on a phone) above the section
  /// itself — a section that WRAPS its body (web `SecHeadLine` in `SecD`) is
  /// measured from its hairline, as a browser measures a box without its
  /// margin, so a jump lands the hairline 24 under the top.
  final bool margin;

  const KitSecHead({
    super.key,
    required this.n,
    required this.title,
    this.actions = const [],
    this.margin = true,
  });

  /// The space above every section after the first.
  static double gap(BuildContext context) => KitD.phone(context) ? 56 : 72;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final first = n == 0;
    return Container(
      margin: EdgeInsets.only(top: first || !margin ? 0 : gap(context)),
      padding: EdgeInsets.only(top: first ? 0 : 22, bottom: 20),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: t.borderStrong)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ExcludeSemantics(
            child: Text(
              '§ ${KitD.numeral(n)}',
              style: AppTheme.serif(
                fontSize: 32,
                height: 1,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                letterSpacing: -0.02 * 32,
                color: t.accent,
                opsz: 60,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTheme.serif(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.016 * 28,
                  color: t.fg,
                ),
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 14),
            Wrap(spacing: 14, children: actions),
          ],
        ],
      ),
    );
  }
}

// ── §34 Switch ──────────────────────────────────────────────────────────────

/// One option of a [KitSlideSwitch].
class KitSlideOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool disabled;

  const KitSlideOption(
    this.value,
    this.label, {
    this.icon,
    this.disabled = false,
  });
}

enum KitSlideVariant { plain, view, priority }

/// §34 — the sliding switch: every segmented choice D draws. An outlined
/// track; the chosen option on the solid fill (`--solid` under `--solid-fg`);
/// the fill slides to the next choice over `--dur-slow` `--ease-quill`, not on
/// first paint and not under reduced motion. **It moves only when [value]
/// moves**: pressing the chosen option does nothing, and a caller that persists
/// the choice awaits its write before changing [value] (write before you move).
/// [held]: the whole control at `--held-opacity`, no pointer events.
class KitSlideSwitch<T> extends StatefulWidget {
  final List<KitSlideOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// The group's accessible name — required: it names the choice.
  final String label;
  final bool held;
  final KitSlideVariant variant;

  /// The options share the track's width (LetterQuick's switches span the
  /// panel).
  final bool expand;

  /// The options fill the track's width each by its own label (`flex: 1 1
  /// auto`, `padding: 0 8px` — the Library's *Order by*), where [expand]
  /// gives every option the same width.
  final bool fill;

  /// Option height; 26 by default (§34), 32/36 where the phone asks.
  final double? height;

  const KitSlideSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
    this.held = false,
    this.variant = KitSlideVariant.plain,
    this.expand = false,
    this.fill = false,
    this.height,
  });

  @override
  State<KitSlideSwitch<T>> createState() => _KitSlideSwitchState<T>();
}

class _KitSlideSwitchState<T> extends State<KitSlideSwitch<T>> {
  static Widget _label(String text, Color fg, bool pri) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.fade,
    style: TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12.5,
      fontWeight: pri ? FontWeight.w400 : FontWeight.w500,
      color: fg,
    ),
  );

  final GlobalKey _track = GlobalKey();
  final Map<int, GlobalKey> _keys = {};
  Rect? _box;
  bool _live = false;

  GlobalKey _keyOf(int i) => _keys.putIfAbsent(i, () => GlobalKey());

  void _measure() {
    if (!mounted) return;
    final i = widget.options.indexWhere((o) => o.value == widget.value);
    final track = _track.currentContext?.findRenderObject() as RenderBox?;
    final opt = i < 0
        ? null
        : _keys[i]?.currentContext?.findRenderObject() as RenderBox?;
    if (track == null || opt == null || !opt.hasSize || !track.hasSize) {
      if (_box != null) setState(() => _box = null);
      return;
    }
    final o = opt.localToGlobal(Offset.zero, ancestor: track);
    final next = o & opt.size;
    if (next != _box) setState(() => _box = next);
    if (!_live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_live) setState(() => _live = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final t = Tokens.of(context);
    final h = widget.height ?? 26;
    final view = widget.variant == KitSlideVariant.view;
    final pri = widget.variant == KitSlideVariant.priority;
    final box = _box;
    final options = <Widget>[];
    for (var i = 0; i < widget.options.length; i++) {
      final o = widget.options[i];
      final on = o.value == widget.value;
      final opt = KitDTap(
        key: _keyOf(i),
        label: o.label,
        selected: on,
        enabled: !o.disabled,
        onTap: on ? () {} : () => widget.onChanged(o.value),
        builder: (context, hover, focus) {
          final fg = on ? t.solidFg : (hover ? t.fg : t.fgMuted);
          return AnimatedContainer(
            duration: KitD.dur(context, AppMotion.durBase),
            curve: AppMotion.easeOut,
            height: h,
            padding: widget.fill
                ? const EdgeInsets.symmetric(horizontal: 8)
                : EdgeInsets.only(
                    left: view ? 9 : (pri ? 12 : 11),
                    right: pri ? 12 : 11,
                  ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Until the fill is measured the chosen option paints its own
              // solid, so its label is never --solid-fg on paper.
              color: on && box == null ? t.solid : null,
              borderRadius: AppRadius.controlR(24),
              border: focus ? Border.all(color: t.accent, width: 2) : null,
            ),
            child: Opacity(
              opacity: o.disabled ? AppSpacing.heldOpacity : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (o.icon != null) ...[
                    KitGlyph(o.icon!, size: 14, color: fg),
                    SizedBox(width: view ? 6 : 4),
                  ],
                  if (widget.fill || widget.expand)
                    Flexible(child: _label(o.label, fg, pri))
                  else
                    _label(o.label, fg, pri),
                ],
              ),
            ),
          );
        },
      );
      options.add(
        widget.fill
            ? Expanded(flex: o.label.length + 4, child: opt)
            : widget.expand
            ? Expanded(child: opt)
            : opt,
      );
      if (i < widget.options.length - 1) options.add(const SizedBox(width: 2));
    }
    final track = Container(
      key: _track,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlR(32),
        border: Border.all(color: t.borderStrong),
      ),
      child: Stack(
        children: [
          if (box != null)
            AnimatedPositioned(
              duration: _live
                  ? KitD.dur(context, AppMotion.durSlow)
                  : Duration.zero,
              curve: AppMotion.easeQuill,
              left: box.left - 3,
              top: box.top - 3,
              width: box.width,
              height: box.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.solid,
                    borderRadius: AppRadius.controlR(24),
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: widget.expand || widget.fill
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: options,
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      child: IgnorePointer(
        ignoring: widget.held,
        child: Opacity(
          opacity: widget.held ? AppSpacing.heldOpacity : 1,
          child: track,
        ),
      ),
    );
  }
}

// ── §32 List / Grid ─────────────────────────────────────────────────────────

/// §32 — the app-wide List / Grid choice, read: [builder] gets `list` or
/// `grid` and is rebuilt on every change, whichever toggle made it.
class KitSourceView extends StatefulWidget {
  final Widget Function(BuildContext context, String view) builder;

  const KitSourceView({super.key, required this.builder});

  @override
  State<KitSourceView> createState() => _KitSourceViewState();
}

class _KitSourceViewState extends State<KitSourceView> {
  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: LocalFlags.sourceView,
    builder: (context, v, _) => widget.builder(context, v),
  );
}

/// §32 — the toggle: a §34 Switch, variant *view*, *List* and *Grid*, named
/// *Show sources as*. Only listings of sources get it, and the caller leaves
/// it out while the listing is empty. Writes before it moves.
class KitViewToggle extends StatelessWidget {
  const KitViewToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = KitD.phone(context);
    return KitSourceView(
      builder: (context, view) => KitSlideSwitch<String>(
        variant: KitSlideVariant.view,
        label: 'Show sources as',
        height: phone ? 32 : 26,
        value: view,
        onChanged: (v) => LocalFlags.setSourceView(v),
        options: const [
          KitSlideOption('list', 'List', icon: Icons.view_agenda_outlined),
          KitSlideOption('grid', 'Grid', icon: Icons.grid_view),
        ],
      ),
    );
  }
}

// ── §35 Shelf tag ───────────────────────────────────────────────────────────

/// §35 — a source's shelf as its NAME: serif italic 14.5 in `--fg-lede`,
/// underlined 2px in the shelf's own colour 5px under the baseline, never
/// skipping ink; *Unshelved* underlined in `--border-strong`. The colour is a
/// line, never the text's colour. [row]: a register row's cell, whose 7px
/// under the text keeps the underline from being clipped.
class KitShelfTag extends StatelessWidget {
  final String? title;

  /// The shelf's colour, resolved for the theme; null draws `--border-strong`.
  final Color? color;
  final bool row;

  const KitShelfTag({super.key, this.title, this.color, this.row = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final text = (title == null || title!.isEmpty) ? 'Unshelved' : title!;
    final style = AppTheme.serif(
      fontSize: 14.5,
      height: 1.25,
      fontStyle: FontStyle.italic,
      color: t.fgLede,
    );
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final tp =
              TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
                ellipsis: '…',
              )..layout(
                maxWidth: c.maxWidth.isFinite ? c.maxWidth : double.infinity,
              );
          final baseline = tp.computeDistanceToActualBaseline(
            TextBaseline.alphabetic,
          );
          final h = math.max(tp.height, baseline + 7);
          final size = Size(tp.width, h);
          // Unshelved is underlined in --border-strong, whatever colour came in.
          final unshelved = title == null || title!.isEmpty;
          final painter = _TagPainter(
            tp,
            baseline,
            unshelved ? t.borderStrong : (color ?? t.borderStrong),
          );
          return CustomPaint(size: size, painter: painter);
        },
      ),
    );
  }
}

class _TagPainter extends CustomPainter {
  final TextPainter tp;
  final double baseline;
  final Color line;
  _TagPainter(this.tp, this.baseline, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, baseline + 5, tp.width, 2),
      Paint()..color = line,
    );
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_TagPainter old) =>
      old.tp.text != tp.text || old.line != line || old.baseline != baseline;
}

// ── §36 Row hover ───────────────────────────────────────────────────────────

/// §36 — every D list row hovers the way the Activity feed does: a rounded
/// `--hover` fill reaching [reach] past the row's text on each side (0 for a
/// row with padding of its own), the text staying on the column's edge and the
/// rule straight; keyboard focus draws the same shape as a 2px accent outline.
/// No hover on touch. [onTap] null is a row with no hover at all.
class KitRowHover extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final double reach;

  const KitRowHover({
    super.key,
    required this.child,
    this.onTap,
    this.label,
    this.reach = 12,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      onTap: onTap,
      label: label,
      builder: (context, hover, focus) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -reach,
            right: -reach,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hover || focus ? 1 : 0,
                duration: KitD.dur(context, AppMotion.durFast),
                curve: AppMotion.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: hover ? t.hover : null,
                    borderRadius: AppRadius.smR,
                    border: focus
                        ? Border.all(color: t.accent, width: 2)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ── §32 Register row ────────────────────────────────────────────────────────

/// The 6px accent unread dot on a row (`.unread-dot`).
class KitUnreadDot extends StatelessWidget {
  const KitUnreadDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: Tokens.of(context).accent,
      shape: BoxShape.circle,
    ),
  );
}

/// What a source still being read is doing, in the row's words (web
/// `stageOf`). The vocabulary is OPEN — anything unknown is *Being read*; a
/// stalled run says so and its bar stops (ADR-108). Null for a source that is
/// not being read.
({String label, bool live})? kitStageOf(Document d, [DateTime? now]) {
  if (d.status != DocumentStatus.queued &&
      d.status != DocumentStatus.processing) {
    return null;
  }
  if (d.isStalled(now)) return (label: 'Stalled', live: false);
  if (d.status == DocumentStatus.queued) return (label: 'Queued', live: false);
  const stage = {
    'embedding': 'Indexing passages',
    'extraction': 'Reading the text',
    'extracting': 'Reading the text',
    'chunking': 'Finding passages',
    'syncing': 'Syncing',
  };
  return (label: stage[d.processingStage] ?? 'Being read', live: true);
}

/// The short progress bar of a source still being read (`.hx-bar`): 32 × 3 on
/// `--surface-sunken`, an `--accent` fill; [live] slides a 28% fill on a 1.8s
/// `--ease-in-out` loop, still under reduced motion. Only a document actually
/// `processing` is live. [value] (0..1) is a MEASURED fraction — the bytes a
/// client's own upload has committed, the one phase with a real fraction
/// (ADR-024) — and [done] fills it in `--positive` (`.lx-bar.done`). [fill]:
/// the fill's colour, `--accent` by default (`.reg-stage .hx-bar i`); the
/// Library's processing rows pass `--fg-muted` (`.lx-bar`, the kit's own).
class KitStageBar extends StatefulWidget {
  final bool live;
  final double? value;
  final bool done;
  final Color? fill;
  const KitStageBar({
    super.key,
    this.live = false,
    this.value,
    this.done = false,
    this.fill,
  });

  @override
  State<KitStageBar> createState() => _KitStageBarState();
}

class _KitStageBarState extends State<KitStageBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(KitStageBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.live &&
        widget.value == null &&
        !widget.done &&
        !KitD.still(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: 32,
        height: 3,
        color: t.surfaceSunken,
        alignment: Alignment.centerLeft,
        child: widget.done || widget.value != null
            ? AnimatedContainer(
                duration: KitD.dur(context, AppMotion.durSlow),
                curve: AppMotion.easeQuill,
                width: 32 * (widget.done ? 1 : widget.value!.clamp(0.0, 1.0)),
                color: widget.done ? t.positive : (widget.fill ?? t.accent),
              )
            : widget.live
            ? AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final p = AppMotion.easeInOut.transform(_c.value);
                  // translateX(-100%) → translateX(360%) of a 28% fill.
                  final x = (-1 + 4.6 * p) * 32 * 0.28;
                  return Transform.translate(
                    offset: Offset(x, 0),
                    child: Container(
                      width: 32 * 0.28,
                      color: widget.fill ?? t.accent,
                    ),
                  );
                },
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// §32 — the register row: a source in List, a link to it, five cells — the
/// date it was added (mono), the title (serif, one line) led by the unread dot
/// while it has never been opened, the author (italic), its §35 shelf tag
/// (its home shelf, or *Unshelved*), and its passage count (mono, trailing; an
/// EMPTY cell when never taken, ADR-109). In a column 760 or narrower author
/// and shelf drop. A source still being read ([kitStageOf]) draws its stage —
/// a bar and the stage word — in the shelf cell, no dot and an empty count.
/// [lead] replaces the date cell: the Library's rank (`01`) when its
/// catalogue is ordered by Most passages (web `RegisterRow`'s `lead`).
class KitRegisterRow extends StatelessWidget {
  final Document doc;

  /// The home shelf's title and colour (resolved for the theme), or null.
  final String? shelfTitle;
  final Color? shelfColor;
  final VoidCallback? onOpen;
  final String? lead;

  const KitRegisterRow({
    super.key,
    required this.doc,
    this.shelfTitle,
    this.shelfColor,
    this.onOpen,
    this.lead,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final stage = kitStageOf(doc);
    final n = doc.chunkCount;
    final title = doc.title.isEmpty ? 'Untitled' : doc.title;
    final unread = stage == null && doc.viewCount == 0;
    return KitSourceLink(
      docId: doc.id,
      onOpen: onOpen,
      builder: (context, open) => KitRowHover(
        onTap: open,
        label: '$title${unread ? ' (unread)' : ''}',
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth <= KitD.regNarrow;
            final date = Text(
              lead ??
                  (doc.createdAt == null
                      ? ''
                      : KitD.shortDate(doc.createdAt!)),
              maxLines: 1,
              style: AppTheme.mono(
                fontSize: 11,
                letterSpacing: 0.04 * 11,
                color: t.fgSubtle,
              ),
            );
            final titleCell = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (unread) ...[const KitUnreadDot(), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      fontSize: 17,
                      height: 23 / 17,
                      fontWeight: FontWeight.w500,
                      color: t.fg,
                    ),
                  ),
                ),
              ],
            );
            final author = Text(
              doc.author ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: t.fgLede,
              ),
            );
            // Wide, the stage takes the shelf cell's track; in a column 760
            // or narrower it is web's `auto` track — its own width, beside a
            // title that takes the rest (a Flexible inside an unbounded cell
            // threw, and Home's phone drew no reading row at all).
            final stageWord = stage == null
                ? null
                : Text(
                    stage.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      letterSpacing: 0.12 * 10.5,
                      color: t.accentText,
                    ),
                  );
            final stageCell = stage == null
                ? null
                : Row(
                    mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      KitStageBar(live: stage.live),
                      const SizedBox(width: 10),
                      if (narrow) stageWord! else Flexible(child: stageWord!),
                    ],
                  );
            final count = Text(
              stage != null || n == null ? '' : '$n',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: AppTheme.mono(fontSize: 12, color: t.fgMuted),
            );
            final cells = <Widget>[
              SizedBox(width: narrow ? 52 : 62, child: date),
              const SizedBox(width: 18),
              Expanded(flex: narrow ? 10 : 15, child: titleCell),
            ];
            if (!narrow) {
              cells
                ..add(const SizedBox(width: 18))
                ..add(Expanded(flex: 10, child: author))
                ..add(const SizedBox(width: 18))
                ..add(
                  Expanded(
                    flex: 8,
                    child:
                        stageCell ??
                        Align(
                          alignment: Alignment.centerLeft,
                          child: KitShelfTag(
                            title: shelfTitle,
                            color: shelfColor,
                            row: true,
                          ),
                        ),
                  ),
                );
            } else if (stageCell != null) {
              cells
                ..add(const SizedBox(width: 18))
                ..add(stageCell);
            }
            if (!(narrow && stageCell != null)) {
              cells
                ..add(const SizedBox(width: 18))
                ..add(SizedBox(width: narrow ? 40 : 44, child: count));
            }
            return Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 8, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: cells,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── §38 Composer ────────────────────────────────────────────────────────────

/// §38 — a composer that starts ONE line tall and grows with its text to
/// about seven lines (172px), then scrolls inside; a change of width rewraps
/// it. Serif italic 17/24 in `--fg`, `7px 0`, no border; the placeholder in
/// `--fg-subtle`. Enter and Shift+Enter are the host's (Ask's, Support's).
class KitGrowField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final double max;

  const KitGrowField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.max = 172,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = AppTheme.serif(
      fontSize: 17,
      height: 24 / 17,
      fontStyle: FontStyle.italic,
      color: t.fg,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: max),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        minLines: 1,
        maxLines: null,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.newline,
        style: style,
        cursorColor: t.accent,
        // §38's field has no border and no fill — its dock is its frame — so
        // the app's input theme (an outlined, filled box) is overridden here,
        // once, for every composer (Ask's, Support's).
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: placeholder,
          hintMaxLines: 1,
          hintStyle: style.copyWith(color: t.fgSubtle),
        ),
      ),
    );
  }
}

// ── The skeleton lines (web `.hx-skel-set`) ─────────────────────────────────

/// One skeleton line's form: a [width] fraction of the column (null → whole)
/// and [tall] for a headline's 40px bar (`.hx-skel.h1`).
class KitSkelLine {
  final double? width;
  final bool tall;
  const KitSkelLine([this.width, this.tall = false]);
}

/// A D page's loading lines (web `.hx-skel-set`, W2's kit request): bars 12
/// tall (a headline's 40), radius 4 (6), 10 apart, 16 above, on the theme's
/// own ink as an overlay — `--hover-strong` under a `--hover` shine that runs
/// 1.6s, still under reduced motion — so they read a step off whatever they
/// sit on (page, sheet, the letter's paper) in both themes (kit §29, W3).
/// Never `--surface-sunken`: it is darker than the dark page, and the lines
/// drew as near-black bars. Hidden from assistive technology; the region is
/// busy.
/// [center] centres the bars (the letter card's loading head).
class KitSkeletonLines extends StatefulWidget {
  final List<KitSkelLine> lines;
  final bool center;
  final double top;

  const KitSkeletonLines({
    super.key,
    this.lines = const [KitSkelLine(0.6), KitSkelLine(), KitSkelLine(0.7)],
    this.center = false,
    this.top = 16,
  });

  @override
  State<KitSkeletonLines> createState() => _KitSkeletonLinesState();
}

class _KitSkeletonLinesState extends State<KitSkeletonLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KitD.still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget bar(KitSkelLine l) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // background-size 200%: the bright middle travels one width.
            final x = 1 - 2 * _c.value;
            return Container(
              height: l.tall ? 40 : 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(l.tall ? 6 : 4),
                gradient: LinearGradient(
                  begin: Alignment(x - 1, 0),
                  end: Alignment(x + 1, 0),
                  colors: [t.hoverStrong, t.hover, t.hoverStrong],
                ),
              ),
            );
          },
        );
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(top: widget.top),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
          return Column(
            crossAxisAlignment: widget.center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                SizedBox(
                  width: w * (widget.lines[i].width ?? 1),
                  child: bar(widget.lines[i]),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
