import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import '../../theme/tokens.dart';

/// The paper ground: the halftone checker (`--checker`) with the grain
/// (`--grain`) layered under it.
///
/// **Background fields only** — the page body, section bands, the app document
/// surface, the onboarding paper pane. Never a card, modal, popover or button:
/// a card is a clean sheet laid *on* the checkered ground, and that contrast is
/// the whole reason it reads as lifted (`design-tokens.md`,
/// `component-kit.md` §5.1).
///
/// Implementation note, recorded because it is a real deviation from the web
/// reference: the web draws the checker as a repeating `radial-gradient` and
/// the grain as an inline SVG `feTurbulence`. Flutter has neither. Both are
/// baked once into a single 48×48 tile (48 is a multiple of the 3px lattice, so
/// the checker repeats seamlessly) and painted through a repeating
/// [ImageShader]. Drawing the dots as circles per frame was the obvious
/// approach and is not viable — a 400×800 pane is ~35,000 circles per paint.
class KitGround extends StatefulWidget {
  final Widget child;

  /// Grain is a light-surface texture. The reference layers it on `.main`
  /// under both themes; set false for a surface that wants the lattice alone.
  final bool grain;

  const KitGround({super.key, required this.child, this.grain = true});

  @override
  State<KitGround> createState() => _KitGroundState();
}

class _KitGroundState extends State<KitGround> {
  static final Map<String, ui.Image> _cache = {};
  ui.Image? _tile;
  String? _key;

  static const int _tileSize = 48;
  static const int _latticeStep = 3;

  Future<void> _ensureTile(bool isDark) async {
    final key = '${isDark ? 'dark' : 'light'}-${widget.grain}';
    if (_key == key && _tile != null) return;
    final cached = _cache[key];
    if (cached != null) {
      if (mounted) setState(() { _tile = cached; _key = key; });
      return;
    }
    final image = await _buildTile(isDark: isDark, grain: widget.grain);
    _cache[key] = image;
    if (mounted) setState(() { _tile = image; _key = key; });
  }

  static Future<ui.Image> _buildTile(
      {required bool isDark, required bool grain}) {
    const n = _tileSize;
    final pixels = Uint8List(n * n * 4);

    // Grain first — a fixed seed, so the texture is identical on every launch
    // and every device. A per-run seed would make golden tests unstable for a
    // reason nothing in the diff would explain.
    if (grain) {
      final rng = math.Random(0x4E4C7231);
      final tint = isDark ? 255 : 20;
      for (var i = 0; i < n * n; i++) {
        // opacity 0.04 in the reference, modulated per pixel.
        final a = (rng.nextDouble() * 0.08 * 255).round();
        final o = i * 4;
        pixels[o] = tint;
        pixels[o + 1] = isDark ? 255 : 23;
        pixels[o + 2] = isDark ? 255 : 31;
        pixels[o + 3] = a;
      }
    }

    // Then the lattice: one dot per 3×3 cell.
    // Light `rgba(20,23,31,.05)` · dark `rgba(255,255,255,.07)`.
    final dotA = ((isDark ? 0.07 : 0.05) * 255).round();
    for (var y = 0; y < n; y += _latticeStep) {
      for (var x = 0; x < n; x += _latticeStep) {
        final o = (y * n + x) * 4;
        pixels[o] = isDark ? 255 : 20;
        pixels[o + 1] = isDark ? 255 : 23;
        pixels[o + 2] = isDark ? 255 : 31;
        pixels[o + 3] = dotA;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, n, n, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Tokens.of(context).isDark;
    _ensureTile(isDark);
    final tile = _tile;
    return CustomPaint(
      painter: tile == null ? null : _GroundPainter(tile),
      child: widget.child,
    );
  }
}

class _GroundPainter extends CustomPainter {
  final ui.Image tile;

  _GroundPainter(this.tile);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(
          tile, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GroundPainter old) => old.tile != tile;
}
