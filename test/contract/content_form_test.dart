/// "Treat as recipe" / "Not a recipe" (4.6.0, ADR-042) and the §Supersession
/// confirm it carries (`screens/reader.md`). Reference: `ContentFormAction` in
/// `ReaderView.jsx`. F-55 found the action missing from this client's reader.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/reader/content_form_action.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _Recorder implements HttpClientAdapter {
  _Recorder(this.reply);
  final (int, Object) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Programs extends FirestoreService {
  _Programs(this.programs) : super.stub();
  final Stream<List<StudyProgram>> programs;
  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => programs;
}

Document _doc(String status) => Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Sourdough',
      'type': 'article',
      'status': status,
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

Future<void> _pump(WidgetTester tester, Document doc, List<Chunk> chunks,
    {VoidCallback? onQueued}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ContentFormAction(
          docId: 'doc-1', doc: doc, chunks: chunks, onQueued: onQueued ?? () {}),
    ),
  ));
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  test('offered on a complete or failed document only', () {
    expect(ContentFormAction.offeredFor(_doc('complete')), isTrue);
    expect(ContentFormAction.offeredFor(_doc('error')), isTrue);
    for (final s in ['queued', 'processing', 'pending_upload', 'skipped']) {
      expect(ContentFormAction.offeredFor(_doc(s)), isFalse, reason: s);
    }
  });

  test('the confirm names what is lost, and says when it could not check', () {
    final plain = ContentFormAction.supersessionLines(
        isRecipe: false, edited: false, inStudy: false);
    expect(plain, hasLength(1));
    final all = ContentFormAction.supersessionLines(
        isRecipe: false, edited: true, inStudy: true);
    expect(all.join(' '), contains('Your edits to these passages'));
    expect(all.join(' '), contains('its schedule for this source will restart'));
    final unknown = ContentFormAction.supersessionLines(
        isRecipe: true, edited: false, inStudy: null);
    expect(unknown.join(' '), contains('We could not check'),
        reason: 'a failed check is not "not in a program"');
  });

  testWidgets(
      'Treat as recipe: the study fact is read, the request is contentForm, a '
      'refusal stays in the confirm, success queues', (tester) async {
    FirestoreService.instance = _Programs(Stream.value([
      const StudyProgram(
          id: 'p1',
          title: 'Bread',
          documentIds: ['doc-1'],
          enabled: true,
          status: 'active'),
    ]));
    var status = 409;
    final rec = _Recorder((_) => status == 409
        ? (409, {'error': 'This source is already being processed.', 'error_code': 'CONFLICT'})
        : (202, {'reprocessing': true}));
    ApiService.instance.httpClientAdapter = rec;
    var queued = 0;
    await _pump(tester, _doc('complete'), _chunks(edited: true),
        onQueued: () => queued++);

    await tester.tap(find.text('Treat as recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce this to the recipe?'), findsOneWidget);
    expect(find.textContaining('This source is in a study program'),
        findsOneWidget);
    expect(find.textContaining('Your edits to these passages'), findsOneWidget);

    await tester.tap(find.text('Reduce to recipe'));
    await tester.pumpAndSettle();
    expect(rec.sent.single.method, 'PATCH');
    expect(rec.sent.single.path, endsWith('/fn_update_document'));
    expect(rec.sent.single.data, {'docId': 'doc-1', 'contentForm': 'recipe'});
    expect(find.text('This source is already being processed.'), findsOneWidget,
        reason: '§18: a refusal renders in the panel, which stays open');
    expect(queued, 0, reason: 'write before you move');

    status = 202;
    await tester.tap(find.text('Reduce to recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce this to the recipe?'), findsNothing);
    expect(queued, 1);
  });

  testWidgets('a recipe offers Not a recipe; an unreadable program list says so',
      (tester) async {
    FirestoreService.instance =
        _Programs(Stream.error(StateError('permission-denied')));
    final recipeDoc = Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Sourdough',
      'type': 'article',
      'status': 'complete',
      'content_form': 'recipe',
      'recipe': {
        'title': 'Sourdough',
        'ingredients': [
          {'text': 'flour'}
        ],
        'steps': [
          {'text': 'Mix.'}
        ],
      },
    });
    expect(recipeDoc.recipe, isNotNull,
        reason: 'the fixture must parse as a recipe for this case to mean anything');
    await _pump(tester, recipeDoc, _chunks());
    await tester.tap(find.text('Not a recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Restore the full text?'), findsOneWidget);
    expect(find.textContaining('We could not check'), findsOneWidget);
    await tester.tap(find.text('Keep it as it is'));
    await tester.pumpAndSettle();
  });
}
