// TODO L265: edit mode draws each passage's shelves (contract 2.35.0,
// ADR-034; web ManuscriptPanel `ChunkShelves`). Until round 2 the rule
// (`effectiveChunkShelves`) was tested and nothing drew it.
//
// Mutants run against it (each turns a case red): `removed` ignored (the
// document's shelf stays drawn after a passage took it off); onSaved called
// before the write answered (the chips move on a refusal); the inherited and
// the added chips drawn alike.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/reader/passage_shelves.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

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

const _finance = Tag(id: 's-fin', userId: 'u1', title: 'Finance');
const _recipes = Tag(id: 's-rec', userId: 'u1', title: 'Recipes');
const _gone = 's-deleted';

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() => ApiService.instance.resetTestSeams());

  Future<List<Map<String, dynamic>>> pump(
    WidgetTester tester, {
    Map<String, dynamic>? overrides,
    List<String> docTagIds = const ['s-fin'],
  }) async {
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return PassageShelves(
            docId: 'doc-1',
            chunkId: 'c-1',
            docTagIds: docTagIds,
            shelves: const [_finance, _recipes],
            tagOverrides: saved.isEmpty ? overrides : saved.last,
            onSaved: (next) => setState(() => saved.add(next)),
          );
        }),
      ),
    ));
    await tester.pump();
    return saved;
  }

  List<(String, bool)> chips(WidgetTester tester) => [
        for (final e in find.byType(KitShelfChipEditor).evaluate())
          for (final c in (e.widget as KitShelfChipEditor).chips)
            (c.shelf.title, c.inherited),
      ];

  testWidgets('a passage inherits its document\'s shelves; an added one is '
      'its own; a removed or dangling one draws nothing', (tester) async {
    await pump(tester);
    expect(chips(tester), [('Finance', true)]);
    await pump(tester, overrides: {
      'added': ['s-rec', _gone],
      'removed': <String>[],
    });
    expect(chips(tester), [('Finance', true), ('Recipes', false)]);
    await pump(tester, overrides: {
      'added': <String>[],
      'removed': ['s-fin'],
    });
    expect(chips(tester), isEmpty);
  });

  testWidgets('taking it off a shelf writes this passage\'s override whole, '
      'and the chips move once it is accepted', (tester) async {
    final rec = _Recorder((_) => (200, {'updated': 1}));
    ApiService.instance.httpClientAdapter = rec;
    final saved = await pump(tester);
    await tester.tap(find.bySemanticsLabel('Take this passage off Finance'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final body = rec.sent.single.data as Map;
    expect(rec.sent.single.path, endsWith('/fn_update_chunk_tags'));
    expect(body['documentId'], 'doc-1');
    expect(body['overrides'], [
      {'chunkId': 'c-1', 'addedTagIds': <String>[], 'removedTagIds': ['s-fin']},
    ]);
    expect(saved.single, {'added': <String>[], 'removed': ['s-fin']});
    expect(chips(tester), isEmpty);
  });

  testWidgets('a refusal stays beside the chips, and nothing moves',
      (tester) async {
    ApiService.instance.httpClientAdapter = _Recorder((_) => (
          400,
          {'error': 'Unknown shelf: s-fin', 'error_code': 'VALIDATION_ERROR'}
        ));
    final saved = await pump(tester);
    await tester.tap(find.bySemanticsLabel('Take this passage off Finance'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(saved, isEmpty);
    expect(chips(tester), [('Finance', true)]);
    expect(find.textContaining('Unknown shelf: s-fin'), findsOneWidget);
  });
}
