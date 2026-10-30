/// A Search result's layout in direction D (screens/search.md §Composition,
/// **Results** and **Reference metrics**; web `app-d-pages.css` `.dp-res*`).
///
/// The split with its reading pane (4.108.0, ADR-146; the pane-width rule of
/// 4.109.0) is retired with direction D: a result's context is read in place.
/// What replaced it is one row whose head is a grid `40px minmax(0,1fr) auto`
/// — rank, title over meta, the score at the row's end — with the passage and
/// its actions indented 56 under it; and in a column 600 or narrower the rank
/// column is 28, the score moves under the meta and the indent goes. Both
/// forms are asserted here, with the cut that folds a long passage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/search_result.dart';
import 'package:flutter_app/pages/search/result_d.dart';
import 'package:flutter_app/pages/search/score_explainer.dart';
import 'package:flutter_app/theme/app_theme.dart';

SearchResult _result({String text = 'Quarter | Invoice total Q2 | \$1,200'}) =>
    SearchResult.fromJson({
      'chunk': {
        'chunk_id': 'c1',
        'document_id': 'd1',
        'chunk_index': 2,
        'text': text,
        'source_type': 'pdf',
      },
      'document': {
        'user_id': 'u1',
        'title': 'Quarterly Tax Summary',
        'type': 'pdf',
        'status': 'complete',
      },
      'score': 0.85,
      'cosine': 0.9,
      'source_priority': 0.65,
      'source_priority_set': true,
    });

Future<void> _pump(WidgetTester tester, double column) async {
  tester.view.physicalSize = Size(column, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SearchResultD(
          result: _result(),
          rank: 1,
          open: false,
          onToggle: () {},
          onOpenSource: () {},
          shelfTitle: 'Finance',
        ),
      ),
    ),
  ));
}

void main() {
  test('the narrow column is 600, the column\'s own width', () {
    expect(searchNarrowColumn, 600);
  });

  testWidgets('wide: rank column 40, the score at the row\'s end, the passage '
      'indented 56', (tester) async {
    await _pump(tester, 1000);
    final rank = tester.getRect(find.text('01'));
    final title = tester.getRect(find.text('Quarterly Tax Summary'));
    final score = tester.getRect(find.text('0.85'));
    final anchor = tester.getRect(find.byType(SearchScoreAnchor));
    final passage = tester.getRect(find.byKey(const ValueKey('search-passage-1')));
    expect(title.left - rank.left, 40 + 16, reason: '40px column, 16 gap');
    expect(anchor.right, closeTo(1000, 0.5), reason: 'the row\'s end');
    expect(score.top, lessThan(tester.getRect(find.text('Finance')).bottom),
        reason: 'beside the title and meta, not under them');
    expect(passage.left, 56, reason: 'the rank\'s column and gap');
  });

  testWidgets('600 or narrower: rank column 28, the score under the meta, no '
      'indent', (tester) async {
    await _pump(tester, 600);
    final rank = tester.getRect(find.text('01'));
    final title = tester.getRect(find.text('Quarterly Tax Summary'));
    final meta = tester.getRect(find.text('Finance'));
    final score = tester.getRect(find.text('0.85'));
    final passage = tester.getRect(find.byKey(const ValueKey('search-passage-1')));
    expect(title.left - rank.left, 28 + 16);
    expect(score.top, greaterThanOrEqualTo(meta.bottom + 6),
        reason: 'under the meta, 6 above it');
    expect(score.left, lessThan(title.left + 60),
        reason: 'at the column\'s start, not its end');
    expect(passage.left, 0);
  });

  group('the cut', () {
    test('a short passage is whole', () {
      expect(searchSnippetCut('A short passage.'), 'A short passage.'.length);
    });

    test('near 280, at a word', () {
      final text = List.filled(80, 'word').join(' '); // 399 chars
      final cut = searchSnippetCut(text);
      expect(cut, lessThanOrEqualTo(280));
      expect(cut, greaterThan(250));
      expect(text[cut], ' ', reason: 'ends at a word, never inside one');
    });

    test('never inside an extraction marker', () {
      final lead = List.filled(52, 'word').join(' '); // 259 chars
      final text = '$lead [Image: a bar chart of quarterly budget figures] '
          'and then the passage goes on for a good while longer.';
      final cut = searchSnippetCut(text);
      final closing = text.indexOf(']') + 1;
      expect(cut, closing,
          reason: 'a marker the cut lands in is kept whole (§17.2)');
    });

    test('a run with no space keeps the plain cut', () {
      final text = 'x' * 400;
      expect(searchSnippetCut(text), 280);
    });
  });
}
