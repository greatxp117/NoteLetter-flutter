/// Extraction markers are annotations, not sentences (4.52.0, ADR-089).
///
/// An extractor that recovers content from a channel other than
/// words-in-order labels it inline — `[On screen: …]`, `[Video: …]`,
/// `[Diagram: …]`, `[Notes: …]`, `[Chart: …]` — and the chunk-text derivation
/// adds a sixth of the same shape, `[Image: {alt}]`. ADR-019 made them plain
/// text inside the normal HTML vocabulary and that stays: nothing here changes
/// anything stored. This is the display rule, which is why it reaches the
/// documents already in the library instead of only the ones ingested after.
///
/// Stripping is NOT the alternative: at 4.52.0 the markers are a median 31.6%
/// of a marker-bearing chunk's characters and 11 documents are more than half
/// marker. For a Reel whose burned-in text IS the content, deleting the
/// markers deletes the document.
///
/// Mirror of `NoteLetter-web/src/shared/extractionMarkers.js`. **Pure Dart,
/// no Flutter import** — `harness/extraction_marker_check.py` executes this
/// file through `tool/marker_probe.dart` with `dart run` and compares what it
/// reports against the spec table and an 8-row split table (/conformance 5z).
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The closed set, in the order `extraction-contract.md` §Non-verbal content
/// markers declares it. THREE OF THESE SIX HAVE NEVER BEEN WRITTEN TO
/// PRODUCTION — the list is declared, never grown from what the corpus holds:
/// a renderer enumerating what it has seen is green on every document that
/// exists and wrong on the first pptx deck with speaker notes (ADR-064's hole:
/// `docKind()` returned `podcast` while `KIND_ORDER` never listed it).
const List<String> markerLabels = [
  'On screen',
  'Video',
  'Image',
  'Diagram',
  'Notes',
  'Chart',
];

/// The canonical pattern from the spec. Labels match case-sensitively, as the
/// emitters write them. A body holding `[` or `]` is deliberately NOT a marker
/// — reading it as one would swallow a span of real content into an
/// annotation. The optional trailing `.` belongs to the marker: the extractor
/// appends one so `split_sentences` treats it as its own sentence (ADR-047,
/// ADR-088), and a renderer that stops at `]` leaves a stray period standing
/// in the body copy.
final String markerPatternSource =
    '\\[(${markerLabels.join('|')})\\s*:\\s*([^\\[\\]]*)\\]\\.?';

final RegExp markerRe = RegExp(markerPatternSource);

bool hasMarker(String? s) => markerRe.hasMatch(s ?? '');

/// One piece of a split: either a run of plain text or a marker.
class MarkerPiece {
  /// `true` for a marker, `false` for a run of text.
  final bool isMark;

  /// The text run (empty for a marker).
  final String text;

  /// The channel name, exactly as the spec spells it (empty for text).
  final String label;

  /// The marker body, trimmed (empty for text — and empty for `[Image: ]`,
  /// which is still a marker).
  final String body;

  const MarkerPiece.text(this.text)
      : isMark = false,
        label = '',
        body = '';

  const MarkerPiece.mark(this.label, this.body)
      : isMark = true,
        text = '';

  @override
  bool operator ==(Object other) =>
      other is MarkerPiece &&
      other.isMark == isMark &&
      other.text == text &&
      other.label == label &&
      other.body == body;

  @override
  int get hashCode => Object.hash(isMark, text, label, body);

  @override
  String toString() =>
      isMark ? 'MarkerPiece.mark($label, $body)' : 'MarkerPiece.text($text)';
}

/// Split plain text into text runs and markers. Nothing is ever dropped — an
/// empty body still yields a mark, because `[Video: ]` is a marker the model
/// returned empty and printing the brackets is the defect this fixes.
List<MarkerPiece> splitMarkers(String? text) {
  final s = text ?? '';
  final out = <MarkerPiece>[];
  var at = 0;
  for (final m in markerRe.allMatches(s)) {
    if (m.start > at) out.add(MarkerPiece.text(s.substring(at, m.start)));
    out.add(MarkerPiece.mark(m.group(1)!, (m.group(2) ?? '').trim()));
    at = m.end;
  }
  if (at < s.length) out.add(MarkerPiece.text(s.substring(at)));
  return out;
}

/// A body that has already closed itself as a sentence (`. ! ? …`, with an
/// optional closing quote or bracket). The extractor writes most bodies that
/// way, so an unconditional `. ` spoke "figures.." — and gave the word timer a
/// token ending in two stops (web 1599258).
final _closedBody = RegExp('[.!?…]["\'’”)\\]]*\$');

String _spokenMark(String label, String body) => body.isEmpty
    ? ' $label. '
    : ' $label: $body${_closedBody.hasMatch(body) ? '' : '.'} ';

/// What a reader that SPEAKS says: the channel name and the body, never the
/// brackets — `"On screen: you."`, not `"bracket on screen colon you bracket"`.
/// One stop closes a marker, never two; an empty body is the label alone.
String markersForSpeech(String? text) => splitMarkers(text)
    .map((p) => p.isMark ? _spokenMark(p.label, p.body) : p.text)
    .join()
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// `true` when a block's whole text is markers — the §17.1 aside case. A block
/// that also holds real text keeps the §17.2 inline shape for each marker.
bool isAllMarkers(String? text) {
  final s = text ?? '';
  return hasMarker(s) && s.replaceAll(markerRe, '').trim().isEmpty;
}

/// Rewrite an already-sanitized chunk fragment so every marker renders as §17.
///
/// The reference's `markSanitizedHtml`, in Dart. **Sanitize first, annotate
/// second, and never the other way round**: the spans this adds carry a
/// `class`, which the chunk vocabulary lists under *Never* — they are ours,
/// added after the allowlist has run, from text set as TEXT and therefore
/// never parsed as markup. Sanitizing afterwards would strip them, which is
/// correct for stored HTML and wrong for this.
///
/// It is a **display** rewrite and must never reach a writer: annotating
/// inside an editor would put a `.x-mark-*` span in front of the cursor and
/// let `fn_update_content` store it back, which is the one way a display rule
/// becomes a data change (ADR-089).
///
/// Returns the input untouched when it holds no marker, so the common case
/// costs one regex test and no parse.
String markSanitizedHtml(String? html) {
  final input = html ?? '';
  if (input.isEmpty || !hasMarker(input)) return input;

  final fragment = html_parser.parseFragment(input);

  // Pass 1 — a block that is NOTHING BUT markers becomes its asides. By block,
  // and first, because the decision belongs to the block: a text node cannot
  // see that it is the only thing in its paragraph.
  // One selector at a time: `package:html` does not take a selector GROUP, and
  // a group it cannot parse matches nothing — which is silent, and leaves
  // every aside rendered as an inline run inside an empty paragraph.
  final blocks = [
    for (final tag in const ['p', 'li', 'figcaption', 'blockquote'])
      ...fragment.querySelectorAll(tag),
  ];
  for (final el in blocks) {
    if (!isAllMarkers(el.text)) continue;
    final marks = splitMarkers(el.text).where((p) => p.isMark);
    final replacements = [
      for (final m in marks) _asideNode(m.label, m.body),
    ];
    // `parent` is typed Element? and is NULL for a node whose parent is the
    // fragment itself — which is every top-level block in a chunk. Reaching
    // for it instead of `parentNode` silently skipped pass 1 entirely, and
    // pass 2 then drew every aside as an inline run inside an empty block.
    final parent = el.parentNode;
    if (parent == null) continue;
    final at = parent.nodes.indexOf(el);
    parent.nodes.removeAt(at);
    parent.nodes.insertAll(at, replacements);
  }

  // Pass 2 — everything left is a marker inside a run of real text.
  final texts = <dom.Text>[];
  void walk(dom.Node n) {
    for (final child in n.nodes) {
      if (child is dom.Text) {
        if (hasMarker(child.text)) texts.add(child);
      } else {
        walk(child);
      }
    }
  }

  walk(fragment);
  for (final node in texts) {
    final parent = node.parentNode;
    if (parent == null) continue;
    final at = parent.nodes.indexOf(node);
    final pieces = [
      for (final p in splitMarkers(node.text))
        p.isMark ? _inlineNode(p.label, p.body) : dom.Text(p.text),
    ];
    parent.nodes.removeAt(at);
    parent.nodes.insertAll(at, pieces);
  }

  return fragment.outerHtml;
}

dom.Element _asideNode(String label, String body) {
  final el = dom.Element.tag('div')..className = 'x-mark-aside';
  el.append(dom.Element.tag('div')
    ..className = 'x-mark-label caps-label'
    ..text = label);
  el.append(dom.Element.tag('div')
    ..className = 'x-mark-body'
    ..text = body);
  return el;
}

dom.Element _inlineNode(String label, String body) {
  final el = dom.Element.tag('span')..className = 'x-mark-inline';
  el.append(dom.Element.tag('span')
    ..className = 'x-mark-label caps-label'
    ..text = label);
  el.append(dom.Element.tag('span')
    ..className = 'x-mark-body'
    ..text = body);
  return el;
}
