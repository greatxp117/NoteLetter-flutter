/// reader.md §Supersession confirm on **Update from source** — both places it
/// appears (4.96.0, ADR-129): the reader's freshness banner (here) and the
/// Sources row of a kept refresh (`cloud_sync_tandem_test.dart`). Before any
/// operation that re-derives content, the client MUST confirm when a passage
/// was edited or the document is in a study program, naming both
/// consequences; it is a §18 Confirmation, danger variant. Both surfaces used
/// to send the request on the first tap.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/reader/source_freshness.dart';
import 'package:flutter_app/pages/reader/supersession_confirm.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Answers by endpoint: the freshness check, then Update from source.
class _Router implements HttpClientAdapter {
  _Router(this.update);
  (int, Object) Function() update;
  final List<RequestOptions> updates = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (int, Object) reply;
    if (options.path.endsWith('/fn_check_source_freshness')) {
      reply = (200, {'provider': 'dropbox', 'newer_at_provider': true});
    } else {
      updates.add(options);
      reply = update();
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Reads extends FirestoreService {
  _Reads({this.edited = false, this.programs}) : super.stub();
  final bool? edited;
  final Stream<List<StudyProgram>>? programs;

  @override
  Future<(Document, List<Chunk>)?> getReaderDocumentQuietly(
      String docId) async {
    if (edited == null) throw StateError('permission-denied');
    return (
      _cloudDoc(),
      [
        Chunk.fromJson({
          'chunk_id': 'c1',
          'document_id': docId,
          'chunk_index': 0,
          'text': 'A passage.',
          'user_edited': edited,
        }),
      ]
    );
  }

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() =>
      programs ?? Stream.value(const []);
}

Document _cloudDoc() => Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'A cloud file',
      'type': 'document',
      'status': 'complete',
      'source_integration': {'provider': 'dropbox', 'file_id': 'f1'},
    });

Future<void> _pumpBanner(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SourceFreshness(docId: 'doc-1', doc: _cloudDoc())),
  ));
  await tester.pumpAndSettle();
  expect(find.textContaining('A newer version of this file exists in Dropbox'),
      findsOneWidget);
}

void main() {
  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    SourceFreshness.resetCacheForTest();
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  test('owed unless BOTH facts are a definite no', () {
    expect(SupersessionConfirm.owed(edited: false, inStudy: false), isFalse);
    for (final (e, s) in [
      (true, false),
      (false, true),
      (null, false),
      (false, null),
      (null, null),
    ]) {
      expect(SupersessionConfirm.owed(edited: e, inStudy: s), isTrue,
          reason: 'edited=$e inStudy=$s — an unread fact is not a "no"');
    }
  });

  test('the sentences: the lead, then each consequence or "could not check"',
      () {
    final lead = SupersessionConfirm.updateLead('google_drive');
    expect(lead, contains('re-imported from Google Drive'));
    expect(SupersessionConfirm.lines(lead: lead, edited: false, inStudy: false),
        [lead]);
    final all = SupersessionConfirm.lines(
        lead: lead, edited: true, inStudy: true).join(' ');
    expect(all, contains('Your edits to these passages'));
    expect(all, contains('its schedule for this source will restart'));
    final unknown = SupersessionConfirm.lines(
        lead: lead, edited: null, inStudy: null).join(' ');
    expect(unknown, contains('could not check whether these passages'));
    expect(unknown, contains('could not check whether this source is in'));
  });

  testWidgets('the banner, nothing edited and no program: no confirm, queued',
      (tester) async {
    FirestoreService.instance = _Reads();
    final rec = _Router(() => (202, {'queued': true}));
    ApiService.instance.httpClientAdapter = rec;
    await _pumpBanner(tester);
    await tester.tap(find.text('Update from source'));
    await tester.pumpAndSettle();
    expect(find.byType(KitConfirm), findsNothing);
    expect(rec.updates.single.data, {'document_id': 'doc-1'});
    expect(find.textContaining('Update queued'), findsOneWidget);
  });

  testWidgets(
      'the banner, in a study program: the §18 confirm first, a refusal in the '
      'panel, the banner flips only on success', (tester) async {
    FirestoreService.instance = _Reads(
      programs: Stream.value([
        const StudyProgram(
            id: 'p1',
            title: 'Files',
            documentIds: ['doc-1'],
            enabled: true,
            status: 'active'),
      ]),
    );
    var status = 429;
    final rec = _Router(() => status == 429
        ? (429, {'error': 'Too many updates — try again in a minute.'})
        : (202, {'queued': true}));
    ApiService.instance.httpClientAdapter = rec;
    await _pumpBanner(tester);

    await tester.tap(find.text('Update from source'));
    await tester.pumpAndSettle();
    expect(find.text('Update from the source?'), findsOneWidget);
    expect(rec.updates, isEmpty, reason: 'nothing leaves before the confirm');
    expect(find.textContaining('re-imported from Dropbox'), findsOneWidget);
    expect(find.textContaining('This source is in a study program'),
        findsOneWidget);
    expect(find.textContaining('Your edits'), findsNothing,
        reason: 'no passage was edited, so the confirm does not say so');

    final confirm = find.descendant(
        of: find.byType(KitConfirm),
        matching: find.widgetWithText(KitButton, 'Update from source'));
    expect(tester.widget<KitButton>(confirm).variant, KitButtonVariant.danger);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(KitConfirm),
            matching: find.textContaining('Too many updates')),
        findsOneWidget,
        reason: '§18: the refusal is in the panel, which stays open');
    expect(find.textContaining('Update queued'), findsNothing,
        reason: 'write before you move');

    status = 202;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byType(KitConfirm), findsNothing);
    expect(find.textContaining('Update queued'), findsOneWidget);
  });

  testWidgets('the banner, edits unreadable: the confirm says so; Keep sends '
      'nothing and gives the control back', (tester) async {
    FirestoreService.instance = _Reads(edited: null);
    final rec = _Router(() => (202, {'queued': true}));
    ApiService.instance.httpClientAdapter = rec;
    await _pumpBanner(tester);
    await tester.tap(find.text('Update from source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not check whether these passages'),
        findsOneWidget);
    await tester.tap(find.text('Keep it as it is'));
    await tester.pumpAndSettle();
    expect(rec.updates, isEmpty);
    expect(find.text('Update from source'), findsOneWidget);
  });
}
