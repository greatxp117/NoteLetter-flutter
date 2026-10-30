/// **Re-process** (5.27.0, ADR-183; `screens/reader.md` §Re-process) and its
/// §Supersession confirm. Reference: `ReprocessAction` / `canReprocess` in
/// web's `ReaderView.jsx` and `tests/contract/reprocess-action.test.js`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/reprocess_action.dart';
import 'package:flutter_app/pages/reader/supersession_confirm.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _Recorder implements HttpClientAdapter {
  _Recorder(this.reply);
  final Future<(int, Object)> Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = await reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(Map<String, dynamic> fields) => Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Sourdough',
      'type': 'article',
      'status': 'complete',
      ...fields,
    });

List<Chunk> _chunks({bool edited = false}) => [
      Chunk.fromJson({
        'chunk_id': 'c1',
        'document_id': 'doc-1',
        'chunk_index': 0,
        'text': 'Mix the flour.',
        'user_edited': edited,
      }),
    ];

const _lead = 'This source will be read again from its original. Passages '
    'that come out the same are kept as they are; the rest are rebuilt, '
    'pictures included.';
const _editedLine = 'Your edits to passages that change will be replaced.';

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(ApiService.instance.resetTestSeams);

  group('offeredFor — web\'s canReprocess', () {
    const url = {'source_url': 'https://example.test/a'};

    test('a document at rest, with an original', () {
      expect(ReprocessAction.offeredFor(_doc({...url})), isTrue);
      expect(ReprocessAction.offeredFor(_doc({...url, 'status': 'error'})),
          isTrue);
      expect(
          ReprocessAction.offeredFor(
              _doc({'type': 'pdf', 'gcs_path': 'raw/u1/a.pdf'})),
          isTrue);
      expect(
          ReprocessAction.offeredFor(_doc({
            'type': 'image_set',
            'gcs_paths': ['raw/u1/image_sets/doc-1/0_a.png'],
          })),
          isTrue,
          reason: 'a set has no single gcs_path');
    });

    test('never mid-pipeline or unprocessed', () {
      for (final s in ['queued', 'processing', 'pending_upload', 'skipped']) {
        expect(ReprocessAction.offeredFor(_doc({...url, 'status': s})),
            isFalse,
            reason: s);
      }
    });

    test('never a captured passage', () {
      expect(
          ReprocessAction.offeredFor(_doc({
            ...url,
            'source_passage': {
              'source': 'browser_extension',
              'scope': 'passage',
            },
          })),
          isFalse);
    });

    test('never without an original — and an empty one is none', () {
      expect(ReprocessAction.offeredFor(_doc({})), isFalse);
      expect(
          ReprocessAction.offeredFor(
              _doc({'gcs_path': '', 'source_url': '', 'gcs_paths': []})),
          isFalse);
    });
  });

  test('the confirm says the lead, and the edit consequence only for an edit',
      () {
    expect(ReprocessAction.confirmLines(edited: false), [_lead]);
    expect(ReprocessAction.confirmLines(edited: true), [_lead, _editedLine]);
    expect(SupersessionConfirm.reprocessTitle, 'Re-process this source?');
    expect(SupersessionConfirm.reprocessConfirmLabel, 'Re-process');
    expect(SupersessionConfirm.reprocessCancelLabel, 'Keep it as it is');
    expect(SupersessionConfirm.reprocessBusyLabel, 'Queuing…');
  });

  Future<void> pump(WidgetTester tester, Document doc, List<Chunk> chunks,
      {VoidCallback? onQueued}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ReprocessAction(
            docId: 'doc-1',
            doc: doc,
            chunks: chunks,
            onQueued: onQueued ?? () {}),
      ),
    ));
  }

  testWidgets('draws nothing where it is not offered', (tester) async {
    await pump(tester, _doc({'status': 'processing', 'source_url': 'x'}),
        _chunks());
    expect(find.text('Re-process'), findsNothing);
  });

  testWidgets('always confirms; nothing is sent until Re-process, and Keep it '
      'as it is sends nothing', (tester) async {
    final rec = _Recorder((_) async => (202, {'reprocessing': true}));
    ApiService.instance.httpClientAdapter = rec;
    var queued = 0;
    await pump(tester, _doc({'source_url': 'https://example.test/a'}),
        _chunks(), onQueued: () => queued++);

    await tester.tap(find.text('Re-process'));
    await tester.pumpAndSettle();
    expect(find.text('Re-process this source?'), findsOneWidget,
        reason: 'confirmed ALWAYS — no edited passage, still asked');
    expect(find.text(_lead), findsOneWidget);
    expect(find.text(_editedLine), findsNothing);
    expect(find.textContaining('study program'), findsNothing,
        reason: 'an update in place keeps the schedule');
    expect(rec.sent, isEmpty);

    await tester.tap(find.text('Keep it as it is'));
    await tester.pumpAndSettle();
    expect(find.text('Re-process this source?'), findsNothing);
    expect(rec.sent, isEmpty);
    expect(queued, 0);
  });

  testWidgets('holds while the call flies, keeps a refusal in the confirm in '
      'the server\'s words, and queues on the 202', (tester) async {
    var reply = Completer<(int, Object)>();
    final rec = _Recorder((_) => reply.future);
    ApiService.instance.httpClientAdapter = rec;
    var queued = 0;
    await pump(tester, _doc({'source_url': 'https://example.test/a'}),
        _chunks(edited: true), onQueued: () => queued++);

    await tester.tap(find.text('Re-process'));
    await tester.pumpAndSettle();
    expect(find.text(_editedLine), findsOneWidget);

    // The panel's confirm, not the Also row under the scrim.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Re-process')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(rec.sent.single.method, 'PATCH');
    expect(rec.sent.single.path, endsWith('/fn_update_document'));
    expect(rec.sent.single.data, {'docId': 'doc-1', 'reprocess': true});
    // The busy label is the spec's (§Re-process: busy "Queuing…").
    expect(find.text('Queuing…'), findsOneWidget);
    // Held: the safe choice cannot be taken mid-flight (§18 rule 3), and
    // the panel does not close on it.
    await tester.tap(find.text('Keep it as it is'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Re-process this source?'), findsOneWidget);
    expect(queued, 0);

    reply.complete((
      409,
      {
        'error': 'This document is still processing — try again when it '
            'finishes.',
        'error_code': 'REQUEST_ERROR',
      }
    ));
    await tester.pumpAndSettle();
    expect(
        find.text('This document is still processing — try again when it '
            'finishes.'),
        findsOneWidget,
        reason: '§18: a refusal renders in the panel, which stays open');
    expect(find.text('Re-process this source?'), findsOneWidget);
    expect(queued, 0, reason: 'write before you move');

    reply = Completer<(int, Object)>();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Re-process')));
    await tester.pump();
    reply.complete((202, {'docId': 'doc-1', 'reprocessing': true, 'updated': []}));
    await tester.pumpAndSettle();
    expect(find.text('Re-process this source?'), findsNothing);
    expect(queued, 1);
  });
}
