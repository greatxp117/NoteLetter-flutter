import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/extraction_markers.dart';

/// The marker splitter, row for row against the table
/// `harness/extraction_marker_check.py` executes (ADR-089). Every row is a
/// decision the ADR records, not a case that happened to work; the gate runs
/// the same rows through `tool/marker_probe.dart`, so a change here that the
/// gate disagrees with is the client's defect (conformance rule 7).
void main() {
  test('the label set is the spec table, in its order, all six', () {
    // Three of these have never been written to production. Declared, not
    // grown from the corpus — ADR-064's hole, one vocabulary over.
    expect(markerLabels,
        ['On screen', 'Video', 'Image', 'Diagram', 'Notes', 'Chart']);
    expect(markerPatternSource,
        r'\[(On screen|Video|Image|Diagram|Notes|Chart)\s*:\s*([^\[\]]*)\]\.?');
  });

  test('the trailing `.` belongs to the marker', () {
    expect(splitMarkers('Hello [On screen: you]. World'), const [
      MarkerPiece.text('Hello '),
      MarkerPiece.mark('On screen', 'you'),
      MarkerPiece.text(' World'),
    ]);
  });

  test('text with no marker is one piece, never re-spaced', () {
    expect(splitMarkers('nothing to see here'),
        const [MarkerPiece.text('nothing to see here')]);
    expect(hasMarker('nothing to see here'), isFalse);
    expect(splitMarkers(null), isEmpty);
    expect(splitMarkers(''), isEmpty);
  });

  test('a body holding `[` or `]` is NOT a marker', () {
    expect(splitMarkers('[Video: a [b] c]'),
        const [MarkerPiece.text('[Video: a [b] c]')]);
  });

  test('labels match case-sensitively', () {
    expect(splitMarkers('[on screen: x]'),
        const [MarkerPiece.text('[on screen: x]')]);
  });

  test('a label never written to production still matches', () {
    expect(splitMarkers('[Notes: a speaker note]'),
        const [MarkerPiece.mark('Notes', 'a speaker note')]);
  });

  test('an empty body is still a marker', () {
    expect(splitMarkers('[Image: ]'), const [MarkerPiece.mark('Image', '')]);
  });

  test('a marker mid-run keeps both neighbours', () {
    expect(splitMarkers('a[Chart: Q3 revenue]b'), const [
      MarkerPiece.text('a'),
      MarkerPiece.mark('Chart', 'Q3 revenue'),
      MarkerPiece.text('b'),
    ]);
  });

  test('whitespace either side of the colon is optional', () {
    expect(splitMarkers('[Diagram:tight]'),
        const [MarkerPiece.mark('Diagram', 'tight')]);
  });

  test('a reader that speaks says the body, not the brackets', () {
    expect(markersForSpeech('Hello [On screen: you]. World'),
        'Hello On screen: you. World');
  });

  test('a block that is nothing but markers takes the aside shape', () {
    expect(isAllMarkers('[On screen: a]. [Video: b].'), isTrue);
    expect(isAllMarkers('said [On screen: a].'), isFalse);
    expect(isAllMarkers(''), isFalse);
  });
}
