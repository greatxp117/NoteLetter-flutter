/// The dwell rule (contract 3.1.0, ADR-039 §3; halved 5.27.0, ADR-184) — when
/// a passage counts as read.
///
/// Extracted as pure arithmetic so it can be asserted directly; the widget that
/// watches visibility cannot be.
library;

/// Words per minute. **Normative** (ADR-020 §4) and shared with the reader's
/// reading-time row: a client must not carry two opinions about how fast people
/// read.
const readingWpm = 220;

/// The longest any passage must be dwelled on — ten seconds since 5.27.0
/// (ADR-184; twenty before). Keeps a 2,000-word chunk reachable, and a long
/// passage counted while it is still being read, rather than effectively
/// unmarkable.
const dwellCapSeconds = 10;

/// `min(0.25 × word_count / 220 × 60, 10)` seconds of continuous visibility —
/// 50 words 3.4 s, 100 words 6.8 s, 147 words or more 10 s (reader.md
/// §Reading state, halved 5.27.0, ADR-184).
///
/// A QUARTER of the estimated reading time, capped at ten seconds. ADR-039
/// asked for half, capped at twenty — and every passage over about 147 words,
/// most of what the chunker makes, sat at the twenty-second cap, so a passage
/// counted only after twenty seconds of holding still. The factor and the cap
/// were both halved, and a reader who has read it sooner presses **Mark as
/// read** (ADR-184). A fixed short dwell is still rejected: it marks a
/// 1,500-word passage read after two seconds, and a signal confidently wrong
/// about the case it exists for is worse than no signal.
Duration dwellFor(int wordCount) {
  final seconds = (0.25 * wordCount / readingWpm) * 60;
  final capped = seconds.clamp(0.0, dwellCapSeconds.toDouble());
  return Duration(milliseconds: (capped * 1000).round());
}

/// Word count of a passage, from its own text.
int wordsIn(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// The words a passage is measured in — for the dwell clock above, and for
/// every count the manuscript prints beside it, so the label and the clock
/// never disagree.
///
/// **The passage's own stored `text`** (`screens/reader.md` §Reading state,
/// ADR-039 §3: "`word_count` is the chunk's own, from `chunk.text` when not
/// stored" — chunks store no `word_count`). That text is INV-11's derivation
/// of the html: blocks joined by newlines, `[Image: alt]` markers, tables
/// linearized. A count taken from the html instead is a different number on
/// every passage holding a table or an image — stripping tags leaves out the
/// markers, and the web reference's `textContent` also glues adjacent cells
/// and blocks into one word (`QuarterInvoice total`).
///
/// [editedText] stands in once a passage is edited: its new words have no
/// stored text yet. Editing is not reading, so no dwell runs meanwhile; only
/// the labels read it.
int passageWords({required String storedText, String? editedText}) =>
    wordsIn(editedText ?? storedText);
