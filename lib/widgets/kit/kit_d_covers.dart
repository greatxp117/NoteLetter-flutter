import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show kKindByType, kitDocKind, kitKindLabel;
import 'kit_shell.dart' show KitQuill;
import 'kit_source_link.dart';

// ── component-kit §33 — Covers (direction D) ─────────────────────────────────
//
// In Grid each source draws as THE OBJECT ITS TYPE IS — painted, no images, no
// thumbnails — in its shelf's cloth. Web reference: `kit/d/Cover.jsx` (COVERS,
// coverOf, typeLabel, Cover, CoverItem, CoverStrip) and the `Covers` section of
// `styles/app-home-shelves.css` (`.cvs-strip`, `.cvi*`, `.cv*`), whose geometry
// is in % of the cover and in `em`, where 1em = 10.4% of the item's width
// (`10.4cqi`). Every object below is laid out in those two units, so a cover
// is the same drawing at 116px on Home and at 52px on the source page's sheet.
//
// Colour: a cover is raw colour that does NOT flip, like §21's spines — it
// keeps its cloth and its paper type in both themes. Every raw step it paints
// with is one of AppColors' `cover*` constants (one value, no dark twin, so no
// pair half is ever named), or the shelf colour the caller resolved for the
// theme; the white and black below are the reference's rgba shades and sheens.

// ── The type vocabulary ──────────────────────────────────────────────────────

/// `COVERS[type] = (object, label)` — normative (§33's table). Every key of
/// [kKindByType] has an entry and every entry is a [kKindByType] key: both
/// directions are asserted by `test/kit/d_covers_test.dart` (umbrella trap: a
/// bucket nothing enumerates is a bucket that vanishes). `social_video`
/// (5.32.0, ADR-189) takes the film strip and reads *Video*.
const Map<String, (String, String)> kCovers = {
  'epub': ('epub', 'Book'),
  'pdf': ('pdf', 'Document'),
  'article': ('web', 'Web clip'),
  'url': ('web', 'Web clip'),
  'plain': ('note', 'Note'),
  'docx': ('type', 'Typescript'),
  'pptx': ('slides', 'Slides'),
  'image': ('photo', 'Image'),
  'image_set': ('prints', 'Images'),
  'youtube': ('screen', 'YouTube'),
  'instagram': ('print', 'Instagram'),
  'tiktok': ('vertical', 'TikTok'),
  'podcast': ('sleeve', 'Podcast'),
  'audio': ('tape', 'Recording'),
  'video': ('reel', 'Video'),
  'social_video': ('reel', 'Video'),
};

// A type no release has heard of falls back through its KIND ([kitDocKind],
// which defaults to `note`), so it still draws an object and a word — web's
// OBJECT_OF_KIND / LABEL_OF_KIND.
const _objectOfKind = <String, String>{
  'pdf': 'pdf',
  'epub': 'epub',
  'web': 'web',
  'note': 'note',
  'youtube': 'screen',
  'instagram': 'print',
  'tiktok': 'vertical',
  'podcast': 'sleeve',
  'video': 'reel',
};
const _labelOfKind = <String, String>{
  'pdf': 'Document',
  'epub': 'Book',
  'web': 'Web clip',
  'note': 'Note',
  'youtube': 'YouTube',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'podcast': 'Recording',
  'video': 'Video',
};

/// The object and the label a source's `type` draws as (web `coverOf`).
(String, String) kitCoverOf(String type) {
  final known = kCovers[type];
  if (known != null) return known;
  final kind = kitDocKind(type);
  return (
    _objectOfKind[kind] ?? 'note',
    _labelOfKind[kind] ?? kitKindLabel(type),
  );
}

/// The one word for a source's type wherever D names it — the cover's eyebrow,
/// rows, folios, intake (web `typeLabel`).
String kitTypeLabel(String type) => kitCoverOf(type).$2;

/// Every type the kit knows (the kind map's vocabulary; web `KNOWN_TYPES`).
List<String> get kitKnownTypes => kKindByType.keys.toList(growable: false);

/// A stable small number from a string — a cover's cloth depth is
/// `kitCoverHash(id) % 4`. Web `hash()` (`kit/d/format.js`):
/// `h = (h * 31 + charCode) >>> 0` over UTF-16 code units, unsigned 32-bit.
int kitCoverHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

// ── OKLab ────────────────────────────────────────────────────────────────────
// The cloth is CSS `color-mix(in oklab, …)` and, in dark, an `oklch(from …)`
// relative colour; Flutter has neither, so the conversion is here (Björn
// Ottosson's matrices, the ones CSS Color 4 specifies).

double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _toGamma(double c) => c <= 0.0031308
    ? 12.92 * c
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

double _cbrt(double x) => x < 0
    ? -math.pow(-x, 1 / 3).toDouble()
    : math.pow(x, 1 / 3).toDouble();

/// sRGB → OKLab `(L, a, b)`.
@visibleForTesting
(double, double, double) kitOklab(Color c) {
  final r = _toLinear(c.r), g = _toLinear(c.g), b = _toLinear(c.b);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// OKLab → sRGB, clamped into gamut.
@visibleForTesting
Color kitFromOklab(double lightness, double a, double b) {
  final (r, g, bl) = _linearOf(lightness, a, b);
  double ch(double v) => _toGamma(v).clamp(0.0, 1.0);
  return Color.from(alpha: 1, red: ch(r), green: ch(g), blue: ch(bl));
}

/// CSS `color-mix(in oklab, a wa, b)` for two opaque colours.
@visibleForTesting
Color kitMixOklab(Color a, Color b, double wa) {
  final (l1, a1, b1) = kitOklab(a);
  final (l2, a2, b2) = kitOklab(b);
  final wb = 1 - wa;
  return kitFromOklab(l1 * wa + l2 * wb, a1 * wa + a2 * wb, b1 * wa + b2 * wb);
}

// Light: `color-mix(in oklab, shelf N%, ink-700)` by tone.
const _lightMix = [0.70, 0.60, 0.74, 0.52];
// Dark: `oklch(from shelf calc(L0 + (l − .62) × .5) min(c × 1.2, .075) h)`.
const _darkL0 = [0.4, 0.375, 0.43, 0.355];

/// The cloth: the shelf colour (null → ink-500, an unshelved source) pressed
/// toward ink-700 in OKLab by [tone] (0..3, `hash(id) % 4`): 70 / 60 / 74 / 52 %.
/// [dark]: the shelf's hue kept at a lightness paper text reads on —
/// `L = L0 + (l − .62) × .5` with L0 .4 / .375 / .43 / .355, `C = min(c × 1.2,
/// .075)`. [shelf] is already resolved for the theme
/// (`AppColors.shelfColor(name, dark: …)`), as web's `--shelf` is.
Color kitCoverCloth(Color? shelf, int tone, {required bool dark}) {
  final base = shelf ?? AppColors.coverInk500;
  final i = tone % 4;
  if (!dark) return kitMixOklab(base, AppColors.coverInk700, _lightMix[i]);
  final (l, a, b) = kitOklab(base);
  final c = math.sqrt(a * a + b * b);
  final h = math.atan2(b, a);
  return _fromOklch(_darkL0[i] + (l - 0.62) * 0.5, math.min(c * 1.2, 0.075), h);
}

// OKLCH → sRGB, gamut-mapped as CSS Color 4 does: where the colour falls
// outside sRGB (a deep teal at L .38 does), the CHROMA comes down at the same
// lightness and hue until it fits — clamping each channel instead would turn
// the hue, and keeping the shelf's hue is the point of the dark cloth.
Color _fromOklch(double l, double c, double h) {
  bool fits(double chroma) {
    final (r, g, b) = _linearOf(l, chroma * math.cos(h), chroma * math.sin(h));
    const eps = 1e-6;
    return r >= -eps && r <= 1 + eps && g >= -eps && g <= 1 + eps &&
        b >= -eps && b <= 1 + eps;
  }

  var chroma = c;
  if (!fits(chroma)) {
    var lo = 0.0, hi = c;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    chroma = lo;
  }
  return kitFromOklab(l, chroma * math.cos(h), chroma * math.sin(h));
}

// OKLab → linear-light sRGB, unclamped.
(double, double, double) _linearOf(double lightness, double a, double b) {
  final l0 = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final m0 = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final s0 = lightness - 0.0894841775 * a - 1.2914855480 * b;
  final l = l0 * l0 * l0, m = m0 * m0 * m0, s = s0 * s0 * s0;
  return (
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  );
}

// ── Raw colour the cover prints with ─────────────────────────────────────────

const _paper = AppColors.coverPaper50;
const _ink = AppColors.coverInk700;
const _inkSoft = AppColors.coverInk400;
const _ink800 = AppColors.coverInk800;
const _black = Color(0xFF000000); // literal-ok: the reference's rgba(0,0,0,a) shades on the cover's cloth — only ever used under an alpha, as a scrim
const _white = Color(0xFFFFFFFF); // literal-ok: the reference's rgba(255,255,255,a) sheens on the cover's cloth — only ever used under an alpha, as a scrim

Color _shade(double a) => _black.withValues(alpha: a);
Color _sheen(double a) => _white.withValues(alpha: a);
Color _a(Color c, double a) => c.withValues(alpha: a);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Web `fmt.short` (`Oct 30`), local time; '' where nothing was stamped.
String _short(int? ms) {
  if (ms == null || ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[d.month - 1]} ${d.day}';
}

String _titleOf(Document d) => d.title.isEmpty ? 'Untitled' : d.title;

// `.cv` 2/5/5/2, `.cv-flat` 4, `.cv-print` 2.
const _flat = {
  'type', 'slides', 'photo', 'prints', 'screen', 'vertical', 'sleeve', //
  'tape', 'reel',
};
BorderRadius _radiusOf(String k, [double grow = 0]) {
  if (k == 'print') return BorderRadius.circular(2 + grow);
  if (_flat.contains(k)) return BorderRadius.circular(4 + grow);
  return BorderRadius.only(
    topLeft: Radius.circular(2 + grow),
    bottomLeft: Radius.circular(2 + grow),
    topRight: Radius.circular(5 + grow),
    bottomRight: Radius.circular(5 + grow),
  );
}

// ── The cover ────────────────────────────────────────────────────────────────

/// One source as the object its type is (§33): aspect 7/10, filling its width.
/// Hidden from assistive technology — the item around it names it.
class KitCover extends StatelessWidget {
  final Document doc;

  /// The home shelf's colour, already resolved for the theme; null → ink.
  final Color? shelf;

  // 0..1 — the item's hover lift, which deepens the cover's own shadow.
  final double _lift;

  const KitCover({super.key, required this.doc, this.shelf}) : _lift = 0;

  const KitCover._lifted({required this.doc, this.shelf, required double lift})
      : _lift = lift;

  @override
  Widget build(BuildContext context) {
    final dark = Tokens.of(context).isDark;
    final (k, label) = kitCoverOf(doc.type);
    final cloth = kitCoverCloth(shelf, kitCoverHash(doc.id) % 4, dark: dark);
    final author = doc.author;
    final date = _short(doc.createdAt);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 7 / 10,
        child: LayoutBuilder(builder: (context, box) {
          final f = _F(
            w: box.maxWidth,
            cloth: cloth,
            label: label,
            title: _titleOf(doc),
            by: (author == null || author.isEmpty) ? label : author,
            // The author's place on a note, an image and a set; the label
            // where nothing was stamped.
            date: date.isEmpty ? label : date,
          );
          return _frame(f, k,
              dark: dark, lift: _lift, unread: doc.viewCount == 0);
        }),
      ),
    );
  }
}

/// A cover's geometry and words: `w` the cover's width, `h` its height, `em`
/// the reference's `10.4cqi`.
class _F {
  final double w;
  final Color cloth;
  final String label, title, by, date;

  const _F({
    required this.w,
    required this.cloth,
    required this.label,
    required this.title,
    required this.by,
    required this.date,
  });

  double get h => w * 10 / 7;
  double get em => w * 0.104;
}

Widget _frame(_F f, String k,
    {required bool dark, required double lift, required bool unread}) {
  final radius = _radiusOf(k);
  final rest = dark
      ? [
          BoxShadow(color: _sheen(0.07), spreadRadius: 1),
          BoxShadow(
              color: _shade(0.7),
              offset: const Offset(0, 12),
              blurRadius: 22,
              spreadRadius: -12),
        ]
      : [
          BoxShadow(
              color: _a(_ink, 0.08),
              offset: const Offset(0, 1),
              blurRadius: 1),
          BoxShadow(
              color: _a(_ink, 0.5),
              offset: const Offset(0, 12),
              blurRadius: 20,
              spreadRadius: -12),
        ];
  // `.cvi:hover .cv` — the same in both themes, as the reference's selector
  // outranks its dark rule.
  final lifted = [
    BoxShadow(
        color: _a(_ink, 0.08), offset: const Offset(0, 1), blurRadius: 1),
    BoxShadow(
        color: _a(_ink, 0.55),
        offset: const Offset(0, 22),
        blurRadius: 28,
        spreadRadius: -14),
  ];
  final shadows =
      lift <= 0 ? rest : BoxShadow.lerpList(rest, lifted, lift.clamp(0, 1))!;

  // Below a legible size there is nothing to draw but the cloth.
  final drawn = f.w >= 24;
  return DecoratedBox(
    decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
    child: ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._ground(f, k),
          // `inset -1px 0 0 rgba(255,255,255,.06)` — the fore-edge catch.
          Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 1,
              child: ColoredBox(color: _sheen(0.06))),
          if (drawn) ..._parts(f, k),
          if (unread)
            Positioned(
              top: 0,
              right: 0.12 * f.w,
              width: 0.11 * f.w,
              height: 0.17 * f.h,
              child: ClipPath(
                key: const ValueKey('cover-ribbon'),
                clipper: const _RibbonClip(),
                child: const ColoredBox(color: AppColors.coverRibbon),
              ),
            ),
        ],
      ),
    ),
  );
}

// The ground each object is printed on.
List<Widget> _ground(_F f, String k) {
  final cloth = f.cloth;
  switch (k) {
    case 'epub':
    case 'pdf':
    case 'web':
      // `.cv` — cloth, with the spine's shade and catch at the hinge.
      return [
        ColoredBox(color: cloth),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_shade(0.32), _shade(0.08), _sheen(0.07), _sheen(0)],
              stops: const [0, 0.05, 0.075, 0.12],
            ),
          ),
        ),
      ];
    case 'note':
      // `.cv-note` — ruled paper with a cloth spine.
      return [
        const ColoredBox(color: AppColors.coverPaper100),
        CustomPaint(painter: _RulesPainter(1.9 * f.em, _a(_ink, 0.09))),
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 0.09 * f.w,
            child: ColoredBox(color: cloth)),
        Positioned(
            left: 0.09 * f.w,
            top: 0,
            bottom: 0,
            width: 0.008 * f.w,
            child: ColoredBox(color: _shade(0.14))),
      ];
    case 'print':
      // `.cv-print` — a white print, warming toward its foot.
      return [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _paper,
                kitMixOklab(_paper, AppColors.coverInk300, 0.88),
              ],
            ),
          ),
        ),
      ];
    case 'vertical':
      return [
        ColoredBox(color: kitMixOklab(cloth, _ink800, 0.5)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_sheen(0.05), _shade(0.14)],
            ),
          ),
        ),
      ];
    case 'reel':
      return [ColoredBox(color: kitMixOklab(cloth, _ink800, 0.7))];
    default:
      // `.cv-flat` — cloth under a top-lit sheen.
      return [
        ColoredBox(color: cloth),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_sheen(0.07), _shade(0.1)],
            ),
          ),
        ),
      ];
  }
}

List<Widget> _parts(_F f, String k) {
  switch (k) {
    case 'epub':
      return _epub(f);
    case 'pdf':
      return _pdf(f);
    case 'web':
      return _web(f);
    case 'type':
      return _typescript(f);
    case 'slides':
      return _slides(f);
    case 'photo':
      return _photo(f);
    case 'prints':
      return _prints(f);
    case 'screen':
      return _screen(f);
    case 'print':
      return _print(f);
    case 'vertical':
      return _vertical(f);
    case 'sleeve':
      return _sleeve(f);
    case 'tape':
      return _tape(f);
    case 'reel':
      return _reel(f);
    default:
      return _note(f);
  }
}

// ── The printed words ────────────────────────────────────────────────────────

/// `.cv-eb` — mono caps .56em, 0.2em tracking, opacity .88, one line.
Widget _eyebrow(_F f,
    {Color color = _paper, double opacity = 0.88, IconData? icon}) {
  final size = 0.56 * f.em;
  final c = _a(color, color.a * opacity);
  final text = Text(
    f.label.toUpperCase(),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
    textScaler: TextScaler.noScaling,
    style: AppTheme.mono(
        fontSize: size, letterSpacing: 0.2 * size, height: 1.2, color: c),
  );
  if (icon == null) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: size, color: c),
      SizedBox(width: 0.4 * size),
      Flexible(child: text),
    ],
  );
}

/// `.cv-t` — serif 600, line-height 1.16, clamped (5 lines; 3 in a caption),
/// with the paper type's `text-shadow`.
Widget _title(
  _F f, {
  double size = 1,
  int lines = 5,
  double height = 1.16,
  Color color = _paper,
  bool shadow = true,
  bool italic = false,
  FontWeight weight = FontWeight.w600,
  TextAlign align = TextAlign.start,
}) {
  var style = AppTheme.serif(
    fontSize: size * f.em,
    fontWeight: weight,
    height: height,
    color: color,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  );
  if (shadow) {
    style = style.copyWith(
        shadows: [Shadow(color: _shade(0.25), offset: const Offset(0, 1))]);
  }
  return _Clamp(f.title, style: style, lines: lines, align: align);
}

/// `.cv-a` — serif italic .8em, one line, ellipsis.
Widget _authorSerif(_F f, String s,
        {double size = 0.8,
        Color color = _paper,
        TextAlign align = TextAlign.start}) =>
    _oneLine(
      s,
      AppTheme.serif(
          fontSize: size * f.em,
          fontStyle: FontStyle.italic,
          height: 1.25,
          color: color),
      align: align,
    );

/// `.cv-a` set in mono — `.cv-flat .cv-a` (.54em, .1em, caps, opacity .85)
/// and the note's and broadside's variants.
Widget _authorMono(
  _F f,
  String s, {
  double size = 0.54,
  double tracking = 0.1,
  bool caps = true,
  Color color = _paper,
  double opacity = 0.85,
}) =>
    _oneLine(
      caps ? s.toUpperCase() : s,
      AppTheme.mono(
        fontSize: size * f.em,
        letterSpacing: tracking * size * f.em,
        height: 1.25,
        color: _a(color, color.a * opacity),
      ),
    );

Widget _oneLine(String s, TextStyle style, {TextAlign align = TextAlign.start}) =>
    Text(
      s,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      textScaler: TextScaler.noScaling,
      style: style,
    );

/// `.cv-seal` — the feather, 1em, at .7.
Widget _seal(_F f) => KitQuill(size: f.em, color: _a(_paper, 0.7));

/// A title clamped to [lines] AND to the lines its slot can hold: CSS clips an
/// overfull flex column silently, where a Flutter column would overflow — so a
/// title in a flexible slot takes whole lines only.
class _Clamp extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int lines;
  final TextAlign align;

  const _Clamp(this.text,
      {required this.style, required this.lines, required this.align});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final line = (style.fontSize ?? 12) * (style.height ?? 1.2);
      var n = lines;
      if (box.maxHeight.isFinite && line > 0) {
        n = math.max(1, math.min(lines, (box.maxHeight / line + 1e-6).floor()));
      }
      return Text(
        text,
        maxLines: n,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        textScaler: TextScaler.noScaling,
        style: style,
      );
    });
  }
}

// A title that takes the slot's remaining height, from its top.
Widget _fill(Widget title) =>
    Expanded(child: Align(alignment: Alignment.topLeft, child: title));

// ── The fourteen objects ─────────────────────────────────────────────────────

/// `.cv-epub` — a cloth book: framed binding, title, a short rule, author, the
/// feather seal.
List<Widget> _epub(_F f) {
  final e = f.em;
  return [
    Positioned(
      left: 0.11 * f.w,
      top: 0.06 * f.h,
      right: 0.07 * f.w,
      bottom: 0.06 * f.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: _a(_paper, 0.26)),
          borderRadius: BorderRadius.circular(1),
        ),
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(0.06 * f.w, 0.12 * f.w, 0.06 * f.w, 0.09 * f.w),
          child: Column(
            children: [
              _eyebrow(f),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                        child: _title(f, size: 1.1, align: TextAlign.center)),
                    Padding(
                      padding: EdgeInsets.only(top: 0.7 * e, bottom: 0.55 * e),
                      child: FractionallySizedBox(
                        widthFactor: 0.16,
                        child: SizedBox(
                            height: 1,
                            child: ColoredBox(color: _a(_paper, 0.55))),
                      ),
                    ),
                    _authorSerif(f, f.by, align: TextAlign.center),
                  ],
                ),
              ),
              SizedBox(height: 0.4 * e),
              _seal(f),
            ],
          ),
        ),
      ),
    ),
  ];
}

/// `.cv-pdf` — a paper band across the cloth, the seal at its foot.
List<Widget> _pdf(_F f) {
  final e = f.em;
  return [
    Positioned(top: 0.09 * f.h, left: 0.13 * f.w, child: _eyebrow(f)),
    Positioned(
      left: 0,
      right: 0,
      top: 0.27 * f.h,
      height: 0.46 * f.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _paper,
          border: Border.symmetric(
              horizontal: BorderSide(color: _shade(0.1))),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(0.13 * f.w, 0, 0.09 * f.w, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _title(f,
                    size: 1.02, lines: 4, color: _ink, shadow: false),
              ),
              SizedBox(height: 0.35 * 0.78 * e),
              _authorSerif(f, f.by, size: 0.78, color: _inkSoft),
            ],
          ),
        ),
      ),
    ),
    Positioned(bottom: 0.08 * f.h, left: 0.13 * f.w, child: _seal(f)),
  ];
}

/// `.cv-web` — a broadside: link-glyph eyebrow, title, author under a rule.
List<Widget> _web(_F f) {
  final e = f.em;
  return [
    Positioned.fill(
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(0.14 * f.w, 0.12 * f.w, 0.10 * f.w, 0.10 * f.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _eyebrow(f, icon: Icons.link),
            SizedBox(height: 0.75 * 1.16 * e),
            _fill(_title(f, size: 1.16, height: 1.1)),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _a(_paper, 0.3))),
              ),
              child: Padding(
                padding: EdgeInsets.only(top: 0.6 * 0.56 * e),
                child: _authorMono(f, f.by,
                    size: 0.56, tracking: 0.12, opacity: 1),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}

/// `.cv-note` — a ruled notebook with a cloth spine (the ground draws both).
List<Widget> _note(_F f) {
  final e = f.em;
  return [
    Positioned.fill(
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(0.19 * f.w, 0.13 * f.w, 0.09 * f.w, 0.10 * f.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _eyebrow(f, color: f.cloth, opacity: 1),
            SizedBox(height: 0.6 * 1.12 * e),
            _fill(_title(f,
                size: 1.12,
                italic: true,
                weight: FontWeight.w500,
                color: _ink,
                shadow: false)),
            _authorMono(f, f.date,
                size: 0.56, tracking: 0.1, color: _inkSoft, opacity: 1),
          ],
        ),
      ),
    ),
  ];
}

/// `.cv-type` — a typed page in its cloth folder, the corner turned.
List<Widget> _typescript(_F f) {
  final e = f.em;
  final cut = 1.3 * e;
  return [
    Positioned(
      left: 0.08 * f.w,
      right: 0.08 * f.w,
      top: 0.07 * f.h,
      bottom: 0,
      child: ClipPath(
        clipper: _CornerCutClip(cut),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _paper),
            Positioned(
              top: 0,
              right: 0,
              width: cut,
              height: cut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      _a(_ink, 0),
                      _a(_ink, 0.2),
                      AppColors.coverPaper200,
                    ],
                    stops: const [0.5, 0.5, 0.64],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  0.11 * f.w, 0.18 * f.w, 0.11 * f.w, 0.12 * f.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _eyebrow(f, color: _inkSoft, opacity: 1),
                  SizedBox(height: 0.55 * e),
                  _fill(_Clamp(
                    f.title.toUpperCase(),
                    lines: 5,
                    align: TextAlign.start,
                    style: AppTheme.mono(
                      fontSize: 0.72 * e,
                      fontWeight: FontWeight.w500,
                      height: 1.42,
                      letterSpacing: 0.05 * 0.72 * e,
                      color: _ink,
                    ),
                  )),
                  SizedBox(height: 0.55 * e),
                  _authorMono(f, f.by, color: _inkSoft, opacity: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}

/// `.cv-slides` — the title slide on its deck of two offset cards.
List<Widget> _slides(_F f) {
  final e = f.em;
  final dw = 0.76 * f.w;
  final card = BorderRadius.circular(0.28 * e);
  Widget under(double off, double paper) => Positioned.fill(
        child: Transform.translate(
          offset: Offset(off, -off),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kitMixOklab(_paper, f.cloth, paper),
              borderRadius: card,
            ),
          ),
        ),
      );
  return [
    Positioned(
      left: 0.11 * f.w,
      top: 0.20 * f.h,
      width: dw,
      height: dw * 10 / 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          under(e, 0.34),
          under(0.5 * e, 0.64),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: card,
                boxShadow: [
                  BoxShadow(
                    color: _a(_ink800, 0.45),
                    offset: Offset(0, 0.2 * e),
                    blurRadius: 0.5 * e,
                    spreadRadius: -0.1 * e,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 0.75 * e),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: _title(f,
                          size: 0.84,
                          height: 1.15,
                          lines: 3,
                          color: _ink,
                          shadow: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    _caption(f, [_eyebrow(f), _authorMono(f, f.by)]),
  ];
}

/// `.cv-cap` — the foot of a flat object.
Widget _caption(_F f, List<Widget> parts,
    {double left = 0.11,
    double right = 0.10,
    double bottom = 0.08,
    double gap = 0.38}) {
  return Positioned(
    left: left * f.w,
    right: right * f.w,
    bottom: bottom * f.h,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) SizedBox(height: gap * f.em),
          parts[i],
        ],
      ],
    ),
  );
}

/// `.cv-ph` / `.cv-stk > i` — a print: a paper border, the cloth washed pale.
Widget _printFace(_F f) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _paper, width: 0.32 * f.em),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          transform: const GradientRotation(-math.pi / 12), // 165deg
          colors: [
            kitMixOklab(f.cloth, _paper, 0.36),
            kitMixOklab(f.cloth, _paper, 0.62),
          ],
        ),
      ),
    );

/// `.cv-photo` — a photograph mounted on the cloth leaf by four corners.
List<Widget> _photo(_F f) {
  final e = f.em;
  final pw = 0.76 * f.w;
  return [
    Positioned(top: 0.085 * f.h, left: 0.11 * f.w, child: _eyebrow(f)),
    Positioned(
      top: 0.20 * f.h,
      left: 0.12 * f.w,
      width: pw,
      height: pw * 3 / 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _printFace(f)),
          Positioned.fill(
            child: CustomPaint(
              painter: _MountCornersPainter(
                  size: e, inset: 0.32 * e - 0.52 * e, color: _a(_ink800, 0.62)),
            ),
          ),
        ],
      ),
    ),
    _caption(f, [
      _title(f, italic: true, weight: FontWeight.w500, lines: 3),
      _authorMono(f, f.date),
    ]),
  ];
}

/// `.cv-prints` — prints in a loose stack.
List<Widget> _prints(_F f) {
  final e = f.em;
  final sw = 0.72 * f.w;
  // (rotation°, dx em, dy em, brightness lost)
  const sheets = [(-9.0, -0.2, 0.3, 0.1), (6.0, 0.3, -0.15, 0.05), (0.0, 0.0, 0.0, 0.0)];
  return [
    Positioned(top: 0.085 * f.h, left: 0.11 * f.w, child: _eyebrow(f)),
    Positioned(
      top: 0.22 * f.h,
      left: 0.14 * f.w,
      width: sw,
      height: sw * 3 / 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (deg, dx, dy, dim) in sheets)
            Positioned.fill(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationZ(deg * math.pi / 180)
                  ..multiply(Matrix4.translationValues(dx * e, dy * e, 0)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: _a(_ink800, 0.35),
                        offset: Offset(0, 0.1 * e),
                        blurRadius: 0.35 * e,
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _printFace(f),
                      // `filter: brightness(.9)` is a black wash of .1.
                      if (dim > 0) ColoredBox(color: _shade(dim)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    _caption(f, [
      _title(f, italic: true, weight: FontWeight.w500, lines: 3),
      _authorMono(f, f.date),
    ]),
  ];
}

/// `.cv-screen` — a lit screen with a play mark, above its title.
List<Widget> _screen(_F f) {
  final e = f.em;
  final r = BorderRadius.circular(0.35 * e);
  return [
    Positioned.fill(
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(0.10 * f.w, 0.10 * f.w, 0.09 * f.w, 0.09 * f.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                        color: _a(_ink800, 0.5), borderRadius: r),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.2,
                        colors: [_sheen(0.14), _sheen(0)],
                        stops: const [0, 0.7],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      border: Border.all(color: _a(_paper, 0.14)),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 1.9 * e,
                      height: 1.9 * e,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: _a(_paper, 0.92), shape: BoxShape.circle),
                        child: CustomPaint(
                            painter: _PlayPainter(f.cloth, 0.62 * e, 0.72 * e)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 0.95 * e),
            _eyebrow(f),
            SizedBox(height: 0.45 * 1.04 * e),
            _fill(_title(f, size: 1.04, lines: 3)),
            _authorMono(f, f.by),
          ],
        ),
      ),
    ),
  ];
}

/// `.cv-print` — a square print, its caption on the broad lower margin.
List<Widget> _print(_F f) {
  final e = f.em;
  final iw = 0.84 * f.w;
  return [
    Positioned(
      top: 0.07 * f.h,
      left: 0.08 * f.w,
      width: iw,
      height: iw,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: f.cloth),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.44, -0.64), // at 28% 18%
                radius: 1.0,
                colors: [_sheen(0.2), _sheen(0)],
                stops: const [0, 0.62],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: _a(_ink800, 0.08))),
          ),
          Positioned(
            left: 0.75 * 0.56 * e,
            bottom: 0.65 * 0.56 * e,
            child: _eyebrow(f),
          ),
        ],
      ),
    ),
    _caption(
      f,
      [
        _title(f,
            size: 0.94,
            height: 1.18,
            italic: true,
            weight: FontWeight.w500,
            lines: 2,
            color: _ink,
            shadow: false),
        _authorMono(f, f.by,
            tracking: 0.04, caps: false, color: _inkSoft, opacity: 1),
      ],
      left: 0.09,
      right: 0.08,
      bottom: 0.07,
      gap: 0.3,
    ),
  ];
}

/// `.cv-vertical` — a tall frame with its segment bars, the caption over its foot.
List<Widget> _vertical(_F f) {
  final e = f.em;
  final fw = 0.70 * f.w, fh = 0.88 * f.h;
  final r = BorderRadius.circular(0.85 * e);
  return [
    Positioned(
      top: 0.06 * f.h,
      left: 0.15 * f.w,
      width: fw,
      height: fh,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(color: _a(_ink800, 0.55), spreadRadius: 0.18 * e),
          ],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: f.cloth),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _sheen(0.1),
                      _sheen(0),
                      _a(_ink800, 0),
                      _a(_ink800, 0.5),
                    ],
                    stops: const [0, 0.38, 0.38, 1],
                  ),
                ),
              ),
              Positioned(
                top: 0.05 * fh,
                left: 0.10 * fw,
                right: 0.10 * fw,
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) SizedBox(width: 0.22 * e),
                      Expanded(
                        child: Container(
                          height: 0.13 * e,
                          decoration: BoxDecoration(
                            color: _a(_paper, i == 0 ? 0.9 : 0.32),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0.10 * fw,
                right: 0.10 * fw,
                bottom: 0.07 * fh,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _eyebrow(f),
                    SizedBox(height: 0.3 * e),
                    _title(f, size: 0.84, lines: 4),
                    SizedBox(height: 0.3 * e),
                    _authorMono(f, f.by, tracking: 0.04, caps: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ];
}

/// `.cv-sleeve` — a die-cut sleeve, the record showing.
List<Widget> _sleeve(_F f) {
  final e = f.em;
  final d = 0.58 * f.w;
  // `circle` gradients size to the farthest corner: half the square's diagonal.
  const corner = 0.7071;
  final label = kitMixOklab(f.cloth, _paper, 0.58);
  return [
    Positioned(
      top: 0.08 * f.h,
      left: 0.21 * f.w,
      width: d,
      height: d,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.coverInk600,
              boxShadow: [
                BoxShadow(
                  color: kitMixOklab(f.cloth, _ink800, 0.78),
                  spreadRadius: 0.3 * e,
                ),
              ],
            ),
          ),
          // The grooves: `repeating-radial-gradient(ink-700 0 1.3%, ink-600 1.3% 2.2%)`.
          const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                radius: 0.022 * corner,
                tileMode: TileMode.repeated,
                colors: [
                  AppColors.coverInk700,
                  AppColors.coverInk700,
                  AppColors.coverInk600,
                  AppColors.coverInk600,
                ],
                stops: [0, 1.3 / 2.2, 1.3 / 2.2, 1],
              ),
            ),
          ),
          // The spindle, the label and its edge.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                radius: corner,
                colors: [
                  _ink800,
                  _ink800,
                  label,
                  label,
                  _a(_ink800, 0.85),
                  _a(_ink800, 0.85),
                  _a(_ink800, 0),
                  _a(_ink800, 0),
                ],
                stops: const [0, 0.022, 0.026, 0.25, 0.256, 0.27, 0.274, 1],
              ),
            ),
          ),
        ],
      ),
    ),
    _caption(f, [
      _eyebrow(f),
      _title(f, size: 0.98, lines: 3),
      _authorMono(f, f.by),
    ]),
  ];
}

/// `.cv-tape` — a cassette with a hand-written label and two reel windows.
List<Widget> _tape(_F f) {
  final e = f.em;
  final cw = 0.82 * f.w;
  final stripe = kitMixOklab(f.cloth, _paper, 0.7);
  Widget reel() => SizedBox(
        width: 1.35 * e,
        height: 1.35 * e,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              radius: 0.7071,
              colors: [
                _a(_ink800, 0.95),
                _a(_ink800, 0.95),
                _a(_paper, 0.82),
                _a(_paper, 0.82),
                _a(_paper, 0.2),
                _a(_paper, 0.2),
              ],
              stops: const [0, 0.26, 0.28, 0.44, 0.46, 1],
            ),
          ),
        ),
      );
  return [
    Positioned(top: 0.085 * f.h, left: 0.11 * f.w, child: _eyebrow(f)),
    Positioned(
      top: 0.19 * f.h,
      left: 0.09 * f.w,
      width: cw,
      height: cw / 1.3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _a(_ink800, 0.42),
          borderRadius: BorderRadius.circular(0.45 * e),
          border: Border.all(color: _a(_paper, 0.12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(0.5 * e),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(0.18 * e),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: _paper),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 0.45 * e,
                        child: ColoredBox(color: stripe),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            0.5 * e, 0.35 * e, 0.5 * e, 0.35 * e),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _title(f,
                              size: 0.8,
                              height: 1.2,
                              italic: true,
                              weight: FontWeight.w500,
                              lines: 2,
                              color: _ink,
                              shadow: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 0.4 * e),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 0.6 * e),
                child: Container(
                  height: 1.9 * e,
                  decoration: BoxDecoration(
                    color: _a(_ink800, 0.55),
                    borderRadius: BorderRadius.circular(0.95 * e),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [reel(), reel()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    _caption(f, [_authorMono(f, f.by)]),
  ];
}

/// `.cv-reel` — a strip of film, sprockets down both edges.
List<Widget> _reel(_F f) {
  final e = f.em;
  final holes = _SprocketPainter(0.9 * e, _a(_paper, 0.7));
  return [
    Positioned(
        top: 0,
        bottom: 0,
        left: 0.035 * f.w,
        width: 0.08 * f.w,
        child: CustomPaint(painter: holes)),
    Positioned(
        top: 0,
        bottom: 0,
        right: 0.035 * f.w,
        width: 0.08 * f.w,
        child: CustomPaint(painter: holes)),
    Positioned(
      top: 0.08 * f.h,
      bottom: 0.08 * f.h,
      left: 0.16 * f.w,
      right: 0.16 * f.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(0.2 * e),
          border: Border.all(color: _a(_paper, 0.1)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(_sheen(0.1), f.cloth),
              Color.alphaBlend(_sheen(0.03), f.cloth),
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(0.55 * e, 0.7 * e, 0.55 * e, 0.6 * e),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _eyebrow(f),
              SizedBox(height: 0.55 * 0.96 * e),
              _fill(_title(f, size: 0.96, lines: 5)),
              _authorMono(f, f.by),
            ],
          ),
        ),
      ),
    ),
  ];
}

// ── Painters ─────────────────────────────────────────────────────────────────

/// `.cv-ribbon` — `polygon(0 0, 100% 0, 100% 100%, 50% 76%, 0 100%)`.
class _RibbonClip extends CustomClipper<Path> {
  const _RibbonClip();

  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height * 0.76)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(_RibbonClip old) => false;
}

/// `.cv-pg`'s `clip-path` — the top-right corner cut at [cut].
class _CornerCutClip extends CustomClipper<Path> {
  final double cut;

  const _CornerCutClip(this.cut);

  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width - cut, 0)
    ..lineTo(s.width, cut)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(_CornerCutClip old) => old.cut != cut;
}

/// The note's rules: a 1px line at the foot of every [period].
class _RulesPainter extends CustomPainter {
  final double period;
  final Color color;

  const _RulesPainter(this.period, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (period <= 1) return;
    final p = Paint()..color = color;
    for (var y = period; y <= size.height; y += period) {
      canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_RulesPainter old) =>
      old.period != period || old.color != color;
}

/// `.cv-ph > i` — four dark mounting corners, [size] square, set [inset]
/// from the print's edge (negative: they reach past it).
class _MountCornersPainter extends CustomPainter {
  final double size;
  final double inset;
  final Color color;

  const _MountCornersPainter(
      {required this.size, required this.inset, required this.color});

  @override
  void paint(Canvas canvas, Size box) {
    final o = inset, e = size, w = box.width, h = box.height;
    final p = Paint()..color = color;
    void tri(Offset a, Offset b, Offset c) => canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        p);
    tri(Offset(o, o), Offset(o + e, o), Offset(o, o + e));
    tri(Offset(w - o - e, o), Offset(w - o, o), Offset(w - o, o + e));
    tri(Offset(w - o, h - o - e), Offset(w - o, h - o), Offset(w - o - e, h - o));
    tri(Offset(o, h - o - e), Offset(o + e, h - o), Offset(o, h - o));
  }

  @override
  bool shouldRepaint(_MountCornersPainter old) =>
      old.size != size || old.inset != inset || old.color != color;
}

/// `.cv-play::after` — the play triangle, centred at 54% / 50%.
class _PlayPainter extends CustomPainter {
  final Color color;
  final double w, h;

  const _PlayPainter(this.color, this.w, this.h);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.54, cy = size.height * 0.5;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w / 2, cy - h / 2)
        ..lineTo(cx + w / 2, cy)
        ..lineTo(cx - w / 2, cy + h / 2)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PlayPainter old) =>
      old.color != color || old.w != w || old.h != h;
}

/// `.cv-spk` — an ellipse (36% × 26% radii) per [period] tile, down the strip.
class _SprocketPainter extends CustomPainter {
  final double period;
  final Color color;

  const _SprocketPainter(this.period, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (period <= 1) return;
    final p = Paint()..color = color;
    final rx = 0.36 * size.width, ry = 0.26 * period;
    for (var y = 0.0; y < size.height; y += period) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width / 2, y + period / 2),
            width: 2 * rx,
            height: 2 * ry),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_SprocketPainter old) =>
      old.period != period || old.color != color;
}

// ── The cover item ───────────────────────────────────────────────────────────

/// A cover as a link to its source (§6.4.3) with a mono line under it (§33's
/// cover item, web `CoverItem`). The cover is hidden from assistive technology;
/// the item reads the title, and *(unread)* while `view_count` is 0.
class KitCoverItem extends StatefulWidget {
  final Document doc;

  /// The home shelf's colour, resolved for the theme; null → ink.
  final Color? shelf;

  /// The line under the cover — a passage figure (absent, never 0, when
  /// uncounted) or the shelf. Mono 10.5 at `--fg-subtle`, one line.
  final Widget? meta;

  /// The in-app open; null → [KitSourceLink]'s default (push the reader).
  final VoidCallback? onOpen;

  /// The item's width (web `--cv-w`); the cover fills it.
  final double width;

  const KitCoverItem({
    super.key,
    required this.doc,
    this.shelf,
    this.meta,
    this.onOpen,
    this.width = 116,
  });

  @override
  State<KitCoverItem> createState() => _KitCoverItemState();
}

class _KitCoverItemState extends State<KitCoverItem> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final doc = widget.doc;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final name = '${_titleOf(doc)}${doc.viewCount == 0 ? ' (unread)' : ''}';
    final ring = _radiusOf(kitCoverOf(doc.type).$1, 5);

    return KitSourceLink(
      docId: doc.id,
      onOpen: widget.onOpen,
      builder: (context, open) => MergeSemantics(
        child: Semantics(
          link: true,
          label: name,
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  open();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (v) => setState(() => _focus = v),
            onShowHoverHighlight: (v) => setState(() => _hover = v),
            child: GestureDetector(
              onTap: open,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: widget.width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hover lifts the cover 5px and turns it −0.5° over
                    // --dur-base --ease-quill; under reduced motion it moves
                    // without the glide.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _hover ? 1 : 0),
                      duration: still ? Duration.zero : AppMotion.durBase,
                      curve: AppMotion.easeQuill,
                      builder: (context, v, _) => Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.translationValues(0, -5 * v, 0)
                          ..multiply(
                              Matrix4.rotationZ(-0.5 * math.pi / 180 * v)),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            KitCover._lifted(
                                doc: doc, shelf: widget.shelf, lift: v),
                            // Focus: a 2px --accent outline 3px off the cover.
                            if (_focus)
                              Positioned(
                                left: -5,
                                top: -5,
                                right: -5,
                                bottom: -5,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: t.accent, width: 2),
                                      borderRadius: ring,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.meta != null) ...[
                      const SizedBox(height: 10),
                      DefaultTextStyle(
                        style: AppTheme.mono(
                          fontSize: 10.5,
                          letterSpacing: 0.21,
                          color: _hover ? t.fgMuted : t.fgSubtle,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        child: widget.meta!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── The cover strip ──────────────────────────────────────────────────────────

/// Home's *Recently added* in Grid (§33's cover strip): the newest volumes
/// face-out in ONE row — `repeat(auto-fill, minmax(124px, 1fr))`, column gap
/// 26, 12 above — as many of [items] as fit, the rest not drawn. Each cover in
/// its own home shelf's cloth, each line its shelf (a 7×9 cloth swatch and the
/// name, or *Unshelved*).
class KitCoverStrip extends StatelessWidget {
  final List<Document> items;

  /// A source's home shelf — its title and its colour resolved for the theme —
  /// or null when it is on none.
  final ({String title, Color? color})? Function(Document) homeOf;

  final void Function(Document)? onOpen;

  const KitCoverStrip({
    super.key,
    required this.items,
    required this.homeOf,
    this.onOpen,
  });

  static const double _minColumn = 124;
  static const double _gap = 26;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth.isFinite
          ? box.maxWidth
          : math.max(1, items.length) * (_minColumn + _gap) - _gap;
      final columns =
          math.max(1, ((width + _gap) / (_minColumn + _gap)).floor());
      final shown = items.take(columns).toList();

      Widget item(Document doc) {
        final home = homeOf(doc);
        final cb = onOpen;
        return KitCoverItem(
          doc: doc,
          shelf: home?.color,
          width: double.infinity,
          onOpen: cb == null ? null : () => cb(doc),
          meta: Row(
            children: [
              Container(
                width: 7,
                height: 9,
                decoration: BoxDecoration(
                  color: home?.color ?? t.fgSubtle,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(1),
                    bottomLeft: Radius.circular(1),
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(home?.title ?? 'Unshelved')),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(
                  child: i < shown.length
                      ? item(shown[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}
