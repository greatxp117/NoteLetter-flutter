/// The dwell rule (contract 3.1.0, ADR-039 §3).
///
/// Pinned because the rule can be wrong in only one direction that matters: a
/// threshold too low marks a long passage read on a fast scroll past it, which
/// is the failure the proportional rule exists to prevent. A fixed 2s dwell was
/// rejected for exactly that — a signal confidently wrong about the case it
/// exists for is worse than no signal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/dwell.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _QuietFirestore extends FirestoreService {
  _QuietFirestore() : super.stub();
  @override
  Future<void> logChunksRead(String documentId, List<String> chunkIds) async {}
}

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

  // F-55. The unit is the passage's STORED text (reader.md §Reading state,
  // ADR-039 §3), never a count taken from the html. The seed's table passage
  // is the case: its html counts 5 words with tags as breaks and 2 through the
  // web reference's textContent (`QuarterInvoice total` / `Q2$1,200`), its
  // stored text 8.
  const tableHtml = '<table><tr><td>Quarter</td><td>Invoice total</td></tr>'
      '<tr><td>Q2</td><td>\$1,200</td></tr></table>';
  const tableText = 'Table of tax invoice totals for the budget.';

  test('a passage is counted from its stored text, not its html', () {
    expect(passageWords(storedText: tableText), 8);
    expect(passageWords(storedText: tableText, editedText: 'two words'), 2,
        reason: 'an edited passage has no stored text for its new words');
    expect(dwellFor(passageWords(storedText: tableText)),
        dwellFor(wordsIn(tableText)));
  });

  testWidgets('the manuscript header counts what the dwell clock counts',
      (tester) async {
    FirestoreService.instance = _QuietFirestore();
    addTearDown(FirestoreService.resetInstance);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ManuscriptPanel(
            docId: 'doc-1',
            doc: Document.fromJson('doc-1', {
              'user_id': 'u1',
              'title': 'Quarterly Tax Summary',
              'type': 'pdf',
              'status': 'complete',
            }),
            chunks: [
              Chunk.fromJson({
                'chunk_id': 'c1',
                'document_id': 'doc-1',
                'chunk_index': 0,
                'text': 'Quarterly tax figures and budget invoice summary.',
                'html': '<p>Quarterly tax figures and the operating budget.</p>',
              }),
              Chunk.fromJson({
                'chunk_id': 'c2',
                'document_id': 'doc-1',
                'chunk_index': 1,
                'text': tableText,
                'html': tableHtml,
              }),
            ],
            onSaved: () async {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('2 passages · 15 words'), findsOneWidget,
        reason: '7 + 8 from the stored text; the html says 12 (tags as '
            'breaks) or 9 (textContent)');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}
