import 'package:flutter/animation.dart';

/// Motion tokens (`spec/design-tokens.md` §motion; source `theme.css`
/// `--ease-*` / `--dur-*`).
///
/// The curves are [Cubic]s, so a widget can hand one straight to an
/// `AnimatedFoo`; their control points ([Cubic.a]…[Cubic.d]) are also what
/// the landing's film reads and solves itself (`site/reel_motion.dart`), the
/// way web's `motionFrom()` reads the custom properties — so the film moves
/// the way the app moves and a token change moves both.
///
/// `--ease-in-out` is in `theme.css` (and ADR-178 names it) but not in
/// design-tokens.md's one-line motion summary; its value here is theme.css's.
class AppMotion {
  AppMotion._();

  /// `--ease-out` — what most of the app's transitions settle on.
  static const Cubic easeOut = Cubic(0.22, 0.61, 0.36, 1);

  /// `--ease-quill` — the long, quick-then-slow stroke of a pen.
  static const Cubic easeQuill = Cubic(0.16, 1, 0.3, 1);

  /// `--ease-in-out` — symmetric, for a thing that moves between two rests.
  static const Cubic easeInOut = Cubic(0.65, 0, 0.35, 1);

  /// `--dur-fast` · `--dur-base` · `--dur-slow`.
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durBase = Duration(milliseconds: 200);
  static const Duration durSlow = Duration(milliseconds: 360);
}
