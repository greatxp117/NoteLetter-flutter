/// The dwell rule (contract 3.1.0, ADR-039 §3; halved 5.27.0, ADR-184) — when
/// a passage counts as read.
///
/// Extracted as pure arithmetic so it can be asserted directly; the widget that
/// watches visibility cannot be.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

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

/// The indexer's word rule, for a passage's HTML (4.108.0, ADR-144;
/// data-model.md `word_count`; web `shared/indexWords.js`, word for word in
/// effect): every text node counted on its own and summed — BeautifulSoup's
/// `get_text(separator="\n", strip=True).split()`, `chunker.index_word_count`.
/// A table counts its cells' words and an image none (its alt is an attribute,
/// not text), and two cells or two blocks never run together into one word.
/// Parsed inert, so nothing in it loads.
int indexWords(String html) {
  if (html.trim().isEmpty) return 0;
  var n = 0;
  void walk(dom.Node node) {
    if (node is dom.Text) {
      final s = node.text.trim();
      if (s.isNotEmpty) n += s.split(RegExp(r'\s+')).length;
    }
    for (final c in node.nodes) {
      walk(c);
    }
  }

  walk(html_parser.parseFragment(html));
  return n;
}

/// The words a passage is measured in — for the dwell clock above, and for
/// every count the manuscript prints beside it, so the label and the clock
/// never disagree.
///
/// **The indexer's rule over the passage's HTML** ([indexWords]; 4.108.0,
/// ADR-144; web `indexWords(c.html)`), so a passage and its document are
/// counted the same way. Never its stored `text`: that is INV-11's
/// linearization, with `[Image: alt]` markers and ` | ` between table cells,
/// so a table passage read high and every pipe was a word (TODO L265). The
/// stored text is the count only for a passage with no HTML (the pre-1.1
/// shape), as data-model.md says.
///
/// [editedText] stands in once a passage is edited: its new words have no
/// HTML yet. Editing is not reading, so no dwell runs meanwhile; only the
/// labels read it.
int passageWords({
  String? html,
  required String storedText,
  String? editedText,
}) {
  if (editedText != null) return wordsIn(editedText);
  if (html != null && html.trim().isNotEmpty) return indexWords(html);
  return wordsIn(storedText);
}
