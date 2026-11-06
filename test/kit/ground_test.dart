import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/widgets/kit/kit_ground.dart';

/// The paper is web's (component-kit §1.1, design-tokens `--checker` `--grain`).
///
/// The first ground here looked like paper and every screen around it was
/// token-clean, so nothing could say it was a different paper for a whole
/// redesign: a 48px ink speckle averaging 245 on white where web averages 250.
/// These numbers are read off the browser's own rendering of `theme.css` at 3x.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens this paper was made from', () {
    final css = File(
      '../NoteLetter-web/src/styles/theme.css',
    ).readAsStringSync();

    test('--grain is the one assets/paper/grain.png was baked from', () {
      // A change here means: node tool/bake_grain.cjs, and update this line.
      expect(
        css,
        contains(
          "--grain: url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)' opacity='0.04'/></svg>\");",
        ),
      );
    });

    test('--checker is the one kitLatticePixels draws, in both themes', () {
      expect(
        css,
        contains(
          '--checker: radial-gradient(rgba(20, 23, 31, 0.05) 1px, transparent 1px);',
        ),
      );
      expect(
        RegExp(
          r'--checker:\s+radial-gradient\(rgba\(255, 255, 255, 0\.07\) 1px, transparent 1px\);',
        ).allMatches(css).length,
        2,
      );
      expect(css, contains('--checker-size: 3px 3px;'));
    });
  });

  group('the lattice', () {
    // One channel of each pixel's alpha, as rows.
    List<List<int>> alphas(Uint8List p, int side) => [
      for (var y = 0; y < side; y++)
        [for (var x = 0; x < side; x++) p[(y * side + x) * 4 + 3]],
    ];

    test('at 3x each 9×9 cell holds the 5×5 dot Chromium draws', () {
      const side = 72;
      expect(kitLatticeTilePixels(3), side);
      final a = alphas(kitLatticePixels(side, dark: false), side);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final inDot = x % 9 >= 2 && x % 9 <= 6 && y % 9 >= 2 && y % 9 <= 6;
          expect(a[y][x], inDot ? 13 : 0, reason: 'pixel $x,$y');
        }
      }
    });

    test('at 1x it is one pixel in each 3×3 cell', () {
      final a = alphas(kitLatticePixels(24, dark: false), 24);
      for (var y = 0; y < 24; y++) {
        for (var x = 0; x < 24; x++) {
          expect(a[y][x] != 0, x % 3 == 1 && y % 3 == 1, reason: 'pixel $x,$y');
        }
      }
    });

    test('over the surface it lands where web\'s does, in both themes', () {
      // Light: 254 under a 5% ink dot reads 242 in the browser. Dark: 33 under
      // a 7% white dot reads 48.
      final light = kitLatticePixels(72, dark: false);
      final dark = kitLatticePixels(72, dark: true);
      const dot = (2 * 72 + 2) * 4; // pixel 2,2: inside a dot
      int over(Uint8List p, int bg) =>
          (p[dot] + bg * (255 - p[dot + 3]) / 255).round();
      expect(over(light, 254), 242);
      expect(over(dark, 33), 49);
    });

    test('premultiplied: no channel above its alpha (the white veil)', () {
      for (final dark in [false, true]) {
        final p = kitLatticePixels(72, dark: dark);
        for (var i = 0; i < p.length; i += 4) {
          for (var c = 0; c < 3; c++) {
            expect(p[i + c] <= p[i + 3], isTrue);
          }
        }
      }
    });

    test('a scale a phone ships at gives a whole tile', () {
      for (final dpr in [1.0, 2.0, 2.625, 2.75, 3.0, 3.5]) {
        expect(kitLatticeTilePixels(dpr), 24 * dpr, reason: '$dpr');
      }
    });
  });

  testWidgets('the grain lands where web\'s does, in both themes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load(KitGround.grainAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 480, reason: '160 logical at grainScale');
      expect(image.height, 480);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      double over(int bg) {
        var sum = 0.0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          // rawRgba is premultiplied: the channel is already scaled by alpha.
          final a = bytes.getUint8(i + 3) / 255;
          sum += bytes.getUint8(i) + bg * (1 - a);
        }
        return sum / (bytes.lengthInBytes / 4);
      }

      // Measured from the browser: 253.5 on white, 33.9 on --surface dark's red.
      expect(over(255), closeTo(253.5, 0.2));
      expect(over(31), closeTo(33.9, 0.2));
      image.dispose();
    });
  });
}
