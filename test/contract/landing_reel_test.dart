// Plate I (ADR-178) — the landing's film, against web
// `tests/landing/reel.test.js` and against the reference's own numbers. The
// film is a pure function of time, which is what makes it checkable without
// a device: paint any instant and read what every element would be.
//
// What these pin, because none of it raises an error when it goes wrong:
//   - the curves are the TOKENS' curves, solved as web solves them — and the
//     tokens are theme.css's, read from its source;
//   - the score is the reference's: the same PRNG sequence, the same field,
//     the same element at the same place at the same instant (numbers taken
//     from web's reelScore.js under node, 2026-10-19);
//   - the loop seam is clean: the last instant and the first draw nothing;
//   - each chapter's key frame (the still a paused or reduced-motion viewer
//     is shown) actually shows that chapter's subject;
//   - nothing a layout places sits off its own stage;
//   - the player: reduced motion opens paused on chapter 05; a chapter
//     button, paused, shows that chapter's still; the clock stops off screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/site/landing_reel.dart';
import 'package:flutter_app/site/reel_motion.dart';
import 'package:flutter_app/site/reel_score.dart';
import 'package:flutter_app/theme/app_motion.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

final _theme = File(
  '../NoteLetter-web/src/styles/theme.css',
).readAsStringSync();

List<double> _token(String name) {
  final m = RegExp('$name:\\s*cubic-bezier\\(([^)]+)\\);').firstMatch(_theme)!;
  return m.group(1)!.split(',').map((s) => double.parse(s.trim())).toList();
}

final _e = ReelEase.tokens;

/// The three faces, so a widget test lays the plate out in the type it is
/// drawn in (landing_test.dart's loader).
Future<void> _loadFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

ReelFrame _frame(ReelLayout l, double t) => paintReel(t, l, buildField(l), _e);

void main() {
  group('the curves', () {
    test('solves a cubic-bezier the way CSS does', () {
      final ease = bezier(0.25, 0.1, 0.25, 1);
      expect(ease(0), 0);
      expect(ease(1), 1);
      expect(ease(0.5), closeTo(0.8024033876954126, 1e-12));
    });

    test(
      'AppMotion is theme.css\'s --ease-out, --ease-quill, --ease-in-out',
      () {
        for (final (name, c) in [
          ('--ease-out', AppMotion.easeOut),
          ('--ease-quill', AppMotion.easeQuill),
          ('--ease-in-out', AppMotion.easeInOut),
        ]) {
          expect([c.a, c.b, c.c, c.d], _token(name), reason: name);
          final f = solveToken(c);
          expect(f(.5), inExclusiveRange(0, 1), reason: name);
        }
      },
    );

    test(
      'every easing the film moves by is a token, solved as web solves it',
      () {
        expect(_e.out(.3), closeTo(0.6725730908798251, 1e-12));
        expect(_e.quill(.3), closeTo(0.8771741996361885, 1e-12));
        expect(_e.inOut(.3), closeTo(0.11238615383406488, 1e-12));
      },
    );
  });

  group('the noise', () {
    test('mulberry32 is web\'s prng, bit for bit', () {
      final r = prng(124);
      expect(
        [for (var i = 0; i < 6; i++) r()],
        [
          0.7611495812889189,
          0.2591881030239165,
          0.3692523017525673,
          0.6604014730546623,
          0.5112375321332365,
          0.3017478126566857,
        ],
      );
      final r7 = prng(7);
      expect(
        [for (var i = 0; i < 3; i++) r7()],
        [0.011704753153026104, 0.06195825757458806, 0.97690763277933],
      );
    });

    test('Math.imul on the high bits', () {
      expect(imul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
      expect(imul32(0x6d2b79f5, 0x7fffffff), 0x12d4860b);
    });

    test('the handwriting is the same hand', () {
      for (final (w, n, counts, last) in [
        (196.0, 10, [25, 49, 37, 25, 25, 49, 25, 37, 25, 49], (141.4, 68.0)),
        (154.0, 9, [25, 49, 37, 25, 25, 49, 25, 37, 25], (118.0, 68.0)),
      ]) {
        final words = inkLines(w, const [20, 44, 68], 7);
        expect(words, hasLength(n));
        expect(words.map((p) => p.length), counts);
        expect(words.first.take(4), [
          (4.0, 20.0),
          (4.5, 19.6),
          (5.5, 18.5),
          (6.8, 17.0),
        ]);
        expect(words.last.last, last);
      }
    });
  });

  group('the chapters', () {
    test(
      'run in order inside the loop, each key frame inside its own chapter',
      () {
        for (var i = 0; i < reelChapters.length; i++) {
          final c = reelChapters[i];
          expect(c.at, lessThan(c.end));
          expect(c.key, greaterThanOrEqualTo(c.at));
          expect(c.key, lessThan(c.end));
          expect(chapterAt(c.key), i);
        }
        expect(reelChapters.last.end, reelDuration);
        expect(reelTitles, hasLength(reelChapters.length));
      },
    );

    test('the copy is Reel.jsx / reelScore.js\'s, verbatim', () {
      final score = File(
        '../NoteLetter-web/src/pages/landing/reelScore.js',
      ).readAsStringSync();
      for (final c in reelChapters) {
        expect(score, contains("caption: '${c.caption}'"), reason: c.name);
      }
      for (final h in reelHits) {
        expect(score, contains("mark: '${h.mark}'"));
      }
      for (final s in reelSections) {
        expect(score, contains("q: '${s.q}'"));
      }
      expect(score, contains("export const QUERY = '$reelQuery';"));
      final reel = File(
        '../NoteLetter-web/src/pages/landing/Reel.jsx',
      ).readAsStringSync();
      for (final line in [
        'A schematic &middot; illustrative library',
        'Your private podcast feed',
        'Four passages &middot; two returning',
        'The essay shares no word with the question. It was found by meaning.',
        '<b>Spacing</b>One passage, over a year',
      ]) {
        expect(reel, contains(line));
      }
    });
  });

  for (final l in reelLayouts) {
    group('the ${l.name} stage', () {
      final field = buildField(l);
      final shown = reelSources.where((s) => l.cards[s.id] != null).toList();

      test('places every card, slip, answer and the letter on the stage', () {
        for (final s in shown) {
          final c = l.cards[s.id]!;
          expect(c.x - c.w / 2, greaterThanOrEqualTo(0), reason: s.id);
          expect(c.x + c.w / 2, lessThanOrEqualTo(l.w), reason: s.id);
          expect(c.y - c.h / 2, greaterThanOrEqualTo(0), reason: s.id);
          expect(c.y + c.h / 2, lessThanOrEqualTo(l.h), reason: s.id);
        }
        for (final p in reelPassages.where((p) => l.cards[p.src] != null)) {
          expect(l.slips[p.id], isNotNull, reason: p.id);
        }
        final lt = l.letter;
        expect(lt.y - lt.h / 2, greaterThanOrEqualTo(0));
        expect(lt.y + lt.h / 2, lessThanOrEqualTo(l.h));
        expect(lt.head + lt.row * reelSections.length, lessThanOrEqualTo(lt.h));
        for (final y in l.results.ys) {
          expect(y, lessThan(l.h));
        }
      });

      test(
        'gives every passage a point, and the answers all sit on one shelf',
        () {
          for (final p in reelPassages) {
            expect(field.dotOf[p.id], isNotNull, reason: p.id);
          }
          for (final h in reelHits) {
            expect(field.dotOf[h.pid]!.shelf, 'att');
          }
          for (final w in field.wires) {
            expect(w.a, lessThan(field.dots.length));
            expect(w.b, lessThan(field.dots.length));
          }
        },
      );

      test('scatters the library exactly as the reference does', () {
        final ref = l.tall
            ? (
                dots: 57,
                wires: 57,
                d0: (
                  245.114916191717,
                  349.73882754222353,
                  1.6277012869901957,
                  0.0,
                ),
                d40: (
                  118.66387558851964,
                  237.49323140704112,
                  4.3892864735983315,
                  0.0,
                ),
                dl: (
                  89.62619998339599,
                  519.3907979389005,
                  3.6566250471770765,
                  0.6458644803306979,
                ),
                w0: (0, 18, false, 0.04163557563442737),
                wl: (16, 37, true, 0.7683752316981555),
              )
            : (
                dots: 79,
                wires: 88,
                d0: (
                  522.9682175980854,
                  346.210761844023,
                  1.6277012869901957,
                  0.0,
                ),
                d40: (
                  749.8557529960785,
                  252.00955106976517,
                  2.3964653996750713,
                  0.76985475573794,
                ),
                dl: (
                  1018.7538171931085,
                  309.0341826962955,
                  2.8608364601805807,
                  1.3035644399988515,
                ),
                w0: (0, 21, false, 0.8226429102942348),
                wl: (13, 51, true, 0.15972019019536673),
              );
        expect(field.dots, hasLength(ref.dots));
        expect(field.wires, hasLength(ref.wires));
        expect(field.wires.where((w) => w.bridge), hasLength(5));
        void dot(ReelDot d, (double, double, double, double) r) {
          expect(d.x, closeTo(r.$1, 1e-9));
          expect(d.y, closeTo(r.$2, 1e-9));
          expect(d.ph, closeTo(r.$3, 1e-12));
          expect(d.delay, closeTo(r.$4, 1e-9));
        }

        dot(field.dots[0], ref.d0);
        dot(field.dots[40], ref.d40);
        dot(field.dots.last, ref.dl);
        void wire(ReelWire w, (int, int, bool, double) r) {
          expect((w.a, w.b, w.bridge), (r.$1, r.$2, r.$3));
          expect(w.delay, closeTo(r.$4, 1e-12));
        }

        wire(field.wires.first, ref.w0);
        wire(field.wires.last, ref.wl);
      });

      test(
        'puts each element where the reference does, at the same instant',
        () {
          // Numbers from web's paint() under node at t = 23.7 and 29.3.
          final ask = _frame(l, 23.7), ret = _frame(l, 29.3);
          void at(ReelPart? p, double x, double y, [double? s, double? o]) {
            expect(p!.x, closeTo(x, 1e-6));
            expect(p.y, closeTo(y, 1e-6));
            if (s != null) expect(p.s, closeTo(s, 1e-9));
            if (o != null) expect(p.o, closeTo(o, 1e-9));
          }

          if (l.tall) {
            at(ask['D:5'], 245.5989516102222, 265.3539443376602, null, .8);
            expect(ask['D:5']!.rad, closeTo(1.38, 1e-9));
            at(
              ask['X:1'],
              212.60075045951598,
              343.16419877834494,
              0.32765594811221627,
              0.8075737438441835,
            );
            at(ask['H:0'], 224.75648673129666, 281.9332443755728);
            expect(ask['QW:2']!.draw, closeTo(0.6045757229199109, 1e-9));
            at(ask['L:mnt'], 264.79999999999995, 176.9392, .86, .28);
            at(
              ret['X:1'],
              204.39347067817636,
              375.55357468272905,
              0.894434826121002,
              0.8266813747171138,
            );
            at(ret['LT'], 210, 336, 1, 1);
            at(ret['LT:s3'], 158, 371, 1, 0);
          } else {
            at(ask['D:5'], 382.9386828795252, 358.138786840251, null, .8);
            expect(ask['D:5']!.rad, closeTo(1.8, 1e-9));
            at(
              ask['X:1'],
              468.4296210733338,
              337.2649643245995,
              0.32765594811221627,
              0.8075737438441835,
            );
            at(ask['H:0'], 346.48131136290357, 388.4917402013921);
            expect(ask['QW:2']!.draw, closeTo(0.6045757229199109, 1e-9));
            at(ask['L:mnt'], 514, 239.168, .86, .28);
            at(
              ret['X:1'],
              697.8479010280402,
              335.1361397151706,
              0.9909096655826418,
              0.8266813747171138,
            );
            at(ret['LT'], 640, 316, 1, 1);
            at(ret['LT:s3'], 174, 454, 1, 0);
          }
          expect(ask['P:1']!.o, closeTo(0.001885279856274691, 1e-12));
          expect(ask['P:1']!.shown, 0, reason: 'the writer hides ≤ 0.002');
          expect(ret['X:1']!.v('--pl-hl'), 1);
        },
      );

      test('draws nothing at either side of the loop seam', () {
        for (final t in [0.0, reelDuration - 0.05]) {
          final f = _frame(l, t);
          final lit = [
            for (final e in f.parts.entries)
              if ((e.value.o ?? 0) > 0.01) e.key,
          ];
          expect(lit, isEmpty, reason: 't=$t');
        }
      });

      test('is the same frame every time it is asked for', () {
        final a = _frame(l, 23.7), b = _frame(l, 23.7);
        expect(a.parts.keys, b.parts.keys);
        for (final k in a.parts.keys) {
          expect(a[k]!.same(b[k]), isTrue, reason: k);
          expect((a[k]!.x, a[k]!.y, a[k]!.o), (b[k]!.x, b[k]!.y, b[k]!.o));
        }
      });

      test('shows each chapter at its key frame', () {
        final keys = [for (final c in reelChapters) _frame(l, c.key)];
        final [gather, read, index, ask, ret] = keys;
        for (var i = 0; i < reelChapters.length; i++) {
          expect(keys[i]['T$i']!.o, 1, reason: reelChapters[i].name);
        }
        for (final s in shown) {
          expect(gather['C:${s.id}']!.o, closeTo(1, .01), reason: s.id);
          expect(read['C:${s.id}']!.v('--pl-p'), 1, reason: s.id);
        }
        for (final p in reelPassages) {
          expect(
            index['D:${field.dotOf[p.id]!.i}']!.o,
            greaterThan(.95),
            reason: p.id,
          );
        }
        expect(
          ask['Q:txt']!.text,
          'that thing about attention not being a currency',
        );
        for (var i = 0; i < reelHits.length; i++) {
          expect(ask['X:$i']!.o, 1);
          expect(ask['X:$i']!.v('--pl-hl'), 1);
        }
        expect(ret['LT']!.o, 1);
        for (var i = 0; i < reelSections.length; i++) {
          expect(ret['LT:s$i']!.o, closeTo(1, .01), reason: '§0${i + 1}');
        }
        expect(ret['LT:seal']!.s, 1);
        for (var i = 0; i < reelHits.length; i++) {
          expect(ret['X:$i']!.o, 0);
        }
      });
    });
  }

  group('fitting the stage', () {
    test(
      'switches to the tall stage below 760px and stops it growing past 1.15',
      () {
        expect(layoutFor(760).name, 'wide');
        expect(layoutFor(759).name, 'tall');
        final narrow = fitFor(reelTall, 354);
        expect(narrow.left, 0);
        expect(narrow.scale, closeTo(354 / 420, 1e-9));
        final tablet = fitFor(reelTall, 700);
        expect(tablet.scale, 1.15);
        expect(tablet.left, closeTo((700 - 420 * 1.15) / 2, 1e-9));
      },
    );
  });

  group('the audio bars', () {
    test('splits into heard and unheard without losing or doubling a bar', () {
      final all = waveBars(3, 34, 200, 38);
      final heard = waveBars(3, 34, 200, 38, .31, WavePart.heard);
      final ahead = waveBars(3, 34, 200, 38, .31, WavePart.unheard);
      expect(heard.length + ahead.length, all.length);
      expect(all, hasLength(34));
      // `M2.9 8.8V29.2M8.8 11.4V26.6M14.7 10.0V28.0` — web's path.
      expect(all.take(3), [
        (2.9, 8.8, 29.2),
        (8.8, 11.4, 26.6),
        (14.7, 10.0, 28.0),
      ]);
      expect(waveBars(33.8 * 1.4, 16, 64, 22).take(2), [
        (2.0, 6.9, 15.1),
        (6.0, 6.2, 15.8),
      ]);
    });
  });

  group('the player', () {
    setUpAll(_loadFonts);
    Future<void> pump(
      WidgetTester tester, {
      double width = 1200,
      bool reduced = false,
    }) async {
      tester.view.physicalSize = Size(width * 2, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: width,
                      child: LandingReel(day: 'Tuesday', phone: width <= 640),
                    ),
                    const SizedBox(height: 3000),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    String timecode(WidgetTester tester) => tester
        .widget<Text>(find.textContaining(' / 00:36', skipOffstage: false))
        .data!;

    testWidgets('reduced motion opens paused on chapter 05\'s still', (
      tester,
    ) async {
      await pump(tester, reduced: true);
      expect(timecode(tester), '00:33 / 00:36');
      expect(find.text(reelChapters.last.caption), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(timecode(tester), '00:33 / 00:36', reason: 'paused');
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Play the film'), findsOneWidget);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('plays, pauses, and a paused chapter button shows its still', (
      tester,
    ) async {
      await pump(tester);
      expect(timecode(tester), '00:00 / 00:36');
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(timecode(tester), '00:02 / 00:36');
      final handle = tester.ensureSemantics();
      await tester.tap(find.byKey(const ValueKey('reel-play')));
      await tester.pump();
      expect(find.bySemanticsLabel('Play the film'), findsOneWidget);
      handle.dispose();
      await tester.tap(find.byKey(const ValueKey('reel-ch-2')));
      await tester.pump();
      expect(timecode(tester), '00:17 / 00:36', reason: 'Index\'s key, 17.6');
      expect(find.text(reelChapters[2].caption), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(timecode(tester), '00:17 / 00:36');
      // Playing, a chapter button goes to the chapter's START.
      await tester.tap(find.byKey(const ValueKey('reel-play')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reel-ch-3')));
      await tester.pump();
      expect(timecode(tester), '00:19 / 00:36');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the track is a slider: a second a step, and it scrubs', (
      tester,
    ) async {
      await pump(tester, reduced: true);
      final handle = tester.ensureSemantics();
      final slider = find.bySemanticsLabel('Film position');
      expect(slider, findsOneWidget);
      final node = tester.getSemantics(slider);
      expect(node.value, '00:33, chapter 05, Return');
      tester.semantics.decrease(find.semantics.byLabel('Film position'));
      await tester.pump();
      expect(timecode(tester), '00:32 / 00:36');
      // A tap a quarter along the track lands a quarter into the film.
      final track = find.byKey(const ValueKey('reel-track'));
      final box = tester.getRect(track);
      await tester.tapAt(Offset(box.left + box.width / 4, box.center.dy));
      await tester.pump();
      expect(timecode(tester), '00:08 / 00:36');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('picks the tall stage on a phone and the wide one on a desk', (
      tester,
    ) async {
      await pump(tester, width: 390);
      expect(find.byKey(const ValueKey('reel-world-tall')), findsOneWidget);
      await pump(tester, width: 1200);
      expect(find.byKey(const ValueKey('reel-world-wide')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the clock stops when the plate leaves the screen', (
      tester,
    ) async {
      await pump(tester);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2400),
      );
      await tester.pump();
      final off = timecode(tester);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(timecode(tester), off, reason: 'off screen, the film holds');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 2400),
      );
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(timecode(tester), isNot(off), reason: 'back on screen, it runs');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
