import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_rows.dart' show KitSettingLink;

/// The manuscript's reading controls (reader.md §Reading state & typography,
/// web `ManuscriptPanel.jsx` + `app-source.css` `.ms-type` · `.ms-progress` ·
/// `.ms-resume` · `::first-letter`). F-74 left them for this file: F-43
/// recomposed the panel's type and left these four, each a behaviour rather
/// than a type role.

/// One row of the type panel: its label and the choices, the chosen one on.
class KitTypeGroup {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const KitTypeGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
}

/// `.ms-type` — the **Aa** ghost control beside Edit text, and the panel it
/// opens: one row per preference (a mono caps label over a small segmented
/// track), on `--surface`, 1px `--border`, `--r-md`, `--shadow-3`, 268 wide,
/// 8 under the control and flush to its trailing edge.
///
/// Unlike §16's anchored popover — which explains a control and holds none —
/// this panel IS the controls, so it takes taps; it closes on a tap outside it
/// or Escape, as the reference's does. It never leaves the viewport: on a
/// phone the trailing edge of a control near the middle would push a 268 panel
/// off the left, so it slides back to 16 inside.
class KitTypeControls extends StatefulWidget {
  final List<KitTypeGroup> groups;

  const KitTypeControls({super.key, required this.groups});

  static const double panelWidth = 268;

  @override
  State<KitTypeControls> createState() => _KitTypeControlsState();
}

class _KitTypeControlsState extends State<KitTypeControls> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();
  final _group = Object();
  double _shift = 0;
  double _width = KitTypeControls.panelWidth;

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
      setState(() {});
      return;
    }
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final view = MediaQuery.sizeOf(context);
    final right = box == null
        ? view.width
        : box.localToGlobal(Offset(box.size.width, 0)).dx;
    final w = math.min(KitTypeControls.panelWidth, view.width - 32);
    // Trailing edges flush (`right: 0`), then back inside the viewport.
    var x = 0.0;
    if (right - w < 16) x = 16 - (right - w);
    setState(() {
      _width = w;
      _shift = x;
    });
    _portal.show();
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _group,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            width: _width,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: Offset(_shift, 8),
              child: TapRegion(
                groupId: _group,
                onTapOutside: (_) => _close(),
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): _close,
                  },
                  child: Focus(
                    autofocus: true,
                    child: _TypePanel(groups: widget.groups),
                  ),
                ),
              ),
            ),
          ),
          child: KeyedSubtree(
            key: _anchorKey,
            child: Semantics(
              label: 'Reading preferences',
              expanded: _portal.isShowing,
              child: KitButton.ghost('Aa',
                  // IcoText, as this client draws it everywhere (F-77 (6)).
                  icon: Icons.title,
                  onPressed: _toggle),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypePanel extends StatelessWidget {
  final List<KitTypeGroup> groups;
  const _TypePanel({required this.groups});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      label: 'Reading preferences',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: t.border),
          boxShadow: AppShadows.s3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(groups[i].label.toUpperCase(),
                  style: AppTheme.mono(
                      fontSize: 10,
                      letterSpacing: 1.0,
                      color: t.fgSubtle)),
              const SizedBox(height: 6),
              _TypeTrack(group: groups[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.ms-type-seg` — a sunken track, 2 inside a 1px `--border`, `--r-sm`; each
/// choice flexes equally, sans 12 `--fg-muted`; the chosen one is `--surface`
/// with `--shadow-1` at `--fg`.
class _TypeTrack extends StatelessWidget {
  final KitTypeGroup group;
  const _TypeTrack({required this.group});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.smR,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < group.options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Semantics(
                button: true,
                selected: i == group.selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => group.onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == group.selected
                          ? t.surface
                          : const Color(0x00000000),
                      borderRadius: AppRadius.xsR,
                      boxShadow:
                          i == group.selected ? AppShadows.s1 : null,
                    ),
                    child: Text(
                      group.options[i],
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12,
                        color: i == group.selected ? t.fg : t.fgMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.ms-progress` — the reading-progress hairline above the sheet: a 2pt pill
/// track in `--rule`, filled in `--accent` to [value]. A MEASURED fraction of
/// the sheet scrolled, never a timer (only measured numbers on screen).
class KitProgressRule extends StatelessWidget {
  /// 0..1.
  final double value;

  const KitProgressRule({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: 'Reading progress',
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: AppRadius.pillR(2),
        child: SizedBox(
          height: 2,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: t.rule)),
              FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                alignment: AlignmentDirectional.centerStart,
                child: ColoredBox(color: t.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ms-resume` — where the reader stopped, OFFERED, never performed: moving
/// someone down a document they just opened is disorienting, and they may mean
/// to start over. A sunken box: the sentence in sans 13 `--fg-muted`, then
/// *Pick up where you left off* and a muted *Start over*, wrapping.
class KitResumeOffer extends StatelessWidget {
  /// The stored fraction, 0..1.
  final double fraction;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  const KitResumeOffer({
    super.key,
    required this.fraction,
    required this.onResume,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.smR,
        border: Border.all(color: t.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'You stopped about ${(fraction * 100).round()}% of the way '
            'through.',
            style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 13,
                color: t.fgMuted),
          ),
          KitSettingLink('Pick up where you left off',
              icon: null, onTap: onResume),
          KitSettingLink('Start over', icon: null, onTap: onDismiss),
        ],
      ),
    );
  }
}

/// The first passage's first paragraph with a **drop cap**
/// (`.ms-chunk:first-child … p:first-child::first-letter`): its opening letter
/// in the serif at 58 / 0.86 / 600 in `--accent-text`, floated with 6 above
/// and 10 after, the paragraph's opening lines running beside it and the rest
/// at full width.
///
/// flutter_html has no `::first-letter` and Flutter text has no float, so the
/// float is laid out here: the paragraph is set at the narrowed width, the
/// lines that share the cap's height stay beside it, and the remainder starts
/// at the next line break at full width. **Plain text only** — the caller
/// passes a paragraph with no inline markup, and draws any other first
/// paragraph without a cap rather than lose its links or emphasis.
class KitDropCap extends StatelessWidget {
  final String text;

  /// The paragraph's own reading style; it must carry a size and a height.
  final TextStyle style;

  const KitDropCap(this.text, {super.key, required this.style});

  /// The leading punctuation and the first letter — what `::first-letter`
  /// takes (`“Quarterly` caps `“Q`), and the rest of the paragraph.
  static (String, String) split(String text) {
    final m = RegExp(r'^\s*([\p{P}\p{S}]*\S)', unicode: true).firstMatch(text);
    if (m == null) return ('', text);
    return (m.group(1)!, text.substring(m.end));
  }

  /// The cap's own style: serif 58 / 0.86 / 600 in `--accent-text`, at the
  /// body's optical size — `::first-letter` inherits `.ms-body`'s `"opsz" 18`.
  static TextStyle capStyle(BuildContext context) => AppTheme.serif(
        fontSize: 58,
        height: 0.86,
        fontWeight: FontWeight.w600,
        opsz: 18,
        color: Tokens.of(context).accentText,
      );

  @override
  Widget build(BuildContext context) {
    final (cap, rest) = split(text);
    if (cap.isEmpty) return Text(text, style: style);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    final capS = capStyle(context);
    return LayoutBuilder(builder: (context, c) {
      final capPainter = TextPainter(
        text: TextSpan(text: cap, style: capS),
        textDirection: dir,
        textScaler: scaler,
      )..layout();
      final capW = capPainter.width + 10;
      final capH = capPainter.height + 6;
      final narrow = math.max(0.0, c.maxWidth - capW);
      final body = TextPainter(
        text: TextSpan(text: rest, style: style),
        textDirection: dir,
        textScaler: scaler,
      )..layout(maxWidth: narrow);
      final lines = body.computeLineMetrics();
      // The lines whose box overlaps the cap's height run beside it.
      var beside = 0;
      var top = 0.0;
      for (final l in lines) {
        if (top >= capH) break;
        beside++;
        top += l.height;
      }
      String first = rest;
      String after = '';
      if (beside < lines.length) {
        final next = lines[beside];
        final at = body
            .getPositionForOffset(
                Offset(0, top + next.height / 2))
            .offset;
        first = rest.substring(0, at).trimRight();
        after = rest.substring(at).trimLeft();
      }
      capPainter.dispose();
      body.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: Text(cap, style: capS),
              ),
              Expanded(child: Text(first, style: style)),
            ],
          ),
          if (after.isNotEmpty) Text(after, style: style),
        ],
      );
    });
  }
}

/// `.ms-body img` — a passage's image as the manuscript frames it: block,
/// at most the measure wide, 1px `--border` at `--r-sm`, 6 above and 14
/// below, and a tap opens it full size (`cursor: zoom-in`). An image that
/// does not load keeps its frame and says its `alt` inside it, as the
/// browser draws a broken image — the bare alt text in the reading type read
/// as a sentence of the author's (the 2026-10-07 reader-manuscript pair,
/// F-77). Manuscript-only, as the reference's rule is: other surfaces that
/// render html keep their own.
HtmlExtension kitManuscriptImage({
  required TextStyle altStyle,
  void Function(String url, String? alt)? onOpen,
}) =>
    ImageExtension(
      handleAssetImages: false,
      handleDataImages: false,
      builder: (ctx) {
        final src = ctx.attributes['src'] ?? '';
        final alt = ctx.attributes['alt'];
        return _ManuscriptImage(
            src: src, alt: alt, altStyle: altStyle, onOpen: onOpen);
      },
    );

class _ManuscriptImage extends StatelessWidget {
  final String src;
  final String? alt;
  final TextStyle altStyle;
  final void Function(String url, String? alt)? onOpen;

  const _ManuscriptImage({
    required this.src,
    required this.alt,
    required this.altStyle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget broken() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 16, color: t.fgSubtle),
              if ((alt ?? '').isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(child: Text(alt!, style: altStyle)),
              ],
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: GestureDetector(
        onTap: onOpen == null ? null : () => onOpen!(src, alt),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: AppRadius.smR,
            border: Border.all(color: t.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            image: true,
            label: alt,
            child: Image.network(
              src,
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              errorBuilder: (_, _, _) => broken(),
            ),
          ),
        ),
      ),
    );
  }
}
