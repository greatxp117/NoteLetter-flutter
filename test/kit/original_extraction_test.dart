/// F-185 · Original shows the extraction beside the file (reader.md §Original;
/// component-kit §15.1 rule 3; web OriginalPanel.jsx).
///
/// The panel drew the stored file, or a button for a link, under a line that
/// said NoteLetter keeps the original "alongside the text it extracted" — and
/// then never showed that text. Web draws what was extracted under its own
/// eyebrow (*The page as we captured it* / *The document as we read it* /
/// *The article it resolved to*), the raw text collapsed where the render
/// above is not the text (a screenshot, a recipe), and for a link its poster.
/// The live embed is web's iframe; on a phone it is the provider's poster and
/// the Open on {host} button (CLAUDE.md §Composition deviations).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/original_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Raw implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode({'signed_url': null}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

Document _doc(Map<String, dynamic> extra) => Document.fromJson('d1', {
      'user_id': 'u1',
      'title': 'On Slowness',
      'status': 'complete',
      ...extra,
    });

Chunk _chunk(int i, String text, {String? html}) => Chunk.fromJson({
      'chunk_id': 'c$i',
      'document_id': 'd1',
      'chunk_index': i,
      'text': text,
      if (html != null) 'html': html,
    });

final _chunks = [
  _chunk(0, 'The first paragraph we read.',
      html: '<p>The first paragraph we read.</p>'),
  _chunk(1, 'A second, plainer one.'),
];

Future<void> _pump(WidgetTester tester, Document doc,
    {List<Chunk> chunks = const [], Size size = const Size(1200, 4000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: OriginalPanel(docId: doc.id, doc: doc, chunks: chunks),
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder _says(String s) => find.textContaining(s, findRichText: true);

void main() {
  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    ApiService.instance.httpClientAdapter = _Raw();
  });
  tearDown(ApiService.instance.resetTestSeams);

  testWidgets('a link: the page as we captured it, under web\'s intro',
      (tester) async {
    await _pump(
        tester,
        _doc({
          'type': 'article',
          'source_url': 'https://www.example.com/slowness',
        }),
        chunks: _chunks);
    expect(
        _says('This source came from a link — there is no uploaded file. '
            'Here is the source itself, and below it the page as NoteLetter '
            'captured it.'),
        findsOneWidget);
    expect(find.text('THE PAGE AS WE CAPTURED IT'), findsOneWidget);
    expect(_says('The first paragraph we read.'), findsOneWidget);
    expect(_says('A second, plainer one.'), findsOneWidget,
        reason: 'a chunk with no html is drawn from its text');
    expect(find.text('Open on example.com'), findsOneWidget);
    expect(find.textContaining('RAW EXTRACTED TEXT'), findsNothing,
        reason: 'raw text only where the render is not the text');
  });

  testWidgets('a file: the document as we read it, beside the file',
      (tester) async {
    await _pump(tester, _doc({'type': 'pdf', 'gcs_path': 'u1/d1/a.pdf'}),
        chunks: _chunks);
    expect(
        _says('The source exactly as it arrived. NoteLetter keeps the '
            'original file alongside the text it extracted.'),
        findsOneWidget);
    expect(find.text('THE DOCUMENT AS WE READ IT'), findsOneWidget);
    expect(_says('The first paragraph we read.'), findsOneWidget);
  });

  testWidgets('a screenshot: the article it resolved to, and its raw text '
      'collapsed', (tester) async {
    await _pump(
        tester,
        _doc({
          'type': 'article',
          'source_url': 'https://www.example.com/slowness',
          'source_image_url': 'https://img.example.com/shot.png',
        }),
        chunks: _chunks);
    expect(find.text('THE ARTICLE IT RESOLVED TO'), findsOneWidget);
    expect(_says('The first paragraph we read.'), findsOneWidget);
    final raw = find.textContaining('RAW EXTRACTED TEXT');
    expect(raw, findsOneWidget);
    expect(find.text('9 words'), findsOneWidget);
    // Collapsed: the stored text is not drawn until it is opened.
    expect(_says('The text of the resolved article, exactly as it was '
        'extracted and stored.'), findsNothing);
    await tester.tap(raw);
    await tester.pump();
    expect(_says('The text of the resolved article, exactly as it was '
        'extracted and stored.'), findsOneWidget);
  });

  testWidgets('a video link: the provider\'s poster in place of the embed',
      (tester) async {
    await _pump(
        tester,
        _doc({
          'type': 'youtube',
          'source_url': 'https://www.youtube.com/watch?v=abc123',
          'thumbnail_url': 'https://i.ytimg.com/vi/abc123/hq.jpg',
        }),
        chunks: _chunks);
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url ==
                'https://i.ytimg.com/vi/abc123/hq.jpg'),
        findsOneWidget);
    expect(find.byType(KitExtractionPreview), findsOneWidget);
  });

  testWidgets('a phone draws every part without overflow', (tester) async {
    await _pump(
        tester,
        _doc({
          'type': 'article',
          'source_url': 'https://www.example.com/slowness',
          'source_image_url': 'https://img.example.com/shot.png',
        }),
        chunks: _chunks,
        size: const Size(390, 4000));
    await tester.tap(find.textContaining('RAW EXTRACTED TEXT'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(KitExtractionPreview), findsOneWidget);
  });
}
