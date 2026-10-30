/// Direction D parts for F-144's settings screens (component-kit §26–§42).
///
/// Settings and Notifications (`screens/settings.md`, `notifications.md`
/// §Composition (direction D); web `.dp-set`, the D rules at the end of
/// `styles/app-settings.css`): the groups as §31 numbered sections 56 apart,
/// each a ruled register of setting rows; Setup's replay a featured row; the
/// Summary style's and a channel's Type's choices as §34 Switches that fill
/// their row and wrap on a narrow phone. Onboarding's *Use generative AI*
/// check row (`onboarding.md` §Rules, 5.29.0) is here too: a part the wizard
/// needs and the kit did not have.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart';
import 'kit_shell.dart' show KitGlyph;
import 'kit_text.dart' show KitText;

/// Marks the main column of Settings and Notifications in D (web `.dp-set
/// .d-main`). The setting rows inside it ([KitRowList], [KitSettingRow],
/// [KitRowSlot], [KitRowNote] in `kit_rows.dart`) and the field groups
/// ([KitFieldGroup]) take their D form here and nowhere else: the same rows
/// sit on the Library, a study page and the readings letter, which D draws
/// otherwise. Inside a §28 panel ([KitPanelScope]) the panel's flat form wins.
class KitDSetScope extends InheritedWidget {
  const KitDSetScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitDSetScope>() != null &&
      !KitPanelScope.of(context);

  @override
  bool updateShouldNotify(KitDSetScope oldWidget) => false;
}

/// The D settings register's metrics (web `.dp-set .d-main .set-row*`).
abstract final class KitDSet {
  /// The groups are short, so their heads stand 56 apart (the source page's
  /// 72 is for long sections) — at every width.
  static const double gap = 56;

  /// `.set-row-title` — serif 600 18/24 at `--fg`, "opsz" 18.
  static TextStyle title(BuildContext context) => AppTheme.serif(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: Tokens.of(context).fg,
    opsz: 18,
  );

  /// `.set-row-desc` — sans 13/19 at `--fg-muted`.
  static TextStyle desc(BuildContext context) => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 13,
    height: 19 / 13,
    color: Tokens.of(context).fgMuted,
  );

  /// The description's measure: at most 64ch of its own face.
  static double descMax(BuildContext context) =>
      64 * KitText.ch(context, desc(context));
}

/// One group of the D settings column: 56 above every group after the first,
/// its §31 numbered head (keyed for Contents), then its body. The group's own
/// eyebrow is not drawn — the head names it. With no [child] it is the head
/// alone, for a section that draws its head with itself (Sources, which
/// exists only once a service is connected).
class KitDSetGroup extends StatelessWidget {
  final int n;
  final String title;
  final Key headKey;
  final Widget? child;

  const KitDSetGroup({
    super.key,
    required this.n,
    required this.title,
    required this.headKey,
    this.child,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (n > 0) const SizedBox(height: KitDSet.gap),
      KitSecHead(key: headKey, n: n, title: title, margin: false),
      ?child,
    ],
  );
}

/// A sentence under a D settings form (web `.dp-notif .d-main .sources-sub`):
/// serif italic 16/25 in `--fg-lede`, 8 under what it qualifies — what adding
/// a push channel will do.
class KitDSetNote extends StatelessWidget {
  final String text;
  const KitDSetNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: AppTheme.serif(
        fontSize: 16,
        height: 25 / 16,
        fontStyle: FontStyle.italic,
        color: Tokens.of(context).fgLede,
      ),
    ),
  );
}

/// Setup's replay as D's featured row (web `.dp-set .set-feature`): under a
/// 1px `--fg` rule, `20px 0`, no card — the 52px chrome mark, a serif 19/600
/// title over a sans 13.5/1.5 description (at most 46ch), the action at the
/// trailing edge; stacked on a phone.
class KitDSetFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  const KitDSetFeature({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final descStyle = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 13.5,
      height: 1.5,
      color: t.fgMuted,
    );
    final mark = Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.chrome, borderRadius: AppRadius.mdR),
      child: KitGlyph(icon, size: 24, color: t.chromeFg),
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTheme.serif(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 46 * KitText.ch(context, descStyle),
          ),
          child: Text(description, style: descStyle),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg)),
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

/// §34's Switch where the choice FILLS its row and, on a narrow phone, wraps
/// its options onto a second line rather than run past the page (web
/// `<Switch className="set-sw">`: `.set-sw {display: flex; flex-wrap: wrap}
/// .set-sw > button {flex: 1 1 auto}`) — the Summary style's three dimensions
/// and a channel's Type. Each line's options grow from their own width by an
/// equal share of what is left; the solid fill slides to the chosen option's
/// box, across lines too.
///
/// Everything else is [KitSlideSwitch]'s: an outlined track, the chosen option
/// on `--solid` under `--solid-fg`, the slide over `--dur-slow` `--ease-quill`
/// (none on first paint, none under reduced motion), a press on the chosen
/// option does nothing, and [held] is the whole control at `--held-opacity`
/// with its options unpressable. It moves only when [value] moves: a caller
/// that persists the choice awaits its write first; a draft moves on the press.
class KitWrapSwitch<T> extends StatefulWidget {
  final List<KitSlideOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// The group's accessible name — required: it names the choice.
  final String label;
  final bool held;

  const KitWrapSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
    this.held = false,
  });

  /// One option's height (§34).
  static const double height = 26;

  /// Between options, and between lines.
  static const double gap = 2;

  static const double _padX = 11;

  @override
  State<KitWrapSwitch<T>> createState() => _KitWrapSwitchState<T>();
}

class _KitWrapSwitchState<T> extends State<KitWrapSwitch<T>> {
  final GlobalKey _stack = GlobalKey();
  final Map<int, GlobalKey> _keys = {};
  Rect? _box;
  bool _live = false;

  GlobalKey _keyOf(int i) => _keys.putIfAbsent(i, () => GlobalKey());

  static TextStyle _style([Color? fg]) => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: fg,
  );

  void _measure() {
    if (!mounted) return;
    final i = widget.options.indexWhere((o) => o.value == widget.value);
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    final opt = i < 0
        ? null
        : _keys[i]?.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || opt == null || !opt.hasSize || !stack.hasSize) {
      if (_box != null) setState(() => _box = null);
      return;
    }
    final o = opt.localToGlobal(Offset.zero, ancestor: stack);
    final next = o & opt.size;
    if (next != _box) setState(() => _box = next);
    if (!_live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_live) setState(() => _live = true);
      });
    }
  }

  /// Each option's max-content width: its label (and glyph) and its padding.
  List<double> _natural(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return [
      for (final o in widget.options)
        () {
          final tp = TextPainter(
            text: TextSpan(text: o.label, style: _style()),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return (w + (o.icon != null ? 18 : 0) + 2 * KitWrapSwitch._padX)
              .ceilToDouble();
        }(),
    ];
  }

  /// `flex-wrap: wrap` over `flex: 1 1 auto`: an option that cannot fit
  /// beside the ones already on a line starts the next; each line's options
  /// then grow by an equal share of the line's free space.
  static List<List<(int, double)>> _lines(List<double> natural, double avail) {
    const g = KitWrapSwitch.gap;
    final lines = <List<int>>[];
    var line = <int>[];
    var used = 0.0;
    for (var i = 0; i < natural.length; i++) {
      final need = natural[i] + (line.isEmpty ? 0 : g);
      if (line.isNotEmpty && used + need > avail) {
        lines.add(line);
        line = <int>[];
        used = 0;
      }
      used += natural[i] + (line.isEmpty ? 0 : g);
      line.add(i);
    }
    if (line.isNotEmpty) lines.add(line);
    return [
      for (final l in lines)
        () {
          final sum =
              l.fold<double>(0, (a, i) => a + natural[i]) + g * (l.length - 1);
          final extra = ((avail - sum) / l.length).clamp(0.0, double.infinity);
          return [
            for (final i in l)
              (i, (natural[i] + extra).clamp(0.0, avail).floorToDouble()),
          ];
        }(),
    ];
  }

  Widget _option(BuildContext context, int i, Rect? box) {
    final t = Tokens.of(context);
    final o = widget.options[i];
    final on = o.value == widget.value;
    return KitDTap(
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
          height: KitWrapSwitch.height,
          padding: const EdgeInsets.symmetric(horizontal: KitWrapSwitch._padX),
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
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    o.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: _style(fg),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final t = Tokens.of(context);
    final box = _box;
    final track = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlR(32),
        border: Border.all(color: t.borderStrong),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final Widget body;
          if (!c.hasBoundedWidth) {
            body = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.options.length; i++) ...[
                  if (i > 0) const SizedBox(width: KitWrapSwitch.gap),
                  _option(context, i, box),
                ],
              ],
            );
          } else {
            final lines = _lines(_natural(context), c.maxWidth);
            body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var l = 0; l < lines.length; l++) ...[
                  if (l > 0) const SizedBox(height: KitWrapSwitch.gap),
                  Row(
                    children: [
                      for (var k = 0; k < lines[l].length; k++) ...[
                        if (k > 0) const SizedBox(width: KitWrapSwitch.gap),
                        SizedBox(
                          width: lines[l][k].$2,
                          child: _option(context, lines[l][k].$1, box),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            );
          }
          return Stack(
            key: _stack,
            children: [
              if (box != null)
                AnimatedPositioned(
                  duration: _live
                      ? KitD.dur(context, AppMotion.durSlow)
                      : Duration.zero,
                  curve: AppMotion.easeQuill,
                  left: box.left,
                  top: box.top,
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
              body,
            ],
          );
        },
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

/// Onboarding's check row (web `.ob-scripture.ob-check`): a whole-row toggle
/// on `--surface` under a 1px `--border` at `--r-md`, `14px` inside — a 20px
/// box at 5px radius, then a sans 13.5/600 title over a sans 12.5/19
/// description at `--fg-muted`. Ticked, the box fills `--accent` under an
/// `--accent-fg` tick and the row takes the accent chip's ground and the
/// accent border. The wizard's *Use generative AI* (5.29.0, ADR-186): an
/// answer held until Finish, so the row moves on the press.
class KitObCheck extends StatefulWidget {
  final bool value;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;

  const KitObCheck({
    super.key,
    required this.value,
    required this.title,
    required this.description,
    required this.onChanged,
  });

  @override
  State<KitObCheck> createState() => _KitObCheckState();
}

class _KitObCheckState extends State<KitObCheck> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final on = widget.value;
    final dur = KitD.dur(context, AppMotion.durFast);
    return Semantics(
      checked: on,
      button: true,
      label: widget.title,
      excludeSemantics: true,
      onTap: () => widget.onChanged(!on),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(!on),
          child: AnimatedContainer(
            duration: dur,
            curve: AppMotion.easeOut,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: on ? t.accentChipBg : (_hover ? t.hover : t.surface),
              borderRadius: AppRadius.mdR,
              border: Border.all(
                color: on ? t.accent : (_hover ? t.borderStrong : t.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AnimatedContainer(
                    duration: dur,
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? t.accent : t.surface,
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                      border: Border.all(color: on ? t.accent : t.borderStrong),
                    ),
                    child: on
                        ? KitGlyph(Icons.check, size: 13, color: t.accentFg)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 12.5,
                          height: 19 / 12.5,
                          color: t.fgMuted,
                        ),
                      ),
                    ],
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
