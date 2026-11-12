/// F-204 — a shelf proposal says how many sources it read (5.92.0, ADR-117
/// addendum 1; web 88e669c: shared/backfillSentence.js, ShelfForm.jsx,
/// ReviewView.jsx; tests/contract/backfill-asked.test.js).
///
/// Over 150 eligible sources the backend shows the model the 150 that lean
/// hardest toward the shelf and stores `asked` beside `scanned` (every
/// eligible source). "14 of your 494 sources look like they belong" claimed a
/// verdict on all 494. A result stored before 5.92.0 has no `asked` and read
/// at most 150, so it is read as min(scanned, 150). The words are the
/// backend's `_backfill_note` (area_tasks.py), byte for byte.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/background_task.dart';
import 'package:flutter_app/pages/review/task_copy.dart' show proposalLine;
import 'package:flutter_app/pages/tags/shelf_sheet.dart';
import 'package:flutter_app/theme/app_theme.dart';

Map<String, dynamic> _c(int i) =>
    {'documentId': 'd$i', 'title': 'Piece $i', 'reason': 'It is funny.'};

String? _line(Map<String, dynamic> result) =>
    proposalLine(BackgroundTask.fromJson('x', {
      'kind': 'shelf_backfill',
      'status': 'awaiting_review',
      'subject': {'title': 'Humor'},
      'params': <String, dynamic>{},
      'result': result,
    }));

Future<String> _lede(WidgetTester tester, Map<String, dynamic> result) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ShelfBackfillReview(
          // A fresh review per result: the review seeds from it once.
          key: ValueKey(result.toString()),
          tagId: 't1',
          title: 'Humor',
          onDone: () {},
          onCancel: () {},
          stored: StoredBackfill(
            key: 'k',
            result: result,
            apply: (_) async => const {'filed': 0, 'skipped': {}},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  // The lede is the review's first rich text.
  final rich = tester.widgetList<RichText>(find.byType(RichText)).first;
  return rich.text.toPlainText();
}

void main() {
  group("For your review's line — the backend's _backfill_note", () {
    test('every eligible source read: unchanged', () {
      expect(_line({'scanned': 40, 'asked': 40, 'candidates': [1, 2, 3]}),
          '3 of your 40 sources look like they belong on Humor.');
      expect(_line({'scanned': 40, 'asked': 40, 'candidates': []}),
          'Nothing in your library looks like it belongs on Humor yet.');
      expect(_line({'scanned': 12, 'candidates': [1, 2, 3]}),
          '3 of your 12 sources look like they belong on Humor.',
          reason: 'asked absent at scanned <= 150 is every source');
    });

    test('fewer read than eligible: what was read, and what was not', () {
      expect(
          _line({
            'scanned': 494,
            'asked': 150,
            'candidates': List.filled(14, 0),
          }),
          '14 of the 150 sources most like Humor look like they belong on '
          'it; your other 344 sources were not checked.');
      expect(
          _line({'scanned': 151, 'asked': 150, 'candidates': []}),
          'Nothing among the 150 sources most like Humor looks like it '
          'belongs on it yet; your other 1 source was not checked.');
    });

    test('a result stored before 5.92.0 (no asked) read at most 150', () {
      expect(_line({'scanned': 494, 'candidates': [1, 2]}),
          startsWith('2 of the 150 sources most like Humor'));
      expect(_line({'scanned': 494, 'candidates': [1, 2]}),
          endsWith('your other 344 sources were not checked.'));
    });
  });

  group('the backfill review says the same', () {
    testWidgets('a proposal over a pool', (tester) async {
      expect(
          await _lede(tester, {
            'scanned': 494,
            'asked': 150,
            'candidates': [_c(1), _c(2)],
          }),
          '2 of the 150 sources most like Humor look like they belong on it; '
          'your other 344 sources were not checked.');
    });

    testWidgets('nothing fits, over a pool', (tester) async {
      expect(
          await _lede(tester, {'scanned': 164, 'asked': 150, 'candidates': []}),
          'Nothing among the 150 sources most like Humor looks like it '
          'belongs on it yet; your other 14 sources were not checked.');
    });

    testWidgets('a result with no asked, over 150', (tester) async {
      expect(
          await _lede(tester, {'scanned': 494, 'candidates': [_c(1)]}),
          '1 of the 150 sources most like Humor look like they belong on it; '
          'your other 344 sources were not checked.');
    });

    testWidgets('every source read: the sentences it always said',
        (tester) async {
      expect(
          await _lede(
              tester, {'scanned': 40, 'asked': 40, 'candidates': [_c(1)]}),
          '1 of your 40 sources look like they belong on Humor.');
      expect(
          await _lede(tester, {'scanned': 40, 'asked': 40, 'candidates': []}),
          'Nothing in your library looks like it belongs on Humor yet.');
    });

    testWidgets('the numbers and the shelf keep their em spans',
        (tester) async {
      await _lede(tester, {
        'scanned': 494,
        'asked': 150,
        'candidates': [_c(1), _c(2)],
      });
      final rich = tester.widgetList<RichText>(find.byType(RichText)).first;
      final ems = <String>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text != null &&
            span.style?.fontStyle == FontStyle.italic) {
          ems.add(span.text!);
        }
        return true;
      });
      expect(ems, ['2', '150', 'Humor']);
    });
  });
}
