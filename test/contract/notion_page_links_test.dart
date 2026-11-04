/// A link to a Notion page that is in the library opens it there (5.58.0,
/// ADR-212; `screens/reader.md` §A link to a Notion page in the library) —
/// web `tests/contract/notion-page-links.test.js`, case for case where this
/// client has the same surface.
///
/// The page's import jobs say which document it is; the manuscript looks its
/// links up when drawn and redraws each resolved one as a link into the
/// Reader. `fake_cloud_firestore` cannot resolve against this SDK, so the two
/// reads are answered at their seams ([FirestoreService.notionImportJobs] and
/// [FirestoreService.getDocument]) the way the rules and the jobs collection
/// answer, and the REAL rule (`resolveNotionPages`) runs over them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/notion_links.dart';
import 'package:flutter_app/shared/reader_origin.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

final String _sub = 'a' * 32;
final String _other = 'b' * 32;

/// The jobs collection, the documents the rules let u1 read, and every jobs
/// query the client sent (its uid and its dashed ids).
class _Reads extends FirestoreService {
  _Reads() : super.stub();

  List<Map<String, dynamic>> jobs = [];

  /// The owner of each document a `get` can read; one absent is gone, and
  /// the rules refuse a read of a document that is gone.
  Map<String, String> owners = {};
  bool jobsFail = false;
  final List<(String, List<String>)> queries = [];
  final List<String> docReads = [];

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Map<String, dynamic>>> notionImportJobs(
      String uid, List<String> providerFileIds) async {
    queries.add((uid, List.of(providerFileIds)));
    if (jobsFail) throw StateError('Missing or insufficient permissions.');
    return [
      for (final j in jobs)
        if (j['user_id'] == uid && providerFileIds.contains(j['provider_file_id']))
          j,
    ];
  }

  @override
  Future<Document?> getDocument(String docId) async {
    docReads.add(docId);
    final owner = owners[docId];
    if (owner == null) {
      throw StateError('Missing or insufficient permissions.');
    }
    return Document.fromJson(
        docId, {'user_id': owner, 'title': docId, 'status': 'complete'});
  }

  @override
  Future<List<String>> logChunksRead(
          String documentId, List<String> chunkIds) async =>
      const [];
}

Map<String, dynamic> _job(String page, String? doc,
        {int created = 1000, Map<String, dynamic> extra = const {}}) =>
    {
      'user_id': 'u1',
      'provider': 'notion',
      'provider_file_id': dashedNotionId(page),
      'document_id': doc,
      'status': 'complete',
      'created_at': Timestamp.fromMillisecondsSinceEpoch(created),
      ...extra,
    };

/// Every fn_update_content body the panel sent.
class _Saves implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Chunk _chunk(String id, int index, String html) => Chunk.fromJson({
      'chunk_id': id,
      'document_id': 'parent',
      'chunk_index': index,
      'text': html_parser.parseFragment(html).text,
      'html': html,
    });

String _a(String href, String text) =>
    '<a href="$href" target="_blank" rel="noopener noreferrer">$text</a>';

List<Chunk> _manuscript() => [
      _chunk(
          'c1',
          0,
          '<p>See ${_a('https://www.notion.so/$_sub', 'The sub-page')}, '
              '${_a('https://www.notion.so/$_other', 'Not imported')} and '
              '${_a('https://www.notion.so/$_sub#$_other', 'A PDF')}.</p>'),
      _chunk('c2', 1, '<p>A plain passage.</p>'),
    ];

void main() {
  late _Reads reads;
  late List<String> opened;
  late List<String> outside;

  setUp(() {
    reads = _Reads();
    FirestoreService.instance = reads;
    opened = [];
    outside = [];
    ManuscriptPanel.debugPauseDwell = true;
  });
  tearDown(() {
    FirestoreService.resetInstance();
    ManuscriptPanel.debugPauseDwell = false;
  });

  group('which links are Notion page links', () {
    test('reads the page id from the address the renderer writes, and from '
        'a titled one', () {
      expect(notionPageId('https://www.notion.so/$_sub'), _sub);
      expect(notionPageId('https://notion.so/${_sub.toUpperCase()}'), _sub);
      expect(notionPageId('https://www.notion.so/team/My-Page-$_sub'), _sub);
      expect(notionPageId('https://www.notion.so/$_sub?pvs=4'), _sub);
    });

    test('leaves a block inside a page, another host and a non-page alone',
        () {
      // A Notion-hosted file (ADR-210) is a block inside a page.
      expect(notionPageId('https://www.notion.so/$_sub#$_other'), isNull);
      expect(notionPageId('https://example.com/$_sub'), isNull);
      expect(notionPageId('https://www.notion.so/pricing'), isNull);
      expect(notionPageId('https://www.notion.so/${_sub.substring(1)}'), isNull);
      expect(notionPageId('not a url'), isNull);
      expect(notionPageId(null), isNull);
    });

    test('collects the distinct pages a set of passages links to', () {
      final html = [
        '<p><a href="https://www.notion.so/$_sub">Sub</a> and '
            '<a href="https://www.notion.so/$_sub">again</a></p>',
        '<p><a href="https://www.notion.so/$_other?a=1&amp;b=2">Other</a> '
            '<a href="https://www.notion.so/$_sub#$_other">A PDF</a></p>',
      ];
      expect(notionPageIdsIn(html)..sort(), [_sub, _other]);
    });

    test('the dashed form is the one the jobs store', () {
      expect(dashedNotionId('0123456789abcdef0123456789abcdef'),
          '01234567-89ab-cdef-0123-456789abcdef');
    });
  });

  group('the lookup (resolveNotionPages)', () {
    test("asks the reader's own import jobs, by the dashed page id, 30 to a "
        'query', () async {
      final ids = [for (var i = 0; i < 35; i++) i.toRadixString(16).padLeft(32, '0')];
      await reads.resolveNotionPages(ids);
      expect(reads.queries, hasLength(2));
      expect(reads.queries[0].$1, 'u1');
      expect(reads.queries[0].$2,
          [for (final id in ids.sublist(0, 30)) dashedNotionId(id)]);
      expect(reads.queries[1].$2, hasLength(5));
    });

    test("takes the newest row whose document is still the reader's, never "
        'a duplicate marker', () async {
      reads.jobs = [
        _job(_sub, 'old-copy', created: 1000),
        _job(_sub, 'deleted-copy', created: 3000),
        _job(_sub, 'kept-elsewhere',
            created: 4000, extra: {'skip_reason': 'duplicate'}),
        _job(_sub, null, created: 5000, extra: {'status': 'error'}),
      ];
      reads.owners = {'old-copy': 'u1'};
      final m = await reads.resolveNotionPages([_sub, _other]);
      expect(m, {_sub: 'old-copy'});
      expect(reads.docReads, ['deleted-copy', 'old-copy']);
    });

    test('reads no document the documents subscription already holds',
        () async {
      reads.jobs = [_job(_sub, 'held-doc')];
      final m = await reads.resolveNotionPages([_sub], held: {'held-doc'});
      expect(m[_sub], 'held-doc');
      expect(reads.docReads, isEmpty);
    });

    test('a document of someone else is not the page', () async {
      reads.jobs = [_job(_sub, 'theirs')];
      reads.owners = {'theirs': 'u2'};
      expect(await reads.resolveNotionPages([_sub]), isEmpty);
    });
  });

  group('the manuscript (reader.md §A link to a Notion page in the library)',
      () {
    Future<void> mount(WidgetTester tester, List<Chunk> chunks,
        {bool canOpen = true}) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManuscriptPanel(
              docId: 'parent',
              doc: Document.fromJson('parent', {
                'user_id': 'u1',
                'title': 'A Notion page',
                'type': 'plain',
                'status': 'complete',
              }),
              chunks: chunks,
              onSaved: () async {},
              onOpenLink: outside.add,
              onOpenSource: canOpen ? opened.add : null,
              heldDocIds: const {'sub-doc'},
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    }

    /// The HTML the manuscript DRAWS, every passage.
    String drawn(WidgetTester tester) =>
        [for (final h in tester.widgetList<Html>(find.byType(Html))) h.data]
            .join();

    /// The drawn anchor whose text is [text].
    Map<Object, String> anchor(WidgetTester tester, String text) =>
        html_parser
            .parseFragment(drawn(tester))
            .querySelectorAll('a')
            .firstWhere((a) => a.text == text)
            .attributes;

    /// Tap the link span drawn as [text].
    void tapLink(WidgetTester tester, String text) {
      TapGestureRecognizer? hit;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((span) {
          if (span is TextSpan &&
              span.text == text &&
              span.recognizer is TapGestureRecognizer) {
            hit = span.recognizer! as TapGestureRecognizer;
            return false;
          }
          return true;
        });
        if (hit != null) break;
      }
      expect(hit, isNotNull, reason: '"$text" is drawn as a link');
      hit!.onTap!();
    }

    testWidgets('draws a resolved link into the Reader, and leaves the others '
        'as written', (tester) async {
      reads.jobs = [_job(_sub, 'sub-doc')];
      await mount(tester, _manuscript());

      final into = anchor(tester, 'The sub-page');
      expect(into['href'], '/reader/sub-doc');
      expect(into['data-nl-doc'], 'sub-doc');
      expect(into.containsKey('target'), isFalse);
      final notion = anchor(tester, 'Not imported');
      expect(notion['href'], 'https://www.notion.so/$_other');
      expect(notion['target'], '_blank');
      expect(anchor(tester, 'A PDF')['href'],
          'https://www.notion.so/$_sub#$_other');
      expect(reads.docReads, isEmpty, reason: 'the shell holds sub-doc');
      await unmount(tester);
    });

    testWidgets('a tap on a resolved link opens the source in the Reader; '
        'any other opens outside the app, as written', (tester) async {
      reads.jobs = [_job(_sub, 'sub-doc')];
      await mount(tester, _manuscript());

      tapLink(tester, 'The sub-page');
      expect(opened, ['sub-doc']);
      expect(outside, isEmpty);
      tapLink(tester, 'Not imported');
      tapLink(tester, 'A PDF');
      expect(outside, [
        'https://www.notion.so/$_other',
        'https://www.notion.so/$_sub#$_other',
      ]);
      expect(opened, ['sub-doc']);
      await unmount(tester);
    });

    testWidgets("editing shows, and a save stores, Notion's address",
        (tester) async {
      ApiService.instance.tokenProvider = () async => 'test-token';
      final saves = _Saves();
      ApiService.instance.httpClientAdapter = saves;
      addTearDown(ApiService.instance.resetTestSeams);
      reads.jobs = [_job(_sub, 'sub-doc')];
      await mount(tester, _manuscript());
      expect(anchor(tester, 'The sub-page')['href'], '/reader/sub-doc');

      await tester.tap(find.text('Edit text'));
      await tester.pump();
      expect(drawn(tester), isNot(contains('/reader/')),
          reason: 'editing is not reading: nothing is redrawn');
      await tester.enterText(find.byType(TextField).last, 'An edited passage.');
      await tester.tap(find.text('Done & save'));
      // The token, the request and the reload are futures and Dio's timers.
      for (var i = 0; i < 10 && saves.sent.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final body = saves.sent.single.data as Map;
      final first = ((body['chunks'] as List).first as Map)['html'] as String;
      expect(first, contains('href="https://www.notion.so/$_sub"'));
      expect(first, isNot(contains('/reader/')));
      expect(first, isNot(contains('data-nl-doc')));
      await unmount(tester);
    });

    testWidgets('a failed lookup leaves every link as written, and is logged',
        (tester) async {
      reads.jobsFail = true;
      final logged = <String>[];
      final was = debugPrint;
      // Restored in the body: flutter_test checks debugPrint before any
      // teardown runs.
      debugPrint = (m, {wrapWidth}) => logged.add(m ?? '');
      try {
        await mount(tester, _manuscript());
      } finally {
        debugPrint = was;
      }

      expect(logged.where((l) => l.contains('Notion page links could not')),
          hasLength(1));
      expect(drawn(tester), isNot(contains('/reader/')));
      expect(anchor(tester, 'The sub-page')['target'], '_blank');
      tapLink(tester, 'The sub-page');
      expect(outside, ['https://www.notion.so/$_sub']);
      expect(opened, isEmpty);
      await unmount(tester);
    });

    testWidgets('a manuscript with no Notion page link reads nothing',
        (tester) async {
      await mount(tester, [
        _chunk('c', 0,
            '<p>${_a('https://www.notion.so/$_sub#$_other', 'A PDF')} and '
            '${_a('https://example.com/$_sub', 'Elsewhere')}</p>'),
      ]);
      expect(reads.queries, isEmpty);
      await unmount(tester);
    });

    testWidgets('the same pages are looked up once, however often the '
        'passages are redrawn', (tester) async {
      reads.jobs = [_job(_sub, 'sub-doc')];
      await mount(tester, _manuscript());
      // A refold (a dwell write, a reload) hands the panel new chunks that
      // link the same pages.
      await mount(tester, _manuscript());
      expect(reads.queries, hasLength(1));
      expect(anchor(tester, 'The sub-page')['href'], '/reader/sub-doc');
      await unmount(tester);
    });

    testWidgets('where nothing can open a source, nothing is looked up',
        (tester) async {
      reads.jobs = [_job(_sub, 'sub-doc')];
      await mount(tester, _manuscript(), canOpen: false);
      expect(reads.queries, isEmpty);
      expect(anchor(tester, 'The sub-page')['href'],
          'https://www.notion.so/$_sub');
      await unmount(tester);
    });
  });

  group('the way back from a source opened from another (ADR-101 + ADR-212)',
      () {
    test('is named by that source, and by "Source" when the title is not held',
        () {
      final docs = [
        Document.fromJson('parent', {'user_id': 'u1', 'title': 'A Notion page'}),
      ];
      final named = readerOrigin('/reader/parent', documents: docs);
      expect((named.label, named.path), ('A Notion page', '/reader/parent'));
      final gone = readerOrigin('/reader/gone', documents: docs);
      expect((gone.label, gone.path), ('Source', '/reader/gone'));
    });

    test('the Reader pushes the source with its own address as the way back',
        () {
      // ReaderPage builds notifiers that reach Firebase, which no widget test
      // here has (leave_guard_test records the same split), so the wiring is
      // read from the source; the device test drives it.
      final src = File('lib/pages/reader_page.dart').readAsStringSync();
      expect(
          src,
          matches(RegExp(r"onOpenSource: \(docId\) => context\.push\("
              r"KitSourceLink\.readerHref\(\s*docId,\s*"
              r"'from=\$\{Uri\.encodeComponent\('/reader/\$\{widget\.docId\}'\)\}'\)\)")));
      expect(src, contains('documents: context.watch<DocumentsNotifier>().documents'));
    });
  });
}
