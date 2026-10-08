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
import 'package:flutter_html/flutter_html.dart';
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

  // 4.109.1: one passage of one word reads as the reference's `counted()`
  // writes it — "1 passage", "1 word" — not the raw plural ("1 PASSAGES").
  testWidgets('the manuscript header counts one passage and one word singly',
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
              'title': 'One word',
              'type': 'plain',
              'status': 'complete',
              'word_count': 1,
            }),
            chunks: [
              Chunk.fromJson({
                'chunk_id': 'c1',
                'document_id': 'doc-1',
                'chunk_index': 0,
                'text': 'Hello.',
                'html': '<p>Hello.</p>',
              }),
            ],
            onSaved: () async {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('1 PASSAGE · 1 WORD'), findsOneWidget);
    expect(find.text('1 passage'), findsOneWidget, reason: 'and the footer');
    expect(find.text('1 word'), findsOneWidget);
    // The dwell's timers, as the tests below dispose them.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  // 4.108.0 (ADR-144): the header shows the document's STORED word_count —
  // the indexer's, canonical — and the unmeasured dash where none is stored.
  // It summed the passages' stored text (15 here) until then, which is a
  // client deriving its own count; the dwell keeps counting stored text.
  testWidgets('the manuscript header shows the stored word_count, never a sum',
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
              'word_count': 12,
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
    // The panel bar's `.pf-label`, set in caps by the caller (F-43).
    expect(find.text('2 PASSAGES · 12 WORDS'), findsOneWidget,
        reason: 'the stored count; the passages\' stored text sums to 15, '
            'which the header showed until 4.108.0');
    expect(find.text('12 words'), findsOneWidget, reason: 'and the footer');
    // F-77 (7): the passage mark sits in the SHEET's padding, 26 left of the
    // passage (`.ms-mark { left: -26px }`), and takes nothing from the text
    // column — it was a 26pt slice of the measure.
    final marks = find.byWidgetPredicate(
        (w) => w is Positioned && w.left == -26 && w.width == 4);
    expect(marks, findsNWidgets(2));
    expect(
        find.byWidgetPredicate((w) =>
            w is Padding && w.padding == const EdgeInsets.only(left: 26)),
        findsNothing);
    // `.ms-body table { font-size: 15px }`: a table is data under the page's
    // 19, and it inherited the 19.
    final html = tester.widgetList<Html>(find.byType(Html));
    expect(html, isNotEmpty);
    for (final h in html) {
      expect(h.style['table']?.fontSize?.value, 15);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('no stored word_count is the unmeasured dash — never a recount',
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
    // One passage is singular (4.109.1); this pinned the raw "1 PASSAGES".
    expect(find.text('1 PASSAGE · — WORDS'), findsOneWidget);
    expect(find.text('— words'), findsOneWidget);
    expect(find.textContaining('8 WORDS'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}
