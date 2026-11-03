// A source's History folds in its Activity (5.44.0, ADR-199; reader.md
// §History; F-147). Ported from the web reference's
// tests/contract/source-history.test.js — the same cases, so the two clients
// are held to one rule: Activity matched by `metadata.doc_id` only, labels by
// type, no count, a window labelled as one, and each half showing what it has.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/pages/reader/history_panel.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/services/source_history.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _doc = 'doc-1';
const _chunks = [
  Chunk(chunkId: 'c0', documentId: _doc, chunkIndex: 0, text: '', sourceType: 'pdf'),
  Chunk(chunkId: 'c1', documentId: _doc, chunkIndex: 1, text: '', sourceType: 'pdf'),
];

ActivityItem _ev(String id, String type, int at,
        {String level = 'info',
        String title = 'Pasta Fundamentals',
        Map<String, dynamic>? metadata}) =>
    ActivityItem(
      kind: 'event',
      id: id,
      type: type,
      status: 'complete',
      level: level,
      title: title,
      metadata: metadata ?? {'doc_id': _doc},
      createdAt: at,
    );

Map<String, dynamic> _read(String id, String type, int at, [String? chunk]) =>
    {'id': id, 'event_type': type, 'chunk_id': chunk, 'created_at': at};

Exception _denied() => Exception('Missing or insufficient permissions.');

/// Both reads, answered by the test.
class _Reads extends FirestoreService {
  _Reads({this.reads, this.readError, this.activity, this.activityError})
      : super.stub();
  List<Map<String, dynamic>>? reads;
  Object? readError;
  List<ActivityItem>? activity;
  Object? activityError;
  int readCalls = 0;
  int subscribeCalls = 0;
  String? subscribedDoc;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Map<String, dynamic>>> getReadHistory(String docId) async {
    readCalls++;
    if (readError != null) throw readError!;
    return reads ?? const [];
  }

  @override
  Stream<List<ActivityItem>> subscribeSourceActivity(String docId,
      {int limit = sourceHistoryLimit}) {
    subscribeCalls++;
    subscribedDoc = docId;
    if (activityError != null) return Stream.error(activityError!);
    return Stream.value(activity ?? const []);
  }
}

Future<void> _pump(WidgetTester tester, _Reads reads) async {
  FirestoreService.instance = reads;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(
      body: SingleChildScrollView(
        child: HistoryPanel(docId: _doc, chunks: _chunks),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(FirestoreService.resetInstance);

  group('sourceHistory — the rows', () {
    test('matches Activity by metadata.doc_id only, never by title or document_id', () {
      final h = sourceHistory(docId: _doc, reads: const [], activity: [
        _ev('mine', 'doc_indexed', 3),
        _ev('same-title', 'doc_indexed', 2, metadata: {'doc_id': 'another-doc'}),
        _ev('document-id', 'doc_indexed', 1, metadata: {'document_id': _doc}),
      ]);
      expect(h.rows.map((r) => r.id), ['act-mine']);
    });

    test('labels by type; the four organizer/import types by title', () {
      sourceEventLabels.forEach((type, label) {
        final h = sourceHistory(
            docId: _doc, activity: [_ev('e', type, 1, title: 'Not a label')]);
        expect(h.rows.single.label, label, reason: type);
      });
      for (final type in sourceEventTitled) {
        final h = sourceHistory(
            docId: _doc,
            activity: [_ev('e', type, 1, title: 'Placed notes.pdf → /Books')]);
        expect(h.rows.single.label, 'Placed notes.pdf → /Books', reason: type);
        final untitled =
            sourceHistory(docId: _doc, activity: [_ev('e', type, 1, title: '')]);
        expect(untitled.rows.single.label, 'Activity', reason: type);
      }
      final unknown = sourceHistory(
          docId: _doc, activity: [_ev('e', 'not_a_type_yet', 1, title: 'X')]);
      expect(unknown.rows.single.label, 'Activity');
    });

    test('the labels are the web reference’s, word for word', () {
      expect(sourceEventLabels, {
        'doc_indexed': 'Indexed into your library',
        'doc_processing_note': 'Note',
        'doc_processing_failed': 'Processing failed',
        'doc_indexing_failed': 'Indexing failed',
        'doc_skipped': 'Skipped at import',
        'doc_duplicate': 'Added again',
        'doc_cancelled': 'Cancelled',
        'article_resolved': 'Article found',
        'organization_move': 'Moved in your cloud folder',
      });
      expect(sourceEventTitled, {
        'cloud_sync_failed', 'organization_placement', 'organization_error',
        'reorg_executed',
      });
    });

    test('detail from note || error, and the level as read', () {
      final h = sourceHistory(docId: _doc, activity: [
        _ev('a', 'doc_processing_failed', 2,
            level: 'error', metadata: {'doc_id': _doc, 'error': 'Not a valid DOCX.'}),
        _ev('b', 'doc_processing_note', 1,
            metadata: {'doc_id': _doc, 'note': 'Recognised a recipe.', 'error': 'ignored'}),
      ]);
      expect(h.rows.map((r) => [r.detail, r.level]), [
        ['Not a valid DOCX.', 'error'],
        ['Recognised a recipe.', 'info'],
      ]);
    });

    test('reading rows by event type with the passage, interleaved newest first', () {
      final h = sourceHistory(
        docId: _doc,
        chunks: _chunks,
        reads: [
          _read('r1', 'chunk_read', 30, 'c1'),
          _read('r2', 'doc_opened', 10),
          _read('r3', 'mystery', 5),
        ],
        activity: [_ev('a1', 'doc_indexed', 20)],
      );
      expect(h.rows.map((r) => r.label), [
        'Read a passage (Passage 2)',
        'Indexed into your library',
        'Opened the source',
        'Activity',
      ]);
    });

    test('a half that returned its whole limit is a window', () {
      final full = [
        for (var i = 0; i < sourceHistoryLimit; i++) _read('r$i', 'doc_opened', i)
      ];
      final h = sourceHistory(docId: _doc, reads: full, activity: const []);
      expect([h.readingWindow, h.activityWindow], [true, false]);
      expect(
          sourceHistory(docId: _doc, reads: full.sublist(1), activity: const [])
              .readingWindow,
          isFalse);
    });
  });

  group('HistoryPanel — the states', () {
    testWidgets('reads Activity for this source only; empty only when both are',
        (tester) async {
      final r = _Reads();
      await _pump(tester, r);
      expect(r.subscribedDoc, _doc);
      expect(find.text('No history yet.'), findsOneWidget);
      expect(find.text('Open this source to start a reading history.'),
          findsOneWidget);
      expect(find.byType(KitSlideSwitch<String>), findsNothing);
    });

    testWidgets('interleaves, tags Activity, marks an error, draws no count',
        (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _pump(
          tester,
          _Reads(reads: [
            _read('r1', 'chunk_read', now - 1000, 'c0')
          ], activity: [
            _ev('a1', 'doc_indexed', now - 5000),
            _ev('a2', 'doc_processing_failed', now - 9000,
                level: 'error',
                metadata: {'doc_id': _doc, 'error': 'Not a valid DOCX.'}),
          ]));
      expect(find.text('Read a passage (Passage 1)'), findsOneWidget);
      expect(find.text('Indexed into your library'), findsOneWidget);
      expect(find.text('Processing failed'), findsOneWidget);
      expect(find.text('Not a valid DOCX.'), findsOneWidget);
      expect(find.text('ACTIVITY'), findsNWidgets(2));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ events?')), findsNothing);
    });

    testWidgets('filters, and says so under a filter with nothing',
        (tester) async {
      await _pump(tester, _Reads(activity: [_ev('a1', 'doc_indexed', 20)]));
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      expect(find.text('Indexed into your library'), findsNothing);
      expect(find.text('Nothing of this kind yet.'), findsOneWidget);
      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(find.text('Indexed into your library'), findsOneWidget);
      expect(find.text('Nothing of this kind yet.'), findsNothing);
    });

    testWidgets('labels a half at its limit as a window, under its filters only',
        (tester) async {
      final full = [
        for (var i = 0; i < sourceHistoryLimit; i++)
          _read('r$i', 'doc_opened', i + 1)
      ];
      await _pump(tester,
          _Reads(reads: full, activity: [_ev('a1', 'doc_indexed', 0)]));
      const note = 'Only your most recent 50 reading events are shown.';
      expect(find.text(note), findsOneWidget);
      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(find.text(note), findsNothing);
    });

    testWidgets('a failed reading half is the block above the Activity',
        (tester) async {
      await _pump(tester,
          _Reads(readError: _denied(), activity: [_ev('a1', 'doc_indexed', 20)]));
      expect(
          find.text(
              'Your reading history could not be loaded. Activity for this source is below.'),
          findsOneWidget);
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(find.text('Indexed into your library'), findsOneWidget);
      expect(find.text('No history yet.'), findsNothing);
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      expect(find.text('Your reading history could not be loaded.'), findsOneWidget);
      expect(find.text('Nothing of this kind yet.'), findsNothing);
    });

    testWidgets('reading failed with no Activity: the block alone, retrying only it',
        (tester) async {
      final r = _Reads(readError: _denied());
      await _pump(tester, r);
      expect(find.text('Your reading history could not be loaded.'), findsOneWidget);
      expect(find.byType(KitSlideSwitch<String>), findsNothing);
      r.readError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No history yet.'), findsOneWidget);
      expect([r.readCalls, r.subscribeCalls], [2, 1]);
    });

    testWidgets('a failed Activity half is the block above the reading — never silence',
        (tester) async {
      await _pump(tester,
          _Reads(reads: [_read('r1', 'doc_opened', 10)], activityError: _denied()));
      expect(
          find.text(
              'Activity for this source could not be loaded. Your reading history is below.'),
          findsOneWidget);
      expect(find.text('Opened the source'), findsOneWidget);
    });

    testWidgets('Activity failed with no reading: the block alone, resubscribing only it',
        (tester) async {
      final r = _Reads(activityError: _denied());
      await _pump(tester, r);
      expect(find.text('Activity for this source could not be loaded.'),
          findsOneWidget);
      expect(find.text('No history yet.'), findsNothing);
      r.activityError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No history yet.'), findsOneWidget);
      expect([r.readCalls, r.subscribeCalls], [1, 2]);
    });

    testWidgets('both failed is one block that retries both', (tester) async {
      await _pump(tester, _Reads(readError: _denied(), activityError: _denied()));
      expect(find.text('This source’s history could not be loaded.'),
          findsOneWidget);
      expect(find.byType(KitFailureBlock), findsOneWidget);
    });
  });
}
