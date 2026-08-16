/// The dwell rule (contract 3.1.0, ADR-039 §3).
///
/// Pinned because the rule can be wrong in only one direction that matters: a
/// threshold too low marks a long passage read on a fast scroll past it, which
/// is the failure the proportional rule exists to prevent. A fixed 2s dwell was
/// rejected for exactly that — a signal confidently wrong about the case it
/// exists for is worse than no signal.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/pages/reader/dwell.dart';

void main() {
  test('220 wpm is the shared constant, not a local opinion', () {
    // ADR-020 §4 made it normative for the reading-time row; a client must not
    // carry two opinions about how fast people read.
    expect(readingWpm, 220);
  });

  test('half the estimated reading time', () {
    // 220 words ~ 1 minute to read, so half is ~30s -- but the cap applies.
    expect(dwellFor(220).inSeconds, dwellCapSeconds);
    // 150 words -> 0.5 * 150/220 * 60 ~ 20.4s, also capped.
    expect(dwellFor(150).inSeconds, dwellCapSeconds);
    // 100 words -> 0.5 * 100/220 * 60 ~ 13.6s, under the cap.
    expect(dwellFor(100).inSeconds, 13);
  });

  test('a short passage is quick but never instant', () {
    expect(dwellFor(20).inMilliseconds, greaterThan(0));
    expect(dwellFor(20).inSeconds, lessThan(dwellCapSeconds));
  });

  test('a very long passage stays reachable — the cap holds', () {
    // Without the cap a 2,000-word chunk would need over four minutes of
    // continuous visibility and would effectively never be markable.
    expect(dwellFor(2000).inSeconds, dwellCapSeconds);
    expect(dwellFor(100000).inSeconds, dwellCapSeconds);
  });

  test('an empty passage asks for no dwell at all', () {
    expect(dwellFor(0), Duration.zero);
    expect(wordsIn('   '), 0);
  });

  test('word counting is whitespace-collapsing', () {
    expect(wordsIn('one two   three\nfour'), 4);
  });
}
