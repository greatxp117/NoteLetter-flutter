import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/cohesive_reading.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/search_result.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/search_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Search in direction D (F-143; screens/search.md §Composition (direction
/// D), web `SearchView.jsx`): the masthead's folio, title and standfirst in
/// every state; the page's own field at both widths; the *Filters* sheet; a
/// result row's anatomy, opened and folded in place; and the failure block
/// and the empty register as two different renderings.

// ── Doubles ─────────────────────────────────────────────────────────────────

/// Every read Search makes, answered by the test.
class _Reads extends FirestoreService {
  _Reads({this.docs, this.tags = const [], this.context, this.failContext})
      : super.stub();

  /// Null: a documents read that never answers (the folio's dash).
  final List<Document>? docs;
  final List<Tag> tags;
  final List<Chunk>? context;
  final String? failContext;
  int contextReads = 0;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      docs == null ? const Stream.empty() : Stream.value(docs!);

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(tags);

  @override
  Future<List<Chunk>> getChunkContext(String chunkId) async {
    contextReads++;
    if (failContext != null) throw StateError(failContext!);
    return context ?? const [];
  }
}

/// The search notifier as the test says the server answered.
class _Search extends SearchNotifier {
  List<SearchResult> next = const [];
  String? fail;
  List<SearchResult> _shown = const [];
  String? _err;
  int searches = 0;
  List<String>? lastTypes;
  int syntheses = 0;

  @override
  List<SearchResult> get results => _shown;
  @override
  bool get isLoading => false;
  @override
  String? get error => _err;
  @override
  String? get requestId => _err == null ? null : '13225b79';

  @override
  Future<void> search(String query,
      {List<String>? sourceTypes, int limit = 10}) async {
    searches++;
    lastTypes = sourceTypes;
    _shown = fail == null ? next : const [];
    _err = fail;
    notifyListeners();
  }

  @override
  Future<void> synthesize(String query,
      {List<String>? sourceTypes, String breadth = 'normal'}) async {
    syntheses++;
  }

  @override
  void clear() {
    _shown = const [];
    _err = null;
    super.clear();
  }
}

SearchResult _result(
  String id, {
  String title = 'Quarterly Tax Summary',
  String type = 'pdf',
  String text = 'Quarter | Invoice total Q2 | \$1,200',
  double score = 0.85,
  int index = 2,
  List<String> tags = const ['t-fin'],
}) =>
    SearchResult.fromJson({
      'chunk': {
        'chunk_id': id,
        'document_id': 'doc-$id',
        'chunk_index': index,
        'text': text,
        'source_type': type,
      },
      'document': {
        'user_id': 'u1',
        'title': title,
        'type': type,
        'status': 'complete',
        'tag_ids': tags,
      },
      'score': score,
      'cosine': 0.9,
      'source_priority': 0.5,
      'source_priority_set': false,
    });

Chunk _chunk(String id, int index, String text) => Chunk.fromJson({
      'chunk_id': id,
      'document_id': 'doc-c1',
      'chunk_index': index,
      'text': text,
    });

Document _doc(String id, int chunks) => Document(
      id: id,
      userId: 'u1',
      title: 'A volume',
      type: 'pdf',
      status: DocumentStatus.complete,
      chunkCount: chunks,
      viewCount: 1,
      tagIds: const [],
    );

const _fin = Tag(id: 't-fin', userId: 'u1', title: 'Finance', color: 'ink-300');

const _phone = Size(402, 874);
const _wide = Size(1280, 900);

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Search search,
  _Reads reads, {
  Size size = _wide,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = reads;
  addTearDown(FirestoreService.resetInstance);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SearchNotifier>.value(value: search),
        ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
        ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: const Scaffold(body: SearchPage()),
      ),
    ),
  );
  await _frames(tester);
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _frames(tester);
}

/// The folio as the masthead draws it: caps, the separator's no-break space.
String _folio(String s) => kitFolioText(s).toUpperCase();

const _idle = 'Ask in plain language. Your library is searched by meaning, so '
    'the words do not have to match.';

/// The bundled faces, so a width is a real width: the test font draws every
/// glyph as a full em box, and the sheet's switches would overflow a sheet
/// they fit on a device.
Future<void> _loadFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
  });

  // ── The masthead's sentences ──────────────────────────────────────────────
  group('the folio', () {
    test('the library\'s passages, with separators; the dash while unread', () {
      expect(searchFolio(15), 'Search · 15 passages · by meaning');
      expect(searchFolio(1), 'Search · 1 passage · by meaning');
      expect(searchFolio(12400), 'Search · 12,400 passages · by meaning');
      expect(searchFolio(null), 'Search · — passages · by meaning');
    });
  });

  group('the standfirst', () {
    test('no query, searching, results in words, figures above twelve, failed',
        () {
      expect(searchStand(asked: false), _idle);
      expect(searchStand(asked: true, loading: true), 'Searching…');
      expect(searchStand(asked: true, count: 7),
          'Seven passages, ranked by meaning.');
      expect(searchStand(asked: true, count: 12),
          'Twelve passages, ranked by meaning.');
      expect(searchStand(asked: true, count: 1),
          'One passage, ranked by meaning.');
      expect(searchStand(asked: true, count: 13),
          '13 passages, ranked by meaning.');
      expect(searchStand(asked: true, failed: true),
          'Search is unavailable right now.');
    });

    test('cohesive: arranging, arranged, could not be built', () {
      final reading = CohesiveReading.fromJson({
        'query': 'q',
        'breadth': 'broad',
        'pool': 20,
        'kept': 9,
        'sections': const [],
      });
      expect(searchStand(asked: true, cohesive: true, cohesiveLoading: true),
          'Arranging the passages into one reading…');
      expect(searchStand(asked: true, cohesive: true, reading: reading),
          '9 of 20 passages, arranged as one reading · broader.');
      expect(searchStand(asked: true, cohesive: true, cohesiveFailed: true),
          'The cohesive reading could not be built.');
      expect(
          searchStand(asked: true, count: 3, cohesive: true),
          'Three passages, ranked by meaning.',
          reason: 'the passages stand until the reading lands');
    });

    test('a citation', () {
      expect(searchStand(asked: true, citationRef: 'John 3:16',
          scriptureLoading: true), 'Reading John 3:16…');
      expect(searchStand(asked: true, citationRef: 'John 3:16',
          scriptureReference: 'John 3:16'), 'John 3:16, verse by verse.');
      expect(searchStand(asked: true, citationRef: 'John 3:16',
          scriptureFailed: true), 'John 3:16 could not be looked up.');
      expect(searchStand(asked: true, citationRef: 'John 3:16'),
          'Not a citation.');
    });
  });

  test('the Kind facet is web\'s FILTERS, All sources first', () {
    expect(searchKinds, const [
      ('all', 'All sources'),
      ('pdf', 'Books & PDFs'),
      ('note', 'My notes'),
      ('web', 'Web'),
      ('youtube', 'YouTube'),
      ('instagram', 'Instagram'),
      ('tiktok', 'TikTok'),
      ('podcast', 'Audio'),
      ('video', 'Video'),
    ]);
  });

  // ── The page ──────────────────────────────────────────────────────────────
  for (final size in [_phone, _wide]) {
    final w = size.width.toInt();
    for (final b in Brightness.values) {
      testWidgets('$w ${b.name}: folio, title, idle standfirst, Try searching '
          'for', (tester) async {
        await _pump(tester, _Search(), _Reads(docs: [_doc('a', 9), _doc('b', 6)]),
            size: size, brightness: b);
        expect(tester.takeException(), isNull);
        expect(find.text(_folio('Search · 15 passages · by meaning')),
            findsOneWidget);
        expect(find.text('Search'), findsOneWidget);
        expect(find.text(_idle), findsOneWidget);
        expect(find.text('Try searching for'), findsOneWidget);
        expect(find.text('Notes on habit formation'), findsOneWidget);
        expect(find.text('→'), findsNWidgets(4));
        expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
        expect(find.text('Ask your library in plain language…'), findsOneWidget);
      });
    }
  }

  testWidgets('the folio says the dash while the documents read is out',
      (tester) async {
    await _pump(tester, _Search(), _Reads());
    expect(find.text(_folio('Search · — passages · by meaning')),
        findsOneWidget);
  });

  testWidgets('wide: the field stands in the rail, beside the folio, above '
      'the title', (tester) async {
    await _pump(tester, _Search(), _Reads(docs: const []));
    final field = tester.getRect(find.byKey(const ValueKey('search-field')));
    final title = tester.getRect(find.text('Search'));
    final folio = tester.getRect(
        find.text(_folio('Search · 0 passages · by meaning')));
    expect(field.bottom, lessThan(title.top));
    expect(field.left, greaterThan(folio.right));
    expect(field.height, 44);
  });

  testWidgets('phone: the field stands under the standfirst, above the rule',
      (tester) async {
    await _pump(tester, _Search(), _Reads(docs: const []), size: _phone);
    final field = tester.getRect(find.byKey(const ValueKey('search-field')));
    final stand = tester.getRect(find.text(_idle));
    final title = tester.getRect(find.text('Search'));
    final head = tester.getRect(find.text('Try searching for'));
    expect(field.top, greaterThanOrEqualTo(stand.bottom + 18 - 0.5));
    expect(field.bottom, lessThan(head.top));
    expect(title.bottom, lessThan(field.top));
    expect(field.width, closeTo(402 - 36, 0.5), reason: 'the column\'s width');
  });

  testWidgets('the clear control is there only while the field holds text, '
      'and clears the search', (tester) async {
    final search = _Search()..next = [_result('c1')];
    await _pump(tester, search, _Reads(docs: const []));
    expect(find.bySemanticsLabel('Clear the search'), findsNothing);
    await _ask(tester, 'budget');
    expect(find.text('Quarterly Tax Summary'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear the search'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-clear')));
    await _frames(tester);
    expect(find.text(_idle), findsOneWidget);
    expect(find.text('Try searching for'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear the search'), findsNothing);
  });

  testWidgets('a suggestion runs that search', (tester) async {
    final search = _Search()..next = [_result('c1')];
    await _pump(tester, search, _Reads(docs: const []));
    await tester.tap(find.text('Ideas about systems thinking'));
    await _frames(tester);
    expect(search.searches, 1);
    expect(find.text('One passage, ranked by meaning.'), findsOneWidget);
  });

  group('Filters', () {
    testWidgets('Kind, then Read as over its note; Breadth only while '
        'Cohesive', (tester) async {
      await _pump(tester, _Search(), _Reads(docs: const []));
      expect(find.text('KIND'), findsOneWidget);
      expect(find.byType(KitFacet), findsOneWidget);
      for (final (_, label) in searchKinds) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
          tester.getRect(find.text('All sources')).top,
          lessThan(tester.getRect(find.text('Books & PDFs')).top));
      // shellAiOn is true today (F-144 wires the setting): Read as is drawn.
      expect(find.text('READ AS'), findsOneWidget);
      expect(find.text('Passages'), findsOneWidget);
      expect(find.text('Cohesive'), findsOneWidget);
      expect(find.text('Each passage on its own, the closest first.'),
          findsOneWidget);
      expect(find.text('BREADTH'), findsNothing);

      await tester.tap(find.text('Cohesive'));
      await _frames(tester);
      expect(find.text('BREADTH'), findsOneWidget);
      for (final l in ['Tighter', 'Normal', 'Broader']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.text('The passages arranged into sections, each one '
          'verbatim.'), findsOneWidget);
    });

    testWidgets('choosing a kind re-runs the search with its types, the fold '
        'included', (tester) async {
      final search = _Search()..next = [_result('c1')];
      await _pump(tester, search, _Reads(docs: const []));
      await _ask(tester, 'budget');
      expect(search.searches, 1);
      expect(search.lastTypes, isNull, reason: 'All sources sends none');
      await tester.tap(find.text('Books & PDFs'));
      await _frames(tester);
      expect(search.searches, 2);
      expect(search.lastTypes, unorderedEquals(searchSourceTypes('pdf')));
      expect(search.lastTypes, containsAll(['pdf', 'epub']));
    });

    testWidgets('phone: the running head says the kind, the mode and the '
        'measured count', (tester) async {
      final search = _Search()..next = [_result('c1'), _result('c2')];
      await _pump(tester, search, _Reads(docs: const []), size: _phone);
      final peek = find.byKey(const ValueKey('d-peek'));
      expect(peek, findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('All sources')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('PASSAGES')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.byIcon(Icons.tune)),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('2')), findsNothing,
          reason: 'no count before anything was measured');
      await _ask(tester, 'budget');
      expect(find.descendant(of: peek, matching: find.text('2')),
          findsOneWidget);
    });
  });

  group('a result', () {
    testWidgets('its anatomy: rank, title, kind label, shelf, score, the '
        'marked passage, the two links', (tester) async {
      final search = _Search()..next = [_result('c1'), _result('c2',
          title: 'Pasta Fundamentals', type: 'article', score: 0.1, tags: [])];
      await _pump(tester, search, _Reads(docs: const [], tags: [_fin]));
      await _ask(tester, 'budget');
      expect(find.text('Two passages, ranked by meaning.'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text(kitTypeLabel('pdf').toUpperCase()), findsOneWidget);
      expect(find.text(kitTypeLabel('article').toUpperCase()), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget,
          reason: 'the first row\'s shelf; the second has none');
      expect(find.text('0.85'), findsOneWidget);
      expect(find.text('0.10'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsNWidgets(2),
          reason: 'Open source wears the book');
      expect(find.text('Read it in context'), findsNWidgets(2));
      final mark = find.byKey(const ValueKey('search-passage-1'));
      final rich = tester.widget<RichText>(
          find.descendant(of: mark, matching: find.byType(RichText)).first);
      // `visitChildren` only visits spans that carry text; the mark is a span
      // of spans, so the tree is walked by hand.
      bool marks(InlineSpan span) =>
          span.style?.backgroundColor != null ||
          (span is TextSpan && (span.children ?? const []).any(marks));
      final marked = marks(rich.text);
      expect(marked, isTrue,
          reason: 'the matched passage is marked (--highlight)');
    });

    testWidgets('opens in place among its neighbours; one row at a time; '
        'folds', (tester) async {
      final search = _Search()
        ..next = [_result('c1', text: 'The matched passage.'), _result('c2')];
      final reads = _Reads(docs: const [], context: [
        _chunk('c0', 1, 'The passage before it.'),
        _chunk('c1', 2, 'The matched passage.'),
        _chunk('c9', 3, 'The passage after it.'),
      ]);
      await _pump(tester, search, reads);
      await _ask(tester, 'budget');
      expect(reads.contextReads, 0,
          reason: 'nothing is read for a row nobody opened (INV-03b)');
      expect(find.text('The passage before it.', findRichText: true),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('search-toggle-1')));
      await _frames(tester);
      expect(reads.contextReads, 1);
      expect(find.text('Fold it away'), findsOneWidget);
      expect(find.text('The passage before it.', findRichText: true),
          findsOneWidget);
      expect(find.text('The passage after it.', findRichText: true),
          findsOneWidget);
      final before = tester.getRect(
          find.text('The passage before it.', findRichText: true));
      final match = tester.getRect(find.byKey(const ValueKey('search-passage-1')));
      expect(before.bottom, lessThanOrEqualTo(match.top));

      // The second row's title opens it and folds the first.
      await tester.tap(find.byKey(const ValueKey('search-title-2')));
      await _frames(tester);
      expect(find.text('Fold it away'), findsOneWidget);
      expect(find.text('Read it in context'), findsOneWidget);
      expect(reads.contextReads, 2);

      await tester.tap(find.text('Fold it away'));
      await _frames(tester);
      expect(find.text('Fold it away'), findsNothing);
      expect(find.text('Read it in context'), findsNWidgets(2));
    });

    testWidgets('a failed context read is a line under it, the passage kept',
        (tester) async {
      final search = _Search()..next = [_result('c1', text: 'Kept.')];
      final reads = _Reads(docs: const [], failContext: 'permission-denied');
      await _pump(tester, search, reads);
      await _ask(tester, 'budget');
      await tester.tap(find.byKey(const ValueKey('search-toggle-1')));
      await _frames(tester);
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(
          find.textContaining('The surrounding passages could not be loaded — '),
          findsOneWidget);
      expect(find.text('Kept.', findRichText: true), findsOneWidget);
    });
  });

  group('failure is not no results', () {
    for (final size in [_phone, _wide]) {
      for (final b in Brightness.values) {
        testWidgets('${size.width.toInt()} ${b.name}', (tester) async {
          final failing = _Search()..fail = 'Search failed. Contact support.';
          await _pump(tester, failing, _Reads(docs: const []),
              size: size, brightness: b);
          await _ask(tester, 'budget');
          expect(tester.takeException(), isNull);
          expect(find.text('Search is unavailable right now.'), findsNWidgets(2),
              reason: 'the standfirst, and the block\'s naming line');
          expect(find.byType(KitFailureBlock), findsOneWidget);
          expect(find.text('Try again'), findsOneWidget);
          expect(find.textContaining('No passages found'), findsNothing);
          await tester.tap(find.text('Try again'));
          await _frames(tester);
          expect(failing.searches, 2);

          final empty = _Search();
          await _pump(tester, empty, _Reads(docs: const []),
              size: size, brightness: b);
          await _ask(tester, 'budget');
          expect(find.text('No passages, ranked by meaning.'), findsOneWidget);
          expect(
              find.text('No passages found. Try a broader phrase, or ask '
                  'your library.'),
              findsOneWidget);
          expect(find.byType(KitFailureBlock), findsNothing);
          expect(find.text('Search is unavailable right now.'), findsNothing);
        });
      }
    }
  });
}
