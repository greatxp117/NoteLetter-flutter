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
//     from web's reelScore.js under node with `{ cut: PLATE }`, 41ffd9a);
//   - the loop seam is clean: the last instant and the first draw nothing;
//   - two titles never share a frame. The first port's titles rose word by
//     word through line masks, and the outgoing one's descenders were still
//     on the stage while the next rose into the same place — every frame
//     individually "correct" (web 41ffd9a);
//   - each chapter's key frame (the still a paused or reduced-motion viewer
//     is shown) actually shows that chapter's subject;
//   - nothing a layout places sits off its own stage;
//   - the player: reduced motion opens paused on chapter 05; a chapter
//     button, paused, shows that chapter's still; a tap on the track lands
//     within the segment under it; the clock stops off screen.
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

final _fields = {for (final l in reelLayouts) l.name: buildField(l)};

ReelFrame _frame(ReelLayout l, double t) =>
    paintReel(t, l, _fields[l.name]!, _e, cut: reelPlate);

/// A part's opacity as the writer sets it (unwritten is hidden).
double _lit(ReelFrame f, String k) => f[k]?.o ?? 0;

/// The web commit this port is of. Web's working tree moves on without it
/// (the plate is being cut there for the hero, 2026-10-19), so the copy and
/// the layout numbers are read from this commit, not from the tree.
const _webRef = '41ffd9a';

/// A web file as [_webRef] has it, with its `\uXXXX` escapes read as the
/// characters they are (web writes a caption's em dash as `\u2014`).
String _source(String path) {
  final r = Process.runSync('git', [
    '-C',
    '../NoteLetter-web',
    'show',
    '$_webRef:$path',
  ]);
  if (r.exitCode != 0) fail('git show $_webRef:$path — ${r.stderr}');
  return (r.stdout as String).replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
  );
}

/// A number as JS source spells it: no `.0` on a whole one.
String _js(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

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
    final cut = reelPlate;
    test(
      'run in order inside the loop, each key frame inside its own chapter',
      () {
        for (var i = 0; i < cut.chapters.length; i++) {
          final c = cut.chapters[i];
          expect(c.at, lessThan(cut.endOf(i)));
          expect(c.key, greaterThanOrEqualTo(c.at));
          expect(c.key, lessThan(cut.endOf(i)));
          expect(chapterAt(cut, c.key), i);
        }
        expect(cut.endOf(cut.chapters.length - 1), cut.duration);
        expect(cut.duration, 36);
        for (var i = 0; i < cut.chapters.length; i++) {
          expect(cut.titles.where((ti) => ti.ch == i), isNotEmpty);
        }
      },
    );

    test(
      'every beat is the reference\'s, computed from the chapter starts',
      () {
        // web `PLATE.beats` under node (41ffd9a), less the hero's own beats.
        const ref = {
          'cardsIn': 0.6,
          'cardGap': 0.3,
          'cardDur': 1.3,
          'inkDur': 1.7,
          'readAt': 6.95,
          'readGap': 0.3,
          'readDur': 1.05,
          'annIn': 8.2,
          'annOut': 10.35,
          'tearAt': 10.55,
          'tearGap': 0.07,
          'flyAt': 12.55,
          'flyGap': 0.075,
          'flyDur': 1.4,
          'libAt': 13.7,
          'wireAt': 14.6,
          'shelfAt': 15.1,
          'fieldMove': 19.05,
          'barIn': 19.3,
          'typeAt': 19.95,
          'typeDur': 2.05,
          'pulseAt': 22.15,
          'pulseSpeed': 760.0,
          'qWireAt': 22.95,
          'resAt': 23.45,
          'resGap': 0.2,
          'hlAt': 24.55,
          'coAt': 25.45,
          'fieldOut': 26.85,
          'letterIn': 27.3,
          'foldAt': 28.45,
          'foldGap': 0.24,
          'sealAt': 30.35,
          'curveAt': 30.55,
          'inboxAt': 31.35,
          'listenAt': 31.9,
          'outAt': 34.7,
          'outDur': 1.0,
        };
        final b = cut.beats;
        final got = {
          'cardsIn': b.cardsIn,
          'cardGap': b.cardGap,
          'cardDur': b.cardDur,
          'inkDur': b.inkDur,
          'readAt': b.readAt,
          'readGap': b.readGap,
          'readDur': b.readDur,
          'annIn': b.annIn,
          'annOut': b.annOut,
          'tearAt': b.tearAt,
          'tearGap': b.tearGap,
          'flyAt': b.flyAt,
          'flyGap': b.flyGap,
          'flyDur': b.flyDur,
          'libAt': b.libAt,
          'wireAt': b.wireAt,
          'shelfAt': b.shelfAt,
          'fieldMove': b.fieldMove,
          'barIn': b.barIn,
          'typeAt': b.typeAt,
          'typeDur': b.typeDur,
          'pulseAt': b.pulseAt,
          'pulseSpeed': b.pulseSpeed,
          'qWireAt': b.qWireAt,
          'resAt': b.resAt,
          'resGap': b.resGap,
          'hlAt': b.hlAt,
          'coAt': b.coAt,
          'fieldOut': b.fieldOut,
          'letterIn': b.letterIn,
          'foldAt': b.foldAt,
          'foldGap': b.foldGap,
          'sealAt': b.sealAt,
          'curveAt': b.curveAt,
          'inboxAt': b.inboxAt,
          'listenAt': b.listenAt,
          'outAt': b.outAt,
          'outDur': b.outDur,
        };
        // Exactly: the same sums in the same doubles as JS.
        expect(got, ref);
      },
    );

    test('never has two titles on the stage at once', () {
      // Sampled every 0.05s, as web's guard is. Red when one title's exit
      // runs into the next (the first title's `out` at 6.3, say).
      for (var n = 0; n * 0.05 < cut.duration; n++) {
        final t = n * 0.05;
        final f = _frame(reelWide, t);
        final on = [
          for (var i = 0; i < cut.titles.length; i++)
            if (_lit(f, 'T$i:0') > .01 || _lit(f, 'T$i:1') > .01) i,
        ];
        expect(
          on.length,
          lessThanOrEqualTo(1),
          reason: 't=${t.toStringAsFixed(2)}: titles $on',
        );
      }
    });

    test('inks each title line in whole, as the reference does', () {
      // web's frame under node: each line's rise, opacity, focus pull and
      // tracking (`filter: blur(Npx)` is N here; `none` is 0).
      void line(
        ReelFrame f,
        String k,
        double y,
        double o,
        double blur,
        double track,
      ) {
        expect(f[k]!.x, 0, reason: k);
        expect(f[k]!.y, closeTo(y, 1e-9), reason: '$k y');
        expect(f[k]!.o, closeTo(o, 1e-9), reason: '$k o');
        expect(f[k]!.v('blur'), blur, reason: '$k blur');
        expect(f[k]!.v('--pl-track'), track, reason: '$k track');
      }

      final f04 = _frame(reelWide, .4);
      line(f04, 'T0:0', 2.0925234298874136, .7461183870868747, .87, .0105);
      line(f04, 'T0:1', 6.515506671152579, .34196976406402146, 2.71, .0326);
      expect(f04['EB:0']!.o, closeTo(.8075308948427076, 1e-9));
      expect(f04['EB:0']!.v('--pl-rule'), .049);
      final f60 = _frame(reelWide, 6.0);
      line(f60, 'T0:0', -1.4907459380414076, .8509254061958592, .6, 0);
      line(f60, 'T0:1', -.5323686789141785, .9467631321085821, .21, 0);
      expect(f60['EB:0']!.o, closeTo(.7919067337334592, 1e-9));
      final f62 = _frame(reelWide, 6.2);
      line(f62, 'T0:0', -9.467631321085834, .05323686789141657, 3.79, 0);
      line(f62, 'T0:1', -8.509254061958616, .14907459380413834, 3.4, 0);
      expect(f62['EB:0']!.o, closeTo(.014466791996507689, 1e-9));
      expect(_lit(f62, 'T1'), 0, reason: 'the next title has not begun');
      final f69 = _frame(reelWide, 6.9);
      expect(_lit(f69, 'T0'), 0);
      line(f69, 'T1:0', .7229327626809545, .9140903086896357, .3, .0036);
      line(f69, 'T1:1', 2.2445636102699993, .729185196965736, .94, .0112);
      expect(f69['EB:1']!.o, closeTo(.9530317628760736, 1e-9));
      expect(f69['EB:1']!.v('--pl-rule'), .312);
      expect(_lit(f69, 'EB:0'), 0);
      final f54 = _frame(reelWide, 5.4);
      line(f54, 'T0:0', 0, 1, 0, 0);
      line(f54, 'T0:1', 0, 1, 0, 0);
    });

    test('the copy is Reel.jsx / reelScore.js\'s, verbatim', () {
      final score = _source('src/pages/landing/reelScore.js');
      for (final c in cut.chapters) {
        expect(score, contains("caption: '${c.caption}'"), reason: c.name);
      }
      for (final ti in cut.titles) {
        expect(
          score,
          contains(
            "{ ch: ${ti.ch}, at: ${ti.at}, out: ${ti.out}, "
            "lines: ['${ti.lines[0]}', '${ti.lines[1]}'] }",
          ),
          reason: ti.lines.join(' '),
        );
      }
      for (final h in reelHits) {
        expect(score, contains("mark: '${h.mark}'"));
      }
      for (final s in reelSections) {
        expect(score, contains("q: '${s.q}'"));
      }
      expect(score, contains("export const QUERY = '$reelQuery';"));
      final reel = _source('src/pages/landing/Reel.jsx');
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

    test('the stages are laid out with the reference\'s numbers', () {
      final score = _source('src/pages/landing/reelScore.js');
      for (final l in reelLayouts) {
        final ti = l.title;
        expect(
          score,
          contains(
            'title: { x: ${_js(ti.x)}, y: ${_js(ti.y)}, '
            'eb: ${_js(ti.eb)} }',
          ),
          reason: l.name,
        );
        final q = l.search;
        expect(
          score,
          contains(
            'search: { x: ${_js(q.x)}, y: ${_js(q.y)}, '
            'w: ${_js(q.w)}, h: ${_js(q.h)} }',
          ),
          reason: l.name,
        );
      }
      final vid = reelTall.cards['vid']!;
      expect(
        score,
        contains(
          'vid: { x: ${_js(vid.x)}, y: ${_js(vid.y)}, '
          'w: ${_js(vid.w)}, h: ${_js(vid.h)}, r: ${_js(vid.r)} }',
        ),
      );
      final p1 = reelTall.slips['p1']!;
      expect(score, contains('p1: [${_js(p1.$1)}, ${_js(p1.$2)}]'));
    });
  });

  for (final l in reelLayouts) {
    group('the ${l.name} stage', () {
      final field = _fields[l.name]!;
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
          // Numbers from web's paint() under node at t = 23.7 and 29.3 (and
          // 5.4, 12.0 for the parts the tall stage moved in 41ffd9a).
          final ask = _frame(l, 23.7), ret = _frame(l, 29.3);
          final gather = _frame(l, 5.4), laid = _frame(l, 12.0);
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
            at(ask['Q'], 210, 140, 1, 1);
            at(gather['C:vid'], 304.3756540236925, 175.4757703168383, 1, 1);
            at(laid['S:p1'], 303.58161572506486, 161.70919781617656, 1, 1);
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
            at(ask['Q'], 790, 92, 1, 1);
            at(gather['C:vid'], 842.3756540236925, 157.4757703168383, 1, 1);
            at(laid['S:p1'], 833.5816157250648, 147.70919781617656, 1, 1);
          }
          expect(ask['P:1']!.o, closeTo(0.001885279856274691, 1e-12));
          expect(ask['P:1']!.shown, 0, reason: 'the writer hides ≤ 0.002');
          expect(ret['X:1']!.v('--pl-hl'), 1);
        },
      );

      test('draws nothing at either side of the loop seam', () {
        for (final t in [0.0, reelPlate.duration - 0.05]) {
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

      test("shows each chapter's subject at its key frame", () {
        final cut = reelPlate;
        final keys = [for (final c in cut.chapters) _frame(l, c.key)];
        final [gather, read, index, ask, ret] = keys;
        for (var i = 0; i < cut.chapters.length; i++) {
          final f = keys[i];
          final name = cut.chapters[i].name;
          final full = [
            for (var j = 0; j < cut.titles.length; j++)
              if (cut.titles[j].ch == i) j,
          ].any((j) => _lit(f, 'T$j:0') > .99 && _lit(f, 'T$j:1') > .99);
          expect(full, isTrue, reason: '$name: a title fully inked');
          expect(f['EB:$i']!.o, closeTo(1, .01), reason: '$name: eyebrow');
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

  group('the track', () {
    test('maps a pointer within the segment under it', () {
      final cut = reelPlate;
      final segs = reelTrackSegments(cut, 1000);
      expect(segs, hasLength(5));
      expect(segs.first.left, 0);
      expect(segs.last.left + segs.last.width, closeTo(1000, 1e-9));
      for (var i = 1; i < segs.length; i++) {
        final prev = segs[i - 1];
        expect(segs[i].left - (prev.left + prev.width), closeTo(4, 1e-9));
        // A segment's left edge is its chapter's start, and so is the gap
        // before it — a linear map put 6.5s ~4px late per gap crossed.
        expect(reelTrackSeek(cut, segs[i].left, 1000), cut.chapters[i].at);
        expect(reelTrackSeek(cut, segs[i].left - 2, 1000), cut.chapters[i].at);
      }
      final idx = segs[2];
      expect(reelTrackSeek(cut, idx.left + idx.width / 2, 1000), 15.75);
      expect(reelTrackSeek(cut, 0, 1000), 0);
      expect(reelTrackSeek(cut, -20, 1000), 0);
      expect(reelTrackSeek(cut, 1000, 1000), cut.duration - .01);
      expect(reelTrackSeek(cut, 1200, 1000), cut.duration - .01);
    });
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
      expect(find.text(reelPlate.chapters.last.caption), findsOneWidget);
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
      expect(find.text(reelPlate.chapters[2].caption), findsOneWidget);
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
      // A tap lands within the segment under it: 6.05s along Gather's
      // segment is 00:06, where one linear map over the whole track (gaps
      // and all) read 00:05.
      final track = find.byKey(const ValueKey('reel-track'));
      final box = tester.getRect(track);
      final dx = (box.width - reelTrackGap * 4) * 6.05 / 36;
      expect(dx / box.width * 36, lessThan(6), reason: 'a linear map');
      await tester.tapAt(Offset(box.left + dx, box.center.dy));
      await tester.pump();
      expect(timecode(tester), '00:06 / 00:36');
      // In the gap before Ask, it is Ask's start.
      final ask = reelTrackSegments(reelPlate, box.width)[3];
      await tester.tapAt(Offset(box.left + ask.left - 2, box.center.dy));
      await tester.pump();
      expect(timecode(tester), '00:19 / 00:36');
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
