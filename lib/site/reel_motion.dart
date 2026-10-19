// The reel's arithmetic — web `pages/landing/reelMotion.js`, ported line for
// line. The film (ADR-178) is a pure function of one number, `t`: every
// element's place, scale, turn and opacity is computed from it, never
// accumulated from the frame before. That is what makes it scrubbable,
// pausable, loopable without drift, and photographable at an exact instant.
//
// The curves are the TOKENS' own: [ReelEase.tokens] reads `AppMotion`'s
// control points and solves them with WebKit's UnitBezier, as web's
// `motionFrom()` solves the custom properties. Flutter's own `Cubic.transform`
// is a bisection to 0.001; a port that used it would disagree with the
// reference in the third decimal, so the reference's solver is ported too.
import 'dart:math' as math;

import 'package:flutter/animation.dart' show Cubic;

import '../theme/app_motion.dart';

double clamp01(double v, [double lo = 0, double hi = 1]) =>
    v < lo ? lo : (v > hi ? hi : v);

double lerp(double a, double b, double p) => a + (b - a) * p;

/// Progress through [a, b], clamped to 0..1.
double seg(double t, double a, double b) => clamp01((t - a) / (b - a));

typedef Ease = double Function(double p);

/// A CSS `cubic-bezier(x1, y1, x2, y2)` as a function of progress — WebKit's
/// UnitBezier: Newton's method, with bisection when the slope is flat.
Ease bezier(double x1, double y1, double x2, double y2) {
  final cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  final cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  double sx(double u) => ((ax * u + bx) * u + cx) * u;
  double sy(double u) => ((ay * u + by) * u + cy) * u;
  double dx(double u) => (3 * ax * u + 2 * bx) * u + cx;
  double solve(double x) {
    var u = x;
    for (var i = 0; i < 8; i++) {
      final e = sx(u) - x;
      if (e.abs() < 1e-6) return u;
      final d = dx(u);
      if (d.abs() < 1e-6) break;
      u -= e / d;
    }
    var lo = 0.0, hi = 1.0;
    u = x;
    for (var i = 0; i < 40 && hi - lo > 1e-7; i++) {
      if (sx(u) < x) {
        lo = u;
      } else {
        hi = u;
      }
      u = (lo + hi) / 2;
    }
    return u;
  }

  return (p) => p <= 0 ? 0 : (p >= 1 ? 1 : sy(solve(p)));
}

/// A motion token, solved.
Ease solveToken(Cubic c) => bezier(c.a, c.b, c.c, c.d);

/// The four curves a beat is written in: linear and the three tokens.
class ReelEase {
  final Ease lin;
  final Ease out;
  final Ease quill;
  final Ease inOut;
  const ReelEase({
    required this.lin,
    required this.out,
    required this.quill,
    required this.inOut,
  });

  static double _lin(double p) => p;

  /// `--ease-out`, `--ease-quill`, `--ease-in-out` from `AppMotion`.
  static final ReelEase tokens = ReelEase(
    lin: _lin,
    out: solveToken(AppMotion.easeOut),
    quill: solveToken(AppMotion.easeQuill),
    inOut: solveToken(AppMotion.easeInOut),
  );
}

/// A point on the quadratic bézier p0 → c → p1.
(double, double) quad(
  (double, double) p0,
  (double, double) c,
  (double, double) p1,
  double u,
) {
  final v = 1 - u;
  return (
    v * v * p0.$1 + 2 * v * u * c.$1 + u * u * p1.$1,
    v * v * p0.$2 + 2 * v * u * c.$2 + u * u * p1.$2,
  );
}

/// A flight from a to b that bows `bend` × its length to one side — the
/// control point sits off the chord's midpoint, so nothing travels in a ruler
/// line.
(double, double) arc(
  (double, double) a,
  (double, double) b,
  double bend,
  double u,
) {
  final mx = (a.$1 + b.$1) / 2, my = (a.$2 + b.$2) / 2;
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  return quad(a, (mx - dy * bend, my + dx * bend), b, u);
}

const int _m32 = 0xFFFFFFFF;

/// JS `Math.imul` on two uint32 bit patterns, as a uint32 bit pattern. Split
/// into 16-bit halves so no intermediate passes 2^53 — exact on the VM and
/// on a web build, where an `int` is a double.
int imul32(int a, int b) {
  a &= _m32;
  b &= _m32;
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return (al * bl + ((((ah * bl + al * bh) & 0xFFFF) << 16) & _m32)) & _m32;
}

/// Deterministic noise — mulberry32, bit for bit the reference's `prng`, so
/// the same library scatters the same way on every client. Every value is
/// kept as its uint32 bit pattern: JS's `>>> 0`, `^`, `|` and `Math.imul`
/// all reduce mod 2^32, and so does this.
double Function() prng(int seed) {
  var s = seed & _m32;
  return () {
    s = (s + 0x6d2b79f5) & _m32;
    var r = imul32(s ^ (s >> 15), 1 | s);
    r = ((r + imul32(r ^ (r >> 7), 61 | r)) & _m32) ^ r;
    return ((r ^ (r >> 14)) & _m32) / 4294967296;
  };
}

/// A slow wander, so nothing at rest is ever quite still.
double drift(double t, double phase, double amp, [double speed = 0.5]) =>
    math.sin(t * speed + phase) * amp;
