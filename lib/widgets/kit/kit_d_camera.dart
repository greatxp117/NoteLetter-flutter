import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Material, MaterialType, showGeneralDialog;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart';
import 'kit_ground.dart';

// ── The camera roll in direction D (5.43.0, ADR-198; F-146) ─────────────────
//
// The flow over the app that the camera roll's setup, its look back, its
// review and its end page share (`screens/sources.md` §Camera roll, *The
// flow's frame*; the prototype's `app-camera.css`, `.cr-*`), and the small
// parts its pages and its settings panel compose. Web has no camera roll,
// so the reference is the prototype (handoff-d README §Camera roll; board
// `Camera Roll Setup.html`, direction A). Every metric below is the
// prototype's; the page logic is `lib/pages/sources/camera_roll.dart`.

/// `.cr-x` / `.cr-top-l` / `.cr-prog` — the flow's top bar: a close control
/// (× — or a chevron that only HIDES while looking back), a running head in
/// mono caps centred on the bar, and under it a 2px progress rule wherever
/// the flow measures progress ([progress] 0..1; null draws none).
class KitFlowTop extends StatelessWidget {
  final String label;
  final double? progress;
  final bool hides;
  final VoidCallback onClose;

  const KitFlowTop({
    super.key,
    required this.label,
    required this.onClose,
    this.progress,
    this.hides = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final p = progress;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  KitDTap(
                    label: hides ? 'Hide' : 'Close',
                    onTap: onClose,
                    builder: (context, hover, focus) => Container(
                      key: const ValueKey('cr-close'),
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hover ? t.hover : null,
                        borderRadius: AppRadius.controlR(44),
                        border: focus
                            ? Border.all(color: t.accent, width: 2)
                            : null,
                      ),
                      child: Icon(
                        hides ? Icons.keyboard_arrow_down : Icons.close,
                        size: 20,
                        color: hover ? t.fg : t.fgMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 44),
                      child: Text(
                        label.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          fontSize: 10.5,
                          letterSpacing: 0.14 * 10.5,
                          color: t.fgMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (p != null)
            Positioned(
              left: 22,
              right: 22,
              bottom: 0,
              height: 2,
              child: KitFlowBar(value: p, height: 2, track: t.rule),
            ),
        ],
      ),
    );
  }
}

/// `.cr` — the flow's frame over the app: the whole screen on a phone (680
/// or narrower; the safe areas kept), and wider a sheet at most 560 wide and
/// 880 tall on the panel scrim, `--r-xl`, `--shadow-3`. The checkered
/// ground, then the top bar, the body that scrolls, and the foot (`.cr-foot`:
/// a rule over it, the primary and a link or two ghosts, 8 apart).
/// **Escape closes it** (a phone's back gesture does too: the flow is a
/// route). [onScrim] is the scrim's tap, wider than a phone.
class KitFlowFrame extends StatelessWidget {
  final Widget top;
  final Widget body;
  final List<Widget> foot;
  final VoidCallback onEscape;

  const KitFlowFrame({
    super.key,
    required this.top,
    required this.body,
    required this.foot,
    required this.onEscape,
  });

  static bool phone(BuildContext context) => KitD.phone(context);

  /// Opens a flow over the app, on the root navigator: the whole screen on a
  /// phone (no scrim to tap), wider the sheet over the panel scrim, which
  /// closes it. It rises 12 and fades in over `--dur-slow` `--ease-quill`
  /// (`cr-in`), and simply appears under reduced motion. The system back
  /// gesture pops it, as Escape does.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: !phone,
      barrierLabel: 'Close',
      // literal-ok: no scrim on a phone, where the flow IS the screen.
      barrierColor: phone ? const Color(0x00000000) : t.scrimPanel,
      transitionDuration: KitD.dur(context, AppMotion.durSlow),
      // A dialog route has no Material above it: without one, every Text
      // inherits the framework's fallback style — bold, with the yellow
      // double underline — which the first device frames showed.
      pageBuilder: (context, a, b) => Material(
        type: MaterialType.transparency,
        child: builder(context),
      ),
      transitionBuilder: (context, a, b, child) {
        final v = AppMotion.easeQuill.transform(a.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final mq = MediaQuery.of(context);
    final phone = KitFlowFrame.phone(context);
    final size = mq.size;
    final pad = phone ? mq.padding : EdgeInsets.zero;
    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: pad.top),
        top,
        Expanded(child: body),
        if (foot.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(top: BorderSide(color: t.rule)),
            ),
            padding: EdgeInsets.fromLTRB(24, 14, 24, 22 + pad.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < foot.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  foot[i],
                ],
              ],
            ),
          ),
      ],
    );
    final framed = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Camera roll',
      child: ClipRRect(
        borderRadius: phone ? BorderRadius.zero : AppRadius.xlR,
        child: Container(
          decoration: BoxDecoration(
            color: t.bg,
            boxShadow: phone ? null : AppShadows.s3,
          ),
          child: KitGround(child: sheet),
        ),
      ),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          onEscape();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: phone
          ? framed
          : Center(
              child: SizedBox(
                width: math.min(560, size.width - 32),
                height: math.min(880, size.height - 48),
                child: framed,
              ),
            ),
    );
  }
}

/// The flow's body: 24 on each side, 24 above, 28 below, scrolling inside the
/// frame (`overscroll-behavior: contain`).
class KitFlowBody extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;

  const KitFlowBody({super.key, required this.children, this.controller});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// `.cr-fo` / `.cr-tt` / `.cr-st` / `.cr-rl` — a flow page's masthead: the
/// folio in mono caps, the serif title (30–38 by width, `--letterpress`), an
/// italic standfirst in `--fg-lede`, and the double rule (2px over 1px).
class KitFlowMast extends StatelessWidget {
  final String folio;
  final String title;
  final String? stand;

  const KitFlowMast({
    super.key,
    required this.folio,
    required this.title,
    this.stand,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final size = (0.08 * w).clamp(30.0, 38.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          folio.toUpperCase(),
          style: AppTheme.mono(
            fontSize: 10.5,
            height: 16 / 10.5,
            letterSpacing: 0.14 * 10.5,
            color: t.fgMuted,
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTheme.serif(
              fontSize: size,
              height: 1.06,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.022 * size,
              color: t.fg,
              opsz: 48,
            ).copyWith(shadows: AppShadows.letterpress),
          ),
        ),
        if (stand != null) ...[
          const SizedBox(height: 12),
          Text(
            stand!,
            style: AppTheme.serif(
              fontSize: 17,
              height: 26 / 17,
              fontStyle: FontStyle.italic,
              color: t.fgLede,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          height: 5,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: t.fg, width: 2),
              bottom: BorderSide(color: t.fg, width: 1),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// `.cr-lb` — a flow page's label: mono caps 10.5, 24 above and 10 below.
class KitFlowLabel extends StatelessWidget {
  final String text;
  const KitFlowLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: AppTheme.mono(
          fontSize: 10.5,
          height: 14 / 10.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.16 * 10.5,
          color: Tokens.of(context).fgMuted,
        ),
      ),
    ),
  );
}

/// The flow's sentences: `.cr-p` (serif 16/25 `--fg`), `.cr-nt` (serif
/// italic 14.5/22 `--fg-lede`, 10 above) and the panel's `.dp-note` (italic
/// 14/21, 10 above).
class KitFlowText extends StatelessWidget {
  final String text;
  final _FlowTextRole _role;

  const KitFlowText.p(this.text, {super.key}) : _role = _FlowTextRole.p;
  const KitFlowText.note(this.text, {super.key}) : _role = _FlowTextRole.note;
  const KitFlowText.panelNote(this.text, {super.key})
    : _role = _FlowTextRole.panelNote;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return switch (_role) {
      _FlowTextRole.p => Text(
        text,
        style: AppTheme.serif(fontSize: 16, height: 25 / 16, color: t.fg),
      ),
      _FlowTextRole.note => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          text,
          style: AppTheme.serif(
            fontSize: 14.5,
            height: 22 / 14.5,
            fontStyle: FontStyle.italic,
            color: t.fgLede,
          ),
        ),
      ),
      _FlowTextRole.panelNote => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          text,
          style: AppTheme.serif(
            fontSize: 14,
            height: 21 / 14,
            fontStyle: FontStyle.italic,
            color: t.fgLede,
          ),
        ),
      ),
    };
  }
}

enum _FlowTextRole { p, note, panelNote }

/// `.cr-rows` — a ruled list under a 1px `--fg` rule.
class KitFlowRows extends StatelessWidget {
  final List<Widget> rows;
  const KitFlowRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).fg)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    ),
  );
}

/// `.cr-row` — one row of a [KitFlowRows]: an optional italic numeral in
/// `--accent-text` ([number]; the prototype's `--seal`, which 5l keeps off
/// text) or a [lead] (a photo tile), the title (serif 16/21,
/// [strong] at 600) over a sans 13/18 line, and an optional trailing word
/// ([trail]; [accent] draws it in `--accent-text`). 13 above and below, a
/// rule under it; [top] aligns to the first line.
class KitFlowRow extends StatelessWidget {
  final int? number;
  final Widget? lead;
  final String title;
  final String? sub;
  final bool strong;
  final String? trail;
  final bool accent;
  final bool top;

  const KitFlowRow({
    super.key,
    required this.title,
    this.number,
    this.lead,
    this.sub,
    this.strong = false,
    this.trail,
    this.accent = false,
    this.top = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        crossAxisAlignment: top
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (number != null) ...[
            SizedBox(
              width: 22,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '$number',
                  style: AppTheme.serif(
                    fontSize: 22,
                    height: 1,
                    fontStyle: FontStyle.italic,
                    // The prototype's `.cr-row-n` is `--seal`; a numeral is
                    // text, and 5l's ROLE floor sends text to the family's
                    // TEXT step (ADR-069).
                    color: t.accentText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (lead != null) ...[lead!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.serif(
                    fontSize: 16,
                    height: 21 / 16,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                    color: t.fg,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13,
                      height: 18 / 13,
                      color: t.fgMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trail != null) ...[
            const SizedBox(width: 12),
            Text(
              trail!,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12.5,
                color: accent ? t.accentText : t.fgMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.cr-rad` — one choice of a radio group: an 18px ring (`--border-strong`;
/// chosen, a 5px `--accent` ring), the label in serif 16, and an optional
/// count in mono 11 `--fg-subtle` at the trailing edge. 46 high at least,
/// a rule under it. [onTap] null holds it.
class KitFlowRadio extends StatelessWidget {
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback? onTap;

  const KitFlowRadio({
    super.key,
    required this.label,
    required this.selected,
    this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      label: label,
      selected: selected,
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, hover, focus) => Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.accent : t.borderStrong,
                  width: selected ? 5 : 1.5,
                ),
                boxShadow: focus
                    ? [BoxShadow(color: t.accent, spreadRadius: 2)]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTheme.serif(
                  fontSize: 16,
                  height: 21 / 16,
                  color: t.fg,
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 12),
              Text(
                count!,
                style: AppTheme.mono(fontSize: 11, color: t.fgSubtle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.cr-big` — a large measured count (serif 600 56, tabular) and what it
/// counts in italic 17 `--fg-lede`, on one baseline, 24 above.
class KitFlowBig extends StatelessWidget {
  final String figure;
  final String label;

  const KitFlowBig({super.key, required this.figure, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(
            figure,
            style: AppTheme.serif(
              fontSize: 56,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.03 * 56,
              color: t.fg,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: AppTheme.serif(
                fontSize: 17,
                fontStyle: FontStyle.italic,
                color: t.fgLede,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.cr-bar` (4px on `--surface-sunken`) or the top bar's 2px rule: a
/// measured fraction in `--accent`. Its width eases, but never under reduced
/// motion.
class KitFlowBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? track;

  const KitFlowBar({
    super.key,
    required this.value,
    this.height = 4,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: track ?? t.surfaceSunken,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: v),
          duration: KitD.dur(context, AppMotion.durSlow),
          curve: AppMotion.easeQuill,
          builder: (context, w, _) => FractionallySizedBox(
            widthFactor: w,
            heightFactor: 1,
            child: ColoredBox(color: t.accent),
          ),
        ),
      ),
    );
  }
}

/// `.cr-figs` — three figures over a 1px `--fg` rule, 20 above: each count in
/// serif 600 26 (tabular) over its label in sans 12.5/16 `--fg-muted`.
class KitFlowFigures extends StatelessWidget {
  final List<(String, String)> figures;

  const KitFlowFigures({super.key, required this.figures});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (n, label) in figures)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n,
                      style:
                          AppTheme.serif(
                            fontSize: 26,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: t.fg,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12.5,
                        height: 16 / 12.5,
                        color: t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.cr-sum` — the review's summary line: centred mono 10.5 `--fg-subtle`,
/// 14 under it.
class KitFlowSummary extends StatelessWidget {
  final String text;
  const KitFlowSummary(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTheme.mono(
        fontSize: 10.5,
        letterSpacing: 0.06 * 10.5,
        color: Tokens.of(context).fgSubtle,
      ),
    ),
  );
}

/// `.cr-tl` — a photo, read on the device: the small tile (44×56, `r 4`) in a
/// Just found row, or [large] (the width, at most 300 or 40% of the
/// screen's height, `--r-lg`) under review. Until its pixels arrive — or when
/// the photo is not on the device — the striped placeholder ground. [label]
/// names it for assistive technology (its date).
class KitPhotoTile extends StatefulWidget {
  final String photoId;
  final Future<Uint8List?> Function() load;
  final bool large;
  final String? label;

  const KitPhotoTile({
    super.key,
    required this.photoId,
    required this.load,
    this.large = false,
    this.label,
  });

  @override
  State<KitPhotoTile> createState() => _KitPhotoTileState();
}

class _KitPhotoTileState extends State<KitPhotoTile> {
  late Future<Uint8List?> _image;

  @override
  void initState() {
    super.initState();
    _image = _read();
  }

  @override
  void didUpdateWidget(KitPhotoTile old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) _image = _read();
  }

  Future<Uint8List?> _read() async {
    try {
      return await widget.load();
    } catch (e) {
      // The tile still stands without its picture — the photo was deleted,
      // or access changed under it.
      debugPrint('photo tile: no picture for ${widget.photoId} — $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final h = MediaQuery.sizeOf(context).height;
    final radius = widget.large
        ? AppRadius.lgR
        : const BorderRadius.all(Radius.circular(4));
    final tile = Container(
      width: widget.large ? double.infinity : 44,
      height: widget.large ? math.min(300, 0.4 * h) : 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: t.border),
      ),
      child: FutureBuilder<Uint8List?>(
        future: _image,
        builder: (context, snap) {
          final bytes = snap.data;
          return bytes == null
              ? CustomPaint(
                  painter: _Stripes(t.surfaceSunken, t.surface),
                  child: const SizedBox.expand(),
                )
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        },
      ),
    );
    return widget.label == null
        ? ExcludeSemantics(child: tile)
        : Semantics(
            image: true,
            label: widget.label,
            child: ExcludeSemantics(child: tile),
          );
  }
}

/// `repeating-linear-gradient(135deg, a 0 5px, b 5px 10px)`.
class _Stripes extends CustomPainter {
  final Color a, b;
  _Stripes(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    final p = Paint()
      ..color = a
      ..strokeWidth = 5;
    final span = size.width + size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < span; x += 10 * math.sqrt2) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Stripes old) => old.a != a || old.b != b;
}

/// `.cr-kick` (mono caps 10.5 `--accent-text`, 18 above) and `.cr-h3` (serif
/// 600 25/1.15, 6 under it): a waiting photo's kind and its heading.
class KitFlowKicker extends StatelessWidget {
  final String kicker;

  /// Null draws the kind alone (a photo that carries no date).
  final String? heading;

  const KitFlowKicker({super.key, required this.kicker, this.heading});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(
          kicker.toUpperCase(),
          style: AppTheme.mono(
            fontSize: 10.5,
            letterSpacing: 0.14 * 10.5,
            color: t.accentText,
          ),
        ),
        if (heading != null) ...[
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(
              heading!,
              style: AppTheme.serif(
                fontSize: 25,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.014 * 25,
                color: t.fg,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `.cr-pick`'s slot, which D's review fills with one sentence: sans 13.5 in
/// `--fg-muted` on `--surface-sunken`, `12 14`, 16 above.
class KitFlowSlot extends StatelessWidget {
  final String text;
  const KitFlowSlot(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.controlR(44),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.fontSans,
          fontSize: 13.5,
          height: 19 / 13.5,
          color: t.fgMuted,
        ),
      ),
    );
  }
}

/// `.cr-dots` — one dot per photo of the review, the current one a bar:
/// 6×6 `--border-strong`, the current 18 wide in `--accent`; 18 above.
class KitFlowDots extends StatelessWidget {
  final int count;
  final int current;

  const KitFlowDots({super.key, required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: i == current ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == current ? t.accent : t.borderStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The flow foot's controls: the primary (48 high, the full width,
/// `--r-c-48`, sans 15/500, an optional leading glyph), a ghost (44 high,
/// `--r-c-44`) — two side by side share the line ([KitFlowGhosts]) — and the
/// quiet link (`.cr-lnk`: sans 14 `--fg-muted`, 44 high, centred). [onTap]
/// null holds the control (`--held-opacity`).
class KitFlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final _FlowButtonRole _role;

  const KitFlowButton.primary(this.label, {super.key, this.icon, this.onTap})
    : _role = _FlowButtonRole.primary;
  const KitFlowButton.ghost(this.label, {super.key, this.icon, this.onTap})
    : _role = _FlowButtonRole.ghost;
  const KitFlowButton.link(this.label, {super.key, this.onTap})
    : icon = null,
      _role = _FlowButtonRole.link;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final held = onTap == null;
    final primary = _role == _FlowButtonRole.primary;
    final link = _role == _FlowButtonRole.link;
    final h = primary ? 48.0 : 44.0;
    final tap = KitDTap(
      label: label,
      enabled: !held,
      onTap: onTap,
      builder: (context, hover, focus) {
        final fg = primary ? t.accentFg : (hover ? t.fg : t.fgMuted);
        final bg = primary
            ? (hover ? t.accentHover : t.accent)
            : (!link && hover ? t.hover : null);
        return Container(
          height: h,
          padding: EdgeInsets.symmetric(horizontal: link ? 12 : 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.controlR(h),
            boxShadow: primary ? AppShadows.s1 : null,
            border: focus ? Border.all(color: t.accent, width: 2) : null,
          ),
          child: Row(
            mainAxisSize: link ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: primary ? 16 : 14, color: fg),
                const SizedBox(width: AppSpacing.s2),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: primary ? 15 : 14,
                    height: 1,
                    fontWeight: link ? FontWeight.w400 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    final held0 = Opacity(
      opacity: held ? AppSpacing.heldOpacity : 1,
      child: tap,
    );
    return link ? Center(child: held0) : held0;
  }
}

enum _FlowButtonRole { primary, ghost, link }

/// `.cr-btns` — ghosts side by side, 8 apart, sharing the line.
class KitFlowGhosts extends StatelessWidget {
  final List<Widget> children;
  const KitFlowGhosts({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: children[i]),
      ],
    ],
  );
}

/// `.cr-status` — the settings panel's status line: a 7px `--positive` dot
/// and the line in sans 13.5 `--fg-muted`, 14 above.
class KitFlowStatus extends StatelessWidget {
  final String text;
  const KitFlowStatus(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: t.positive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 13.5,
                height: 19 / 13.5,
                color: t.fgMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.cr-back` — the panel's reach as set (serif 16 `--fg`), its links at the
/// trailing edge on one baseline, wrapping under it on a narrow panel.
class KitFlowReach extends StatelessWidget {
  final String text;
  final List<Widget> links;

  const KitFlowReach({super.key, required this.text, this.links = const []});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 6,
    children: [
      Text(
        text,
        style: AppTheme.serif(
          fontSize: 16,
          height: 22 / 16,
          color: Tokens.of(context).fg,
        ),
      ),
      if (links.isNotEmpty) Wrap(spacing: 14, runSpacing: 6, children: links),
    ],
  );
}

/// `.cr-pnl-f` — the panel's foot: a rule, 22 above and 16 inside, then its
/// buttons (40 high) wrapping 8 apart. [danger] is the last one's
/// `--critical-text` label.
class KitFlowPanelFoot extends StatelessWidget {
  final List<Widget> children;
  const KitFlowPanelFoot({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 22),
    padding: const EdgeInsets.only(top: 16),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).rule)),
    ),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );
}

/// One button of [KitFlowPanelFoot]: a ghost 40 high, `--r-c-40`; [danger]
/// draws its label in `--critical-text`. [onTap] null holds it.
class KitFlowPanelButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool danger;
  final VoidCallback? onTap;

  const KitFlowPanelButton(
    this.label, {
    super.key,
    this.icon,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onTap == null ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        label: label,
        enabled: onTap != null,
        onTap: onTap,
        builder: (context, hover, focus) {
          final fg = danger ? t.criticalText : (hover ? t.fg : t.fgMuted);
          return Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: hover ? t.hover : null,
              borderRadius: AppRadius.controlR(40),
              border: focus ? Border.all(color: t.accent, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: AppSpacing.s2),
                ],
                Flexible(
                  child: Text(
                    label,
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
          );
        },
      ),
    );
  }
}

// ── The camera roll's dates ─────────────────────────────────────────────────

const List<String> _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A photo's day as the camera roll says it: `14 March`, with the year when
/// it is not this year (`14 March 2025`); [year] always adds it
/// (`Since 14 March 2026`). Local time.
String kitDayMonth(DateTime d, {bool year = false, DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final base = '${l.day} ${_monthsLong[l.month - 1]}';
  return year || l.year != n.year ? '$base ${l.year}' : base;
}

/// "looked {ago}" (the prototype's `ago`): `just now`, `{m}m ago`,
/// `{h}h ago`, `{d}d ago`, then the day (`Mar 14`).
String kitAgo(DateTime at, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final m = (n.difference(at).inSeconds / 60).round();
  if (m < 1) return 'just now';
  if (m < 60) return '${m}m ago';
  final h = (m / 60).round();
  if (h < 24) return '${h}h ago';
  final d = (h / 24).round();
  if (d < 7) return '${d}d ago';
  final l = at.toLocal();
  return '${_monthsShort[l.month - 1]} ${l.day}';
}
