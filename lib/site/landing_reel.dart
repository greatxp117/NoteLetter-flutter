// Plate I — the landing's film (ADR-178), web `pages/landing/Reel.jsx` and
// the `.pl-*` section of `landing-actual.css`. The score (`reel_score.dart`)
// says where every element is at any instant; this file builds the cast once
// per layout and theme, runs the clock, and hands each frame to the cast
// through notifiers that fire only when a value changed at the precision the
// reference's writer writes it — the writer that "skips any value that has
// not changed". Nothing here renders a frame from scratch: a part rebuilds
// when its own state moved, and the field repaints when a point did.
//
// The controls are the show reel's and the page's obligation both: anything
// that moves for longer than five seconds can be paused (WCAG 2.2.2), the
// chapters are buttons, and the track is a slider that scrubs. With reduced
// motion the film opens paused on the letter — chapter 05's still — and a
// chapter button paused shows that chapter's still rather than playing it.
// The clock stops when the plate leaves the scroll view's viewport, and the
// ticker is muted with the app (a hidden tab or a backgrounded app).
//
// Departures, each because the reference's mechanism does not exist here:
//  * The world is drawn with widgets for the paper and painters for the ink —
//    there is no SVG. `pathLength="1"` dash reveals are a path metric's first
//    `draw` of its length; `clip-path: inset()` is a fractional ClipRect.
//  * `--shadow-inset` is its two hairlines, as KitSearchField draws it:
//    Flutter casts no inner shadow.
//  * The slip's 3px shelf rule is a strip under a 1px three-sided border:
//    Flutter rounds no border whose sides differ in colour.
//  * The answer's highlight sweeps each line fragment of the mark, as
//    `box-decoration-break: clone` does, from the paragraph's own line boxes.
//  * "Off screen" is under 4% of the plate inside the scroll viewport —
//    IntersectionObserver's threshold — measured on scroll, not observed.
//  * `text-wrap: pretty` has no counterpart: a card's text can break a word
//    earlier or later than the reference's on its last two lines.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit_ground.dart';
import '../widgets/kit/kit_shell.dart' show KitQuill;
import 'landing_bits.dart' show svgPath;
import 'reel_motion.dart';
import 'reel_score.dart';

/// `00:05` — the timecode's clock face.
String reelTimecode(double s) {
  final v = math.max(0, s.floor());
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(v ~/ 60)}:${two(v % 60)}';
}

// ─── type ────────────────────────────────────────────────────────────────────
// Design sizes: the world is laid out in design pixels and scaled to the
// plate, so these are the reference's numbers. Leading is EVEN, as CSS
// splits a line box's half-leading.

TextStyle _mono(double size, double tracking, Color c, {double? height}) =>
    TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: size,
      letterSpacing: tracking * size,
      color: c,
      height: height,
      leadingDistribution: TextLeadingDistribution.even,
    );

TextStyle _sans(double size, Color c, {double? height, FontWeight? weight}) =>
    TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: size,
      color: c,
      height: height,
      fontWeight: weight,
      leadingDistribution: TextLeadingDistribution.even,
    );

TextStyle _serif(
  double size,
  Color c, {
  double? height,
  FontWeight weight = FontWeight.w400,
  double tracking = 0,
  double? opsz,
  bool italic = false,
  bool press = false,
}) =>
    AppTheme.serif(
      fontSize: size,
      fontWeight: weight,
      color: c,
      height: height,
      fontStyle: italic ? FontStyle.italic : null,
      letterSpacing: tracking * size,
      opsz: opsz,
    ).copyWith(
      leadingDistribution: TextLeadingDistribution.even,
      shadows: press ? AppShadows.letterpress : null,
    );

Color _alpha(Color c, double o) => c.withValues(alpha: c.a * o);

/// The line box a rule with no `line-height` of its own inherits — the page's
/// `body { line-height: var(--lh-base) }`, 24px — as a height for [size].
/// It sizes the card's foot, the slip's kind line, every chip without
/// `line-height: 1`, the letter's strap and kicker, the inbox's rows.
double _lb(double size) => 24 / size;

// ─── the parts a frame moves ─────────────────────────────────────────────────

class _Sel<T> {
  final String key;
  final T Function(ReelPart?) pick;
  final bool Function(T, T) eq;
  final ValueNotifier<T> n;
  _Sel(this.key, this.pick, this.eq, T initial) : n = ValueNotifier<T>(initial);

  void apply(ReelFrame f) {
    final v = pick(f[key]);
    if (!eq(v, n.value)) n.value = v;
  }
}

bool _samePart(ReelPart? a, ReelPart? b) {
  final sa = a?.shown ?? 0, sb = b?.shown ?? 0;
  if (sa == 0 && sb == 0) return true;
  return a != null && a.same(b);
}

bool _sameBars(List<WaveBar> a, List<WaveBar> b) => listEquals(a, b);

/// One layout's notifiers. A widget asks for the slice of a part it draws —
/// its placement, one custom property, its text — and is told only when
/// that slice changes.
class _Parts {
  ReelFrame frame;
  final List<String> fieldKeys;
  final ValueNotifier<int> fieldTick = ValueNotifier<int>(0);
  final Map<String, _Sel<dynamic>> _sels = {};

  _Parts(this.frame, this.fieldKeys);

  ValueListenable<T> sel<T>(
    String key,
    String tag,
    T Function(ReelPart?) pick, [
    bool Function(T, T)? eq,
  ]) {
    final s = _sels.putIfAbsent(
      '$key|$tag',
      () => _Sel<T>(key, pick, eq ?? (a, b) => a == b, pick(frame[key])),
    );
    return (s as _Sel<T>).n;
  }

  ValueListenable<ReelPart?> part(String key) =>
      sel<ReelPart?>(key, '@', (p) => p, _samePart);

  ValueListenable<double> shown(String key) =>
      sel<double>(key, 'o', (p) => p?.shown ?? 0);

  ValueListenable<double> v(String key, String name, double fallback) =>
      sel<double>(key, name, (p) => p?.vars?[name] ?? fallback);

  ValueListenable<List<WaveBar>> bars(String key) => sel<List<WaveBar>>(
    key,
    'bars',
    (p) => p?.bars ?? const <WaveBar>[],
    _sameBars,
  );

  void apply(ReelFrame next) {
    var moved = false;
    for (final k in fieldKeys) {
      if (!_samePart(next[k], frame[k])) {
        moved = true;
        break;
      }
    }
    frame = next;
    for (final s in _sels.values) {
      s.apply(next);
    }
    if (moved) fieldTick.value++;
  }

  void dispose() {
    for (final s in _sels.values) {
      s.n.dispose();
    }
    fieldTick.dispose();
  }
}

List<String> _fieldKeysOf(ReelField f) => [
  for (final s in reelShelves) 'R:${s.id}',
  for (final w in f.wires) 'W:${w.i}',
  for (var i = 0; i < 3; i++) 'P:$i',
  for (var i = 0; i < reelHits.length; i++) 'QW:$i',
  for (final d in f.dots) 'D:${d.i}',
  for (var i = 0; i < reelHits.length; i++) 'H:$i',
];

// ─── how a part is placed ────────────────────────────────────────────────────

/// The reference's `at()`: the part's centre at (x, y), turned r degrees and
/// scaled (s, sy) about that centre, at its opacity. The structure never
/// changes with the state, so a part that hides keeps its subtree mounted
/// (an `Opacity` of 0 paints nothing).
class _At extends StatelessWidget {
  final ValueListenable<ReelPart?> part;
  final Widget child;
  const _At(this.part, this.child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReelPart?>(
    valueListenable: part,
    child: RepaintBoundary(child: child),
    builder: (context, p, child) {
      final o = p?.shown ?? 0;
      final s = p?.s ?? 1;
      return Positioned(
        left: p?.x ?? 0,
        top: p?.y ?? 0,
        child: FractionalTranslation(
          translation: const Offset(-.5, -.5),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ((p?.r ?? 0) * math.pi / 180)
              ..scaleByDouble(s, p?.sy ?? s, 1, 1),
            child: Opacity(opacity: o, child: child),
          ),
        ),
      );
    },
  );
}

/// `tl()`: a plain offset — a title's word inside its line mask.
class _Tl extends StatelessWidget {
  final ValueListenable<ReelPart?> part;
  final Widget child;
  const _Tl(this.part, this.child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReelPart?>(
    valueListenable: part,
    child: child,
    builder: (context, p, child) =>
        Transform.translate(offset: Offset(p?.x ?? 0, p?.y ?? 0), child: child),
  );
}

/// `sr()`: scale and turn in place — for parts the sheet itself positions.
class _Sr extends StatelessWidget {
  final ValueListenable<ReelPart?> part;
  final Widget child;
  const _Sr(this.part, this.child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReelPart?>(
    valueListenable: part,
    child: child,
    builder: (context, p, child) {
      final s = p?.s ?? 1;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ((p?.r ?? 0) * math.pi / 180)
          ..scaleByDouble(s, s, 1, 1),
        child: Opacity(opacity: p?.shown ?? 0, child: child),
      );
    },
  );
}

/// `o()`: an opacity alone.
class _Op extends StatelessWidget {
  final ValueListenable<double> o;
  final Widget child;
  const _Op(this.o, this.child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: o,
    child: child,
    builder: (context, o, child) => Opacity(opacity: o, child: child),
  );
}

/// A short rule drawn on from its left end (`transform: scaleX(var(--…))`).
class _Rule extends StatelessWidget {
  final ValueListenable<double> draw;
  final double width;
  final Color color;
  const _Rule(this.draw, this.width, this.color);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: draw,
    builder: (context, d, _) => Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.diagonal3Values(d, 1, 1),
      child: Container(width: width, height: 1, color: color),
    ),
  );
}

/// `clip-path: inset(top right bottom 0)` as fractions of the box —
/// negative values reach outside it.
class _Inset extends CustomClipper<Rect> {
  final double top, right, bottom;
  const _Inset({this.top = 0, this.right = 0, this.bottom = 0});

  @override
  Rect getClip(Size s) => Rect.fromLTRB(
    0,
    top * s.height,
    s.width - right * s.width,
    s.height - bottom * s.height,
  );

  @override
  bool shouldReclip(_Inset old) =>
      old.top != top || old.right != right || old.bottom != bottom;
}

// ─── the cast ────────────────────────────────────────────────────────────────

class _Cast {
  final Tokens t;
  final ReelLayout l;
  final ReelField field;
  final _Parts parts;
  final String day;
  _Cast(this.t, this.l, this.field, this.parts, this.day);

  bool get tall => l.tall;

  Color tone(String shelf) =>
      AppColors.shelfColor(reelShelf(shelf).tone, dark: t.isDark) ?? t.fgMuted;

  Widget world() => SizedBox(
    key: ValueKey('reel-world-${l.name}'),
    width: l.w,
    height: l.h,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _FieldPainter(parts, field, t)),
          ),
        ),
        for (var i = 0; i < reelTitles.length; i++) title(i),
        for (final s in reelSources)
          if (l.cards[s.id] != null) _At(parts.part('C:${s.id}'), card(s)),
        for (var i = 0; i < l.anns.length; i++) _At(parts.part('A:$i'), ann(i)),
        for (final p in reelPassages)
          if (l.cards[p.src] != null) _At(parts.part('S:${p.id}'), slip(p)),
        for (final s in reelShelves)
          _At(parts.part('L:${s.id}'), shelfLabel(s)),
        _At(parts.part('Q'), search()),
        _At(parts.part('LT'), letter()),
        for (var i = 0; i < reelHits.length; i++)
          _At(parts.part('X:$i'), answer(i)),
        if (l.callout != null) _At(parts.part('CO'), callout()),
        if (l.curve != null) _At(parts.part('CV'), curve()),
        _At(parts.part('IN'), inbox()),
        if (l.listen != null) _At(parts.part('LS'), listen()),
      ],
    ),
  );

  // ── the chapter lines ──
  Widget title(int i) {
    final size = l.title.size;
    final ebSize = tall ? 11.0 : 10.5;
    final line = _serif(
      size,
      t.fg,
      height: 1.12,
      weight: FontWeight.w600,
      tracking: -.028,
      opsz: 60,
      press: true,
    );
    final accent = _serif(
      size,
      t.accent,
      height: 1.12,
      weight: FontWeight.w500,
      tracking: -.028,
      opsz: 60,
      italic: true,
      press: true,
    );
    final ch = reelChapters[i];
    final ebStyle = _mono(ebSize, .16, t.fgMuted, height: 1);
    final eb = _Op(
      parts.shown('T$i:eb'),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ch.n, style: ebStyle.copyWith(color: t.accentText)),
          const SizedBox(width: 9),
          _Rule(parts.v('T$i:eb', '--pl-rule', 0), 20, t.borderStrong),
          const SizedBox(width: 9),
          Text(ch.name.toUpperCase(), style: ebStyle),
        ],
      ),
    );
    Widget lineOf(int li) {
      final words = reelTitles[i][li];
      return ClipRect(
        child: Padding(
          padding: EdgeInsets.only(right: .12 * size, bottom: .08 * size),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var wi = 0; wi < words.length; wi++)
                Padding(
                  padding: EdgeInsets.only(right: .24 * size),
                  child: _Tl(
                    parts.part('T$i:$li:$wi'),
                    Text(
                      words[wi],
                      style: li == 0 ? line : accent,
                      softWrap: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      left: l.title.x,
      top: l.title.y,
      child: _Op(
        parts.shown('T$i'),
        RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eb,
              SizedBox(height: tall ? 7 : 10),
              lineOf(0),
              // `.pl-line { margin-bottom: -.08em }`: the second line's box
              // starts one line-height below the first.
              Transform.translate(
                offset: Offset(0, -.08 * size),
                child: lineOf(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.pl-kind` — the accent chip a kind is set in.
  Widget chip(
    String text,
    double size, {
    double tracking = .12,
    double? height = 1,
    EdgeInsets pad = const EdgeInsets.fromLTRB(6, 3, 6, 2),
  }) => Container(
    padding: pad,
    decoration: ShapeDecoration(
      color: t.accentChipBg,
      shape: StadiumBorder(side: BorderSide(color: t.accentChipBorder)),
    ),
    child: Text(
      text.toUpperCase(),
      style: _mono(size, tracking, t.accentChipFg, height: height),
      softWrap: false,
    ),
  );

  // ── 01 the sources ──
  Widget card(ReelSource s) {
    final c = l.cards[s.id]!;
    final key = 'C:${s.id}';
    final txtSize = tall ? 13.5 : 12.5;
    final body = LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        return ValueListenableBuilder<double>(
          valueListenable: parts.v(key, '--pl-p', 0),
          child: media(s, c, Size(box.maxWidth, h)),
          builder: (context, p, raw) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRect(
                  clipper: _Inset(top: p),
                  child: raw,
                ),
              ),
              Positioned.fill(
                child: ClipRect(
                  clipper: _Inset(bottom: 1 - p),
                  child: Text(
                    s.text,
                    style: _serif(
                      txtSize,
                      t.fg,
                      height: (tall ? 18 : 17) / txtSize,
                      opsz: 14,
                    ),
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              Positioned(
                left: -12,
                right: -12,
                top: p * h - 1,
                height: 2,
                child: _Op(
                  parts.v(key, '--pl-scan', 0),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accent,
                      boxShadow: [
                        BoxShadow(
                          color: t.highlight,
                          blurRadius: 16,
                          spreadRadius: 3,
                        ),
                        BoxShadow(color: t.accentSoft, spreadRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    final face = Container(
      width: c.w,
      height: c.h,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.smR,
        boxShadow: AppShadows.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: Row(
              children: [
                chip(s.kind, tall ? 9.5 : 8.5),
                const SizedBox(width: 8),
                Expanded(
                  child: tall
                      ? const SizedBox()
                      : Text(
                          s.meta.toUpperCase(),
                          textAlign: TextAlign.right,
                          style: _mono(8.5, .08, t.fgMuted),
                          softWrap: false,
                          overflow: TextOverflow.visible,
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 7),
              child: body,
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    s.title,
                    style: _serif(
                      12.5,
                      t.fg,
                      height: _lb(12.5),
                      weight: FontWeight.w600,
                      opsz: 14,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  s.stamp,
                  style: _mono(
                    tall ? 9.5 : 9,
                    .06,
                    t.accentText,
                    height: _lb(tall ? 9.5 : 9),
                  ),
                  softWrap: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // `.pl-card::after` — the lift a card lands with: --shadow-3 at
    // `--pl-lift`, over its resting --shadow-2.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: parts.v(key, '--pl-lift', 0),
            builder: (context, lift, _) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadius.smR,
                boxShadow: [
                  for (final b in AppShadows.s3)
                    b.copyWith(color: _alpha(b.color, lift)),
                ],
              ),
            ),
          ),
        ),
        face,
      ],
    );
  }

  /// The face each source shows before it is read.
  Widget media(ReelSource s, ReelCard c, Size body) {
    switch (s.media) {
      case 'video':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: t.surfaceSunken,
                  borderRadius: AppRadius.xsR,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: ShapeDecoration(
                        color: t.accent,
                        shape: const CircleBorder(),
                        shadows: AppShadows.s2,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Center(child: _Glyph.play(13, t.accentFg)),
                      ),
                    ),
                    if (!tall)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 6,
                        child: Text(
                          '…attention is a currency. It is not.',
                          textAlign: TextAlign.center,
                          style: _sans(9.5, t.fg, height: 12 / 9.5),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: t.borderStrong),
                    ValueListenableBuilder<double>(
                      valueListenable: parts.v('C:vid', '--pl-play', .6),
                      builder: (context, play, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: play,
                        child: ColoredBox(color: t.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'page':
        return CustomPaint(painter: _PageFace(t), size: body);
      case 'ink':
        final bodyW = c.w - 24;
        return ValueListenableBuilder<double>(
          valueListenable: parts.v('C:note', '--pl-ink', 0),
          builder: (context, ink, _) => CustomPaint(
            painter: _InkFace(_inkFor(bodyW), bodyW, ink, t.fgMuted),
            size: body,
          ),
        );
      case 'audio':
        return Center(
          child: SizedBox(
            width: body.width,
            height: math.min(38, body.height),
            child: CustomPaint(
              painter: _WaveFace(
                [
                  (parts.bars('C:pod:heard'), t.accent),
                  (parts.bars('C:pod:ahead'), t.borderStrong),
                ],
                c.w - 32,
                38,
                stretch: true,
              ),
            ),
          ),
        );
      case 'mic':
        return Row(
          children: [
            // `flex: none` — the disc keeps its 30px in a body shorter than
            // it (the tall stage's is 10) and the raw face's clip cuts it.
            SizedBox(
              width: 30,
              height: body.height,
              child: OverflowBox(
                minHeight: 30,
                maxHeight: 30,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: ShapeDecoration(
                    color: t.accentSoft,
                    shape: const CircleBorder(),
                  ),
                  child: Center(child: _Glyph.mic(15, t.seal)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: math.min(38, body.height),
                child: CustomPaint(
                  painter: _WaveFace(
                    [(parts.bars('C:memo:bars'), t.borderStrong)],
                    c.w - 92,
                    30,
                    stretch: true,
                  ),
                ),
              ),
            ),
          ],
        );
      case 'article':
        return CustomPaint(painter: _ArtFace(t), size: body);
      case 'slides':
        return CustomPaint(painter: _DeckFace(t), size: body);
      default:
        return CustomPaint(painter: _BookFace(t), size: body);
    }
  }

  static final Map<double, List<List<Pt>>> _ink = {};
  List<List<Pt>> _inkFor(double w) =>
      _ink.putIfAbsent(w, () => inkLines(w, const [20, 44, 68], 7));

  // ── 02 the reading ──
  Widget ann(int i) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Rule(parts.v('A:$i', '--pl-rule', 0), 22, t.accent),
      const SizedBox(width: 9),
      Text(
        l.anns[i].text.toUpperCase(),
        style: _mono(10, .12, t.accentText),
        softWrap: false,
      ),
    ],
  );

  /// A slip of a passage; in flight it closes into a bead of its shelf's
  /// colour.
  Widget slip(ReelPassage p) {
    final src = reelSource(p.src);
    final col = tone(p.shelf);
    return ValueListenableBuilder<double>(
      valueListenable: parts.v('S:${p.id}', '--pl-bead', 0),
      builder: (context, bead, _) {
        final r = BorderRadius.circular(AppRadius.xs + bead * 24);
        return Container(
          width: l.slip.w,
          height: l.slip.h,
          decoration: BoxDecoration(borderRadius: r, boxShadow: AppShadows.s2),
          child: ClipRRect(
            borderRadius: r,
            child: ColoredBox(
              color: col,
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border(
                      top: BorderSide(color: t.border),
                      right: BorderSide(color: t.border),
                      bottom: BorderSide(color: t.border),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // `overflow: hidden` — the kind's 24px line and two
                      // lines of quote run past a 66px slip by a hair.
                      Positioned.fill(
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(11, 7, 10, 8),
                              child: Opacity(
                                opacity: 1 - bead,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${src.kind} · ${src.stamp}'
                                          .toUpperCase(),
                                      style: _mono(
                                        8.5,
                                        .12,
                                        t.accentText,
                                        height: _lb(8.5),
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      p.q,
                                      style: _serif(
                                        12,
                                        t.fg,
                                        height: 16 / 12,
                                        opsz: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ColoredBox(color: _alpha(col, bead)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 03 the field's labels ──
  Widget shelfLabel(ReelShelf s) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: tone(s.id),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        s.name,
        style: _serif(
          tall ? 16 : 19,
          t.fg,
          weight: FontWeight.w500,
          italic: true,
          opsz: 20,
        ),
        softWrap: false,
      ),
    ],
  );

  // ── 04 the question and its answers ──
  Widget search() {
    final s = l.search;
    return Container(
      width: s.w,
      height: s.h,
      padding: tall
          ? const EdgeInsets.symmetric(horizontal: 14)
          : const EdgeInsets.only(left: 18, right: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.borderStrong),
        borderRadius: AppRadius.controlR(tall ? 48 : 58),
        boxShadow: AppShadows.s3,
      ),
      child: Row(
        children: [
          _Glyph.search(18, t.fgMuted),
          SizedBox(width: tall ? 10 : 12),
          Expanded(
            child: ClipRect(
              child: Row(
                children: [
                  Flexible(
                    child: ValueListenableBuilder<String>(
                      valueListenable: parts.sel<String>(
                        'Q:txt',
                        'x',
                        (p) => p?.text ?? '',
                      ),
                      builder: (context, txt, _) => Text(
                        txt,
                        style: _serif(tall ? 12.5 : 19, t.fg, opsz: 20),
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: _Op(
                      parts.shown('Q:caret'),
                      Container(
                        width: 2,
                        height: tall ? 16 : 22,
                        color: t.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!tall) ...[
            const SizedBox(width: 12),
            _Op(
              parts.shown('Q:n'),
              chip(
                '3 passages',
                10,
                tracking: .1,
                height: _lb(10),
                pad: const EdgeInsets.fromLTRB(10, 5, 10, 4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget answer(int i) {
    final h = reelHits[i];
    final size = tall ? 13.5 : 14.5;
    return Container(
      width: l.results.w,
      padding: tall
          ? const EdgeInsets.fromLTRB(13, 9, 13, 10)
          : const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              chip(h.kind, tall ? 9.5 : 8.5),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  h.src,
                  style: _sans(
                    tall ? 12 : 11.5,
                    t.fgMuted,
                    height: _lb(tall ? 12 : 11.5),
                  ),
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                h.at,
                style: _mono(9.5, .06, t.fgMuted, height: _lb(9.5)),
                softWrap: false,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<double>(
            valueListenable: parts.v('X:$i', '--pl-hl', 0),
            builder: (context, hl, _) => _MarkText(
              before: h.before,
              mark: h.mark,
              sweep: hl,
              style: _serif(
                size,
                t.fg,
                height: (tall ? 18 : 21) / size,
                opsz: 16,
              ),
              mark0: t.highlight,
              maxLines: tall ? 2 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget callout() => SizedBox(
    width: 360,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _Rule(parts.v('CO', '--pl-rule', 0), 24, t.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'The essay shares no word with the question. It was found by meaning.',
            style: _serif(14, t.fgMuted, height: 20 / 14, italic: true),
          ),
        ),
      ],
    ),
  );

  // ── 05 the letter ──
  Widget letter() {
    final lt = l.letter;
    final mono = _mono(10, .14, t.fgMuted, height: _lb(10));
    final shSize = tall ? 9.5 : 9.0;
    final sh = _mono(shSize, .12, t.fgMuted, height: _lb(shSize));
    final titleSize = tall ? 26.0 : 30.0;
    final titleStyle = _serif(
      titleSize,
      t.fg,
      height: 1.12,
      weight: FontWeight.w600,
      tracking: -.022,
      opsz: 32,
      press: true,
    );
    final pSize = tall ? 13.0 : 14.5;
    return Container(
      width: lt.w,
      height: lt.h,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s3,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 24,
            right: 70,
            top: 22,
            child: _Op(
              parts.shown('LT:strap'),
              Row(
                children: [
                  Text('№ 124', style: mono.copyWith(color: t.accentText)),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      '$day, 6:30'.toUpperCase(),
                      style: mono,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 22,
            top: 14,
            width: 30,
            height: 30,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Sr(
                    parts.part('LT:ring'),
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: CircleBorder(
                          side: BorderSide(color: t.seal, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _Sr(
                    parts.part('LT:seal'),
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: t.accentSoft,
                        shape: const CircleBorder(),
                      ),
                      child: Center(child: KitQuill(size: 15, color: t.seal)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 52,
            height: 2,
            child: _Rule0(parts.v('LT:rule', '--pl-draw', 0), t.fg),
          ),
          Positioned(
            left: 24,
            top: tall ? 62 : 68,
            child: _Op(
              parts.shown('LT:kick'),
              Text(
                'Four passages · two returning'.toUpperCase(),
                style: _mono(9.5, .16, t.accentText, height: _lb(9.5)),
                softWrap: false,
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: tall ? 78 : 84,
            child: ValueListenableBuilder<double>(
              valueListenable: parts.v('LT:title', '--pl-wipe', 0),
              builder: (context, wipe, _) => ClipRect(
                clipper: _Inset(top: -.2, right: 1 - wipe, bottom: -.2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Margin & '),
                      TextSpan(
                        text: 'Memory',
                        style: _serif(
                          titleSize,
                          t.accent,
                          height: 1.12,
                          weight: FontWeight.w500,
                          tracking: -.022,
                          opsz: 32,
                          italic: true,
                          press: true,
                        ),
                      ),
                    ],
                  ),
                  style: titleStyle,
                  softWrap: false,
                ),
              ),
            ),
          ),
          for (var i = 0; i < reelSections.length; i++)
            _At(
              parts.part('LT:s$i'),
              SizedBox(
                width: lt.w - 48,
                height: lt.row - 10,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Container(
                    padding: EdgeInsets.only(top: tall ? 8 : 10),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.rule)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '§ 0${i + 1}',
                                      style: TextStyle(color: t.accentText),
                                    ),
                                    const WidgetSpan(
                                      child: SizedBox(width: 10),
                                    ),
                                    TextSpan(
                                      text:
                                          '${reelSections[i].kind} · ${reelSections[i].at}'
                                              .toUpperCase(),
                                    ),
                                  ],
                                ),
                                style: sh,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                            const Spacer(),
                            if (reelSections[i].back != null)
                              _Op(
                                parts.shown('LT:b$i'),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    7,
                                    3,
                                    7,
                                    2,
                                  ),
                                  decoration: ShapeDecoration(
                                    color: t.positiveChipBg,
                                    shape: StadiumBorder(
                                      side: BorderSide(
                                        color: t.positiveChipBorder,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    (tall
                                            ? 'Returning'
                                            : 'Returning · ${reelSections[i].back}')
                                        .toUpperCase(),
                                    style: sh.copyWith(color: t.positiveChipFg),
                                    softWrap: false,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          reelSections[i].q,
                          style: _serif(
                            pSize,
                            t.fg,
                            height: (tall ? 17 : 20) / pSize,
                            opsz: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Fig. 1, compressed: left alone, and posted back.
  Widget curve() {
    final cv = l.curve!;
    return Container(
      width: cv.w,
      height: cv.h,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'SPACING',
                  style: TextStyle(color: t.accentText),
                ),
                const WidgetSpan(child: SizedBox(width: 8)),
                const TextSpan(text: 'ONE PASSAGE, OVER A YEAR'),
              ],
            ),
            style: _mono(9.5, .14, t.fgMuted, height: _lb(9.5)),
            softWrap: false,
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 304 / 150,
            child: CustomPaint(
              painter: _CurveFace(
                t,
                parts.v('CV:off', '--pl-draw', 0),
                parts.v('CV:on', '--pl-draw', 0),
                [
                  for (var i = 0; i < reelCurveMarks.length; i++)
                    parts.shown('CV:m$i'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration get _floating => BoxDecoration(
    color: t.surface,
    border: Border.all(color: t.border),
    borderRadius: AppRadius.mdR,
    boxShadow: AppShadows.s3,
  );

  Widget _sealDisc(Widget child) => Container(
    width: 30,
    height: 30,
    decoration: ShapeDecoration(
      color: t.accentSoft,
      shape: const CircleBorder(),
    ),
    child: Center(child: child),
  );

  Widget inbox() => Container(
    width: l.inbox.w,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: _floating,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sealDisc(KitQuill(size: 13, color: t.seal)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NoteLetter',
                    style: _sans(
                      12,
                      t.fg,
                      height: _lb(12),
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text('6:30', style: _mono(10, 0, t.fgMuted, height: _lb(10))),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '№ 124 Margin & Memory',
                style: _sans(
                  tall ? 13.5 : 12.5,
                  t.fg,
                  height: _lb(tall ? 13.5 : 12.5),
                  weight: FontWeight.w500,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              if (!tall) ...[
                const SizedBox(height: 1),
                Text(
                  'Four passages · two returning',
                  style: _sans(11.5, t.fgMuted, height: _lb(11.5)),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget listen() => Container(
    width: l.listen!.w,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: _floating,
    child: Row(
      children: [
        _sealDisc(
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _Glyph.play(12, t.seal),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Read aloud',
                style: _sans(
                  12,
                  t.fg,
                  height: _lb(12),
                  weight: FontWeight.w600,
                ),
                softWrap: false,
              ),
              const SizedBox(height: 1),
              Text(
                'Your private podcast feed',
                style: _sans(11, t.fgMuted, height: _lb(11)),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56,
          height: 22,
          child: CustomPaint(
            painter: _WaveFace(
              [(parts.bars('LS:bars'), t.borderStrong)],
              64,
              22,
              stretch: false,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A rule the full width of its box, drawn on from the left.
class _Rule0 extends StatelessWidget {
  final ValueListenable<double> draw;
  final Color color;
  const _Rule0(this.draw, this.color);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: draw,
    builder: (context, d, _) => Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.diagonal3Values(d, 1, 1),
      child: ColoredBox(color: color),
    ),
  );
}

/// A paragraph with its marked run highlighted from the left to [sweep] of
/// each line fragment's width — `box-decoration-break: clone` under a
/// background sized `calc(var(--pl-hl) * 100%)`.
class _MarkText extends StatelessWidget {
  final String before;
  final String mark;
  final double sweep;
  final TextStyle style;
  final Color mark0;
  final int? maxLines;
  const _MarkText({
    required this.before,
    required this.mark,
    required this.sweep,
    required this.style,
    required this.mark0,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final tp = TextPainter(
        text: TextSpan(style: style, text: before + mark),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: box.maxWidth);
      return SizedBox(
        width: box.maxWidth,
        height: tp.height,
        child: CustomPaint(
          painter: _MarkPainter(tp, before.length, mark.length, sweep, mark0),
        ),
      );
    },
  );
}

class _MarkPainter extends CustomPainter {
  final TextPainter tp;
  final int from, len;
  final double sweep;
  final Color color;
  _MarkPainter(this.tp, this.from, this.len, this.sweep, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep > 0 && len > 0) {
      final paint = Paint()..color = color;
      for (final b in tp.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: from + len),
      )) {
        final r = b.toRect();
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, r.width * sweep, r.height),
          paint,
        );
      }
    }
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.sweep != sweep || old.tp != tp || old.color != color;
}

// ─── glyphs ──────────────────────────────────────────────────────────────────

/// The reference's inline icons, on their 24-unit grid.
class _Glyph extends StatelessWidget {
  final double size;
  final Color color;
  final String kind;
  const _Glyph(this.kind, this.size, this.color);
  const _Glyph.play(double size, Color color) : this('play', size, color);
  const _Glyph.pause(double size, Color color) : this('pause', size, color);
  const _Glyph.search(double size, Color color) : this('search', size, color);
  const _Glyph.mic(double size, Color color) : this('mic', size, color);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GlyphPainter(kind, color)),
  );
}

class _GlyphPainter extends CustomPainter {
  final String kind;
  final Color color;
  _GlyphPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case 'play': // M8 5.5v13l10.5-6.5z
        canvas.drawPath(
          Path()
            ..moveTo(8, 5.5)
            ..lineTo(8, 18.5)
            ..lineTo(18.5, 12)
            ..close(),
          fill,
        );
      case 'pause': // M7.5 5.5h3v13h-3zM13.5 5.5h3v13h-3z
        canvas.drawRect(const Rect.fromLTWH(7.5, 5.5, 3, 13), fill);
        canvas.drawRect(const Rect.fromLTWH(13.5, 5.5, 3, 13), fill);
      case 'search': // circle 11,11 r7 · m20 20-3.5-3.5
        canvas.drawCircle(const Offset(11, 11), 7, stroke);
        canvas.drawLine(const Offset(20, 20), const Offset(16.5, 16.5), stroke);
      case 'mic':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(9, 3, 15, 14),
            const Radius.circular(3),
          ),
          stroke,
        );
        canvas.drawArc(
          const Rect.fromLTRB(6, 5, 18, 17),
          0,
          math.pi,
          false,
          stroke,
        );
        canvas.drawLine(const Offset(12, 17), const Offset(12, 20), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color;
}

// ─── faces ───────────────────────────────────────────────────────────────────

void _bar(Canvas c, double x, double y, double w, double h, Color col) =>
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(2),
      ),
      Paint()..color = col,
    );

/// `.pl-bars i` widths: every second 88%, the last 58%.
double _barW(int n, int count) => n == count ? .58 : (n.isEven ? .88 : 1);

/// `.pl-page`: eleven lines of a page, the sixth marked, the folio below.
class _PageFace extends CustomPainter {
  final Tokens t;
  _PageFace(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 11; i++) {
      final n = i + 1;
      final f = n == 11 ? .48 : (n % 4 == 2 ? .93 : (n % 3 == 0 ? .84 : 1.0));
      _bar(
        canvas,
        0,
        2 + i * 11.0,
        size.width * f,
        4,
        i == 5 ? t.highlightStrong : t.borderStrong,
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '61',
        style: _mono(8.5, 0, t.fgMuted, height: _lb(8.5)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, size.height - tp.height),
    );
  }

  @override
  bool shouldRepaint(_PageFace old) => old.t != t;
}

/// `.pl-art`: a lead image and five lines.
class _ArtFace extends CustomPainter {
  final Tokens t;
  _ArtFace(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final img = size.height * .44;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, img),
        const Radius.circular(AppRadius.xs),
      ),
      Paint()..color = t.surfaceSunken,
    );
    for (var i = 0; i < 5; i++) {
      _bar(
        canvas,
        0,
        img + 8 + i * 10.0,
        size.width * _barW(i + 1, 5),
        4,
        t.borderStrong,
      );
    }
  }

  @override
  bool shouldRepaint(_ArtFace old) => old.t != t;
}

/// `.pl-deck`: three slides fanned, the front one titled.
class _DeckFace extends CustomPainter {
  final Tokens t;
  _DeckFace(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(0, 6, size.width - 10, size.height);
    void sheet(Offset by, double o) {
      final rr = RRect.fromRectAndRadius(
        r.shift(by).deflate(.5),
        const Radius.circular(AppRadius.xs),
      );
      canvas.drawRRect(rr, Paint()..color = _alpha(t.surface, o));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _alpha(t.borderStrong, o),
      );
    }

    sheet(const Offset(10, -6), .5);
    sheet(const Offset(5, -3), .8);
    sheet(Offset.zero, 1);
    final x0 = r.left + 11, y0 = r.top + 10, cw = r.width - 22;
    // The front is a flex column: when the card is short (the tall stage)
    // its title shrinks to nothing and the three lines keep their 24px —
    // the title's minimum is 0, the lines' block is its content.
    final title = (r.height - 20 - 8 - 24).clamp(0.0, 7.0);
    if (title > 0) _bar(canvas, x0, y0, cw * .58, title, _alpha(t.accent, .7));
    for (var i = 0; i < 3; i++) {
      _bar(
        canvas,
        x0,
        y0 + title + 8 + i * 10.0,
        cw * _barW(i + 1, 3),
        4,
        t.borderStrong,
      );
    }
  }

  @override
  bool shouldRepaint(_DeckFace old) => old.t != t;
}

/// `.pl-book`: a spread, six lines a page about the gutter.
class _BookFace extends CustomPainter {
  final Tokens t;
  _BookFace(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = (size.width - 16) / 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()..color = t.border,
    );
    for (final x in [0.0, cw + 16]) {
      for (var i = 0; i < 6; i++) {
        _bar(canvas, x, 2 + i * 10.0, cw * _barW(i + 1, 6), 4, t.borderStrong);
      }
    }
  }

  @override
  bool shouldRepaint(_BookFace old) => old.t != t;
}

/// Handwriting, written on word by word as `--pl-ink` runs 0 → 1.
class _InkFace extends CustomPainter {
  final List<List<Pt>> words;
  final double viewW;
  final double ink;
  final Color color;
  _InkFace(this.words, this.viewW, this.ink, this.color);

  static final Map<List<List<Pt>>, List<(Path, double)>> _paths = {};

  List<(Path, double)> get _built => _paths.putIfAbsent(words, () {
    return [
      for (final w in words)
        () {
          final p = Path()..moveTo(w.first.$1, w.first.$2);
          for (final q in w.skip(1)) {
            p.lineTo(q.$1, q.$2);
          }
          final len = p.computeMetrics().fold<double>(
            0,
            (a, m) => a + m.length,
          );
          return (p, len);
        }(),
    ];
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ink <= 0) return;
    // viewBox `0 0 bodyW 80`, `xMinYMin meet`.
    final s = math.min(size.width / viewW, size.height / 80);
    canvas.scale(s);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final built = _built;
    for (var i = 0; i < built.length; i++) {
      final f = clamp01((ink - i / built.length) * 5);
      if (f <= 0) continue;
      final (path, len) = built[i];
      if (f >= 1) {
        canvas.drawPath(path, paint);
      } else {
        for (final m in path.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, len * f), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_InkFace old) =>
      old.ink != ink || old.color != color || old.words != words;
}

/// Audio bars from one or more sets; a viewBox `vw × vh` stretched to the box
/// (`preserveAspectRatio="none"`) or fitted and centred (`meet`).
class _WaveFace extends CustomPainter {
  final List<(ValueListenable<List<WaveBar>>, Color)> sets;
  final double vw, vh;
  final bool stretch;
  _WaveFace(this.sets, this.vw, this.vh, {required this.stretch})
    : super(repaint: Listenable.merge([for (final s in sets) s.$1]));

  @override
  void paint(Canvas canvas, Size size) {
    if (stretch) {
      canvas.scale(size.width / vw, size.height / vh);
    } else {
      final s = math.min(size.width / vw, size.height / vh);
      canvas.translate((size.width - vw * s) / 2, (size.height - vh * s) / 2);
      canvas.scale(s);
    }
    for (final (bars, color) in sets) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color;
      for (final (x, top, bottom) in bars.value) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WaveFace old) =>
      old.vw != vw ||
      old.vh != vh ||
      old.stretch != stretch ||
      old.sets != sets;
}

/// Fig. 1 in the plate's corner: the decay dashed and wiped on, the lifted
/// curve drawn along its length, the marks set down as it reaches them.
class _CurveFace extends CustomPainter {
  final Tokens t;
  final ValueListenable<double> off, on;
  final List<ValueListenable<double>> marks;
  _CurveFace(this.t, this.off, this.on, this.marks)
    : super(repaint: Listenable.merge([off, on, ...marks]));

  static const _decay = 'M12 16 C 50 82, 92 108, 150 115 S 250 121, 292 122';
  static const _lifted =
      'M12 16 C 34 52, 56 66, 79 72 C 80 42, 86 27, 93 23 '
      'C 110 41, 124 53, 135 59 C 136 35, 142 23, 151 21 C 175 33, 196 41, 208 45 '
      'C 209 29, 216 20, 227 18 C 250 22, 270 24, 292 25';
  static final Path _decayPath = svgPath(_decay);
  static final Path _liftedPath = svgPath(_lifted);
  static final double _liftedLen = _liftedPath.computeMetrics().fold<double>(
    0,
    (a, m) => a + m.length,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 304);
    final thin = Paint()..strokeWidth = 1;
    for (final (fx, _) in reelCurveMarks) {
      final x = 12 + fx * 280;
      canvas.drawLine(Offset(x, 10), Offset(x, 128), thin..color = t.rule);
    }
    canvas.drawLine(
      const Offset(6, 128),
      const Offset(298, 128),
      thin..color = t.borderStrong,
    );

    // Left alone: dashed 3 5, wiped on from the left over its fill box.
    final od = off.value;
    if (od > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-20, -20, 12 + 280 * od, 170));
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = t.fgSubtle;
      for (final m in _decayPath.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 8) {
          canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), p);
        }
      }
      canvas.restore();
    }
    // Posted back: drawn along its length.
    final dn = on.value;
    if (dn > 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = t.accent;
      if (dn >= 1) {
        canvas.drawPath(_liftedPath, p);
      } else {
        var left = _liftedLen * dn;
        for (final m in _liftedPath.computeMetrics()) {
          if (left <= 0) break;
          canvas.drawPath(m.extractPath(0, math.min(left, m.length)), p);
          left -= m.length;
        }
      }
    }
    for (var i = 0; i < reelCurveMarks.length; i++) {
      final o = marks[i].value;
      if (o <= 0) continue;
      final (fx, label) = reelCurveMarks[i];
      final c = Offset(12 + fx * 280, 128);
      if (i == 0) {
        canvas.drawCircle(c, 4, Paint()..color = _alpha(t.surfaceRaised, o));
        canvas.drawCircle(
          c,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _alpha(t.fgSubtle, o),
        );
      } else {
        canvas.drawCircle(c, 4, Paint()..color = _alpha(t.seal, o));
      }
      final tp = TextPainter(
        text: TextSpan(
          text: label.toUpperCase(),
          style: _mono(8.5, .1, _alpha(t.fgMuted, o)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(c.dx - tp.width / 2, 145 - base));
    }
  }

  @override
  bool shouldRepaint(_CurveFace old) =>
      old.t != t || old.off != off || old.on != on;
}

/// The index: rings, wires drawn on, the query's pulses and curved wires, the
/// points, and the halos of the three it finds — SVG order.
class _FieldPainter extends CustomPainter {
  final _Parts parts;
  final ReelField field;
  final Tokens t;
  final Map<String, Color> _tone;
  _FieldPainter(this.parts, this.field, this.t)
    : _tone = {
        for (final s in reelShelves)
          s.id: AppColors.shelfColor(s.tone, dark: t.isDark) ?? t.fgMuted,
      },
      super(repaint: parts.fieldTick);

  @override
  void paint(Canvas canvas, Size size) {
    final f = parts.frame;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final fill = Paint();

    for (final s in reelShelves) {
      final p = f['R:${s.id}'];
      final o = p?.shown ?? 0;
      if (o == 0) continue;
      final c = Offset(p!.x!, p.y!);
      final r = p.rad!;
      if (r <= 0) continue;
      final col = _tone[s.id]!;
      canvas.drawCircle(c, r, fill..color = _alpha(col, .05 * o));
      // stroke-dasharray: 2 5, from three o'clock, clockwise
      final dashes = Path();
      final rect = Rect.fromCircle(center: c, radius: r);
      final circ = 2 * math.pi * r;
      for (var d = 0.0; d < circ; d += 7) {
        dashes.addArc(rect, d / r, math.min(2, circ - d) / r);
      }
      canvas.drawPath(
        dashes,
        stroke
          ..strokeWidth = 1
          ..color = _alpha(col, o),
      );
    }

    for (final wr in field.wires) {
      final p = f['W:${wr.i}'];
      final o = p?.shown ?? 0;
      final draw = p?.draw ?? 0;
      if (o == 0 || draw <= 0) continue;
      final a = p!.a!, b = p.b!;
      final col = wr.bridge
          ? _alpha(t.fgSubtle, .45 * o)
          : _alpha(_tone[field.dots[wr.a].shelf]!, .6 * o);
      canvas.drawLine(
        Offset(a.$1, a.$2),
        Offset(a.$1 + (b.$1 - a.$1) * draw, a.$2 + (b.$2 - a.$2) * draw),
        stroke
          ..strokeWidth = 1
          ..color = col,
      );
    }

    for (var i = 0; i < 3; i++) {
      final p = f['P:$i'];
      final o = p?.shown ?? 0;
      if (o == 0 || (p!.rad ?? 0) <= 0) continue;
      canvas.drawCircle(
        Offset(p.x!, p.y!),
        p.rad!,
        stroke
          ..strokeWidth = 1.5
          ..color = _alpha(t.accent, o),
      );
    }

    for (var i = 0; i < reelHits.length; i++) {
      final p = f['QW:$i'];
      final o = p?.shown ?? 0;
      final draw = p?.draw ?? 0;
      if (o == 0 || draw <= 0) continue;
      final a = p!.a!, b = p.b!, c = p.c!;
      final path = Path()
        ..moveTo(a.$1, a.$2)
        ..quadraticBezierTo(c.$1, c.$2, b.$1, b.$2);
      final paint = stroke
        ..strokeWidth = 1.25
        ..color = _alpha(t.accent, o);
      if (draw >= 1) {
        canvas.drawPath(path, paint);
      } else {
        for (final m in path.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, m.length * draw), paint);
        }
      }
    }

    for (final d in field.dots) {
      final p = f['D:${d.i}'];
      final o = p?.shown ?? 0;
      final r = p?.rad ?? 0;
      if (o == 0 || r <= 0) continue;
      final c = Offset(p!.x!, p.y!);
      canvas.drawCircle(c, r, fill..color = _alpha(_tone[d.shelf]!, o));
      if (d.pid != null) {
        canvas.drawCircle(
          c,
          r,
          stroke
            ..strokeWidth = 1.5
            ..color = _alpha(t.surface, o),
        );
      }
    }

    for (var i = 0; i < reelHits.length; i++) {
      final p = f['H:$i'];
      final o = p?.shown ?? 0;
      if (o == 0 || (p!.rad ?? 0) <= 0) continue;
      final c = Offset(p.x!, p.y!);
      canvas.drawCircle(c, p.rad!, fill..color = _alpha(t.accentSoft, o));
      canvas.drawCircle(
        c,
        p.rad!,
        stroke
          ..strokeWidth = 1.5
          ..color = _alpha(t.accent, o),
      );
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.parts != parts || old.t != t || old.field != field;
}

// ─── the player ──────────────────────────────────────────────────────────────

/// Plate I: its header, the stage, the controls and the chapter's caption.
/// [phone] (≤640) runs the stage to the sheet's edges; the caller gives the
/// plate the sheet's full width there, and the header, controls and caption
/// take the 18px gutter back.
class LandingReel extends StatefulWidget {
  final String day;
  final bool phone;
  const LandingReel({super.key, required this.day, required this.phone});

  @override
  State<LandingReel> createState() => _LandingReelState();
}

class _LandingReelState extends State<LandingReel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _clock = ValueNotifier<double>(0);
  final _sec = ValueNotifier<int>(0);

  ReelLayout _layout = reelWide;
  ReelField _field = buildField(reelWide);
  late _Parts _parts;
  Widget? _world;
  Tokens? _worldTokens;

  double _t = 0;
  bool _playing = true;
  bool _visible = true;
  bool _scrubbing = false;
  bool _ready = false;
  int _chapter = 0;
  Duration? _last;
  ScrollableState? _scrollable;
  ScrollPosition? _pos;
  bool _hoverPlay = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      // Reduced motion opens paused on chapter 05's still — the letter, the
      // one frame that holds the whole argument. Play is the viewer's choice.
      if (MediaQuery.disableAnimationsOf(context)) {
        _playing = false;
        _chapter = reelChapters.length - 1;
        _t = reelChapters.last.key;
      }
      _parts = _Parts(_frameAt(_t), _fieldKeysOf(_field));
      _clock.value = _t;
      _sec.value = _t.floor();
    }
    _scrollable = Scrollable.maybeOf(context);
    final pos = _scrollable?.position;
    if (pos != _pos) {
      _pos?.removeListener(_measure);
      _pos = pos;
      _pos?.addListener(_measure);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _run();
  }

  @override
  void didUpdateWidget(LandingReel old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _world = null;
  }

  @override
  void dispose() {
    _pos?.removeListener(_measure);
    _ticker.dispose();
    _parts.dispose();
    _clock.dispose();
    _sec.dispose();
    super.dispose();
  }

  ReelFrame _frameAt(double t) =>
      paintReel(t, _layout, _field, ReelEase.tokens);

  /// The clock: runs only while playing, seen and not being scrubbed.
  void _run() {
    final go = _playing && _visible && !_scrubbing;
    if (go && !_ticker.isActive) {
      _last = null;
      _ticker.start();
    } else if (!go && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    if (last == null) return;
    final dt = math.min(0.1, (elapsed - last).inMicroseconds / 1e6);
    _t = (_t + dt) % reelDuration;
    _paint();
  }

  void _paint() {
    _parts.apply(_frameAt(_t));
    _clock.value = _t;
    final s = _t.floor();
    if (s != _sec.value) _sec.value = s;
    final ch = chapterAt(_t);
    if (ch != _chapter && mounted) setState(() => _chapter = ch);
  }

  void _seek(double t) {
    _t = ((t % reelDuration) + reelDuration) % reelDuration;
    _paint();
  }

  void _goChapter(int i) =>
      _seek(_playing ? reelChapters[i].at : reelChapters[i].key);

  void _toggle() {
    setState(() => _playing = !_playing);
    _run();
  }

  /// Off screen, the film holds its place and costs nothing: under 4% of the
  /// plate inside the scroll viewport stops the clock.
  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final vp = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    var seen = true;
    if (vp is RenderBox && vp.attached && vp.hasSize) {
      final r = box.localToGlobal(Offset.zero) & box.size;
      final v = vp.localToGlobal(Offset.zero) & vp.size;
      final i = r.intersect(v);
      final area = r.width * r.height;
      seen =
          i.width > 0 &&
          i.height > 0 &&
          area > 0 &&
          (i.width * i.height) / area >= .04;
    }
    if (seen != _visible) {
      _visible = seen;
      _run();
    }
  }

  /// A new layout is a new cast: a new field, new notifiers and a world built
  /// at the current instant — so the cast is never seen piled at the origin.
  /// Called from layout, so it notifies nothing.
  void _switchLayout(ReelLayout l) {
    final old = _parts;
    _layout = l;
    _field = buildField(l);
    _parts = _Parts(_frameAt(_t), _fieldKeysOf(_field));
    _world = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (!identical(t, _worldTokens)) _world = null;
    final phone = widget.phone;
    final gutter = EdgeInsets.symmetric(horizontal: phone ? 18 : 0);
    final hd = _mono(10, .16, t.fgMuted, height: _lb(10));
    return Semantics(
      container: true,
      label: "Plate I. One morning's work, a film in five chapters",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: gutter.copyWith(bottom: phone ? 0 : 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'PLATE I',
                        style: TextStyle(color: t.accentText),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: "One morning's work".toUpperCase()),
                    ],
                  ),
                  style: hd,
                ),
                Text(
                  'A schematic · illustrative library'.toUpperCase(),
                  style: hd,
                ),
              ],
            ),
          ),
          _stage(t, phone),
          const SizedBox(height: 14),
          Padding(padding: gutter, child: _controls(t, phone)),
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 18 : 48, 6, phone ? 18 : 0, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: phone ? 92 : 50,
                  maxWidth: _ch(t, phone) * 64,
                ),
                child: Text(
                  reelChapters[_chapter].caption,
                  style: _capStyle(t, phone),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _capStyle(Tokens t, bool phone) => _serif(
    phone ? 15 : 16,
    t.fgLede,
    height: phone ? 23 / 15 : 25 / 16,
    italic: true,
    opsz: 18,
  );

  /// One `ch` of the caption's face — the width of its "0".
  double _ch(Tokens t, bool phone) {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: _capStyle(t, phone)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  Widget _stage(Tokens t, bool phone) => LayoutBuilder(
    builder: (context, box) {
      final side = phone ? 0.0 : 1.0;
      final inner = box.maxWidth - 2 * side;
      final l = layoutFor(inner);
      if (l.name != _layout.name) _switchLayout(l);
      final fit = fitFor(l, inner);
      final world = _world ??= MediaQuery.withNoTextScaling(
        child: _Cast(t, _layout, _field, _parts, widget.day).world(),
      );
      _worldTokens = t;
      final radius = phone ? BorderRadius.zero : AppRadius.mdR;
      return Container(
        height: fit.height,
        decoration: BoxDecoration(
          color: t.bg,
          border: phone
              ? Border.symmetric(horizontal: BorderSide(color: t.border))
              : Border.all(color: t.border),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: phone
              ? BorderRadius.zero
              : BorderRadius.circular(AppRadius.md - 1),
          child: Stack(
            children: [
              Positioned.fill(
                child: KitGround(grain: false, child: const SizedBox.expand()),
              ),
              Positioned(
                left: fit.left,
                top: 0,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Transform.scale(
                      scale: fit.scale,
                      alignment: Alignment.topLeft,
                      child: world,
                    ),
                  ),
                ),
              ),
              // `--shadow-inset`: its two hairlines.
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1,
                child: ColoredBox(color: AppShadows.insetTop),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 1,
                child: ColoredBox(color: AppShadows.insetBottom),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ── the controls ──

  static int _flex(ReelChapter c) => ((c.end - c.at) * 10).round();

  Widget _controls(Tokens t, bool phone) {
    final gap = phone ? 10.0 : 14.0;
    final tcStyle = _mono(
      10.5,
      .08,
      t.fgMuted,
      height: _lb(10.5),
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final tcText = '00:00 / ${reelTimecode(reelDuration)}';
    final tcW = (TextPainter(
      text: TextSpan(text: tcText, style: tcStyle),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    final chStyle = _mono(10.5, phone ? .1 : .14, t.fgMuted, height: _lb(10.5));
    final play = Semantics(
      container: true,
      button: true,
      label: _playing ? 'Pause the film' : 'Play the film',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoverPlay = true),
        onExit: (_) => setState(() => _hoverPlay = false),
        child: GestureDetector(
          key: const ValueKey('reel-play'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            width: 34,
            height: 34,
            decoration: ShapeDecoration(
              color: _hoverPlay ? t.hoverStrong : t.surface,
              shape: CircleBorder(side: BorderSide(color: t.borderStrong)),
            ),
            child: Center(
              child: _playing ? _Glyph.pause(14, t.fg) : _Glyph.play(14, t.fg),
            ),
          ),
        ),
      ),
    );
    final track = LayoutBuilder(
      builder: (context, box) {
        void from(double dx) =>
            _seek(clamp01(dx / box.maxWidth) * reelDuration * 0.9999);
        return ValueListenableBuilder<int>(
          valueListenable: _sec,
          builder: (context, _, child) {
            final ch = reelChapters[chapterAt(_t)];
            return Semantics(
              container: true,
              slider: true,
              label: 'Film position',
              value: '${reelTimecode(_t)}, chapter ${ch.n}, ${ch.name}',
              increasedValue: reelTimecode(
                math.min(reelDuration - .01, _t + 1),
              ),
              decreasedValue: reelTimecode(math.max(0, _t - 1)),
              onIncrease: () => _seek(math.min(reelDuration - .01, _t + 1)),
              onDecrease: () => _seek(math.max(0, _t - 1)),
              child: child,
            );
          },
          child: Focus(
            onKeyEvent: _onTrackKey,
            child: GestureDetector(
              key: const ValueKey('reel-track'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => from(d.localPosition.dx),
              onHorizontalDragStart: (d) {
                _scrubbing = true;
                _run();
                from(d.localPosition.dx);
              },
              onHorizontalDragUpdate: (d) => from(d.localPosition.dx),
              onHorizontalDragEnd: (_) {
                _scrubbing = false;
                _run();
              },
              onHorizontalDragCancel: () {
                _scrubbing = false;
                _run();
              },
              child: SizedBox(
                height: 26,
                child: CustomPaint(
                  painter: _TrackPainter(_clock, t.borderStrong, t.accent),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        );
      },
    );
    final chapters = Row(
      children: [
        for (var i = 0; i < reelChapters.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            flex: _flex(reelChapters[i]),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                container: true,
                button: true,
                selected: i == _chapter,
                label: 'Chapter ${reelChapters[i].n}, ${reelChapters[i].name}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('reel-ch-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goChapter(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: reelChapters[i].n,
                            style: TextStyle(
                              color: i == _chapter ? t.accentText : t.fgMuted,
                            ),
                          ),
                          if (!phone) ...[
                            const WidgetSpan(child: SizedBox(width: 7)),
                            TextSpan(
                              text: reelChapters[i].name.toUpperCase(),
                              style: TextStyle(
                                color: i == _chapter ? t.fg : t.fgMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: chStyle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            play,
            SizedBox(width: gap),
            Expanded(child: track),
            SizedBox(width: gap),
            SizedBox(
              width: tcW,
              child: ValueListenableBuilder<int>(
                valueListenable: _sec,
                builder: (context, _, _) => Text(
                  '${reelTimecode(_t)} / ${reelTimecode(reelDuration)}',
                  style: tcStyle,
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(width: 34 + gap),
            Expanded(child: chapters),
            SizedBox(width: gap + tcW),
          ],
        ),
      ],
    );
  }

  KeyEventResult _onTrackKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final ch = chapterAt(_t);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      _seek(math.min(reelDuration - .01, _t + 1));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seek(math.max(0, _t - 1));
    } else if (k == LogicalKeyboardKey.pageDown) {
      _goChapter(math.min(reelChapters.length - 1, ch + 1));
    } else if (k == LogicalKeyboardKey.pageUp) {
      _goChapter(math.max(0, ch - 1));
    } else if (k == LogicalKeyboardKey.home) {
      _seek(0);
    } else if (k == LogicalKeyboardKey.end) {
      _seek(reelDuration - .01);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}

/// The track: five segments as long as their chapters, each filled with the
/// accent as far as the clock has run through it.
class _TrackPainter extends CustomPainter {
  final ValueListenable<double> clock;
  final Color rest, fill;
  _TrackPainter(this.clock, this.rest, this.fill) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 4.0;
    final total = reelChapters.fold<double>(0, (a, c) => a + (c.end - c.at));
    final w = size.width - gap * (reelChapters.length - 1);
    var x = 0.0;
    final y = (size.height - 3) / 2;
    for (final c in reelChapters) {
      final sw = w * (c.end - c.at) / total;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, sw, 3),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, Paint()..color = rest);
      final p = clamp01((clock.value - c.at) / (c.end - c.at));
      if (p > 0) {
        canvas.save();
        canvas.clipRRect(r);
        canvas.drawRect(Rect.fromLTWH(x, y, sw * p, 3), Paint()..color = fill);
        canvas.restore();
      }
      x += sw + gap;
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.rest != rest || old.fill != fill || old.clock != clock;
}
