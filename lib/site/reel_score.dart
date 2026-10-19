// The reel's score — Plate I, "One morning's work" (ADR-178). A 1:1 port of
// web `pages/landing/reelScore.js`: the same cast, the same two layouts, the
// same beats, the same seeded field and the same paint, so the two clients
// show the same frame at the same `t`.
//
//   01 Gather  what you kept arrives — a lecture, a PDF, a page of your own
//              handwriting, a podcast, an article, a voice memo, a deck, a book
//   02 Read    each is read through: audio and video transcribed, ink typed,
//              and the text torn into passages that keep their source
//   03 Index   the passages fall into a field by what they MEAN; shelves form
//              around them, and the rest of the library fades in behind
//   04 Ask     a half-remembered sentence goes in; the field is read from the
//              query outward and three passages come back quoted, one of them
//              sharing no word with what was typed
//   05 Return  those passages fold into the morning's letter, the seal is
//              pressed, and the letter is spaced to arrive before it is lost
//
// Everything here is illustrative CONTENT — the specimen library §05 and §06
// read from — and the plate is captioned a schematic.
//
// [paintReel] is pure in `t`: it returns every element's state for that
// instant as a [ReelFrame] and reads nothing back. Where the reference writes
// a CSS custom property with `toFixed(n)`, the value here is rounded the same
// way ([_fx]), so a recorded frame compares number for number with web's.
//
// Departures from the JS, each because Dart has no such thing: JS's stable
// `Array.sort` is a sort with an index tie-break ([buildField]); `Math.hypot`
// is `sqrt(dx² + dy²)`; an SVG path string (`wavePath`) is a list of bars.
import 'dart:math' as math;

import 'reel_motion.dart';

typedef Pt = (double, double);

const double reelDuration = 36;

class ReelChapter {
  final String n;
  final String name;
  final double at;
  final double key;
  final String caption;
  const ReelChapter(this.n, this.name, this.at, this.key, this.caption);

  /// Where the chapter ends: the next one's start, or the loop's end.
  double get end {
    final i = reelChapters.indexOf(this);
    return i + 1 < reelChapters.length ? reelChapters[i + 1].at : reelDuration;
  }
}

/// Chapter starts, and the frame each one is best seen at when the film is
/// paused or motion is reduced (`key`).
const reelChapters = <ReelChapter>[
  ReelChapter(
    '01',
    'Gather',
    0,
    5.4,
    'Lectures, PDFs, podcasts, voice memos, your own handwriting — whatever you kept, wherever you kept it.',
  ),
  ReelChapter(
    '02',
    'Read',
    6.5,
    10.25,
    'Every source is read through. Audio and video are transcribed, ink is typed, and each passage keeps its source and the second it was said.',
  ),
  ReelChapter(
    '03',
    'Index',
    12.5,
    17.6,
    'Passages are filed by what they mean, not by what they were called, and the shelves form around them on their own.',
  ),
  ReelChapter(
    '04',
    'Ask',
    19,
    26.2,
    'Ask in a half-remembered sentence. The answer comes back quoted, with its source — even a passage that never used your words.',
  ),
  ReelChapter(
    '05',
    'Return',
    27,
    33.8,
    'Then a few passages come back to you each morning, spaced to arrive just before you would have lost them.',
  ),
];

/// Which chapter `t` falls in.
int chapterAt(double t) {
  var i = 0;
  for (var j = 0; j < reelChapters.length; j++) {
    if (t >= reelChapters[j].at) i = j;
  }
  return i;
}

/// The display line of each chapter — two lines, the second in the accent
/// italic, as every headline on the page is set.
const reelTitles = <List<List<String>>>[
  [
    ['Everything'],
    ['you', 'kept.'],
  ],
  [
    ['Read,'],
    ['every', 'word.'],
  ],
  [
    ['Filed', 'by'],
    ['meaning.'],
  ],
  [
    ['Found', 'in'],
    ['a', 'sentence.'],
  ],
  [
    ['Handed', 'back,'],
    ['in', 'time.'],
  ],
];

// ─── the specimen library ────────────────────────────────────────────────────

class ReelSource {
  final String id, media, kind, meta, title, stamp, text;
  const ReelSource(
    this.id,
    this.media,
    this.kind,
    this.meta,
    this.title,
    this.stamp,
    this.text,
  );
}

const reelSources = <ReelSource>[
  ReelSource(
    'vid',
    'video',
    'Lecture',
    'Video · 52 min',
    'Weather, Not Currency',
    '41:20',
    'You will be told that attention is a currency. It is not. It is a weather system.',
  ),
  ReelSource(
    'pdf',
    'page',
    'Essay',
    'PDF · 212 pp.',
    'The Maintenance Essays',
    'p. 61',
    'Spending implies a purse with a bottom. Tending implies a season. The roof held.',
  ),
  ReelSource(
    'note',
    'ink',
    'Your note',
    'Handwriting',
    'Kyoto notebook',
    'Apr 3',
    'If attention is weather then the calendar is a barometer, not a budget.',
  ),
  ReelSource(
    'pod',
    'audio',
    'Podcast',
    'Episode 48',
    'The Rehearsal Hour',
    '12:05',
    'Most of what we call memory is rehearsal we never noticed.',
  ),
  ReelSource(
    'art',
    'article',
    'Article',
    '6 min read',
    'The Unread Shelf',
    '¶ 4',
    'An unread shelf is not a failure. It is a map of who you meant to become.',
  ),
  ReelSource(
    'memo',
    'mic',
    'Voice memo',
    'Walk home',
    'Voice memo',
    '0:48',
    'Write the ending first. Then earn it.',
  ),
  ReelSource(
    'deck',
    'slides',
    'Slides',
    '22 slides',
    'How we decide',
    'Slide 7',
    'Reversible: decide fast. Irreversible: decide slowly.',
  ),
  ReelSource(
    'book',
    'book',
    'EPUB',
    'Chapter 3',
    'The Weeknight Kitchen',
    'ch. 3',
    'Salt early. Taste late. Most of cooking is waiting well.',
  ),
];

ReelSource reelSource(String id) => reelSources.firstWhere((s) => s.id == id);

class ReelShelf {
  final String id, name;

  /// A shelf colour token NAME (`--shelf-*`), the same pair a reader's own
  /// shelf is painted with — resolved by `AppColors.shelfColor`.
  final String tone;
  const ReelShelf(this.id, this.name, this.tone);
}

const reelShelves = <ReelShelf>[
  ReelShelf('att', 'Attention', 'brick-500'),
  ReelShelf('mnt', 'Maintenance', 'sage-500'),
  ReelShelf('dec', 'Deciding', 'plum-500'),
  ReelShelf('wri', 'Writing', 'ink-400'),
  ReelShelf('ckg', 'Cooking', 'sage-700'),
];

ReelShelf reelShelf(String id) => reelShelves.firstWhere((s) => s.id == id);

class ReelPassage {
  final String id, src, shelf, q;
  const ReelPassage(this.id, this.src, this.shelf, this.q);
}

/// Passages, as the reading tears them out. The first three are what §04's
/// question finds.
const reelPassages = <ReelPassage>[
  ReelPassage(
    'p1',
    'vid',
    'att',
    'Attention is not a currency. It is a weather system.',
  ),
  ReelPassage(
    'p2',
    'pdf',
    'att',
    'Spending implies a purse with a bottom. Tending implies a season.',
  ),
  ReelPassage(
    'p3',
    'note',
    'att',
    'The calendar is a barometer, not a budget.',
  ),
  ReelPassage('p4', 'pod', 'att', 'Most memory is rehearsal we never noticed.'),
  ReelPassage(
    'p5',
    'pdf',
    'mnt',
    'The roof is not in the history book, because the roof held.',
  ),
  ReelPassage(
    'p6',
    'art',
    'mnt',
    'An unread shelf is a map of who you meant to become.',
  ),
  ReelPassage('p7', 'memo', 'wri', 'Write the ending first. Then earn it.'),
  ReelPassage(
    'p8',
    'deck',
    'dec',
    'Reversible: decide fast. Irreversible: slowly.',
  ),
  ReelPassage('p9', 'book', 'ckg', 'Salt early. Taste late.'),
  ReelPassage(
    'p10',
    'art',
    'wri',
    'A short sentence is a kindness to the tired.',
  ),
];

const reelQuery = 'that thing about attention not being a currency';

class ReelHit {
  final String pid, kind, src, at, before, mark;

  /// The one that shares no word with the query: the callout points at it.
  final bool plain;
  const ReelHit(
    this.pid,
    this.kind,
    this.src,
    this.at,
    this.before,
    this.mark, {
    this.plain = false,
  });
}

/// §04's three answers — §05's search panel, word for word.
const reelHits = <ReelHit>[
  ReelHit(
    'p1',
    'Lecture',
    'Weather, Not Currency',
    '41:20',
    'You will be told that attention is a currency. ',
    'It is not. It is a weather system.',
  ),
  ReelHit(
    'p2',
    'Essay',
    'The Maintenance Essays',
    'p. 61',
    'Spending implies a purse with a bottom. ',
    'Tending implies a season.',
    plain: true,
  ),
  ReelHit(
    'p3',
    'Your note',
    'Kyoto notebook',
    'Apr 3',
    '',
    'If attention is weather then the calendar is a barometer, not a budget.',
  ),
];

class ReelSection {
  final String kind, at, q;
  final String? back;
  const ReelSection(this.kind, this.at, this.q, [this.back]);
}

/// The letter the answers fold into — № 124, the specimen §06 lists first.
const reelSections = <ReelSection>[
  ReelSection(
    'Lecture',
    '41:20',
    'Attention is not a currency. It is a weather system.',
    'Third time',
  ),
  ReelSection(
    'Essay',
    'p. 61',
    'Spending implies a purse with a bottom. Tending implies a season.',
  ),
  ReelSection(
    'Your note',
    'Apr 3',
    'If attention is weather, the calendar is a barometer, not a budget.',
    'Second time',
  ),
  ReelSection(
    'Podcast',
    '12:05',
    'Most of what we call memory is rehearsal we never noticed.',
  ),
];

/// Fig. 1's marks, compressed into the plate's corner.
const reelCurveMarks = <(double, String)>[
  (0.06, 'Read'),
  (0.24, 'Day 3'),
  (0.44, 'Day 10'),
  (0.7, 'A month'),
];

// ─── layouts ─────────────────────────────────────────────────────────────────
// Two stages in design pixels. The world is laid out at this size and scaled
// to the plate's width, so a beat lands in the same place on every screen.
// `wide` for a plate 760px and over; `tall` (portrait) below it. A part a
// layout sets to null is not drawn there.

class ReelCard {
  final double x, y, w, h, r;
  const ReelCard(this.x, this.y, this.w, this.h, this.r);
}

class ReelCluster {
  final double x, y, rad;
  const ReelCluster(this.x, this.y, this.rad);
}

class ReelBox {
  final double x, y, w, h;
  const ReelBox(this.x, this.y, this.w, [this.h = 0]);
}

class ReelLetterBox {
  final double x, y, w, h, head, row;
  const ReelLetterBox(this.x, this.y, this.w, this.h, this.head, this.row);
}

class ReelAnn {
  final String src, text;
  final double dx, dy;
  const ReelAnn(this.src, this.text, this.dx, this.dy);
}

class ReelLayout {
  final String name;
  final double w, h;
  final ({double x, double y, double size}) title;
  final Map<String, ReelCard?> cards;
  final ({double w, double h}) slip;
  final Map<String, Pt> slips;
  final Map<String, ReelCluster> clusters;
  final Map<String, int> ambient;
  final ({double s, double dx, double dy}) askField;
  final ReelBox search;
  final ({double x, double w, List<double> ys}) results;
  final ReelBox? callout;
  final ReelLetterBox letter;
  final ReelBox? curve;
  final ReelBox inbox;
  final ReelBox? listen;
  final List<ReelAnn> anns;

  const ReelLayout({
    required this.name,
    required this.w,
    required this.h,
    required this.title,
    required this.cards,
    required this.slip,
    required this.slips,
    required this.clusters,
    required this.ambient,
    required this.askField,
    required this.search,
    required this.results,
    required this.callout,
    required this.letter,
    required this.curve,
    required this.inbox,
    required this.listen,
    required this.anns,
  });

  bool get tall => name == 'tall';
}

const reelWide = ReelLayout(
  name: 'wide',
  w: 1200,
  h: 600,
  title: (x: 64, y: 40, size: 46),
  cards: {
    'art': ReelCard(178, 352, 204, 176, -2.4),
    'pdf': ReelCard(404, 384, 204, 236, 1.8),
    'note': ReelCard(618, 258, 220, 156, -3),
    'book': ReelCard(636, 468, 218, 134, 2.4),
    'vid': ReelCard(842, 156, 256, 172, -2),
    'deck': ReelCard(868, 404, 236, 160, 2.8),
    'pod': ReelCard(1072, 226, 222, 124, 2.4),
    'memo': ReelCard(1074, 440, 206, 108, -2.2),
  },
  slip: (w: 236, h: 66),
  slips: {
    'p1': (834, 146),
    'p4': (1068, 206),
    'p3': (606, 252),
    'p2': (410, 344),
    'p5': (428, 424),
    'p6': (170, 326),
    'p10': (180, 406),
    'p9': (664, 474),
    'p8': (868, 392),
    'p7': (1070, 452),
  },
  clusters: {
    'wri': ReelCluster(212, 372, 72),
    'att': ReelCluster(480, 330, 116),
    'mnt': ReelCluster(800, 206, 84),
    'dec': ReelCluster(884, 446, 78),
    'ckg': ReelCluster(1084, 312, 60),
  },
  ambient: {'att': 22, 'mnt': 14, 'dec': 13, 'wri': 11, 'ckg': 9},
  askField: (s: 0.6, dx: 34, dy: 182),
  search: ReelBox(790, 92, 660, 58),
  results: (x: 962, w: 360, ys: [222, 340, 458]),
  callout: ReelBox(962, 548, 360),
  letter: ReelLetterBox(640, 316, 404, 532, 132, 92),
  curve: ReelBox(64, 316, 330, 222),
  inbox: ReelBox(1012, 196, 272),
  listen: ReelBox(1012, 302, 272),
  anns: [
    ReelAnn('vid', 'Transcribed · kept to the second', 0, -112),
    ReelAnn('note', 'Your handwriting, typed', -6, -104),
  ],
);

const reelTall = ReelLayout(
  name: 'tall',
  w: 420,
  h: 640,
  title: (x: 24, y: 22, size: 31),
  cards: {
    'vid': ReelCard(300, 150, 180, 126, -2),
    'pod': ReelCard(114, 198, 178, 106, 2.4),
    'note': ReelCard(302, 300, 178, 134, -3),
    'pdf': ReelCard(118, 354, 172, 192, 1.8),
    'art': ReelCard(302, 446, 178, 136, -2.2),
    'deck': ReelCard(118, 522, 178, 124, 2.6),
    'memo': ReelCard(300, 572, 178, 96, -2),
    'book': null,
  },
  slip: (w: 190, h: 66),
  slips: {
    'p1': (300, 140),
    'p4': (112, 200),
    'p3': (305, 272),
    'p2': (115, 318),
    'p5': (118, 390),
    'p6': (305, 412),
    'p10': (300, 484),
    'p8': (115, 522),
    'p7': (300, 562),
  },
  clusters: {
    'wri': ReelCluster(98, 228, 50),
    'att': ReelCluster(214, 338, 84),
    'mnt': ReelCluster(330, 206, 56),
    'dec': ReelCluster(320, 486, 56),
    'ckg': ReelCluster(104, 494, 44),
  },
  ambient: {'att': 15, 'mnt': 9, 'dec': 9, 'wri': 8, 'ckg': 6},
  askField: (s: 0.46, dx: 113, dy: 122),
  search: ReelBox(210, 130, 372, 48),
  results: (x: 210, w: 372, ys: [414, 504, 594]),
  callout: null,
  letter: ReelLetterBox(210, 336, 372, 424, 112, 74),
  curve: null,
  inbox: ReelBox(210, 598, 372),
  listen: null,
  anns: [],
);

const reelLayouts = [reelWide, reelTall];

ReelLayout layoutFor(double stageWidth) =>
    stageWidth >= 760 ? reelWide : reelTall;

/// How the world sits in a plate `width` wide: its scale, its left inset and
/// the plate's height. The tall stage stops growing at 1.15 and centres on
/// the desk, so a tablet is not handed a film a screen and a half high.
({double scale, double left, double height}) fitFor(
  ReelLayout l,
  double width,
) {
  final scale = l.tall ? math.min(width / l.w, 1.15) : width / l.w;
  return (
    scale: scale,
    left: math.max(0, (width - l.w * scale) / 2),
    height: l.h * scale,
  );
}

// ─── the field ───────────────────────────────────────────────────────────────
// Every point the index holds, placed once per layout: one per torn passage,
// and the rest of the library around them. Wires join each point to its
// nearest neighbours on the same shelf, plus a few faint bridges between
// shelves — meaning does not stop at a shelf's edge.

class ReelDot {
  final int i;
  final String shelf;
  final double x, y;
  final String? pid;
  final double ph, delay;

  /// The order this passage's slip flies in (-1 for the library around it).
  int gi = -1;

  /// One of §04's three answers.
  bool hit = false;

  ReelDot(this.i, this.shelf, this.x, this.y, this.pid, this.ph, this.delay);
}

class ReelWire {
  final int i, a, b;
  final bool bridge;
  final double delay;
  const ReelWire(this.i, this.a, this.b, this.bridge, this.delay);
}

class ReelField {
  final List<ReelDot> dots;
  final List<ReelWire> wires;
  final Map<String, ReelDot> dotOf;
  const ReelField(this.dots, this.wires, this.dotOf);
}

double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

ReelField buildField(ReelLayout l) {
  final rnd = prng(124);
  final dots = <ReelDot>[];
  final byShelf = <String, List<ReelDot>>{
    for (final s in reelShelves) s.id: [],
  };

  Pt place(String shelf, int i, int n, bool named) {
    final c = l.clusters[shelf]!;
    final ang = i * 2.39996 + rnd() * 0.6;
    final rr =
        c.rad *
        (named
            ? 0.22 + 0.42 * math.sqrt((i + 0.5) / n)
            : 0.3 + 0.68 * math.sqrt(rnd()));
    return (c.x + math.cos(ang) * rr * 1.12, c.y + math.sin(ang) * rr * 0.86);
  }

  for (final s in reelShelves) {
    final named = reelPassages.where((p) => p.shelf == s.id).toList();
    for (var i = 0; i < named.length; i++) {
      final (x, y) = place(s.id, i, named.length, true);
      final d = ReelDot(dots.length, s.id, x, y, named[i].id, rnd() * 6.28, 0);
      dots.add(d);
      byShelf[s.id]!.add(d);
    }
    final n = l.ambient[s.id]!;
    for (var i = 0; i < n; i++) {
      final (x, y) = place(s.id, i + named.length, n, false);
      final c = l.clusters[s.id]!;
      final far = _hypot(x - c.x, y - c.y) / c.rad;
      final ph = rnd() * 6.28;
      final d = ReelDot(
        dots.length,
        s.id,
        x,
        y,
        null,
        ph,
        far * 0.9 + rnd() * 0.5,
      );
      dots.add(d);
      byShelf[s.id]!.add(d);
    }
  }

  final wires = <ReelWire>[];
  final seen = <String>{};
  void join(ReelDot a, ReelDot b, bool bridge) {
    final key = a.i < b.i ? '${a.i}-${b.i}' : '${b.i}-${a.i}';
    if (!seen.add(key)) return;
    wires.add(ReelWire(wires.length, a.i, b.i, bridge, rnd() * 1.3));
  }

  for (final s in reelShelves) {
    final set = byShelf[s.id]!;
    for (final d in set) {
      // JS's sort is stable: equal distances keep the shelf's order.
      final near =
          [
            for (var j = 0; j < set.length; j++)
              if (!identical(set[j], d)) (j, set[j]),
          ]..sort((p, q) {
            final c = _hypot(
              p.$2.x - d.x,
              p.$2.y - d.y,
            ).compareTo(_hypot(q.$2.x - d.x, q.$2.y - d.y));
            return c != 0 ? c : p.$1.compareTo(q.$1);
          });
      final take = d.pid != null || rnd() < 0.35 ? 2 : 1;
      for (final (_, o) in near.take(take)) {
        join(d, o, false);
      }
    }
  }
  for (final (p, q) in const [
    ('att', 'mnt'),
    ('att', 'wri'),
    ('mnt', 'dec'),
    ('dec', 'ckg'),
    ('att', 'dec'),
  ]) {
    (ReelDot, ReelDot, double)? best;
    for (final a in byShelf[p]!) {
      for (final b in byShelf[q]!) {
        final dd = _hypot(a.x - b.x, a.y - b.y);
        if (best == null || dd < best.$3) best = (a, b, dd);
      }
    }
    if (best != null) join(best.$1, best.$2, true);
  }

  final flown = [
    for (final p in reelPassages)
      if (l.cards[p.src] != null) p.id,
  ];
  for (final d in dots) {
    d.gi = d.pid != null ? flown.indexOf(d.pid!) : -1;
    d.hit = reelHits.any((h) => h.pid == d.pid);
  }
  return ReelField(dots, wires, {
    for (final d in dots)
      if (d.pid != null) d.pid!: d,
  });
}

// ─── the beats ───────────────────────────────────────────────────────────────

abstract final class B {
  // 01 Gather
  static const cardsIn = 0.6, cardGap = 0.3, cardDur = 1.3, inkDur = 1.7;
  // 02 Read
  static const readAt = 6.95,
      readGap = 0.3,
      readDur = 1.05,
      annIn = 8.2,
      annOut = 10.35,
      tearAt = 10.55,
      tearGap = 0.07;
  // 03 Index
  static const flyAt = 12.55,
      flyGap = 0.075,
      flyDur = 1.4,
      libAt = 13.7,
      wireAt = 14.6,
      shelfAt = 15.1;
  // 04 Ask
  static const fieldMove = 19.05,
      barIn = 19.3,
      typeAt = 19.95,
      typeDur = 2.05,
      pulseAt = 22.15,
      pulseSpeed = 760.0,
      qWireAt = 22.95,
      resAt = 23.45,
      resGap = 0.2,
      hlAt = 24.55,
      coAt = 25.45;
  // 05 Return
  static const fieldOut = 26.85,
      letterIn = 27.3,
      foldAt = 28.45,
      foldGap = 0.24,
      sealAt = 30.35,
      curveAt = 30.55,
      inboxAt = 31.35,
      listenAt = 31.9,
      outAt = 34.7;
}

const _titleIn = [0.15, 6.5, 12.5, 19.0, 27.0];
const _titleOut = [5.95, 11.95, 18.55, 26.5, 34.55];

/// The order the cards land and are read in — not the array's order: the eye
/// is walked across the desk rather than down a list.
const reelArrive = ['vid', 'pdf', 'pod', 'note', 'art', 'deck', 'memo', 'book'];

// ─── a frame ─────────────────────────────────────────────────────────────────

/// One bar of an audio wave: its centre x and its two ends, as the
/// reference's path writes them (to 0.1).
typedef WaveBar = (double x, double top, double bottom);

/// One element's state at an instant. Which fields are set depends on how the
/// element is written: `at` sets x/y/s/sy/r/o, `dot` and `ring` x/y/rad/o,
/// `wire` a/b/c/draw/o, and a custom property lands in [vars].
class ReelPart {
  double? x, y, s, sy, r, o, rad, draw;
  Pt? a, b, c;
  String? text;
  List<WaveBar>? bars;
  Map<String, double>? vars;

  double v(String name, [double fallback = 0]) => vars?[name] ?? fallback;

  /// The opacity the reference's writer would set: anything at or under
  /// 0.002 is hidden, and an element never written is hidden.
  double get shown {
    final op = o ?? 0;
    return op <= 0.002 ? 0 : _f(op);
  }

  /// Whether a frame drawn from [other] would look the same — the
  /// reference's writer, which skips a value that has not changed at the
  /// precision it writes (0.01 px and opacity, 0.001 scale).
  bool same(ReelPart? other) {
    if (other == null) return false;
    if (shown != other.shown) return false;
    if (shown == 0) return true;
    bool eq(double? p, double? q, [double k = 100]) =>
        (p == null && q == null) ||
        (p != null && q != null && (p * k).round() == (q * k).round());
    bool pt(Pt? p, Pt? q) =>
        (p == null && q == null) ||
        (p != null && q != null && eq(p.$1, q.$1) && eq(p.$2, q.$2));
    if (!eq(x, other.x) || !eq(y, other.y) || !eq(r, other.r)) return false;
    if (!eq(s, other.s, 1000) || !eq(sy, other.sy, 1000)) return false;
    if (!eq(rad, other.rad) || !eq(draw, other.draw)) return false;
    if (!pt(a, other.a) || !pt(b, other.b) || !pt(c, other.c)) return false;
    if (text != other.text) return false;
    if (!_mapEq(vars, other.vars) || !_barsEq(bars, other.bars)) return false;
    return true;
  }

  static bool _mapEq(Map<String, double>? p, Map<String, double>? q) {
    if (p == null || q == null) return p == q;
    if (p.length != q.length) return false;
    for (final e in p.entries) {
      if (q[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _barsEq(List<WaveBar>? p, List<WaveBar>? q) {
    if (p == null || q == null) return p == q;
    if (p.length != q.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (p[i] != q[i]) return false;
    }
    return true;
  }
}

double _f(double n) => (n * 100).round() / 100;

/// `Number(v.toFixed(n))` — how the reference rounds a custom property.
double _fx(double v, int n) => double.parse(v.toStringAsFixed(n));

/// Every element's state at one instant, by the reference's keys
/// (`C:vid`, `S:p2`, `D:5`, `LT:s3` …).
class ReelFrame {
  final double t;
  final Map<String, ReelPart> parts = {};
  ReelFrame(this.t);

  ReelPart? operator [](String k) => parts[k];
  ReelPart _p(String k) => parts.putIfAbsent(k, ReelPart.new);

  /// Centre-anchored place, scale, turn and opacity; `sy` scales the height
  /// apart from the width.
  void at(
    String k,
    double x,
    double y, [
    double s = 1,
    double r = 0,
    double o = 1,
    double? sy,
  ]) {
    _p(k)
      ..x = x
      ..y = y
      ..s = s
      ..sy = sy ?? s
      ..r = r
      ..o = o;
  }

  /// A plain offset, for the words of a title inside their line masks.
  void tl(String k, double x, double y, [double o = 1]) {
    _p(k)
      ..x = x
      ..y = y
      ..o = o;
  }

  /// Scale and turn in place — for parts the sheet itself positions.
  void sr(String k, double s, double r, double o) {
    _p(k)
      ..s = s
      ..r = r
      ..o = o;
  }

  void op(String k, double o) => _p(k).o = o;

  void v(String k, String name, double val, int digits) =>
      (_p(k).vars ??= {})[name] = _fx(val, digits);

  void x(String k, String text) => _p(k).text = text;

  void bars(String k, List<WaveBar> bars) => _p(k).bars = bars;

  void dot(String k, double x, double y, double rad, double o) {
    _p(k)
      ..x = x
      ..y = y
      ..rad = rad
      ..o = o;
  }

  void ring(String k, double x, double y, double rad, double o) =>
      dot(k, x, y, rad, o);

  /// A line a → b, or a curve through control `c`, drawn on to `draw`.
  void wire(String k, Pt a, Pt b, double draw, double o, [Pt? c]) {
    _p(k)
      ..a = a
      ..b = b
      ..c = c
      ..draw = draw
      ..o = o;
  }
}

// ─── paint ───────────────────────────────────────────────────────────────────

ReelFrame paintReel(double t, ReelLayout l, ReelField field, ReelEase e) {
  final w = ReelFrame(t);
  double k(double a, double d, [Ease? ease]) =>
      (ease ?? e.quill)(seg(t, a, a + d));
  bool live(double a, double b) => t >= a && t < b;

  _paintTitles(t, l, e, w);
  final cardsShown = [
    for (final id in reelArrive)
      if (l.cards[id] != null) id,
  ];

  // 01 · 02 — the cards: land, are read, tear
  for (var n = 0; n < cardsShown.length; n++) {
    final id = cardsShown[n];
    final c = l.cards[id]!;
    final at = B.cardsIn + n * B.cardGap;
    final p = k(at, B.cardDur);
    final ang = math.atan2(c.y - l.h / 2, c.x - l.w / 2);
    final far = l.w * 0.42;
    final sx = math.cos(ang) * far, sy = math.sin(ang) * far + 70;
    final spin = (n.isOdd ? 1 : -1) * 14;
    final tear = k(B.tearAt + n * B.tearGap, 0.55, e.inOut);
    final x = c.x + sx * (1 - p) + drift(t, n * 1.7, 2.2, 0.55);
    final y = c.y + sy * (1 - p) + drift(t, n * 2.3, 2.6, 0.47);
    final r = c.r + spin * (1 - p) + drift(t, n.toDouble(), 0.35, 0.4);
    final o = clamp01(p * 2.4) * (1 - tear);
    w.at('C:$id', x, y, lerp(0.9, 1, p) * lerp(1, 0.94, tear), r, o);
    if (o > 0) {
      w.v('C:$id', '--pl-lift', 1 - p, 3);
      final rd = k(B.readAt + n * B.readGap, B.readDur, e.inOut);
      w.v('C:$id', '--pl-p', rd, 4);
      w.v('C:$id', '--pl-scan', rd > 0 && rd < 1 ? 1 : 0, 0);
      _paintMedia(t, id, c, at, w, e);
    }
  }

  // 02 — the two notes in the margin
  for (var i = 0; i < l.anns.length; i++) {
    final a = l.anns[i];
    final c = l.cards[a.src]!;
    final o =
        k(B.annIn + i * 0.45, 0.6) * (1 - k(B.annOut + i * 0.1, 0.4, e.inOut));
    w.at('A:$i', c.x + a.dx, c.y + a.dy + (1 - o) * 8, 1, 0, o);
    w.v('A:$i', '--pl-rule', o, 3);
  }

  // 02 → 03 — slips tear out, are laid out, then fly into the field and
  // become the points they will be: each one closes into a bead of its
  // shelf's colour on the way.
  final f0 = fieldTf(t, l, e);
  final fieldOut = 1 - k(B.fieldOut, 0.8, e.out);
  for (final pz in reelPassages) {
    final c = l.cards[pz.src];
    final dot = field.dotOf[pz.id]!;
    if (c == null) {
      w.op('S:${pz.id}', 0);
      continue;
    }
    final n = cardsShown.indexOf(pz.src);
    final sib = reelPassages.where((q) => q.src == pz.src).toList().indexOf(pz);
    final born = B.tearAt + n * B.tearGap + sib * 0.09;
    final p0 = k(born, 0.85);
    final rest = l.slips[pz.id]!;
    final fly = B.flyAt + dot.gi * B.flyGap;
    final f = k(fly, B.flyDur, e.inOut);
    final target = applyTf(f0, (dot.x, dot.y));
    final from = (
      lerp(c.x, rest.$1, p0) + drift(t, dot.gi.toDouble(), 2.4, 0.8),
      lerp(c.y, rest.$2, p0) + drift(t, dot.gi * 1.3, 2, 0.7),
    );
    final (x, y) = f > 0
        ? arc(from, target, dot.gi.isOdd ? 0.22 : -0.22, f)
        : from;
    final shrink = e.inOut(seg(f, 0.02, 0.66));
    final s0 = lerp(0.9, 1, p0);
    final bead = 10 * f0.s;
    final o = clamp01(p0 * 3) * (1 - seg(f, 0.86, 1));
    w.at(
      'S:${pz.id}',
      x,
      y,
      lerp(s0, bead / l.slip.w, shrink),
      lerp(sib != 0 ? 1.6 : -1.2, 0, f),
      o,
      lerp(s0, bead / l.slip.h, shrink),
    );
    if (o > 0) w.v('S:${pz.id}', '--pl-bead', seg(f, 0.2, 0.6), 3);
  }

  // 03 · 04 — the field
  final qo = (l.search.x, l.search.y + l.search.h / 2);
  Pt drifted(ReelDot d) => applyTf(f0, (
    d.x + drift(t, d.ph, 2.6, 0.42),
    d.y + drift(t, d.ph * 1.7, 2.4, 0.37),
  ));
  double judgedAt(Pt p) => k(
    B.pulseAt + _hypot(p.$1 - qo.$1, p.$2 - qo.$2) / B.pulseSpeed,
    0.35,
    e.out,
  );

  for (final d in field.dots) {
    final landed = d.gi >= 0
        ? k(B.flyAt + d.gi * B.flyGap + B.flyDur * 0.86, 0.32, e.out)
        : k(B.libAt + d.delay, 0.45, e.out);
    final pos = drifted(d);
    final judged = judgedAt(pos);
    final keep = d.shelf == 'att' ? (d.pid != null ? 1.0 : 0.8) : 0.14;
    final rest = d.pid != null ? 1.0 : 0.62;
    final o = landed * lerp(rest, keep, judged) * fieldOut;
    final r =
        (d.pid != null ? 4.6 : 3) *
        f0.s *
        landed *
        (d.hit ? lerp(1, 1.45, judged) : 1);
    w.dot('D:${d.i}', pos.$1, pos.$2, math.max(0, r), o);
  }

  for (final wr in field.wires) {
    final a = field.dots[wr.a], b = field.dots[wr.b];
    final draw = k(B.wireAt + wr.delay, 0.9, e.inOut);
    final pa = drifted(a), pb = drifted(b);
    final judged = judgedAt(((pa.$1 + pb.$1) / 2, (pa.$2 + pb.$2) / 2));
    final keep = !wr.bridge && a.shelf == 'att' ? 0.9 : 0.12;
    final o = (draw > 0 ? 1 : 0) * lerp(1, keep, judged) * fieldOut;
    w.wire('W:${wr.i}', pa, pb, draw, o);
  }

  for (var i = 0; i < reelShelves.length; i++) {
    final s = reelShelves[i];
    final c = l.clusters[s.id]!;
    final (x, y) = applyTf(f0, (c.x, c.y));
    final p = k(B.shelfAt + i * 0.16, 0.9);
    final judged = judgedAt((x, y));
    final keep = s.id == 'att' ? 1.0 : 0.28;
    final o = p * lerp(1, keep, judged) * fieldOut;
    w.ring('R:${s.id}', x, y, c.rad * f0.s * lerp(0.7, 1.08, p), o * 0.9);
    final ly = y - c.rad * f0.s * 1.08 - 12 + (1 - p) * 8;
    w.at('L:${s.id}', x, ly, lerp(1, 0.86, seg(f0.s, 1, l.askField.s)), 0, o);
  }

  // 04 — the question
  final barIn = k(B.barIn, 0.7);
  final barOut = k(B.fieldOut, 0.6, e.inOut);
  w.at(
    'Q',
    l.search.x,
    l.search.y - 26 * (1 - barIn) - 30 * barOut,
    1,
    0,
    barIn * (1 - barOut),
  );
  if (live(B.barIn, B.fieldOut + 0.7)) {
    final typed = (k(B.typeAt, B.typeDur, e.lin) * reelQuery.length).round();
    w.x('Q:txt', reelQuery.substring(0, typed));
    final typing = t >= B.typeAt && typed < reelQuery.length;
    w.op('Q:caret', typing || (t * 1.9).floor() % 2 == 0 ? 1 : 0);
    w.op('Q:n', k(B.qWireAt + 0.5, 0.5, e.out));
  }

  for (var i = 0; i < 3; i++) {
    final p = k(B.pulseAt + i * 0.2, 1.5, e.out);
    w.ring(
      'P:$i',
      qo.$1,
      qo.$2,
      p * l.w * 0.95,
      (p > 0 && p < 1 ? (1 - p) * 0.55 : 0) * fieldOut,
    );
  }

  for (var i = 0; i < reelHits.length; i++) {
    final h = reelHits[i];
    final (x, y) = drifted(field.dotOf[h.pid]!);
    final dist = _hypot(x - qo.$1, y - qo.$2);
    final lit = k(B.pulseAt + dist / B.pulseSpeed + 0.1, 0.45);
    w.ring(
      'H:$i',
      x,
      y,
      lerp(5, 12, lit) + math.sin(t * 3 + i) * 0.8,
      lit * fieldOut,
    );
    final draw = k(B.qWireAt + i * 0.16, 0.8, e.inOut);
    final a = (l.search.x - l.search.w / 2 + 56 + i * 26, qo.$2);
    w.wire('QW:$i', a, (x, y), draw, draw > 0 ? fieldOut * 0.9 : 0, (a.$1, y));

    // the answer: out of its point, into the column, then into the letter
    final slot = (l.results.x, l.results.ys[i]);
    final ep = k(B.resAt + i * B.resGap, 1.05);
    final fold = k(B.foldAt + i * B.foldGap, 0.95, e.inOut);
    final sec = sectionPos(l, i);
    var pos = arc((x, y), slot, i.isOdd ? -0.16 : 0.16, ep);
    if (fold > 0) pos = arc(slot, sec, -0.12, fold);
    final sw = (l.letter.w - 48) / l.results.w;
    final s = lerp(0.08, 1, ep) * lerp(1, sw, fold);
    final o = clamp01(ep * 3) * (1 - seg(fold, 0.78, 1));
    w.at('X:$i', pos.$1, pos.$2, s, lerp(i.isOdd ? 3 : -3, 0, ep), o);
    if (o > 0) w.v('X:$i', '--pl-hl', k(B.hlAt + i * 0.28, 0.75, e.inOut), 3);
  }

  final co = l.callout;
  if (co != null) {
    final o = k(B.coAt, 0.6) * (1 - k(B.fieldOut, 0.4, e.inOut));
    w.at('CO', co.x, co.y + (1 - o) * 6, 1, 0, o);
    w.v('CO', '--pl-rule', o, 3);
  }

  // 05 — the letter
  final lin = k(B.letterIn, 1.15);
  final out = k(B.outAt, 1.0, e.inOut);
  final thump =
      math.sin(math.pi * seg(t, B.sealAt + 0.2, B.sealAt + 0.42)) * 2.2;
  final lo = clamp01(lin * 2) * (1 - out);
  w.at(
    'LT',
    l.letter.x,
    l.letter.y + 36 * (1 - lin) + thump - 10 * out,
    lerp(0.965, 1, lin) * lerp(1, 0.985, out),
    lerp(1.4, 0, lin),
    lo,
  );
  if (lo > 0) {
    w.op('LT:strap', k(B.letterIn + 0.55, 0.6, e.out));
    w.v('LT:rule', '--pl-draw', k(B.letterIn + 0.6, 0.8, e.inOut), 3);
    w.op('LT:kick', k(B.letterIn + 0.85, 0.5, e.out));
    w.v('LT:title', '--pl-wipe', k(B.letterIn + 0.95, 0.9, e.inOut), 3);
    for (var i = 0; i < reelSections.length; i++) {
      final arrive = i < 3
          ? k(B.foldAt + i * B.foldGap + 0.72, 0.3, e.out)
          : k(B.foldAt + 0.95, 0.75);
      final dx = i < 3 ? 0.0 : -28 * (1 - arrive);
      w.at(
        'LT:s$i',
        l.letter.w / 2 + dx,
        l.letter.head + l.letter.row * (i + 0.5),
        1,
        0,
        arrive,
      );
      if (reelSections[i].back != null) {
        w.op('LT:b$i', k(B.sealAt - 0.35 + i * 0.12, 0.5, e.out));
      }
    }
    final press = k(B.sealAt, 0.36);
    w.sr(
      'LT:seal',
      lerp(2.4, 1, press),
      lerp(-24, -8, press),
      clamp01(press * 1.6),
    );
    final ring = seg(t, B.sealAt + 0.25, B.sealAt + 1.05);
    w.sr(
      'LT:ring',
      lerp(1, 2.6, e.out(ring)),
      0,
      ring > 0 && ring < 1 ? (1 - ring) * 0.7 : 0,
    );
  }

  final cv = l.curve;
  if (cv != null) {
    final p = k(B.curveAt, 0.8);
    final o = p * (1 - out);
    w.at('CV', cv.x + cv.w / 2, cv.y + cv.h / 2 + (1 - p) * 14, 1, 0, o);
    if (o > 0) {
      w.v('CV:off', '--pl-draw', k(B.curveAt + 0.3, 1.0, e.inOut), 3);
      w.v('CV:on', '--pl-draw', k(B.curveAt + 0.75, 1.6, e.inOut), 3);
      for (var i = 0; i < reelCurveMarks.length; i++) {
        final fx = reelCurveMarks[i].$1;
        w.op('CV:m$i', k(B.curveAt + 0.75 + fx * 1.6 * 0.92, 0.3, e.out));
      }
    }
  }

  final ib = k(B.inboxAt, 0.85);
  w.at('IN', l.inbox.x + 34 * (1 - ib), l.inbox.y, 1, 0, ib * (1 - out));
  final ls = l.listen;
  if (ls != null) {
    final lp = k(B.listenAt, 0.85);
    final o = lp * (1 - out);
    w.at('LS', ls.x + 34 * (1 - lp), ls.y, 1, 0, o);
    if (o > 0) w.bars('LS:bars', waveBars(t * 1.4, 16, 64, 22));
  }
  return w;
}

// ─── parts of paint ──────────────────────────────────────────────────────────

void _paintTitles(double t, ReelLayout l, ReelEase e, ReelFrame w) {
  for (var i = 0; i < reelTitles.length; i++) {
    final tin = _titleIn[i], tout = _titleOut[i];
    final on = t >= tin - 0.05 && t < tout + 0.9;
    w.op('T$i', on ? 1 : 0);
    if (!on) continue;
    var n = 0;
    final lh = l.title.size * 1.12;
    final lines = reelTitles[i];
    for (var li = 0; li < lines.length; li++) {
      for (var wi = 0; wi < lines[li].length; wi++) {
        final pin = e.quill(seg(t, tin + n * 0.075, tin + n * 0.075 + 0.95));
        final pout = e.inOut(seg(t, tout + n * 0.04, tout + n * 0.04 + 0.55));
        w.tl('T$i:$li:$wi', 0, lh * (1 - pin) - lh * 0.9 * pout, 1);
        n += 1;
      }
    }
    final eb =
        e.out(seg(t, tin, tin + 0.6)) * (1 - e.inOut(seg(t, tout, tout + 0.5)));
    w.op('T$i:eb', eb);
    w.v('T$i:eb', '--pl-rule', eb, 3);
  }
}

void _paintMedia(
  double t,
  String id,
  ReelCard c,
  double at,
  ReelFrame w,
  ReelEase e,
) {
  final local = t - at;
  switch (id) {
    case 'pod':
      final play = 0.31 + local * 0.006;
      w.bars(
        'C:pod:ahead',
        waveBars(t * 1.2, 34, c.w - 32, 38, play, WavePart.unheard),
      );
      w.bars(
        'C:pod:heard',
        waveBars(t * 1.2, 34, c.w - 32, 38, play, WavePart.heard),
      );
    case 'memo':
      w.bars('C:memo:bars', waveBars(t * 1.9 + 3, 22, c.w - 92, 30, 1));
    case 'vid':
      w.v('C:vid', '--pl-play', clamp01(0.62 + local * 0.006, 0, 1), 4);
    case 'note':
      w.v('C:note', '--pl-ink', e.inOut(seg(local, 0.25, 0.25 + B.inkDur)), 4);
  }
}

enum WavePart { all, heard, unheard }

/// A row of audio bars. `part` keeps the bars left of `upto` (0..1, the part
/// already heard — drawn in the accent), the rest, or all.
List<WaveBar> waveBars(
  double phase,
  int n,
  double width,
  double height, [
  double upto = 1,
  WavePart part = WavePart.all,
]) {
  final gap = width / n;
  final mid = height / 2;
  final out = <WaveBar>[];
  for (var i = 0; i < n; i++) {
    final heard = i / n < upto;
    if ((part == WavePart.heard && !heard) ||
        (part == WavePart.unheard && heard)) {
      continue;
    }
    final env =
        0.35 +
        0.65 *
            (math.sin(i * 0.61 + phase * 0.9) *
                    math.sin(i * 0.23 + phase * 0.37 + 1.3))
                .abs();
    final h = math.max(2.0, env * height);
    final x = (i + 0.5) * gap;
    out.add((_fx(x, 1), _fx(mid - h / 2, 1), _fx(mid + h / 2, 1)));
  }
  return out;
}

/// The field's camera: a slow push-in while the shelves form (03), then a
/// move down and left to give the answers the right of the stage (04).
({double s, double dx, double dy}) fieldTf(double t, ReelLayout l, ReelEase e) {
  final cam = e.inOut(seg(t, B.flyAt, B.fieldMove));
  final s0 = lerp(1, 1.035, cam);
  final bdx = (l.w / 2) * (1 - s0), bdy = (l.h / 2) * (1 - s0);
  final m = e.inOut(seg(t, B.fieldMove, B.fieldMove + 1.35));
  final a = l.askField;
  return (s: lerp(s0, a.s, m), dx: lerp(bdx, a.dx, m), dy: lerp(bdy, a.dy, m));
}

Pt applyTf(({double s, double dx, double dy}) f, Pt p) =>
    (p.$1 * f.s + f.dx, p.$2 * f.s + f.dy);

/// Where §0{i} of the letter sits on the stage.
Pt sectionPos(ReelLayout l, int i) {
  final top = l.letter.y - l.letter.h / 2;
  return (l.letter.x, top + l.letter.head + l.letter.row * (i + 0.5));
}

// ─── handwriting ─────────────────────────────────────────────────────────────
// A word of joined loops — a prolate cycloid, slanted, with the odd ascender.
// Not a typeface: the brand sets three faces and handwriting is none of them,
// so the hand is drawn. Web `Reel.jsx` `inkWord`/`inkLines`, seeded alike.

({List<Pt> points, double w}) inkWord(
  double x0,
  double y0,
  int loops,
  int seed,
  double h,
) {
  final r = prng(seed);
  const a = 2.05;
  final pts = <Pt>[];
  for (var l = 0; l < loops; l++) {
    final c = h * (r() < 0.22 ? 1.95 : 0.72 + r() * 0.5);
    final b = r() < 0.55 ? 3.05 : 1.35;
    for (var s = l == 0 ? 0 : 1; s <= 12; s++) {
      final u = (l + s / 12) * math.pi * 2;
      final y = y0 - (c * (1 - math.cos(u))) / 2;
      final x = x0 + a * u - b * math.sin(u) + (y0 - y) * 0.32;
      pts.add((_fx(x, 1), _fx(y, 1)));
    }
  }
  return (points: pts, w: a * loops * math.pi * 2);
}

/// The words of a handwritten page `width` wide, on the given baselines.
List<List<Pt>> inkLines(double width, List<double> rows, int seed) {
  final r = prng(seed);
  final words = <List<Pt>>[];
  for (var ri = 0; ri < rows.length; ri++) {
    var x = 4.0 + (ri == 0 ? 0.0 : r() * 6);
    while (true) {
      final loops = 2 + (r() * 4).floor();
      if (x + loops * 13 > width - 4) break;
      final wd = inkWord(x, rows[ri], loops, (r() * 1e6).floor(), 6.5);
      words.add(wd.points);
      x += wd.w + 7 + r() * 5;
    }
  }
  return words;
}
