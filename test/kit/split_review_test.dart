// screens/library.md §Splitting a shelf from a stored proposal (4.102.0,
// ADR-136), mirroring web's SplitReview: the apply names each kept part by its
// index with the reader's title — never document ids; what left the shelf
// meanwhile is said before Done; a 409 STALE is drawn in the sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/tags/split_shelf_sheet.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

const _proposal = {
  'tagId': 't1',
  'title': 'Politics',
  'documentCount': 9,
  'rationale': 'Two subjects.',
  'unassignedDocumentIds': ['d9'],
  'parts': [
    {'title': 'US politics', 'description': 'Elections.', 'color': 'sage-500', 'documentIds': ['d1', 'd2']},
    {'title': 'Geopolitics', 'description': 'States.', 'color': 'plum-500', 'documentIds': ['d3']},
    {'title': 'Media', 'description': '', 'color': null, 'documentIds': ['d4']},
  ],
};

Future<List<List<Map<String, dynamic>>>> _mount(WidgetTester tester,
    Future<Map<String, dynamic>> Function(List<Map<String, dynamic>>) answer) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sent = <List<Map<String, dynamic>>>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SplitShelfSheet(
        title: 'Politics',
        proposal: _proposal,
        apply: (parts) {
          sent.add(parts);
          return answer(parts);
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return sent;
}

void main() {
  testWidgets('the kept parts go by index and title — never document ids',
      (tester) async {
    final sent = await _mount(tester, (_) async => {'created': ['a', 'b'], 'skipped': {'moved_away': []}});
    await tester.tap(find.text('Skip').last); // skip Media
    await tester.pump();
    await tester.tap(find.text('Create 2 shelves'));
    await tester.pumpAndSettle();
    expect(sent, [
      [
        {'index': 0, 'title': 'US politics', 'description': 'Elections.'},
        {'index': 1, 'title': 'Geopolitics', 'description': 'States.'},
      ]
    ]);
  });

  testWidgets('sources that left the shelf meanwhile are said before Done',
      (tester) async {
    await _mount(tester, (_) async => {
          'created': ['a', 'b', 'c'],
          'skipped': {'moved_away': ['d3']},
        });
    await tester.tap(find.text('Create 3 shelves'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 source had left “Politics” since this was suggested'),
        findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a 409 STALE is drawn in the sheet, which stays', (tester) async {
    await _mount(tester, (_) async => throw const ApiException(409,
        'This shelf changed since the split was suggested, so it no longer divides as proposed. Run it again.',
        errorCode: 'STALE'));
    await tester.tap(find.text('Create 3 shelves'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer divides as proposed'), findsOneWidget);
    expect(find.text('Create 3 shelves'), findsOneWidget);
  });
}
