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

/// What a reader that SPEAKS says: the channel name and the body, never the
/// brackets — `"On screen: you."`, not `"bracket on screen colon you bracket"`.
String markersForSpeech(String? text) => splitMarkers(text)
    .map((p) => p.isMark ? ' ${p.label}: ${p.body}. ' : p.text)
    .join()
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// `true` when a block's whole text is markers — the §17.1 aside case. A block
/// that also holds real text keeps the §17.2 inline shape for each marker.
bool isAllMarkers(String? text) {
  final s = text ?? '';
  return hasMarker(s) && s.replaceAll(markerRe, '').trim().isEmpty;
}
