import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/sources/browse_section.dart' show procSummary;
import 'package:flutter_app/pages/sources/source_facets.dart';
import 'package:flutter_app/pages/sources_page.dart' show librarySentence;
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The Library's D kit (F-141; screens/sources.md §Composition, web
/// `SourcesBrowse.jsx`, `kit/d/Catalogue.jsx`, `pages/sources/intake.jsx`,
/// `proc.jsx`): the facet table in BOTH directions (a bucket nothing
/// enumerates is a bucket that vanishes), identical to web's `SRC_KINDS`; the
/// catalogue's order and groups; the library sentence; and every new part
/// pumped in both themes with the behaviour its required parts name.

Document _doc(
  String id, {
  String title = 'On the Shortness of Life',
  String type = 'pdf',
  String status = 'complete',
  int? chunks = 12,
  int views = 0,
  String? author,
  int? created,
  int? stallsAt,
}) => Document.fromJson(id, {
  'user_id': 'u1',
  'title': title,
  'type': type,
  'status': status,
  'chunk_count': ?chunks,
  'view_count': views,
  'author': ?author,
  'created_at': created ?? DateTime(2026, 10, 30).millisecondsSinceEpoch,
  'processing_stalls_at': ?stallsAt,
});

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    LocalFlags.sourceView.value = 'list';
  });

  Future<void> pumpBoth(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 900),
    void Function(Brightness b)? check,
  }) async {
    for (final b in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'threw in $b');
      check?.call(b);
    }
  }

  // ── The facet table ───────────────────────────────────────────────────────
  group('the Kind facet table', () {
    test('every type the kind map knows is held by exactly one facet', () {
      for (final type in kKindByType.keys) {
        final holders = [
          for (final f in kSourceFacets)
            if ((f.types ?? const []).contains(type)) f.id,
        ];
        expect(holders, hasLength(1), reason: '`$type` is held by $holders');
      }
    });

    test('every type a facet names is one a document can carry', () {
      for (final f in kSourceFacets) {
        for (final t in f.types ?? const <String>[]) {
          expect(kKindByType.containsKey(t), isTrue,
              reason: '${f.id} names `$t`, which no document can carry');
        }
      }
      // All and Unread are not kinds: they hold no types.
      expect(kSourceFacets.first.id, 'all');
      expect(kSourceFacets.first.types, isNull);
      expect(kSourceFacets.last.id, 'unread');
      expect(kSourceFacets.last.types, isNull);
    });

    test('ids, labels and types are web\'s SRC_KINDS, in its order', () {
      final web = File('../NoteLetter-web/src/pages/SourcesBrowse.jsx');
      expect(web.existsSync(), isTrue, reason: 'SourcesBrowse.jsx moved');
      final body = RegExp(r'export const SRC_KINDS = \[(.*?)\];', dotAll: true)
          .firstMatch(web.readAsStringSync())!
          .group(1)!;
      final rows = RegExp(
              r"\{ id: '([a-z_]+)',\s*label: '([^']+)'(?:,\s*types: \[([^\]]*)\])? \}")
          .allMatches(body)
          .map((m) => (
                m.group(1)!,
                m.group(2)!,
                m.group(3) == null
                    ? null
                    : RegExp(r"'([a-z_]+)'")
                        .allMatches(m.group(3)!)
                        .map((t) => t.group(1)!)
                        .toList(),
              ))
          .toList();
      expect(rows, hasLength(kSourceFacets.length));
      for (var i = 0; i < rows.length; i++) {
        expect(kSourceFacets[i].id, rows[i].$1);
        expect(kSourceFacets[i].label, rows[i].$2);
        expect(kSourceFacets[i].types, rows[i].$3);
      }
    });

    test('a type no release has heard of falls through its kind, then Notes',
        () {
      expect(sourceFacetOf('docx'), 'pdf');
      expect(sourceFacetOf('image_set'), 'image');
      expect(sourceFacetOf('audio'), 'podcast');
      expect(sourceFacetOf('social_video'), 'video');
      expect(sourceFacetOf('hologram'), 'note',
          reason: 'kitDocKind defaults to note, a facet');
    });

    test('what you can add: both size rows, 100 MB and 2 GB', () {
      expect(kAddable, [
        ('Files', 'PDF, EPUB, Word, slides, Markdown, images, audio, video'),
        ('Each up to', '100 MB'),
        ('A video up to', '2 GB'),
        ('Links', 'Articles, videos, podcasts'),
      ]);
    });
  });

  // ── The catalogue's order and groups ─────────────────────────────────────
  group('the catalogue', () {
    final oct = DateTime(2026, 10, 2).millisecondsSinceEpoch;
    final sep = DateTime(2026, 9, 9).millisecondsSinceEpoch;
    final a = _doc('a', title: 'The Library of Babel', chunks: 3, created: sep);
    final b = _doc('b', title: 'An Atlas', chunks: 9, created: oct);
    final c = _doc('c', title: '1984 notes', chunks: null, created: oct);
    final d = _doc('d', title: 'Zeno', chunks: 3, created: sep);

    test('A–Z files under the title less a leading The, A or An', () {
      expect(kitSortKey('The Library of Babel'), 'Library of Babel');
      expect(kitSortKey('An Atlas'), 'Atlas');
      expect(kitSortKey('A Room'), 'Room');
      expect(kitSortKey('Theory'), 'Theory');
      expect([for (final v in kitSortSources([a, b, c, d], 'title')) v.id],
          ['c', 'b', 'a', 'd']);
    });

    test('Most passages: a count never taken sorts as none; ties keep order',
        () {
      expect([for (final v in kitSortSources([a, b, c, d], 'passages')) v.id],
          ['b', 'a', 'd', 'c']);
    });

    test('Recent: newest first, stable', () {
      expect([for (final v in kitSortSources([a, b, c, d], 'recent')) v.id],
          ['b', 'c', 'a', 'd']);
    });

    test('groups follow the order: month, initial (# for a digit), one run',
        () {
      final months = kitGroupSources(kitSortSources([a, b, c, d], 'recent'),
          'recent');
      expect([for (final g in months) g.label],
          ['October 2026', 'September 2026']);
      final letters =
          kitGroupSources(kitSortSources([a, b, c, d], 'title'), 'title');
      expect([for (final g in letters) g.key], ['#', 'A', 'L', 'Z']);
      final run = kitGroupSources([a, b], 'passages');
      expect(run, hasLength(1));
      expect(run.single.label, isNull);
      expect([for (final s in kSorts) s.$2], ['Recent', 'A–Z', 'Most passages']);
    });
  });

  // ── The library sentence and the pipeline's meta ──────────────────────────
  group('sentences', () {
    test('the standfirst, in each of its cases', () {
      expect(
          librarySentence(volumes: 0, passages: 0, unread: 0, incoming: 0),
          'Nothing here yet. Add a file, paste a link, or connect a service, '
          'and each source is read and indexed as it arrives.');
      expect(
          librarySentence(volumes: 0, passages: 0, unread: 0, incoming: 2),
          'Two volumes are being read now. Each joins the catalogue as soon as '
          'its passages are indexed.');
      expect(
          librarySentence(volumes: 7, passages: 15, unread: 6, incoming: 2),
          '15 passages from seven volumes, indexed and searchable. Six are '
          'still unread, and two more are being read now.');
      expect(
          librarySentence(volumes: 1, passages: 1, unread: 0, incoming: 0),
          '1 passage from one volume, indexed and searchable.');
      expect(
          librarySentence(volumes: 13, passages: 1200, unread: 1, incoming: 0),
          '1,200 passages from 13 volumes, indexed and searchable. One is '
          'still unread.');
    });

    test('Being catalogued\'s meta splits off what needs you (stalls too)', () {
      final now = DateTime(2026, 10, 30, 12);
      final stalled = _doc('s',
          status: 'processing',
          stallsAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch);
      expect(procSummary([_doc('p', status: 'processing')], now), '1 indexing');
      expect(
          procSummary([
            _doc('p', status: 'processing'),
            _doc('e', status: 'error'),
            stalled,
          ], now),
          '1 indexing · 2 need you');
      expect(procSummary([_doc('e', status: 'skipped')], now),
          '0 indexing · 1 needs you');
    });
  });

  // ── The parts, in both themes ─────────────────────────────────────────────
  group('parts', () {
    testWidgets('a notice: its sentence on a rule, and Dismiss', (tester) async {
      var dismissed = 0;
      await pumpBoth(
        tester,
        Column(children: [
          KitLibNotices(children: [
            const KitLibNotice('Finishing the Google Drive connection…',
                status: true),
            KitLibNotice('Access to Notion was declined.',
                warn: true, onDismiss: () => dismissed++),
          ]),
        ]),
        check: (_) {
          expect(find.text('Finishing the Google Drive connection…'),
              findsOneWidget);
          expect(find.text('Dismiss'), findsOneWidget);
        },
      );
      await tester.tap(find.text('Dismiss'));
      expect(dismissed, 1);
      // An empty strip takes no room.
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: KitLibNotices(children: []))));
      expect(tester.getSize(find.byType(KitLibNotices)).height, 0);
    });

    testWidgets('a service row: plate, name, Connected or its line, one action',
        (tester) async {
      var pressed = 0;
      await pumpBoth(
        tester,
        Column(children: [
          KitServiceList(rows: [
            KitServiceRow(
              provider: 'notion',
              name: 'Notion',
              line: 'Pages & databases',
              action: KitLibAct('Connect', strong: true, onTap: () => pressed++),
            ),
            const KitServiceRow(
              provider: 'google_drive',
              name: 'Google Drive',
              line: 'Docs, PDFs, slides',
              connected: true,
              action: KitLibAct('Disconnect'),
              failure: KitFailureInline('The sign-in link did not come back.',
                  dense: true),
            ),
            const KitServiceRow(
              glyph: Icons.photo_camera_outlined,
              name: 'Camera roll',
              line: 'The camera roll stopped',
              critical: true,
              action: KitLibAct('Settings'),
            ),
          ]),
        ]),
        check: (_) {
          expect(find.text('Pages & databases'), findsOneWidget);
          expect(find.text('Connected'), findsOneWidget);
          expect(find.text('Docs, PDFs, slides'), findsNothing,
              reason: 'connected says so, not its line');
          expect(find.byType(KitProviderLogo), findsNWidgets(2));
          expect(find.byType(KitFailureInline), findsOneWidget);
        },
      );
      await tester.tap(find.text('Connect'));
      expect(pressed, 1);
      // A held action does nothing.
      await tester.tap(find.text('Disconnect'));
    });

    testWidgets('an action waits with its m:ss and is held', (tester) async {
      var pressed = 0;
      await pumpBoth(
        tester,
        KitLibAct('Retry', strong: true, wait: 240, onTap: () => pressed++),
        check: (_) => expect(find.text('Retry · 4:00'), findsOneWidget),
      );
      await tester.tap(find.text('Retry · 4:00'));
      expect(pressed, 0, reason: 'a waiting control is held');
    });

    for (final width in const [1280.0, 390.0]) {
      testWidgets('a processing row and an attention row at $width',
          (tester) async {
        await pumpBoth(
          tester,
          Column(children: const [
            KitLibProcRow(
              word: 'Web clip',
              title: 'The Commonplace Book',
              stage: KitLibStage('Embedding passages', tone: KitProcTone.work),
              bar: KitLibBar(live: true),
              actions: KitLibActs(children: [
                KitLibAct('Open the link'),
                KitLibAct('Cancel'),
              ]),
            ),
            KitLibProcRow(
              word: 'Document',
              title: 'Quarterly Tax Summary',
              stage: KitLibStage('Error', tone: KitProcTone.fail),
              attention: true,
              message: 'No readable text was found. Retry, or remove this source.',
              refusal: KitFailureInline('Retry limit reached.', dense: true),
              actions: KitLibActs(children: [
                KitLibAct('Retry', strong: true),
                KitLibAct('Remove'),
                KitLibAct('View file'),
              ]),
            ),
            KitLibProcRow(
              word: 'Image',
              title: 'Uploading',
              stage: KitLibStage('Uploading · 42%', tone: KitProcTone.work),
              bar: KitLibBar(value: 0.42),
            ),
          ]),
          size: Size(width, 900),
          check: (_) {
            expect(find.text('WEB CLIP'), findsOneWidget);
            expect(find.text('EMBEDDING PASSAGES'), findsOneWidget);
            expect(find.text('ERROR'), findsOneWidget);
            expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget,
                reason: 'fail carries the alert glyph');
            expect(find.text('UPLOADING · 42%'), findsOneWidget);
            expect(find.byType(KitStageBar), findsNWidgets(2),
                reason: 'an attention row draws no bar');
          },
        );
      });
    }

    testWidgets('an arrival: a ruled slip with its stamp', (tester) async {
      await pumpBoth(
        tester,
        const KitLibGrid(top: 10, children: [
          KitArrivalSlip(
            word: 'Document',
            title: 'Quarterly Tax Summary',
            author: 'IRS',
            stage: KitLibStage('Error', tone: KitProcTone.fail),
            stamp: 'Couldn’t be read',
            attention: true,
            message: 'No readable text was found.',
            actions: KitLibActs(tight: true, children: [KitLibAct('Remove')]),
          ),
          KitArrivalSlip(
            word: 'Web clip',
            title: 'The Commonplace Book',
            stage: KitLibStage('Queued', tone: KitProcTone.wait),
            bar: KitLibBar(),
          ),
        ]),
        check: (_) {
          expect(find.text('COULDN’T BE READ'), findsOneWidget);
          expect(find.text('IRS'), findsOneWidget);
          expect(find.text('QUEUED'), findsOneWidget);
        },
      );
    });

    testWidgets('the Shelf facet: Every shelf, then tree order; the chosen row '
        'does nothing when pressed', (tester) async {
      final picked = <String?>[];
      await pumpBoth(
        tester,
        SizedBox(
          width: 300,
          child: KitShelfFacet(
            total: 7,
            value: null,
            onChanged: picked.add,
            items: const [
              KitShelfFacetItem('r', 'Recipes', count: 2),
              KitShelfFacetItem('b', 'Baking', depth: 1, count: 0),
            ],
          ),
        ),
        check: (_) {
          expect(find.text('SHELF'), findsOneWidget);
          expect(find.text('Every shelf'), findsOneWidget);
          final baking = tester.widget<Text>(find.text('Baking'));
          expect(baking.style?.fontStyle, FontStyle.italic,
              reason: 'a nested shelf is italic');
        },
      );
      await tester.tap(find.text('Every shelf'));
      expect(picked, isEmpty, reason: 'pressing the chosen row does nothing');
      await tester.tap(find.text('Baking'));
      expect(picked, ['b']);
      // Absent with no shelves.
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: KitShelfFacet(
                  total: 0, value: null, onChanged: (_) {}, items: const []))));
      expect(find.text('SHELF'), findsNothing);
    });

    testWidgets('jump letters: a letter with no volumes is held', (tester) async {
      final jumped = <String>[];
      await pumpBoth(
        tester,
        KitJumpLetters(have: const {'C', 'K'}, onJump: jumped.add),
      );
      await tester.tap(find.text('A'));
      await tester.tap(find.text('K'));
      expect(jumped, ['K']);
    });

    testWidgets('the register: the rank leads under Most passages; A–Z files '
        'under its letters', (tester) async {
      final docs = [
        _doc('x', title: 'The Zebra', chunks: 9),
        _doc('y', title: 'Apples', chunks: 4),
      ];
      await pumpBoth(
        tester,
        KitLibRegister(items: docs, sort: 'passages'),
        check: (_) {
          expect(find.text('01'), findsOneWidget);
          expect(find.text('02'), findsOneWidget);
        },
      );
      await pumpBoth(
        tester,
        KitLibRegister(items: kitSortSources(docs, 'title'), sort: 'title'),
        check: (_) {
          expect(find.byType(KitJumpLetters), findsOneWidget);
          // The group letters, beside the jump row's own.
          expect(find.text('Z'), findsNWidgets(2));
          expect(find.text('A'), findsNWidgets(2));
        },
      );
    });

    testWidgets('the wall: covers with their shelf and figure', (tester) async {
      await pumpBoth(
        tester,
        KitLibWall(items: [
          _doc('w1', title: 'Counted', chunks: 1),
          _doc('w2', title: 'Never counted', chunks: null),
        ]),
        check: (_) {
          expect(find.byType(KitCoverItem), findsNWidgets(2));
          expect(find.text('Unshelved'), findsNWidgets(2));
          expect(find.text('1 passage'), findsOneWidget);
          expect(find.textContaining('passages'), findsNothing,
              reason: 'an uncounted cover draws no figure (ADR-109)');
        },
      );
    });

    testWidgets('the peek, the order switch, the drop card, the link field',
        (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var sent = 0;
      var picked = '';
      await pumpBoth(
        tester,
        SizedBox(
          width: 320,
          child: Column(children: [
            const KitLibPeek(
                icon: Icons.tune,
                title: 'Web clips',
                meta: 'Recipes · Recent',
                count: '3',
                tail: ' of 7'),
            KitLibOrder(
                options: kSorts,
                value: 'recent',
                onChanged: (v) => picked = v),
            KitDropCard(
              icon: Icons.upload,
              title: 'Drop files to begin',
              sub: 'or tap to browse — PDF, EPUB, Word, slides, Markdown, '
                  'images, audio, video',
              onTap: () {},
            ),
            KitLibLinkField(
                controller: controller,
                focusNode: focus,
                onSubmit: () => sent++),
            const KitRefusedNotices(children: [
              KitRefusedNotice(
                  name: 'main.py',
                  reason: 'Source code files aren’t supported (.py).'),
            ]),
          ]),
        ),
        check: (_) {
          expect(find.text('RECIPES · RECENT'), findsOneWidget);
          expect(find.text('ORDER'), findsOneWidget);
          expect(find.text('Most passages'), findsOneWidget);
        },
      );
      await tester.tap(find.text('Add link'));
      expect(sent, 0, reason: 'held on an empty field');
      await tester.enterText(find.byType(TextField), 'example.com/a');
      await tester.pump();
      await tester.tap(find.text('Add link'));
      expect(sent, 1);
      await tester.tap(find.text('A–Z'));
      expect(picked, 'title');
    });
  });
}
