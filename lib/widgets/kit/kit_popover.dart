import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// `--dur-fast`. Spelled the way the rest of the kit spells it — there is no
/// duration token file, and inventing one here would put half the app's
/// timings in a place the other half does not read.
const Duration _durFast = Duration(milliseconds: 120);

/// §16 · Anchored popover (4.44.0, ADR-082).
///
/// A small panel that opens **from a control** to explain that control, and
/// closes when attention leaves it. Distinct from §15's overlay sheet, which
/// covers the viewport behind a scrim and holds something the reader came for:
/// a popover has no scrim, takes no focus, blocks nothing, and is worth
/// nothing on its own — it is always *about* the thing it points at.
///
/// Required parts: an **anchor** (a control in its own right, with a real
/// focus treatment) · a **panel** against the anchor's trailing edge,
/// `--surface-raised`, 1px `--border`, `--r-md`, `--shadow-3` · a **beak**
/// joining the two, drawn from the same surface and border · a **head** —
/// a mono caps label and the headline figure in serif, closed by a
/// 1px `--rule` · a **body** · an optional **foot** on a 1px `--rule`, mono at
/// `--fg-subtle`.
///
/// The head label is **`--fg-subtle`**, which is both §16's own reference
/// metric and what `.pop-head-lbl` draws. §16's required-parts sentence says
/// `--seal` instead, and that half is the wrong one: `--seal` is floored as a
/// GRAPHIC at 3.0, so handing it to 9.5px text fails the small-text floor —
/// `token_contrast_check.py` ROLE refused it the first time this client obeyed
/// the sentence. The same shape as §5.4's time chip (TODO, 2026-09-14).
///
/// **The anchor is a control, not a `tabIndex`.** A presentational box made
/// reachable by a tab stop announces nothing and does nothing — worse than
/// unreachable, because it costs a keyboard reader a stop to find out. So the
/// anchor here is a [Semantics] button with a focus ring, and `cursor: help`
/// (the promise this pattern's own anchor carried for fifteen months with no
/// popover behind it) goes on it only because there now is one.
///
/// The panel never traps focus and holds **no control of its own** — anything
/// actionable belongs on the screen, not in a panel that closes when you reach
/// for it. It is [IgnorePointer] while open for exactly that reason, and
/// unmounted while closed, so nothing about it is reachable or readable then.
///
/// **A coarse pointer has no hover and no tab stop**, and this client's
/// primary target is one. Hover and focus both open it, as the pattern
/// requires; a **tap toggles** it, which is the same control answering the only
/// gesture a phone has. Recorded in `CLAUDE.md` §Composition deviations —
/// the same adaptation §9's rail made when it stopped hiding its entry actions
/// behind a hover this client can never produce.
class KitAnchoredPopover extends StatefulWidget {
  /// The control. Drawn by the caller — §16 asks that an anchor *be* a
  /// control, not that every anchor look alike, so neither score surface
  /// changes appearance.
  final Widget child;

  /// Head — the mono caps label, then the headline figure.
  final String headLabel;
  final String headValue;

  /// Body. Rows of measured figures; [KitPopoverMeterRow] is the one shape
  /// this pattern was transcribed from.
  final List<Widget> body;

  /// Foot, on its own rule. Null renders no foot and no rule.
  final String? foot;

  /// What a screen reader is told the control is. §16's anchor announces the
  /// figure AND that there is an explanation behind it.
  final String semanticsLabel;

  const KitAnchoredPopover({
    super.key,
    required this.child,
    required this.headLabel,
    required this.headValue,
    required this.body,
    required this.semanticsLabel,
    this.foot,
  });

  /// Reference metrics (web): panel 268 wide, 9px below the anchor and flush
  /// to its trailing edge, padding `13 14 11`. Beak 9×9 rotated 45°, 5px above
  /// the panel, 18px in from the trailing edge.
  static const double panelWidth = 268;
  static const double _gap = 9;
  static const double _beak = 9;
  static const double _beakInset = 18;

  @override
  State<KitAnchoredPopover> createState() => _KitAnchoredPopoverState();
}

class _KitAnchoredPopoverState extends State<KitAnchoredPopover> {
  final _link = LayerLink();
  final _controller = OverlayPortalController();
  final _focus = FocusNode(debugLabel: 'KitAnchoredPopover');
  bool _open = false;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _set(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    open ? _controller.show() : _controller.hide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape && _open) {
      _set(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) => _panel(context, t),
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          onFocusChange: (has) {
            setState(() => _focused = has);
            _set(has);
          },
          child: Semantics(
            button: true,
            label: widget.semanticsLabel,
            child: MouseRegion(
              // The promise this pattern names: `cursor: help` belongs on an
              // anchor that has a popover behind it, and only on one.
              cursor: SystemMouseCursors.help,
              onEnter: (_) => _set(true),
              onExit: (_) => _set(_focused),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A coarse pointer's only gesture. It also takes focus, so a
                // tap and a tab arrive at the same control in the same state.
                onTap: () {
                  _focus.requestFocus();
                  _set(!_open);
                },
                child: AnimatedContainer(
                  duration: _durFast,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.xsR,
                    // The focus treatment §16 requires of the anchor. Nothing
                    // is drawn when it is merely hovered — the panel is that.
                    border: Border.all(
                      color: _focused ? t.accent : const Color(0x00000000),
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, Tokens t) {
    return Positioned(
      left: 0,
      top: 0,
      width: KitAnchoredPopover.panelWidth,
      child: CompositedTransformFollower(
        link: _link,
        // Flush to the anchor's TRAILING edge, the gap below its bottom.
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, KitAnchoredPopover._gap),
        child: IgnorePointer(
          child: _PopoverPanel(
            headLabel: widget.headLabel,
            headValue: widget.headValue,
            body: widget.body,
            foot: widget.foot,
          ),
        ),
      ),
    );
  }
}

/// Panel · beak · head · body · foot. Enters on `opacity` plus a 4px rise over
/// `--dur-fast` `--ease-out`, as the reference does.
class _PopoverPanel extends StatefulWidget {
  final String headLabel;
  final String headValue;
  final List<Widget> body;
  final String? foot;

  const _PopoverPanel({
    required this.headLabel,
    required this.headValue,
    required this.body,
    required this.foot,
  });

  @override
  State<_PopoverPanel> createState() => _PopoverPanelState();
}

class _PopoverPanelState extends State<_PopoverPanel> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);

    return AnimatedOpacity(
      opacity: _in ? 1 : 0,
      duration: _durFast,
      curve: Curves.easeOut,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _in ? 1 : 0),
        duration: _durFast,
        curve: Curves.easeOut,
        builder: (context, v, child) =>
            Transform.translate(offset: Offset(0, 4 * (1 - v)), child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              // The gap the beak stands in, so the panel body starts below it.
              margin: const EdgeInsets.only(top: KitAnchoredPopover._beak / 2),
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: AppRadius.mdR,
                border: Border.all(color: t.border),
                boxShadow: AppShadows.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Head — the mono caps label, the figure in
                  // serif, closed by a rule.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.headLabel.toUpperCase(),
                          style: KitText.capsLabel(
                            context,
                            fontSize: 9.5,
                            letterSpacing: 0.1,
                            color: t.fgSubtle,
                          ),
                        ),
                      ),
                      Text(
                        widget.headValue,
                        style: AppTheme.serif(
                          fontSize: 18,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: t.fg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Container(height: 1, color: t.rule),
                  const SizedBox(height: 9),
                  ...widget.body,
                  if (widget.foot != null) ...[
                    const SizedBox(height: 11),
                    Container(height: 1, color: t.rule),
                    const SizedBox(height: 9),
                    Text(
                      widget.foot!,
                      style: AppTheme.mono(
                        fontSize: 9,
                        height: 13 / 9,
                        letterSpacing: 0.04 * 9,
                        color: t.fgSubtle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The beak — the same surface and border, so panel and beak read
            // as one object rather than a panel with a triangle beside it.
            Positioned(
              top: 0,
              right: KitAnchoredPopover._beakInset,
              child: Transform.rotate(
                angle: 0.7853981633974483, // 45°
                child: Container(
                  width: KitAnchoredPopover._beak,
                  height: KitAnchoredPopover._beak,
                  decoration: BoxDecoration(
                    color: t.surfaceRaised,
                    border: Border(
                      top: BorderSide(color: t.border),
                      left: BorderSide(color: t.border),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One measured component of a blended figure — the §16 body row this pattern
/// was transcribed from (`screens/search.md` §Score explainer).
///
/// Required parts, in order: the component's **name**, its **weight** as a
/// mono pill, its **contribution** to the blend, a **bar**, and a **hint line**
/// naming what the component means.
///
/// **The bar's fill is the component, not the contribution.** Similarity 0.612
/// fills 61%, and its 0.490 contribution is the number beside it. A bar scaled
/// to the contribution would make the 0.2-weighted row look like a weak
/// *source* rather than a small *share*.
class KitPopoverMeterRow extends StatelessWidget {
  final String label;

  /// The blend weight. A constant of the ranking, not a response field.
  final double weight;

  /// The measured component, 0–1 — the bar's fill.
  final double value;

  /// `weight × value`, arithmetic over a returned value.
  final double contribution;

  final String hint;

  const KitPopoverMeterRow({
    super.key,
    required this.label,
    required this.weight,
    required this.value,
    required this.contribution,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fill = value.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w500,
                    color: t.fg,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: t.surfaceSunken,
                  borderRadius: AppRadius.pillR(14),
                ),
                child: Text(
                  '×${weight.toStringAsFixed(1)}',
                  style: AppTheme.mono(fontSize: 9, color: t.fgMuted),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                contribution.toStringAsFixed(4),
                style: AppTheme.mono(fontSize: 11, color: t.accentText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fill,
              child: Container(
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 10.5,
              height: 15 / 10.5,
              color: t.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}
