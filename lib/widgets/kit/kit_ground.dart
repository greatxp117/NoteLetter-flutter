import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import '../../theme/tokens.dart';

/// The paper ground: the halftone checker (`--checker`) over the grain
/// (`--grain`).
///
/// **Background fields only** — the page body, section bands, the app document
/// surface, the onboarding paper pane. Never a card, modal, popover or button:
/// a card is a clean sheet laid *on* the checkered ground, and that contrast is
/// the whole reason it reads as lifted (`design-tokens.md`,
/// `component-kit.md` §5.1).
///
/// Two repeating images with their own periods, as on web: a 160px grain and a
/// 3px lattice, painted through [ImageShader]s. Drawing the dots as circles per
/// frame is not viable — a 400×800 pane is ~35,000 circles per paint.
///
/// **The grain is web's own pixels.** Flutter has no `feTurbulence`, so
/// [grainAsset] is what the browser draws for the token, baked at 3x by
/// `tool/bake_grain.cjs`. It is one image in both themes, as the token is. A
/// noise written here is a different paper: this widget's first ground was a
/// 48px tile of ink speckle, averaging 245 on white where web averages 250, in
/// blotches of 3 screen pixels where web's lattice reads cleanly.
///
/// **The lattice is computed at the screen's own pixels** ([kitLatticePixels]),
/// a 1px-radius dot in each 3px cell, so a phone draws what a phone's browser
/// draws rather than a 1px square scaled up.
class KitGround extends StatefulWidget {
  final Widget child;

  /// Grain is on every ground that asks for it, in both themes; set false for a
  /// surface that wants the lattice alone (`.lac::before`).
  final bool grain;

  /// The halftone checker. The onboarding rail is the one surface that wants
  /// the **grain alone** — `.ob-rail::after` lays grain over the plum field so
  /// it is not flat, and a lattice of ink dots on chrome is a different
  /// surface, not a softer one (`spec/screens/onboarding.md` §Composition).
  final bool lattice;

  /// The strength of the grain, where the reference sets one: `.ob-main::before`
  /// and `.ob-rail::after` lay it at 0.5.
  final double grainOpacity;

  /// How the grain meets what is under it. `.ob-rail::after` is the one that is
  /// not plain: `mix-blend-mode: overlay` on the plum.
  final BlendMode grainBlend;

  const KitGround({
    super.key,
    required this.child,
    this.grain = true,
    this.lattice = true,
    this.grainOpacity = 1,
    this.grainBlend = BlendMode.srcOver,
  });

  /// `--grain`, baked by `tool/bake_grain.cjs`.
  static const String grainAsset = 'assets/paper/grain.png';

  /// The asset's pixels per logical pixel: 480 over the token's 160.
  static const double grainScale = 3;

  /// `background-image: var(--grain)` on a card's own decoration (`.ms-sheet`,
  /// `.rsvp-stage`), which is grain and no lattice, clipped to the card's shape
  /// by the decoration that holds it. Const, so an `AnimatedContainer` easing
  /// its border is not cross-fading two copies of the same paper.
  static const DecorationImage grainImage = DecorationImage(
    image: AssetImage(grainAsset),
    repeat: ImageRepeat.repeat,
    alignment: Alignment.topLeft,
    scale: grainScale,
  );

  /// [grainImage] where the reference sets a strength: the landing's `.pg` at
  /// .6 and `.pl-letter` at .5.
  static DecorationImage grainImageAt(double opacity) => DecorationImage(
    image: const AssetImage(grainAsset),
    repeat: ImageRepeat.repeat,
    alignment: Alignment.topLeft,
    scale: grainScale,
    opacity: opacity,
  );

  /// Reads the tiles ahead of the first frame, so no page draws without its
  /// paper. A failure is said and survived: this is the ground, not the page.
  static Future<void> prepare() async {
    final dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio;
    await Future.wait([
      _Tiles.loadGrain(),
      if (dpr != null) ...[
        _Tiles.loadLattice(dark: false, dpr: dpr),
        _Tiles.loadLattice(dark: true, dpr: dpr),
      ],
    ]);
  }

  @override
  State<KitGround> createState() => _KitGroundState();
}

class _KitGroundState extends State<KitGround> {
  void _arrived(void _) {
    if (mounted) setState(() {});
  }

  /// A grain that failed stays null and its load stays finished, so asking
  /// again answers at once: rebuilding on that answer would never stop.
  void _grainArrived(void _) {
    if (_Tiles.grain != null) _arrived(null);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final dark = Tokens.of(context).isDark;

    ui.Image? grain;
    if (widget.grain) {
      grain = _Tiles.grain;
      if (grain == null) _Tiles.loadGrain().then(_grainArrived);
    }
    ui.Image? lattice;
    if (widget.lattice) {
      lattice = _Tiles.lattice(dark: dark, dpr: dpr);
      if (lattice == null) {
        _Tiles.loadLattice(dark: dark, dpr: dpr).then(_arrived);
      }
    }

    return CustomPaint(
      painter: _GroundPainter(
        grain: grain,
        grainOpacity: widget.grainOpacity,
        grainBlend: widget.grainBlend,
        lattice: lattice,
        dpr: dpr,
      ),
      child: widget.child,
    );
  }
}

/// One copy of each tile for the life of the app. A page change builds a new
/// ground, and it must find its paper already here on that frame.
abstract final class _Tiles {
  static ui.Image? grain;
  static Future<void>? _grainLoad;
  static final Map<String, ui.Image> _lattices = {};
  static final Map<String, Future<void>> _latticeLoads = {};

  static String _key(bool dark, double dpr) => '$dark@$dpr';

  static ui.Image? lattice({required bool dark, required double dpr}) =>
      _lattices[_key(dark, dpr)];

  static Future<void> loadGrain() => _grainLoad ??= _readGrain();

  static Future<void> _readGrain() async {
    try {
      final data = await rootBundle.load(KitGround.grainAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      grain = (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('KitGround: the grain did not load: $e');
    }
  }

  static Future<void> loadLattice({required bool dark, required double dpr}) =>
      _latticeLoads[_key(dark, dpr)] ??= _buildLattice(dark, dpr);

  static Future<void> _buildLattice(bool dark, double dpr) {
    final n = kitLatticeTilePixels(dpr);
    final done = Completer<void>();
    ui.decodeImageFromPixels(
      kitLatticePixels(n, dark: dark),
      n,
      n,
      ui.PixelFormat.rgba8888,
      (image) {
        _lattices[_key(dark, dpr)] = image;
        done.complete();
      },
    );
    return done.future;
  }
}

/// The lattice tile's side in logical pixels: eight 3px cells. 24 is whole in
/// the pixels of every scale a phone ships at (2, 2.625, 2.75, 3, 3.5).
const double _latticeTile = 24;

/// The lattice tile's side in pixels at [dpr].
@visibleForTesting
int kitLatticeTilePixels(double dpr) => (_latticeTile * dpr).round();

/// One tile of `--checker`, premultiplied RGBA, [side] pixels square:
/// `radial-gradient(rgba(20,23,31,.05) 1px, transparent 1px)` on `3px 3px` in
/// light, `rgba(255,255,255,.07)` in dark.
///
/// A pixel takes the dot when its centre is under 1 CSS pixel from the cell's.
/// A gradient has no antialiased edge, so that is the whole rule, and at 3x it
/// gives Chromium's 5×5 block in each 9×9 cell.
@visibleForTesting
Uint8List kitLatticePixels(int side, {required bool dark}) {
  final pixels = Uint8List(side * side * 4);
  final perPixel = _latticeTile / side;
  final alpha = ((dark ? 0.07 : 0.05) * 255).round();
  final r = _pm(dark ? 255 : 20, alpha);
  final g = _pm(dark ? 255 : 23, alpha);
  final b = _pm(dark ? 255 : 31, alpha);
  double fromCentre(int i) => ((i + 0.5) * perPixel) % 3 - 1.5;
  for (var y = 0; y < side; y++) {
    final dy = fromCentre(y);
    for (var x = 0; x < side; x++) {
      final dx = fromCentre(x);
      if (dx * dx + dy * dy >= 1) continue;
      final o = (y * side + x) * 4;
      pixels[o] = r;
      pixels[o + 1] = g;
      pixels[o + 2] = b;
      pixels[o + 3] = alpha;
    }
  }
  return pixels;
}

/// **`decodeImageFromPixels` takes PREMULTIPLIED colour.** Passing straight
/// rgba — white at alpha 18 — hands the compositor a channel value far above
/// its own alpha, and the result paints as an almost solid veil rather than a
/// 7% dot.
///
/// In light mode the tint is near-black, so `rgb <= a` roughly held and the
/// ground looked right; in dark mode the tint is white, and the whole page
/// rendered as a white sheet under dark cards and light text. The screen was
/// verified in light. **A screen verified only in light is not verified.**
int _pm(int channel, int alpha) => (channel * alpha / 255).round();

class _GroundPainter extends CustomPainter {
  final ui.Image? grain;
  final double grainOpacity;
  final BlendMode grainBlend;
  final ui.Image? lattice;
  final double dpr;

  _GroundPainter({
    required this.grain,
    required this.grainOpacity,
    required this.grainBlend,
    required this.lattice,
    required this.dpr,
  });

  static Float64List _scale(double k) =>
      Matrix4.diagonal3Values(k, k, 1).storage;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    // `background-image: var(--checker), var(--grain)`: the first named is on
    // top, so the grain goes down first.
    final g = grain;
    if (g != null) {
      canvas.drawRect(
        area,
        Paint()
          ..shader = ImageShader(
            g,
            TileMode.repeated,
            TileMode.repeated,
            _scale(1 / KitGround.grainScale),
            // One asset pixel is one screen pixel at 3x; anywhere else it is
            // resampled.
            filterQuality: dpr == KitGround.grainScale
                ? FilterQuality.none
                : FilterQuality.low,
          )
          // A shader takes its alpha from the paint's colour.
          ..color = Color.fromRGBO(0, 0, 0, grainOpacity)
          ..blendMode = grainBlend,
      );
    }
    final l = lattice;
    if (l != null) {
      canvas.drawRect(
        area,
        Paint()
          ..shader = ImageShader(
            l,
            TileMode.repeated,
            TileMode.repeated,
            _scale(_latticeTile / l.width),
            filterQuality: FilterQuality.none,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_GroundPainter old) =>
      old.grain != grain ||
      old.grainOpacity != grainOpacity ||
      old.grainBlend != grainBlend ||
      old.lattice != lattice ||
      old.dpr != dpr;
}
