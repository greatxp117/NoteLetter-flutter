/// Web follow-up 3's five rulings (Xavier, 2026-10-14; contracts b39e72a,
/// web 088099c), Flutter's half. One group per ruling; each has a mutant that
/// turns it red.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/pages/activity_page.dart';
import 'package:flutter_app/pages/letters/pinned_sources.dart';
import 'package:flutter_app/pages/sources/shelf_books.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/passage_figure.dart';
import 'package:flutter_app/shared/stalled.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/theme/app_spacing.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

// ── harness ─────────────────────────────────────────────────────────────────

class _Activity extends ActivityNotifier {
  _Activity(this._items);
  final List<ActivityItem> _items;
  @override
  void start({int limit = 100}) {}
  @override
  List<ActivityItem> get items => _items;
  @override
  String? get error => null;
  @override
  bool get isLoading => false;
  @override
  int get newestEventAt => 0;
}

class _Docs extends DocumentsNotifier {
  _Docs(this._docs);
  final List<Document> _docs;
  @override
  void start() {}
  @override
  List<Document> get documents => _docs;
}

class _Canned implements HttpClientAdapter {
  _Canned(this.status, this.body);
  final int status;
  final Object body;
  final sent = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? req,
      Future<void>? cancel) async {
    sent.add(o);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(String id, String status,
        {int? chunkCount, int? stallsAt, String title = 'A source'}) =>
    Document.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'type': 'pdf',
      'status': status,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (stallsAt != null) 'processing_stalls_at': stallsAt,
    });

Future<void> _pumpActivity(WidgetTester tester, List<ActivityItem> items,
    List<Document> docs) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ActivityNotifier>.value(value: _Activity(items)),
      ChangeNotifierProvider<DocumentsNotifier>.value(value: _Docs(docs)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ActivityPage()),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

ActivityItem _docItem(String id, String status, {int at = 1757000000000}) =>
    ActivityItem(
      kind: 'document',
      id: id,
      type: 'pdf',
      status: status,
      level: 'info',
      title: 'Doc $id',
      createdAt: at,
    );

ActivityItem _failEvent(String id, String docId, {required int at}) =>
    ActivityItem(
      kind: 'event',
      id: id,
      type: 'doc_processing_failed',
      status: 'error',
      level: 'error',
      title: 'Doc $docId',
      metadata: {'doc_id': docId, 'error': 'Extraction failed.'},
      createdAt: at,
    );

Finder _retry() => find.widgetWithText(KitButton, 'Retry');

void main() {
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  // ── 1 ─────────────────────────────────────────────────────────────────────
  group('1 · a passage figure needs a count', () {
    test('a document never counted is a book with no count', () {
      expect(bookOf(_doc('u', 'complete'), const [], dark: false).passages,
          isNull);
      expect(
          bookOf(_doc('z', 'complete', chunkCount: 0), const [], dark: false)
              .passages,
          0);
    });

    test('null draws nothing; a measured 0 draws "0 passages"', () {
      expect(passagesLabel(null), isNull);
      expect(passagesLabel(0), '0 passages');
      expect(passagesLabel(1), '1 passage');
      expect(passagesLabel(12), '12 passages');
    });

    testWidgets('a book never counted has no Passages stat and no count in '
        'its note or its card; a total adds the counts that exist',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? open;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, set) => KitShelfUnit(
                label: 'Finance',
                dot: const Color(0xFF888888),
                books: const [
                  KitBook(id: 'b1', title: 'Never counted', kind: 'pdf'),
                  KitBook(
                      id: 'b2', title: 'Counted', kind: 'pdf', passages: 3),
                ],
                openId: open,
                onOpen: (id) => set(() => open = id),
              ),
            ),
          ),
        ),
      ));
      // The head's total adds what exists: 3, not "3 + nothing".
      expect(find.textContaining('3 passages'), findsOneWidget);
      await tester.tap(find.text('Never counted').first);
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'^passages$', caseSensitive: false)), findsNothing,
          reason: 'no Passages stat for a count never taken');
      expect(find.textContaining('indexed and searchable'), findsNothing);
      expect(find.textContaining('Open it to read'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KitSourceCard(
            book: const KitBook(id: 'b1', title: 'Never counted', kind: 'pdf'),
            kindLabel: 'PDF',
            date: 'Jul 1',
          ),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('passage'), findsNothing);
    });
  });

  // ── 2 ─────────────────────────────────────────────────────────────────────
  group('2 · the Aa popover track is §6.8\'s compact variant', () {
    testWidgets('a named group whose segments say whether they are pressed',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: KitTypeControls(groups: [
              KitTypeGroup(
                label: 'Type size',
                options: const ['Small', 'Default', 'Large'],
                selected: 1,
                onChanged: (_) {},
              ),
            ]),
          ),
        ),
      ));
      await tester.tap(find.text('Aa'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Type size'), findsWidgets,
          reason: 'the track is a group named by its row');
      expect(
          tester.getSemantics(find.text('Default')),
          containsSemantics(
              isButton: true, isSelected: true, hasSelectedState: true));
      expect(
          tester.getSemantics(find.text('Large')),
          containsSemantics(
              isButton: true, isSelected: false, hasSelectedState: true));
      handle.dispose();
    });
  });

  // ── 3 ─────────────────────────────────────────────────────────────────────
  group('3 · a busy Unpin holds steady', () {
    testWidgets('at the held opacity, not Material\'s disabled grey',
        (tester) async {
      final pinned = Completer<void>();
      FirestoreService.instance = _Pinned([_doc('p1', 'complete')]);
      ApiService.instance.tokenProvider = () async => 't';
      ApiService.instance.httpClientAdapter = _Slow(pinned.future);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PinnedSources(settings: NewsletterSettings(enabled: true)),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Unpin'));
      await tester.pump();
      expect(find.text('Unpinning…'), findsOneWidget);
      final opacity = tester.widget<Opacity>(find.ancestor(
          of: find.text('Unpinning…'), matching: find.byType(Opacity)).first);
      expect(opacity.opacity, AppSpacing.heldOpacity);
      final button = tester.widget<TextButton>(find.ancestor(
          of: find.text('Unpinning…'), matching: find.byType(TextButton)));
      expect(button.onPressed, isNotNull,
          reason: 'held, not disabled: Material would grey a null onPressed');
      // Steady: no animation runs on it.
      expect(
          find.ancestor(
              of: find.text('Unpinning…'),
              matching: find.byType(FadeTransition)),
          findsNothing);
      pinned.complete();
      await tester.pumpAndSettle();
    });
  });

  // ── 4 ─────────────────────────────────────────────────────────────────────
  group('4 · Activity draws a stalled run Stalled', () {
    testWidgets('chip Stalled, not live, critical node, the Sources sentence',
        (tester) async {
      final past = DateTime.now().millisecondsSinceEpoch - 60000;
      await _pumpActivity(tester, [
        _docItem('q1', 'queued'),
        _docItem('p1', 'processing', at: 1756000000000),
      ], [
        _doc('q1', 'queued', stallsAt: past),
        _doc('p1', 'processing', stallsAt: past),
      ]);
      expect(find.text('STALLED'), findsNWidgets(2));
      expect(find.text('PROCESSING'), findsNothing);
      expect(find.text(stalledQueuedMsg), findsOneWidget);
      expect(find.text(stalledProcMsg), findsOneWidget);
      for (final row in tester.widgetList<KitTimelineRow>(
          find.byType(KitTimelineRow))) {
        expect(row.live, isFalse);
        expect(row.tone, KitNodeTone.critical);
      }
    });

    testWidgets('before its moment it is still Processing, and live',
        (tester) async {
      final future = DateTime.now().millisecondsSinceEpoch + 3600000;
      await _pumpActivity(tester, [_docItem('p1', 'processing')],
          [_doc('p1', 'processing', stallsAt: future)]);
      expect(find.text('PROCESSING'), findsOneWidget);
      expect(find.text('STALLED'), findsNothing);
    });
  });

  // ── 5 ─────────────────────────────────────────────────────────────────────
  group('5 · a failed document\'s newest row carries Retry', () {
    testWidgets('one Retry, on the newest failure row, while it is error',
        (tester) async {
      await _pumpActivity(tester, [
        _failEvent('e2', 'd1', at: 1757000002000),
        _failEvent('e1', 'd1', at: 1757000001000),
        _docItem('d1', 'error', at: 1757000000000),
      ], [
        _doc('d1', 'error'),
      ]);
      expect(_retry(), findsOneWidget,
          reason: 'one document never shows two');
      final newest = find.ancestor(
          of: _retry(), matching: find.byType(KitTimelineRow));
      expect(tester.widget<KitTimelineRow>(newest).time,
          tester.widget<KitTimelineRow>(find.byType(KitTimelineRow).first)
              .time);
    });

    testWidgets('no Retry once the document has left error', (tester) async {
      await _pumpActivity(tester, [_failEvent('e1', 'd1', at: 1757000001000)],
          [_doc('d1', 'queued')]);
      expect(_retry(), findsNothing);
    });

    testWidgets('a refusal is the endpoint\'s sentence, verbatim',
        (tester) async {
      ApiService.instance.tokenProvider = () async => 't';
      final adapter = _Canned(409, {
        'error': 'This document is not retryable.',
        'error_code': 'NOT_RETRYABLE',
      });
      ApiService.instance.httpClientAdapter = adapter;
      FirestoreService.instance = _NoChecks();
      await _pumpActivity(
          tester, [_failEvent('e1', 'd1', at: 1757000001000)], [
        _doc('d1', 'error'),
      ]);
      await tester.tap(_retry());
      await tester.pumpAndSettle();
      expect(adapter.sent.single.path, endsWith('/fn_retry_document'));
      expect(find.text('This document is not retryable.'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsOneWidget);
    });
  });
}

/// Pinned documents for [PinnedSources].
class _Pinned extends FirestoreService {
  _Pinned(this.docs) : super.stub();
  final List<Document> docs;
  @override
  String? get currentUid => 'u1';
  @override
  Stream<List<Document>> subscribePinnedDocuments() => Stream.value(docs);
}

/// The supersession checks answer "no" without a read, so the Retry sends
/// straight through (no §18 confirm owed).
class _NoChecks extends FirestoreService {
  _NoChecks() : super.stub();
  @override
  String? get currentUid => 'u1';
  @override
  Future<(Document, List<Chunk>)?> getReaderDocumentQuietly(String docId) async =>
      (_doc(docId, 'error'), const <Chunk>[]);
  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => Stream.value(const []);
}

/// An unpin that does not answer until [gate] completes.
class _Slow implements HttpClientAdapter {
  _Slow(this.gate);
  final Future<void> gate;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? req,
      Future<void>? cancel) async {
    await gate;
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}
