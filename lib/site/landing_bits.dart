// Pure pieces of the landing (F-68 / F-44b), kept apart from the widgets so a
// test can assert them without a frame: the computed dateline, the retyping
// pairs, and the small SVG path reader that draws Fig. 1 from the reference's
// own path strings rather than from a hand-traced copy of them.
import 'dart:ui' show Offset, Path;

const _roman = <(int, String)>[(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];

/// `roman(n)` in LandingActual.jsx — `I` for anything below one.
String roman(int n) {
  final out = StringBuffer();
  for (final (v, s) in _roman) {
    while (n >= v) {
      out.write(s);
      n -= v;
    }
  }
  return out.isEmpty ? 'I' : out.toString();
}

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// The masthead's dateline — computed, never invented, so it can never
/// disagree with the calendar the way a hardcoded "Vol. III · No. 124" does.
/// Vol. counts years since the press was founded (2026 is Vol. I); No. is the
/// day of the year.
class Dateline {
  final String vol;
  final String no;
  final String day;
  final String date;
  const Dateline(this.vol, this.no, this.day, this.date);

  String get stamp => '$vol · $no';

  factory Dateline.of(DateTime d) {
    final dayOfYear =
        DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(d.year, 1, 1)).inDays + 1;
    return Dateline(
      'Vol. ${roman(d.year - 2026 + 1)}',
      'No. $dayOfYear',
      _weekdays[d.weekday - 1],
      '${_months[d.month - 1]} ${d.day}, ${d.year}',
    );
  }
}

/// The two words that retype: the noun is the thing saved, the verb is how
/// it reached the reader. The reference's pairs, in its order.
const rotPairs = <(String, String)>[
  ('notes', 'read'), ('podcasts', 'heard'), ('articles', 'read'),
  ('lectures', 'watched'), ('papers', 'read'), ('presentations', 'seen'),
  ('videos', 'watched'), ('saved posts', 'seen'),
];

/// A reader for the absolute `M`/`L`/`C`/`S` subset the reference's Fig. 1
/// paths are written in. Anything else is a thrown error, not a silently
/// dropped segment: a curve that loses a command still draws, wrongly.
Path svgPath(String d) {
  final tokens = RegExp(r'[MLCS]|-?\d*\.?\d+')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final leftovers = d.replaceAll(RegExp(r'[MLCS]|-?\d*\.?\d+|[\s,]'), '');
  if (leftovers.isNotEmpty) {
    throw FormatException('svgPath reads M/L/C/S only; found "$leftovers"');
  }
  final path = Path();
  var i = 0;
  String? cmd;
  var cur = Offset.zero;
  Offset? lastCtrl;
  double n() => double.parse(tokens[i++]);
  Offset p() {
    final x = n();
    return Offset(x, n());
  }

  while (i < tokens.length) {
    if (RegExp(r'^[MLCS]$').hasMatch(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        cur = p();
        path.moveTo(cur.dx, cur.dy);
        lastCtrl = null;
        cmd = 'L'; // implicit repeats of M are line-tos
      case 'L':
        cur = p();
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'C':
        final c1 = p(), c2 = p(), e = p();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        cur = e;
      case 'S':
        final c1 = lastCtrl == null ? cur : cur * 2 - lastCtrl;
        final c2 = p(), e = p();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        cur = e;
      default:
        throw FormatException('svgPath: no command before "${tokens[i]}"');
    }
  }
  return path;
}

/// Fig. 1's two curves and its marks — the reference's strings, verbatim.
const curveDecay = 'M60 40 C 120 130, 180 190, 260 212 S 560 236, 900 240';
const curveLifted = 'M60 40 C 110 120, 160 168, 200 180 '
    'C 200 90, 250 80, 260 74 C 300 130, 320 158, 340 168 '
    'C 340 76, 400 62, 420 58 C 470 108, 500 130, 520 140 '
    'C 520 60, 600 46, 620 44 C 660 84, 690 100, 700 106 '
    'C 700 48, 800 38, 900 40';
const curveMarks = <(double, String)>[
  (60, 'You read it'), (200, 'Day 3'), (340, 'Day 10'), (520, 'A month'),
  (700, 'Three months'), (900, 'A year'),
];
