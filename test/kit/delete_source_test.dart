// screens/reader.md §Deleting a source (4.105.0, ADR-138), mirroring web's
// `DeleteSource` / `deleteBody` in ReaderView.jsx. The body names what is lost
// and what is not; the §18 panel holds until fn_delete_document answers, keeps
// a refusal inside it, and only a success hands the reader back.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/reader/delete_source.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

Document _doc({String status = 'complete', List<String> tags = const []}) =>
    Document.fromJson('doc-1', {
      'user_id': 'u',
      'title': 'Household budget',
      'type': 'pdf',
      'status': status,
      'tag_ids': tags,
    });

Tag _tag(String id, String title) => Tag(id: id, userId: 'u', title: title);
final _shelves = [
  _tag('t1', 'Finance'),
  _tag('t2', 'Tax records'),
  _tag('t3', 'Home'),
];

const _kept = ' Letters you have already received keep their passages, and your '
    'shelves and other sources stay as they are. A study program that uses it '
    'drops its passages at its next session.';

void main() {
  group('the body', () {
    test('names the passages, and the shelves it comes off', () {
      expect(
          deleteSourceBody(_doc(tags: ['t1', 't2']), 12, _shelves),
          'Its 12 passages, its original file and its reading history are '
          'deleted for good, and it comes off Finance and Tax records.$_kept');
    });

    test('singular at 1, grouped past 999, and three shelves in a list', () {
      expect(deleteSourceBody(_doc(), 1, _shelves),
          startsWith('Its 1 passage, its original file'));
      expect(deleteSourceBody(_doc(), 1234, _shelves), startsWith('Its 1,234 passages,'));
      expect(deleteSourceBody(_doc(tags: ['t1', 't2', 't3']), 2, _shelves),
          contains('it comes off Finance, Tax records and Home.'));
    });

    test('at 0 it begins at the original file; no shelves, no clause', () {
      expect(
          deleteSourceBody(_doc(), 0, _shelves),
          'Its original file and its reading history are deleted for good.'
          '$_kept');
    });

    test('a shelf the tags subscription no longer has is not named', () {
      expect(deleteSourceBody(_doc(tags: ['gone', 't3']), 2, _shelves),
          contains('it comes off Home.'));
    });
  });

  test('offered for complete, error and skipped — never in progress', () {
    for (final s in ['complete', 'error', 'skipped']) {
      expect(DeleteSourceAction.offeredFor(_doc(status: s)), isTrue, reason: s);
    }
    for (final s in ['queued', 'processing', 'pending_upload']) {
      expect(DeleteSourceAction.offeredFor(_doc(status: s)), isFalse, reason: s);
    }
  });

  group('the confirmation', () {
    Future<List<String>> mount(WidgetTester tester,
        Future<void> Function(String) delete, VoidCallback onDeleted) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DeleteSourceAction(
              docId: 'doc-1',
              doc: _doc(tags: ['t1']),
              passages: 3,
              shelves: _shelves,
              onDeleted: onDeleted,
              delete: (id) {
                calls.add(id);
                return delete(id);
              },
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('holds while the call is in flight, then hands back once',
        (tester) async {
      final gate = Completer<void>();
      var back = 0;
      final calls = await mount(tester, (_) => gate.future, () => back++);
      expect(find.text('Delete “Household budget”?'), findsOneWidget);
      expect(find.textContaining('it comes off Finance.'), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);

      await tester.tap(find.text('Delete source'));
      await tester.pump();
      expect(calls, ['doc-1']);
      expect(find.text('Working…'), findsOneWidget);
      expect(back, 0);

      gate.complete();
      await tester.pumpAndSettle();
      expect(back, 1);
      expect(find.text('Delete “Household budget”?'), findsNothing);
    });

    testWidgets('a refusal answers inside the panel, and nothing moves',
        (tester) async {
      var back = 0;
      await mount(
          tester,
          (_) async => throw const ApiException(409, 'This source is still processing.'),
          () => back++);
      await tester.tap(find.text('Delete source'));
      await tester.pumpAndSettle();
      expect(find.text('This source is still processing.'), findsOneWidget);
      expect(find.text('Delete “Household budget”?'), findsOneWidget);
      expect(back, 0);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Household budget”?'), findsNothing);
      expect(back, 0);
    });
  });
}
