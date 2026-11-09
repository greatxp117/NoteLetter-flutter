/// **Echoes** (5.83.0, ADR-255; screens/reader.md §Echoes, component-kit §43
/// Echo pair, api/echoes.md) — web's `pages/reader/EchoesPanel.jsx`.
///
/// The call is faked at the HTTP seam, so what is driven is the real builder
/// (`POST /fn_find_echoes {docId}`, `limit` omitted) and the real envelope
/// mapping. Asserted: the rows grouped under one head per passage and only
/// when consecutive, each state's sentence (the contract's, byte for byte),
/// the echo's open with its docId and chunkId, the head's passage, §14.1 with
/// the server's sentence and a *Try again* that calls again, the pair in both
/// themes and flush on a phone, the section's place in Contents, and the
/// head's jump landing on the Manuscript's own `?p=` anchor.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/echo.dart';
import 'package:flutter_app/pages/reader/echoes_panel.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/reader_page.dart'
    show readerContentsItems, readerSections;
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Each request, answered by [reply] — or held, when it returns a future the
/// test completes.
class _Server implements HttpClientAdapter {
  _Server(this.reply);
  Future<(int, Object)> Function(int n) reply;
  final List<(RequestOptions, Object?)> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object? body;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final part in requestStream) {
        bytes.addAll(part);
      }
      final text = utf8.decode(bytes);
      body = text.isEmpty ? null : jsonDecode(text);
    }
    sent.add((options, body));
    final (status, out) = await reply(sent.length);
    return ResponseBody.fromString(jsonEncode(out), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(
  String passageId,
  int passageIndex,
  String passageText,
  String echoId,
  String echoDoc,
  String echoText, {
  String? title = 'Another source',
  String type = 'article',
}) =>
    {
      'passage': {
        'chunkId': passageId,
        'chunkIndex': passageIndex,
        'excerpt': passageText,
      },
      'echo': {
        'chunkId': echoId,
        'chunkIndex': 7,
        'docId': echoDoc,
        'title': title,
        'type': type,
        'tagIds': ['t1'],
        'excerpt': echoText,
        'link': 'https://noteletter.com/reader/$echoDoc?p=$echoId',
      },
      'cosine': 0.6650,
    };

Map<String, dynamic> _answer(List<Map<String, dynamic>> rows,
        {int compared = 12, int passages = 12}) =>
    {
      'docId': 'd1',
      'echoes': rows,
      'count': rows.length,
      'compared': compared,
      'passages': passages,
    };

final _found = _answer([
  _row('c3', 2, 'The closer people feel to finishing, the harder they push.',
      'x9', 'd7', "That's the goal gradient effect at work.",
      title: "The UX Psychology Behind Apps People Can't Stop Using",
      type: 'youtube'),
  _row('c3', 2, 'The closer people feel to finishing, the harder they push.',
      'y1', 'd8', 'Progress that is visible pulls the reader on.',
      title: null, type: 'pdf'),
  _row('c5', 4, 'Streaks are a promise kept to yourself.', 'z2', 'd9',
      'A streak is a commitment device with a counter.'),
]);

void main() {
  late _Server server;
  late List<(String, String)> opened;
  late List<String> shown;

  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    opened = [];
    shown = [];
  });
  tearDown(ApiService.instance.resetTestSeams);

  void answer(Future<(int, Object)> Function(int n) reply) {
    server = _Server(reply);
    ApiService.instance.httpClientAdapter = server;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: EchoesPanel(
            docId: 'd1',
            onOpenEcho: (doc, chunk) => opened.add((doc, chunk)),
            onShowPassage: shown.add,
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  group('the model', () {
    test('consecutive rows of one passage share a head, and only consecutive '
        'ones', () {
      final rows = EchoesAnswer.fromJson(_answer([
        _row('a', 0, 'A', 'e1', 'd2', 'one'),
        _row('a', 0, 'A', 'e2', 'd3', 'two'),
        _row('b', 1, 'B', 'e3', 'd4', 'three'),
        _row('a', 0, 'A', 'e4', 'd5', 'four'),
      ])).echoes;
      final groups = echoGroups(rows);
      expect([for (final g in groups) g.passage.chunkId], ['a', 'b', 'a'],
          reason: 'the server order is the source order; regrouping across it '
              'would be a re-sort');
      expect([for (final g in groups) g.echoes.map((e) => e.chunkId).toList()],
          [
            ['e1', 'e2'],
            ['e3'],
            ['e4'],
          ]);
    });

    test('reads defensively, as the reference does', () {
      final a = EchoesAnswer.fromJson({'echoes': 'nope', 'compared': '3'});
      expect(a.echoes, isEmpty);
      expect(a.compared, 0);
      expect(a.passages, 0);
      expect(a.partial, isFalse);
      expect(
          EchoesAnswer.fromJson(_answer([], compared: 40, passages: 120))
              .partial,
          isTrue);
    });

    test('the sentences are the contract\'s', () {
      expect(echoesNothingClose,
          'Nothing elsewhere in your library is close to this yet.');
      expect(echoesNothingToCompare,
          'This source has no passages to compare yet.');
      expect(echoesStandfirst,
          'Passages in your other sources that say something close to this one.');
      expect(echoesComparedNote(40, 1200),
          'Compared 40 of this source’s 1,200 passages.');
      expect(echoReaderQuery('x9', 'd1'), 'p=x9&from=%2Freader%2Fd1');
    });
  });

  testWidgets('one call, POST {docId} with limit omitted; skeleton lines '
      'while it is out, never a sentence', (tester) async {
    final held = Completer<(int, Object)>();
    answer((_) => held.future);
    await pumpPanel(tester);

    expect(server.sent, hasLength(1));
    final (opts, body) = server.sent.single;
    expect(opts.method, 'POST');
    expect(opts.path, endsWith('/fn_find_echoes'));
    expect(body, {'docId': 'd1'}, reason: 'a closed key set: no null limit');
    expect(find.byType(KitSkeletonLines), findsOneWidget);
    expect(find.text(echoesStandfirst), findsOneWidget);
    expect(find.text(echoesNothingClose), findsNothing);
    expect(find.text(echoesNothingToCompare), findsNothing);

    held.complete((200, _found));
    await settle(tester);
    expect(find.byType(KitSkeletonLines), findsNothing);
    expect(server.sent, hasLength(1), reason: 'it never refetches on its own');
  });

  testWidgets('the rows: grouped under one head, the kind, Untitled, no '
      'figure, opens and shows by id', (tester) async {
    answer((_) async => (200, _found));
    await pumpPanel(tester);

    expect(find.text(echoesStandfirst), findsOneWidget);
    expect(find.byType(KitEchoPair), findsNWidgets(2),
        reason: 'two rows of one passage share a head');
    expect(find.text('¶ 3'), findsOneWidget);
    expect(find.text('¶ 5'), findsOneWidget);
    expect(find.text('YOUTUBE'), findsOneWidget);
    expect(find.text('DOCUMENT'), findsOneWidget, reason: "pdf's word");
    expect(find.text('WEB CLIP'), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget, reason: 'a null title');
    expect(find.textContaining('0.66'), findsNothing,
        reason: 'the cosine is not drawn');
    expect(find.textContaining('Compared'), findsNothing,
        reason: 'every passage was asked');

    await tester.tap(find.text("That's the goal gradient effect at work.",
        findRichText: true));
    await tester.pump();
    expect(opened, [('d7', 'x9')]);
    await tester.tap(find.text('A streak is a commitment device with a counter.',
        findRichText: true));
    await tester.pump();
    expect(opened.last, ('d9', 'z2'));
    expect(shown, isEmpty, reason: 'an echo opens; it does not show a passage');

    await tester.tap(find.text('¶ 5'));
    await tester.pump();
    expect(shown, ['c5'], reason: "the head shows this source's own passage");
    expect(opened, hasLength(2), reason: 'the head never navigates');
  });

  testWidgets('nothing to compare: the note alone, no standfirst',
      (tester) async {
    answer((_) async => (200, _answer([], compared: 0, passages: 0)));
    await pumpPanel(tester);
    expect(find.text(echoesNothingToCompare), findsOneWidget);
    expect(find.text(echoesStandfirst), findsNothing);
    expect(find.byType(KitEchoList), findsNothing);
  });

  testWidgets('nothing close: the standfirst, then the note', (tester) async {
    answer((_) async => (200, _answer([])));
    await pumpPanel(tester);
    expect(find.text(echoesStandfirst), findsOneWidget);
    expect(find.text(echoesNothingClose), findsOneWidget);
    expect(find.byType(KitEchoList), findsNothing);
  });

  testWidgets('a long source: the list, then how many were compared',
      (tester) async {
    answer((_) async => (200, {..._found, 'compared': 40, 'passages': 120}));
    await pumpPanel(tester);
    expect(find.byType(KitEchoPair), findsNWidgets(2));
    final note = find.text('Compared 40 of this source’s 120 passages.');
    expect(note, findsOneWidget);
    expect(tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.byType(KitEchoList)).dy - 1),
        reason: 'the note follows the list');
  });

  testWidgets('a failure is §14.1 with the server\'s sentence and its '
      'reference, and Try again calls again', (tester) async {
    answer((n) async => n == 1
        ? (
            500,
            {
              'error': 'Something failed on our side. Quote req-42 to support.',
              'errorCode': 'INTERNAL',
              'request_id': 'req-42',
            }
          )
        : (200, _found));
    await pumpPanel(tester);

    expect(find.byType(KitFailureBlock), findsOneWidget);
    expect(find.text(echoesFailed), findsOneWidget);
    expect(find.text('Something failed on our side. Quote req-42 to support.'),
        findsOneWidget,
        reason: "the server's sentence, verbatim");
    expect(find.textContaining('req-42', findRichText: true), findsWidgets);
    expect(find.text(echoesNothingClose), findsNothing,
        reason: 'a failure is never an empty state');

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(server.sent, hasLength(2), reason: 'Try again is the second call');
    expect(find.byType(KitFailureBlock), findsNothing);
    expect(find.byType(KitEchoPair), findsNWidgets(2));
  });

  testWidgets('the pair in both themes; indented on a desk, flush on a phone',
      (tester) async {
    for (final b in Brightness.values) {
      answer((_) async => (200, _found));
      await pumpPanel(tester, brightness: b);
      expect(tester.takeException(), isNull, reason: '$b');
      final t = b == Brightness.dark ? Tokens.dark : Tokens.light;
      final kind = tester.widget<Text>(find.text('YOUTUBE'));
      expect(kind.style?.color, t.accentText, reason: 'the kind is accent copy');
    }

    double indent() =>
        tester.getTopLeft(find.text('YOUTUBE')).dx -
        tester.getTopLeft(find.text('¶ 3')).dx;
    answer((_) async => (200, _found));
    await pumpPanel(tester);
    expect(indent(), closeTo(38, 0.5), reason: "under the head's text");
    answer((_) async => (200, _found));
    await pumpPanel(tester, size: const Size(390, 844));
    expect(indent(), closeTo(0, 0.5), reason: 'flush on a phone');
  });

  test('Echoes is third, and stays with generative AI off; its Contents row '
      'carries no count', () {
    expect([for (final (id, _) in readerSections) id], [
      'summary',
      'manuscript',
      'echoes',
      'speedread',
      'listen',
      'original',
      'history',
    ]);
    final doc = Document.fromJson('d1', {
      'user_id': 'u1',
      'title': 'A source',
      'type': 'web',
      'status': 'complete',
    });
    final off = readerContentsItems(doc, aiOn: false);
    expect(off.map((i) => i.id).take(2), ['manuscript', 'echoes']);
    expect(off.firstWhere((i) => i.id == 'echoes').count, isNull);
    expect(off.firstWhere((i) => i.id == 'echoes').label, 'Echoes');
  });

  group("the head's jump rides the Manuscript's ?p= anchor", () {
    setUp(() {
      FirestoreService.instance = FirestoreService.stub();
      ManuscriptPanel.debugPauseDwell = true;
    });
    tearDown(() {
      FirestoreService.resetInstance();
      ManuscriptPanel.debugPauseDwell = false;
    });

    testWidgets('scrolled to and flashed, each time it is asked',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jumps = PassageJumps();
      addTearDown(jumps.dispose);
      final long = List.filled(60, 'A sentence that takes up some room.')
          .join(' ');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManuscriptPanel(
              docId: 'doc-1',
              doc: Document.fromJson('doc-1', {
                'user_id': 'u1',
                'title': 'Twelve passages',
                'type': 'article',
                'status': 'complete',
              }),
              chunks: [
                for (var i = 0; i < 12; i++)
                  Chunk.fromJson({
                    'chunk_id': 'c$i',
                    'document_id': 'doc-1',
                    'chunk_index': i,
                    'text': 'Passage $i. $long',
                    'html': '<p>Passage $i. $long</p>',
                  }),
              ],
              onSaved: () async {},
              passageJumps: jumps,
            ),
          ),
        ),
      ));
      await tester.pump();
      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(pos.pixels, 0);

      // The jump is a 320 ms animation that starts on the frame after the
      // one that asked for it: step through it.
      Future<void> glide(WidgetTester tester) async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      bool flashing() => find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  Tokens.light.accentSoft)
          .evaluate()
          .isNotEmpty;

      jumps.show('c10');
      await glide(tester);
      expect(pos.pixels, greaterThan(400), reason: 'the passage came into view');
      expect(flashing(), isTrue, reason: 'and flashed, as ?p= does');
      await tester.pump(const Duration(milliseconds: 2400));
      expect(flashing(), isFalse, reason: 'a flash, not a state');

      // Asked again from the top: a request, not a state.
      pos.jumpTo(0);
      await tester.pump();
      jumps.show('c10');
      await glide(tester);
      expect(pos.pixels, greaterThan(400));
      await tester.pump(const Duration(milliseconds: 2700));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  });
}
