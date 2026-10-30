import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/theme/app_colors.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit_controls.dart';
import 'package:flutter_app/widgets/kit/kit_d_covers.dart';

/// component-kit §33 — direction D's covers.
///
/// The vocabulary is asserted in BOTH directions (umbrella trap: a bucket
/// nothing enumerates is a bucket that vanishes); the cloth's colour maths
/// against known OKLab values; every object is pumped in both themes.
Document _doc(
  String type, {
  String id = 'doc-1',
  String title = 'The Name of the Rose',
  String? author = 'Umberto Eco',
  int viewCount = 0,
  int? createdAt = 1793318400000, // 2026-10-30
}) =>
    Document(
      id: id,
      userId: 'u',
      title: title,
      type: type,
      status: DocumentStatus.complete,
      author: author,
      viewCount: viewCount,
      createdAt: createdAt,
    );

void main() {
  group('§33 vocabulary', () {
    test('every kind-map type has a cover, and every cover is a known type',
        () {
      for (final t in kKindByType.keys) {
        expect(kCovers.containsKey(t), isTrue, reason: '$t draws no object');
      }
      for (final t in kCovers.keys) {
        expect(kKindByType.containsKey(t), isTrue,
            reason: '$t is a cover for a type the kind map does not know');
      }
      expect(kitKnownTypes.toSet(), kKindByType.keys.toSet());
      expect(kitKnownTypes, hasLength(16));
    });

    test('social_video takes the film strip and reads Video', () {
      expect(kitCoverOf('social_video'), ('reel', 'Video'));
      expect(kitTypeLabel('social_video'), 'Video');
      expect(kitCoverOf('podcast'), ('sleeve', 'Podcast'));
      expect(kitCoverOf('audio'), ('tape', 'Recording'));
    });

    test('an unknown type falls back through its kind to an object and a word',
        () {
      expect(kitCoverOf('zzz'), ('note', 'Note'));
      expect(kitTypeLabel('zzz'), 'Note');
    });
  });

  group('hash', () {
    // Expected values from web's formula, run in node:
    // h = (h * 31 + s.charCodeAt(i)) >>> 0
    test('matches web hash()', () {
      expect(kitCoverHash(''), 0);
      expect(kitCoverHash('a'), 97);
      expect(kitCoverHash('doc-1'), 95755484);
      expect(kitCoverHash('Xq8F2mLp0aZr9tYb3kWc'), 2841389655);
      expect(kitCoverHash('the quick brown fox jumps over the lazy dog'),
          2212148595);
      expect(kitCoverHash('épée—✓'), 2486362178);
      expect(kitCoverHash('Xq8F2mLp0aZr9tYb3kWc') % 4, 3);
    });
  });

  group('OKLab', () {
    const white = Color(0xFFFFFFFF); // literal-ok: a reference value for the colour maths
    const black = Color(0xFF000000); // literal-ok: a reference value for the colour maths
    const red = Color(0xFFFF0000); // literal-ok: a reference value for the colour maths

    test('known values', () {
      final (lw, aw, bw) = kitOklab(white);
      expect(lw, closeTo(1.0, 1e-4));
      expect(aw, closeTo(0, 1e-4));
      expect(bw, closeTo(0, 1e-4));
      final (lr, ar, br) = kitOklab(red);
      expect(lr, closeTo(0.62796, 1e-4));
      expect(ar, closeTo(0.22486, 1e-4));
      expect(br, closeTo(0.12585, 1e-4));
    });

    test('a 50% white/black mix is L .5 — rgb(99, 99, 99)', () {
      final mid = kitMixOklab(white, black, 0.5);
      expect(kitOklab(mid).$1, closeTo(0.5, 1e-4));
      expect((mid.r * 255).round(), 99);
      expect((mid.g * 255).round(), 99);
      expect((mid.b * 255).round(), 99);
    });

    test('round trip', () {
      const teal = Color(0xFF2E7774); // literal-ok: a reference value for the colour maths
      final (l, a, b) = kitOklab(teal);
      final back = kitFromOklab(l, a, b);
      expect(back.r, closeTo(teal.r, 1e-6));
      expect(back.g, closeTo(teal.g, 1e-6));
      expect(back.b, closeTo(teal.b, 1e-6));
    });
  });

  group('cloth', () {
    final shelf = AppColors.shelfColor('teal-500', dark: false)!;
    final shelfDark = AppColors.shelfColor('teal-500', dark: true)!;

    test('light: each tone presses the shelf toward ink-700 in OKLab', () {
      const weights = [0.70, 0.60, 0.74, 0.52];
      final ls = kitOklab(shelf).$1;
      final li = kitOklab(AppColors.coverInk700).$1;
      for (var tone = 0; tone < 4; tone++) {
        final cloth = kitCoverCloth(shelf, tone, dark: false);
        final w = weights[tone];
        expect(kitOklab(cloth).$1, closeTo(ls * w + li * (1 - w), 1e-4),
            reason: 'tone $tone');
        expect(kitOklab(cloth).$1, lessThan(ls));
      }
    });

    test('dark keeps the shelf hue at the reference lightness and chroma', () {
      const l0 = [0.4, 0.375, 0.43, 0.355];
      // rose-500's dark cloths are all inside sRGB; teal-500's tones 1 and 3
      // are not (oklch .42 .075 h has a negative red), so their chroma comes
      // down — at the same lightness and, above all, the same hue.
      final rose = AppColors.shelfColor('rose-500', dark: true)!;
      for (final (shelf, inGamut) in [(rose, true), (shelfDark, false)]) {
        final (l, a, b) = kitOklab(shelf);
        final hue = math.atan2(b, a);
        final target = math.min(math.sqrt(a * a + b * b) * 1.2, 0.075);
        for (var tone = 0; tone < 4; tone++) {
          final (cl, ca, cb) = kitOklab(kitCoverCloth(shelf, tone, dark: true));
          final why = '$shelf tone $tone';
          expect(math.atan2(cb, ca), closeTo(hue, 1e-3), reason: why);
          expect(cl, closeTo(l0[tone] + (l - 0.62) * 0.5, 1e-3), reason: why);
          final chroma = math.sqrt(ca * ca + cb * cb);
          if (inGamut) {
            expect(chroma, closeTo(target, 1e-4), reason: why);
          } else {
            expect(chroma, lessThanOrEqualTo(target + 1e-4), reason: why);
            expect(chroma, greaterThan(0.03), reason: why);
          }
        }
      }
    });

    test('an unshelved source takes ink-500 as its base', () {
      for (final dark in [false, true]) {
        final a = kitCoverCloth(null, 2, dark: dark);
        final b = kitCoverCloth(AppColors.coverInk500, 2, dark: dark);
        expect(a.r, b.r);
        expect(a.g, b.g);
        expect(a.b, b.b);
      }
    });
  });

  group('render', () {
    Future<void> pumpBoth(
      WidgetTester tester,
      Widget child, {
      Size size = const Size(1200, 900),
      Future<void> Function(Brightness)? check,
    }) async {
      for (final brightness in Brightness.values) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // Unmount first: re-pumping MaterialApp with the other theme
        // cross-fades to it (F-17).
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          TokenScope(
            brightness: brightness,
            child: MaterialApp(
              theme:
                  brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
              home: Scaffold(body: SingleChildScrollView(child: child)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'threw in $brightness');
        if (check != null) await check(brightness);
      }
    }

    final shelf = AppColors.shelfColor('rose-500', dark: false);

    testWidgets('every type draws as a cover item, in both themes',
        (tester) async {
      final types = [...kitKnownTypes, 'zzz'];
      await pumpBoth(
        tester,
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            for (var i = 0; i < types.length; i++)
              KitCoverItem(
                doc: _doc(types[i],
                    id: 'id-$i',
                    viewCount: i.isEven ? 0 : 3,
                    // a long title and no author on some, to fill every slot
                    title: i % 3 == 0
                        ? 'A very long title that runs on and on past where any '
                            'cover could hold it in five lines of serif type'
                        : 'Short',
                    author: i % 4 == 0 ? null : 'Someone'),
                shelf: i % 5 == 0 ? null : shelf,
                meta: Text('${i * 12} passages'),
                onOpen: () {},
              ),
            // the source page's sheet draws the same cover at 52
            SizedBox(width: 52, child: KitCover(doc: _doc('epub'))),
          ],
        ),
      );
      expect(find.byType(KitCover), findsNWidgets(kitKnownTypes.length + 2));
    });

    testWidgets('the strip draws one row of as many as fit, in both themes',
        (tester) async {
      final items = [
        for (var i = 0; i < 12; i++)
          _doc(kitKnownTypes[i % kitKnownTypes.length],
              id: 'strip-$i', viewCount: i % 2),
      ];
      ({String title, Color? color})? homeOf(Document d) =>
          d.id.endsWith('3') ? null : (title: 'Medieval', color: shelf);

      for (final (width, expected) in [(390.0, 2), (1200.0, 8)]) {
        await pumpBoth(
          tester,
          SizedBox(
            width: width,
            child: KitCoverStrip(items: items, homeOf: homeOf, onOpen: (_) {}),
          ),
          size: Size(width, 900),
          check: (_) async {
            expect(find.byType(KitCoverItem), findsNWidgets(expected),
                reason: 'at $width');
            expect(find.text('Medieval'), findsWidgets);
          },
        );
      }
      // strip-3 has no home shelf: its line says so.
      expect(find.text('Unshelved'), findsOneWidget);
    });

    testWidgets('the ribbon marks an unread source and only an unread one',
        (tester) async {
      await pumpBoth(
        tester,
        KitCoverItem(doc: _doc('pdf', viewCount: 0)),
        check: (_) async {
          expect(find.byKey(const ValueKey('cover-ribbon')), findsOneWidget);
        },
      );
      await pumpBoth(
        tester,
        KitCoverItem(doc: _doc('pdf', viewCount: 2)),
        check: (_) async {
          expect(find.byKey(const ValueKey('cover-ribbon')), findsNothing);
        },
      );
    });

    testWidgets('the item reads the title and (unread); the cover is hidden',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoth(
        tester,
        Column(children: [
          KitCoverItem(doc: _doc('epub', title: 'Moby Dick', viewCount: 0)),
          KitCoverItem(
              doc: _doc('epub', id: 'b', title: 'Middlemarch', viewCount: 4)),
        ]),
      );
      expect(find.bySemanticsLabel(RegExp(r'^Moby Dick \(unread\)')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Middlemarch$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Middlemarch \(unread\)')),
          findsNothing);
      // The eyebrow is printed on the cover, never announced.
      expect(find.bySemanticsLabel(RegExp('BOOK')), findsNothing);
      handle.dispose();
    });

    testWidgets('a tap opens the source', (tester) async {
      var opened = 0;
      await pumpBoth(
        tester,
        KitCoverItem(doc: _doc('youtube'), onOpen: () => opened++),
      );
      await tester.tap(find.byType(KitCover));
      expect(opened, 1);
    });
  });
}
