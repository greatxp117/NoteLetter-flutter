/// The dwell rule (contract 3.1.0, ADR-039 §3) — when a passage counts as read.
///
/// Extracted as pure arithmetic so it can be asserted directly; the widget that
/// watches visibility cannot be.
library;

/// Words per minute. **Normative** (ADR-020 §4) and shared with the reader's
/// reading-time row: a client must not carry two opinions about how fast people
/// read.
const readingWpm = 220;

/// The longest any passage must be dwelled on. Keeps a 2,000-word chunk
/// reachable rather than effectively unmarkable.
const dwellCapSeconds = 20;

/// `min(0.5 × word_count / 220 × 60, 20)` seconds of continuous visibility.
///
/// HALF the estimated reading time, because a reader who has spent half a
/// passage's worth of attention on it has read it in every sense this system
/// can observe. A fixed short dwell was rejected: it marks a 1,500-word passage
/// read after two seconds, and a signal confidently wrong about the case it
/// exists for is worse than no signal.
Duration dwellFor(int wordCount) {
  final seconds = (0.5 * wordCount / readingWpm) * 60;
  final capped = seconds.clamp(0.0, dwellCapSeconds.toDouble());
  return Duration(milliseconds: (capped * 1000).round());
}

/// Word count of a passage, from its own text.
int wordsIn(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
