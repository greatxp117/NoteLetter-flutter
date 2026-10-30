import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// The Library's catalogue in direction D (screens/sources.md §Composition,
/// *The catalogue*; web `SourcesBrowse.jsx`, `kit/d/Catalogue.jsx`) — what
/// F-65's list · cards · shelf toggle guarded, moved to D's List / Grid:
///
/// * the choice is the app-wide `nl-source-view` (List by default; the pre-D
///   `nl-sources-view` is ignored), written BEFORE the listing moves, and a
///   stored choice is what the Library opens on;
/// * List is §32's register under the order's group heads — the month added,
///   the initial under A–Z (with a row of letters that jumps), one ranked run
///   under Most passages — and Grid is one wall of §33 covers;
/// * the Kind facet narrows by the covers' facets, and narrowed to nothing
///   the catalogue says so and offers every volume back.
///
/// The spine Shelf (§21), the source cards and the Type order are retired
/// with D; their cases went with them.

Document _doc(String id, String title,
        {String type = 'pdf', int? n = 3, int created = 1750000000000}) =>
    Document.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'type': type,
      'status': 'complete',
      'chunk_count': ?n,
      'created_at': created,
    });

final _oct = DateTime(2026, 10, 12).millisecondsSinceEpoch;
final _sep = DateTime(2026, 9, 3).millisecondsSinceEpoch;

final _docs = [
  _doc('d1', 'Quarterly Tax Summary', created: _oct, n: 2),
  _doc('d2', 'The Espresso Article', type: 'article', n: 5, created: _oct),
  _doc('d3', 'Sourdough Notes', type: 'plain', n: 1, created: _sep),
];

Future<void> _pump(WidgetTester tester, [List<Document>? docs]) async {
  tester.view.physicalSize = const Size(1280, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpSources(
      tester, SourcesStubService(documents: Stream.value(docs ?? _docs)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    LocalFlags.resetForTest();
    LocalFlags.sourceView.value = 'list';
  });

  testWidgets('List is the default — the register under month heads',
      (tester) async {
    SharedPreferences.setMockInitialValues({'nl-sources-view': 'cards'});
    await _pump(tester);
    expect(find.byType(KitLibRegister), findsOneWidget,
        reason: 'the pre-D nl-sources-view is ignored');
    expect(find.byType(KitRegisterRow), findsNWidgets(3));
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('2 volumes'), findsOneWidget);
    expect(find.text('1 volume'), findsOneWidget);
    expect(find.byType(KitLibWall), findsNothing);
    expect(find.byType(KitShelfView), findsNothing);
    expect(find.byType(KitSourceCard), findsNothing);
  });

  testWidgets('Grid is written under nl-source-view, then drawn',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.tap(find.text('Grid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nl-source-view'), 'grid');
    expect(find.byType(KitLibWall), findsOneWidget);
    expect(find.byType(KitCoverItem), findsNWidgets(3));
    expect(find.byType(KitRegisterRow), findsNothing);
    // Each cover names its home shelf, and a counted source its figure.
    expect(find.text('Unshelved'), findsNWidgets(3));
    expect(find.text('5 passages'), findsOneWidget);
  });

  testWidgets('a stored Grid is what the Library opens on', (tester) async {
    SharedPreferences.setMockInitialValues({'nl-source-view': 'grid'});
    await _pump(tester);
    expect(find.byType(KitLibWall), findsOneWidget);
  });

  testWidgets('an uncounted cover draws no figure (ADR-109)', (tester) async {
    SharedPreferences.setMockInitialValues({'nl-source-view': 'grid'});
    await _pump(tester, [_doc('u1', 'Never counted', n: null)]);
    expect(find.byType(KitCoverItem), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(KitCoverItem),
            matching: find.textContaining('passage')),
        findsNothing);
  });

  testWidgets('A–Z files under the title less a leading The, with jump letters',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.tap(find.text('A–Z'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitJumpLetters), findsOneWidget);
    // "The Espresso Article" files under E; Q and S hold the others.
    final rows = tester.widgetList<KitRegisterRow>(find.byType(KitRegisterRow));
    expect([for (final r in rows) r.doc.id], ['d2', 'd1', 'd3']);
    expect(find.text('October 2026'), findsNothing);
  });

  testWidgets('Most passages is one ranked run: 01, 02, 03', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.tap(find.text('Most passages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final rows = tester.widgetList<KitRegisterRow>(find.byType(KitRegisterRow));
    expect([for (final r in rows) r.doc.id], ['d2', 'd1', 'd3']);
    expect([for (final r in rows) r.lead], ['01', '02', '03']);
    expect(find.text('01'), findsOneWidget);
  });

  testWidgets('a kind narrows the catalogue and its meta says by how much',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    expect(find.text('3 VOLUMES'), findsOneWidget);
    await tester.tap(find.text('Web clips'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitRegisterRow), findsOneWidget);
    expect(find.text('1 OF 3 VOLUMES'), findsOneWidget);
  });

  testWidgets('a shelf narrows to its subtree, in tree order with its swatch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shelved = [
      Document.fromJson('s1', {
        'user_id': 'u1',
        'title': 'Cornbread',
        'type': 'youtube',
        'status': 'complete',
        'chunk_count': 1,
        'tag_ids': ['t-recipes'],
        'created_at': _oct,
      }),
      ..._docs,
    ];
    tester.view.physicalSize = const Size(1280, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSources(tester, SourcesStubService(documents: Stream.value(shelved)),
        shelves: const [
          Tag(id: 't-recipes', userId: 'u1', title: 'Recipes', color: 'red'),
          Tag(
              id: 't-baking',
              userId: 'u1',
              title: 'Baking',
              color: 'green',
              parentTagId: 't-recipes'),
        ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Every shelf'), findsOneWidget);
    // Tree order: the child under its parent.
    expect(tester.getTopLeft(find.text('Baking')).dy,
        greaterThan(tester.getTopLeft(find.text('Recipes').first).dy));
    // The folio counts the top-level shelves.
    expect(find.textContaining('4 VOLUMES · 1 SHELF'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(KitShelfFacet), matching: find.text('Recipes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitRegisterRow), findsOneWidget);

    // A sub-shelf holding nothing: narrowed to nothing, and the way back.
    await tester.tap(find.text('Baking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitRegisterRow), findsNothing);
    expect(find.text('No volumes match.'), findsOneWidget);
    await tester.tap(find.text('Show every volume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitRegisterRow), findsNWidgets(4));
  });

  testWidgets('reading: nothing complete, something arriving', (tester) async {
    SharedPreferences.setMockInitialValues({});
    KitPageTools.instance.reset();
    await _pump(tester, [
      Document.fromJson('p1', {
        'user_id': 'u1',
        'title': 'Arriving',
        'type': 'article',
        'status': 'processing',
        'processing_stage': 'embedding',
        'source_url': 'https://example.com/a',
        'created_at': _oct,
      }),
      Document.fromJson('e1', {
        'user_id': 'u1',
        'title': 'Refused',
        'type': 'pdf',
        'status': 'error',
        'error_message': 'The file is encrypted.',
        'gcs_path': 'uploads/u1/e1.pdf',
        'created_at': _oct,
      }),
    ]);
    // The page's tools reach the chrome: Add a source, Library settings.
    expect(KitPageTools.instance.action?.label, 'Add a source');
    expect(KitPageTools.instance.action?.short, 'Add');
    expect(KitPageTools.instance.settings?.label, 'Library settings');

    expect(find.textContaining('— VOLUMES'), findsNothing,
        reason: 'measured: the folio draws its figures');
    expect(find.textContaining('0 VOLUMES · 0 SHELVES'), findsOneWidget);
    expect(find.text('One volume is being read now. Each joins the catalogue '
        'as soon as its passages are indexed.'), findsOneWidget);
    expect(find.text('WHAT YOU CAN ADD'), findsOneWidget,
        reason: 'the sheet before anything is complete');
    expect(find.text('Being catalogued'), findsOneWidget);
    expect(find.text('1 INDEXING · 1 NEEDS YOU'), findsOneWidget);
    // The row that needs the reader leads, with its sentence and actions.
    final rows = tester.widgetList<ProcessingRow>(find.byType(ProcessingRow));
    expect([for (final r in rows) r.doc.id], ['e1', 'p1']);
    expect(find.text('The file is encrypted.'), findsOneWidget);
    expect(find.widgetWithText(KitLibAct, 'Retry'), findsOneWidget);
    expect(find.widgetWithText(KitLibAct, 'View file'), findsOneWidget);
    expect(find.widgetWithText(KitLibAct, 'Open the link'), findsOneWidget);
    expect(find.widgetWithText(KitLibAct, 'Cancel'), findsOneWidget);
    expect(find.text('EMBEDDING PASSAGES'), findsOneWidget);
    expect(find.text('Nothing has finished reading yet. Each volume joins the '
        'catalogue as soon as its passages are indexed.'), findsOneWidget);
    expect(find.byType(KitViewToggle), findsNothing,
        reason: 'no toggle over an empty listing');
    expect(find.text('Drop files to begin'), findsNothing);

    // Grid: the same rows arrive face-out, a failure stamped.
    await LocalFlags.setSourceView('grid');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(KitArrivalSlip), findsNWidgets(2));
    expect(find.text('COULDN’T BE READ'), findsOneWidget);
  });

  testWidgets('loading: skeleton lines, the dash, no sentence', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final never = StreamController<List<Document>>();
    addTearDown(never.close);
    await pumpSources(tester, SourcesStubService(documents: never.stream));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(KitSkeletonLines), findsNWidgets(2));
    expect(find.textContaining('— VOLUMES · — SHELVES'), findsOneWidget);
    expect(find.textContaining('Nothing here yet'), findsNothing);
    expect(find.text('Drop files to begin'), findsNothing);
  });

  for (final b in Brightness.values) {
    testWidgets('on a phone ($b): the running head says what is showing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSources(
          tester,
          SourcesStubService(
              documents: Stream.value([
            ..._docs,
            Document.fromJson('p1', {
              'user_id': 'u1',
              'title': 'A long title that will not fit on a phone line at all',
              'type': 'article',
              'status': 'error',
              'error_message': 'The page could not be read.',
              'source_url': 'https://example.com/a',
              'created_at': _oct,
            }),
          ])),
          dark: b == Brightness.dark);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // LibPeek: All volumes · RECENT · 3 — the line the dock folds to.
      final peek = find.byType(KitLibPeek);
      expect(peek, findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('All volumes')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('RECENT')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('3')),
          findsOneWidget);
      // A kind narrows it, and the peek counts the narrowing.
      await tester.tap(find.byKey(const ValueKey('d-peek')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: peek, matching: find.text('Notes')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('1 of 3')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
