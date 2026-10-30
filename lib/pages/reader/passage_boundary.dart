/// Moving where a passage begins (`screens/reader.md` §Moving a passage
/// boundary; feature `passage-boundary-drag.md`) — web's
/// `pages/reader/passageBoundary.js`, rule for rule.
///
/// A boundary sits between two neighbouring passages, A (before) and B (this
/// one). Moving it re-cuts the blocks of A and B at a new point; it never cuts
/// inside a block, which is what *Split here* is for. A cut is OFFERED only
/// where both sides keep content — text, or an `<img>` — the save preflight's
/// own test, because a passage with neither is one `fn_update_content`
/// refuses, and with it the whole save.
///
/// Pure, so the rules are asserted without geometry
/// (`test/contract/passage_boundary_test.dart`, over web's own cases); the
/// gesture that calls them lives in `manuscript_panel.dart`.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

String _escapeText(String t) =>
    t.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// The top-level blocks of a passage's html, as html strings. A loose text
/// node at the top (stored html is normally all blocks) is a block of its own,
/// so no text is lost by a re-cut. Whitespace-only text and comments are not
/// blocks.
List<String> passageBlocks(String? html) {
  final frag = html_parser.parseFragment(html ?? '');
  final out = <String>[];
  for (final n in frag.nodes) {
    if (n is dom.Element) {
      out.add(n.outerHtml);
    } else if (n is dom.Text && n.text.trim().isNotEmpty) {
      out.add(_escapeText(n.text));
    }
  }
  return out;
}

/// Text, or an `<img>` — the save preflight's test, over the blocks joined.
bool _hasContent(List<String> blocks) {
  final frag = html_parser.parseFragment(blocks.join());
  return (frag.text ?? '').trim().isNotEmpty ||
      frag.querySelector('img') != null;
}

/// Every cut k (A keeps the first k of the joined blocks, B the rest) that
/// leaves both passages with content, in order.
List<int> offeredCuts(String aHtml, String bHtml) {
  final joined = [...passageBlocks(aHtml), ...passageBlocks(bHtml)];
  return [
    for (var k = 1; k < joined.length; k++)
      if (_hasContent(joined.sublist(0, k)) && _hasContent(joined.sublist(k)))
        k,
  ];
}

/// Where the boundary is now: the number of blocks A holds.
int currentCut(String aHtml) => passageBlocks(aHtml).length;

/// The two passages re-cut at [k], or null when [k] is where the boundary
/// already is or is not an offered cut — the caller then changes nothing.
({String a, String b})? recut(String aHtml, String bHtml, int k) {
  if (k == currentCut(aHtml) || !offeredCuts(aHtml, bHtml).contains(k)) {
    return null;
  }
  final joined = [...passageBlocks(aHtml), ...passageBlocks(bHtml)];
  return (a: joined.sublist(0, k).join(), b: joined.sublist(k).join());
}

/// The offered cut one step from [from] in [dir] (-1 earlier, +1 later), or
/// [from] itself when there is none that way. Keyboard moves use it.
int stepCut(String aHtml, String bHtml, int from, int dir) {
  final cuts = offeredCuts(aHtml, bHtml);
  if (dir < 0) {
    final earlier = cuts.where((k) => k < from);
    return earlier.isEmpty ? from : earlier.last;
  }
  for (final k in cuts) {
    if (k > from) return k;
  }
  return from;
}
