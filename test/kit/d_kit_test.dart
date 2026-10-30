import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Direction D's kit (component-kit §26–§42, §1.2's compact rail and Reader's
/// card, §13 in D) — every part pumped in BOTH themes, and the behaviour each
/// part's required parts name: the running head opens and folds three ways,
/// the panel closes three ways, the page's tools reach the chrome and leave
/// with the page, a switch moves only when its value moves, List / Grid writes
/// before it moves, a count never taken is an empty cell, and a refused
/// activity read is the dash, never 0. The covers are `d_covers_test.dart`.

Document _doc(
  String id, {
  String title = 'On the Shortness of Life',
  String type = 'pdf',
  String status = 'complete',
  int? chunks = 12,
  int views = 0,
  String? author = 'Seneca',
  String? stage,
}) => Document.fromJson(id, {
  'user_id': 'u1',
  'title': title,
  'type': type,
  'status': status,
  'chunk_count': ?chunks,
  'view_count': views,
  'author': ?author,
  'processing_stage': ?stage,
  'created_at': DateTime(2026, 10, 30).millisecondsSinceEpoch,
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
    bool scroll = true,
  }) async {
    for (final b in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: scroll ? SingleChildScrollView(child: child) : child,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'threw in $b');
    }
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(390, 844),
    Brightness b = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: home,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // ── §26 masthead ──────────────────────────────────────────────────────────
  group('§26 masthead', () {
    for (final size in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets(
        'folio, accent clause, standfirst, double rule at ${size.width}',
        (tester) async {
          await pumpBoth(
            tester,
            const KitMasthead(
              folio: '§ Library · 41 sources',
              title: 'Good evening, *reader*',
              stand: 'Everything you have added, in the order it arrived.',
            ),
            size: size,
          );
          expect(find.text('§ LIBRARY · 41 SOURCES'), findsOneWidget);
          final rich = tester.widget<RichText>(
            find.byWidgetPredicate(
              (w) =>
                  w is RichText &&
                  w.text.toPlainText() == 'Good evening, reader',
            ),
          );
          TextSpan? em;
          rich.text.visitChildren((s) {
            if (s is TextSpan && s.text == 'reader') em = s;
            return true;
          });
          expect(
            em!.style!.fontStyle,
            FontStyle.italic,
            reason: 'the *clause* is the accent italic',
          );
          expect(
            find.text('Everything you have added, in the order it arrived.'),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('a crumb: the back control names where it returns', (
      tester,
    ) async {
      var back = 0;
      await pumpBoth(
        tester,
        KitMasthead(
          folio: '§ A source',
          title: 'Meditations',
          back: KitDBackControl(
            'Library',
            onTap: () => back++,
            separator: true,
          ),
        ),
      );
      expect(find.text('LIBRARY'), findsOneWidget);
      await tester.tap(find.text('LIBRARY'));
      expect(back, 1);
      expect(
        tester.getSize(find.byType(KitDBackControl)).height,
        greaterThanOrEqualTo(44),
        reason: '§39: a 44px hit area',
      );
    });
  });

  // ── §27 / §28 / §30: the page's tools reach the chrome ─────────────────────
  group('§27 the one toolbar and its registration', () {
    Widget page({KitPageAction? action, KitPageSettings? settings}) => KitDPage(
      folio: '§ Letters',
      title: 'Letters',
      action: action,
      settings: settings,
      child: const SizedBox(height: 400, child: Text('column')),
    );

    // F-142's device holds: going from Home (inner shell) to the source page
    // (outer shell), Home re-registered AFTER the source page and then
    // disposed — and the chrome was left with no tools at all.
    test('the leaving page cannot take the arriving page\'s tools with it',
        () {
      final tools = KitPageTools.instance;
      final home = Object(), reader = Object();
      KitSettingsHandle h(String l) => KitSettingsHandle(
          label: l, open: false, held: false, has: const [],
          toggle: () {}, show: () {});
      tools.register(home, null, h('Letter settings'));
      tools.register(reader, null, h('Source details'));
      tools.register(home, null, h('Letter settings')); // the transition
      expect(tools.settings?.label, 'Letter settings');
      tools.clear(home);
      expect(tools.settings?.label, 'Source details',
          reason: 'the page still mounted takes the chrome back');
      tools.clear(reader);
      expect(tools.settings, isNull);
      expect(tools.action, isNull);
    });

    testWidgets('wide: Search, the action, the gear in the masthead rail', (
      tester,
    ) async {
      var added = 0;
      await pumpBoth(
        tester,
        page(
          action: KitPageAction(
            label: 'Write a letter',
            short: 'Write',
            onPressed: () => added++,
          ),
          settings: KitPageSettings(
            label: 'Letter settings',
            body: (_, _) => const Text('body'),
          ),
        ),
        scroll: false,
      );
      expect(find.byType(KitSearchField), findsOneWidget);
      expect(find.text('Write a letter'), findsOneWidget);
      expect(find.bySemanticsLabel('Letter settings'), findsOneWidget);
      await tester.tap(find.text('Write a letter'));
      expect(added, 1);
    });

    testWidgets(
      'at 1024 and under the rail keeps its folio; the tab bar draws the '
      "page's short label and calls its LATEST handler",
      (tester) async {
        var calls = <String>[];
        await pumpApp(
          tester,
          Scaffold(
            body: page(
              action: KitPageAction(
                label: 'Write a letter',
                short: 'Write',
                onPressed: () => calls.add('page'),
              ),
            ),
            bottomNavigationBar: KitTabBar(
              route: '/letters',
              onGo: (_) {},
              onAdd: () => calls.add('add'),
              aiOn: true,
            ),
          ),
        );
        expect(
          find.byType(KitSearchField),
          findsNothing,
          reason: 'the tools leave the rail at 1024 and under',
        );
        expect(find.text('Write'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('d-tab-action')));
        expect(calls, ['page']);
      },
    );

    testWidgets(
      'a page with no action leaves the default Add; unmount clears',
      (tester) async {
        final calls = <String>[];
        final show = ValueNotifier(true);
        await pumpApp(
          tester,
          Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, on, _) => on
                  ? page(
                      action: KitPageAction(
                        label: 'Write a letter',
                        short: 'Write',
                        onPressed: () => calls.add('page'),
                      ),
                    )
                  : const Text('no page'),
            ),
            bottomNavigationBar: KitTabBar(
              route: '/',
              onGo: (_) {},
              onAdd: () => calls.add('add'),
            ),
          ),
        );
        expect(find.text('Write'), findsOneWidget);
        show.value = false;
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Add'),
          findsOneWidget,
          reason: 'a page that unmounts takes its tools with it',
        );
        await tester.tap(find.byKey(const ValueKey('d-tab-action')));
        expect(calls, ['add']);
      },
    );

    testWidgets('a disabled action is held at the centre and does nothing', (
      tester,
    ) async {
      var n = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: page(
            action: KitPageAction(
              label: 'Ask',
              disabled: true,
              onPressed: () => n++,
            ),
          ),
          bottomNavigationBar: KitTabBar(
            route: '/',
            onGo: (_) {},
            onAdd: () => n += 10,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('d-tab-action')));
      expect(n, 0);
      final op = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('d-tab-action')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(op.opacity, lessThan(1));
    });

    testWidgets(
      "the header's gear opens the panel from the header; Escape, the scrim "
      'and Close each close it',
      (tester) async {
        await pumpApp(
          tester,
          Scaffold(
            appBar: KitAppHeader(onMenu: () {}, onSearch: () {}),
            body: page(
              settings: KitPageSettings(
                label: 'Letter settings',
                body: (_, close) => Column(
                  children: [
                    const KitDLabel('Scheduled delivery', top: 18),
                    const Text('panel body'),
                  ],
                ),
              ),
            ),
          ),
        );
        Future<void> open() async {
          await tester.tap(find.bySemanticsLabel('Letter settings').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('panel body'), findsOneWidget);
        }

        await open();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.text('panel body'), findsNothing, reason: 'Escape closes');

        await open();
        await tester.tapAt(const Offset(195, 700));
        await tester.pump();
        expect(
          find.text('panel body'),
          findsNothing,
          reason: 'the scrim closes',
        );

        await open();
        await tester.tap(find.byKey(const ValueKey('d-panel-close')));
        await tester.pump();
        expect(find.text('panel body'), findsNothing, reason: 'Close closes');
      },
    );

    testWidgets(
      "an open panel's scrim covers the tab bar too, and a tap on it closes",
      (tester) async {
        await pumpApp(
          tester,
          Scaffold(
            appBar: KitAppHeader(onMenu: () {}, onSearch: () {}),
            body: page(
              settings: KitPageSettings(
                label: 'Letter settings',
                body: (_, _) => const Text('panel body'),
              ),
            ),
            bottomNavigationBar: KitTabBar(
              route: '/',
              onGo: (_) {},
              onAdd: () {},
            ),
          ),
        );
        final scrim = find.byKey(const ValueKey('d-tabbar-scrim'));
        expect(scrim, findsNothing);
        await tester.tap(find.bySemanticsLabel('Letter settings').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(scrim.hitTestable(), findsOneWidget);
        await tester.tap(scrim);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('panel body'), findsNothing);
        expect(
          scrim.hitTestable(),
          findsNothing,
          reason: 'faded out and no longer takes taps',
        );
      },
    );

    testWidgets('openSettings(topic) opens only where the panel covers it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Scaffold(
          body: page(
            settings: KitPageSettings(
              label: 'Letter settings',
              has: const ['letter'],
              body: (_, _) => const Text('panel body'),
            ),
          ),
        ),
        size: const Size(1280, 900),
      );
      expect(KitPageTools.instance.openSettings('study'), isFalse);
      expect(KitPageTools.instance.openSettings('letter'), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('panel body'), findsOneWidget);
    });
  });

  // ── §29 / §30: the sheet and the running head ─────────────────────────────
  group('§29 sheet, §30 running head', () {
    const items = [
      KitContentsItem('recent', 'Recently added', count: '12'),
      KitContentsItem('shelves', 'The shelves'),
    ];

    Widget page(KitSections sec) => KitDPage(
      folio: '§ Home',
      title: 'Good evening, *reader*',
      sections: sec,
      sheet: KitDSheet(
        label: 'On this page',
        foldOnPick: true,
        peek: KitSecPeek(items: items, sections: sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(items: items, sections: sec),
            const KitFigures(rows: [('Sources', '41'), ('Unread', '—')]),
            KitSheetAlso(
              children: [
                KitAlsoButton(
                  'Open the map',
                  icon: Icons.map_outlined,
                  onTap: () {},
                ),
                KitAlsoButton('Delete', onTap: () {}, danger: true),
              ],
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitSecHead(key: sec.keyOf('recent'), n: 0, title: 'Recently added'),
          const SizedBox(height: 900),
          KitSecHead(key: sec.keyOf('shelves'), n: 1, title: 'The shelves'),
          const SizedBox(height: 900),
        ],
      ),
    );

    for (final size in const [Size(1280, 900), Size(820, 900)]) {
      testWidgets('the sheet beside (or above) the column at ${size.width}', (
        tester,
      ) async {
        final sec = KitSections(['recent', 'shelves']);
        await pumpBoth(tester, page(sec), size: size, scroll: false);
        expect(find.bySemanticsLabel('On this page'), findsOneWidget);
        expect(find.text('Recently added'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('d-peek')), findsNothing);
      });
    }

    testWidgets('Contents jumps the page to its section and marks it current', (
      tester,
    ) async {
      final sec = KitSections(['recent', 'shelves']);
      await pumpApp(
        tester,
        Scaffold(body: page(sec)),
        size: const Size(1280, 900),
      );
      expect(sec.current, 'recent');
      await tester.tap(find.bySemanticsLabel('II The shelves'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(sec.current, 'shelves');
    });

    testWidgets(
      'phone: one line under the header; it drops and folds by the line, the '
      'scrim, Escape and a picked row; folded, its body is inert',
      (tester) async {
        final sec = KitSections(['recent', 'shelves']);
        for (final b in Brightness.values) {
          await pumpApp(tester, Scaffold(body: page(sec)), b: b);
          final peek = find.byKey(const ValueKey('d-peek'));
          expect(peek, findsOneWidget);
          expect(tester.getSize(peek).height, greaterThanOrEqualTo(46));
          expect(
            find.textContaining('1 of 2', findRichText: true),
            findsOneWidget,
            reason: '§ I · … · 1 of 2',
          );

          Future<void> drop() async {
            await tester.tap(peek);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.bySemanticsLabel('II The shelves'), findsOneWidget);
          }

          expect(
            find.bySemanticsLabel('II The shelves'),
            findsNothing,
            reason: 'folded, the body is inert',
          );
          await drop();
          await tester.tap(peek);
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.bySemanticsLabel('II The shelves'),
            findsNothing,
            reason: 'the line folds it',
          );

          await drop();
          await tester.tap(
            find.byKey(const ValueKey('d-dock-scrim')),
            warnIfMissed: false,
          );
          await tester.tapAt(const Offset(195, 800));
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.bySemanticsLabel('II The shelves'),
            findsNothing,
            reason: 'the scrim folds it',
          );

          await drop();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.bySemanticsLabel('II The shelves'),
            findsNothing,
            reason: 'Escape folds it',
          );

          await drop();
          await tester.tap(find.bySemanticsLabel('II The shelves'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            find.bySemanticsLabel('II The shelves'),
            findsNothing,
            reason: 'a row the page names folds it',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('the Facet: one chosen, a held choice, lines when stacked', (
      tester,
    ) async {
      String? picked;
      await pumpBoth(
        tester,
        SizedBox(
          width: 300,
          child: KitFacet(
            label: 'Kind',
            value: 'all',
            onChanged: (v) => picked = v,
            items: const [
              KitFacetItem('all', 'All', count: '41'),
              KitFacetItem('pdf', 'Documents', count: '12'),
              KitFacetItem('epub', 'Books', disabled: true),
            ],
          ),
        ),
      );
      await tester.tap(find.text('All'));
      expect(picked, isNull, reason: 'pressing the chosen one does nothing');
      await tester.tap(find.text('Documents'));
      expect(picked, 'pdf');
      picked = null;
      await tester.tap(find.text('Books'), warnIfMissed: false);
      expect(picked, isNull, reason: 'a held choice does nothing');
    });

    testWidgets('FigurePeek leaves out an unmeasured figure, never 0', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const KitFigurePeek(items: [('41', 'sources'), (null, 'shelves')]),
      );
      final t = tester.widget<RichText>(find.byType(RichText).last);
      expect(t.text.toPlainText(), '41 sources');
    });
  });

  // ── §31 heads ─────────────────────────────────────────────────────────────
  group('§31 section heads', () {
    testWidgets('SectionHead (and small), SecHead, in both themes', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          children: [
            KitSectionHead(
              'The shelves',
              meta: '6 shelves',
              actions: [const Text('Open shelf →')],
            ),
            const KitSectionHead('Recently added', small: true),
            const KitSecHead(n: 0, title: 'Passages'),
            const KitSecHead(n: 2, title: 'Notes'),
          ],
        ),
      );
      expect(find.text('6 SHELVES'), findsOneWidget);
      expect(find.text('§ I'), findsOneWidget);
      expect(find.text('§ III'), findsOneWidget);
    });
  });

  // ── §32 / §34 / §35 listings ──────────────────────────────────────────────
  group('§34 sliding switch', () {
    testWidgets(
      'moves only when its value moves; pressing the chosen does nothing',
      (tester) async {
        final got = <String>[];
        await pumpBoth(
          tester,
          KitSlideSwitch<String>(
            label: 'Order',
            value: 'new',
            onChanged: got.add,
            options: const [
              KitSlideOption('new', 'Newest'),
              KitSlideOption('old', 'Oldest'),
              KitSlideOption('az', 'A–Z', disabled: true),
            ],
          ),
        );
        await tester.tap(find.text('Newest'));
        await tester.tap(find.text('Oldest'));
        await tester.tap(find.text('A–Z'), warnIfMissed: false);
        expect(got, ['old']);
      },
    );

    testWidgets('held: no pointer events at all', (tester) async {
      final got = <String>[];
      await pumpBoth(
        tester,
        KitSlideSwitch<String>(
          label: 'Priority',
          value: 'a',
          held: true,
          variant: KitSlideVariant.priority,
          onChanged: got.add,
          options: const [
            KitSlideOption('a', 'Low'),
            KitSlideOption('b', 'High'),
          ],
        ),
      );
      await tester.tap(find.text('High'), warnIfMissed: false);
      expect(got, isEmpty);
    });
  });

  group('§32 List / Grid', () {
    testWidgets(
      'List by default; a toggle writes nl-source-view, then every listing '
      'follows',
      (tester) async {
        await pumpBoth(
          tester,
          Column(
            children: [
              const KitViewToggle(),
              KitSourceView(builder: (_, v) => Text('listing: $v')),
            ],
          ),
        );
        expect(find.text('listing: list'), findsOneWidget);
        await tester.tap(find.text('Grid'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('listing: grid'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('nl-source-view'), 'grid');
      },
    );

    testWidgets(
      'an unknown stored value reads as List; the pre-D key is ignored',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'nl-source-view': 'shelf',
          'nl-sources-view': 'cards',
        });
        LocalFlags.resetForTest();
        await LocalFlags.ensureLoaded();
        expect(LocalFlags.sourceView.value, 'list');
      },
    );
  });

  group('§32 register row, §35 shelf tag', () {
    testWidgets('five cells; an unread dot; a count never taken is EMPTY', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          children: [
            KitRegisterRow(
              doc: _doc('a'),
              shelfTitle: 'Stoics',
              shelfColor: Colors.teal,
              onOpen: () {},
            ),
            KitRegisterRow(
              doc: _doc('b', chunks: null, views: 3),
              onOpen: () {},
            ),
            KitRegisterRow(doc: _doc('c', chunks: 0, views: 1), onOpen: () {}),
          ],
        ),
      );
      expect(find.text('Oct 30'), findsNWidgets(3));
      expect(find.text('Seneca'), findsNWidgets(3));
      Finder tag(String? title) =>
          find.byWidgetPredicate((w) => w is KitShelfTag && w.title == title);
      expect(tag('Stoics'), findsOneWidget);
      expect(tag(null), findsNWidgets(2), reason: 'Unshelved');
      expect(
        find.bySemanticsLabel(RegExp(r'^On the Shortness of Life \(unread\)$')),
        findsOneWidget,
        reason: 'the row names its source, and unread',
      );
      expect(find.byType(KitUnreadDot), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('0'), findsOneWidget, reason: 'a measured 0 draws 0');
    });

    testWidgets('a column 760 or narrower drops author and shelf', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        SizedBox(
          width: 380,
          child: KitRegisterRow(doc: _doc('a'), onOpen: () {}),
        ),
        size: const Size(390, 844),
      );
      expect(find.text('Seneca'), findsNothing);
      expect(find.byType(KitShelfTag), findsNothing);
    });

    testWidgets('a source still being read draws its stage, no dot, no count', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          children: [
            KitRegisterRow(
              doc: _doc('a', status: 'processing', stage: 'embedding'),
              onOpen: () {},
            ),
            KitRegisterRow(
              doc: _doc('b', status: 'queued'),
              onOpen: () {},
            ),
          ],
        ),
      );
      expect(find.text('INDEXING PASSAGES'), findsOneWidget);
      expect(find.text('QUEUED'), findsOneWidget);
      expect(find.byType(KitUnreadDot), findsNothing);
      expect(find.text('12'), findsNothing);
    });

    test('the stage vocabulary is open; stalled stops', () {
      expect(
        kitStageOf(_doc('a', status: 'processing', stage: 'mystery'))!.label,
        'Being read',
      );
      expect(kitStageOf(_doc('a', status: 'complete')), isNull);
      final stalled = Document.fromJson('s', {
        'user_id': 'u1',
        'title': 't',
        'type': 'pdf',
        'status': 'processing',
        'processing_stalls_at': 1,
      });
      final s = kitStageOf(stalled)!;
      expect(s.label, 'Stalled');
      expect(s.live, isFalse);
    });
  });

  // ── §1.2 compact rail parts, §30 chrome ───────────────────────────────────
  group('§30 chrome', () {
    testWidgets(
      'the tab bar: Home, Library, Add, Letters, Ask — Shelves in Ask\'s slot '
      'while AI is off; Letters lit on Letter settings',
      (tester) async {
        for (final ai in [true, false]) {
          await pumpBoth(
            tester,
            KitTabBar(
              route: '/letters/settings',
              aiOn: ai,
              onGo: (_) {},
              onAdd: () {},
            ),
            size: const Size(390, 844),
          );
          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Library'), findsOneWidget);
          expect(find.text('Add'), findsOneWidget);
          expect(find.bySemanticsLabel('Add a source'), findsOneWidget);
          expect(find.text('Letters'), findsOneWidget);
          expect(find.text('Ask'), ai ? findsOneWidget : findsNothing);
          expect(find.text('Shelves'), ai ? findsNothing : findsOneWidget);
          final letters = tester.widget<Text>(find.text('Letters'));
          final home = tester.widget<Text>(find.text('Home'));
          expect(letters.style!.color, isNot(home.style!.color));
        }
      },
    );

    testWidgets("the header's dot and its name while something waits", (
      tester,
    ) async {
      await pumpBoth(
        tester,
        KitAppHeader(onMenu: () {}, onSearch: () {}, attention: true),
        size: const Size(390, 844),
      );
      expect(find.byKey(const ValueKey('menu-attention-dot')), findsOneWidget);
      expect(find.text('Search your library…'), findsOneWidget);
    });
  });

  group('§1.2 the Reader\'s card', () {
    Widget card(
      KitActivityStub stub, {
      bool settings = false,
      bool activity = false,
    }) => ColoredBox(
      color: AppTheme.light.colorScheme.primary,
      child: SizedBox(
        width: 232,
        child: KitReaderCard(
          initials: 'XP',
          name: 'Xavier Polisetty',
          email: 'x@example.com',
          onSettings: () {},
          onActivity: () {},
          settingsLit: settings,
          activityLit: activity,
          stub: stub,
        ),
      ),
    );

    testWidgets('a refused read: no latest line, the dash — never 0', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        card(const KitActivityStub(failed: true, answered: true)),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Nothing new'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('READER’S CARD'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    });

    testWidgets('not yet answered: the dash, no Nothing new', (tester) async {
      await pumpBoth(tester, card(const KitActivityStub()));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Nothing new'), findsNothing);
    });

    testWidgets('answered empty: Nothing new and a measured 0', (tester) async {
      await pumpBoth(
        tester,
        card(const KitActivityStub(answered: true, unread: 0)),
      );
      expect(find.text('Nothing new'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('the newest event, its age, and 999+ past 999', (tester) async {
      final at = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      await pumpBoth(
        tester,
        card(
          KitActivityStub(
            answered: true,
            unread: 1200,
            latestTitle: 'Meditations is ready',
            latestAt: at,
          ),
          activity: true,
        ),
      );
      expect(find.text('Meditations is ready'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('999+'), findsOneWidget);
    });

    test('ages: now, minutes, hours, days', () {
      final now = DateTime(2026, 10, 30, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(kitAgoShort(ago(Duration.zero), now), 'now');
      expect(kitAgoShort(ago(const Duration(minutes: 7)), now), '7m');
      expect(kitAgoShort(ago(const Duration(hours: 3)), now), '3h');
      expect(kitAgoShort(ago(const Duration(days: 2)), now), '2d');
    });

    testWidgets('the Shelves row and its + in both themes', (tester) async {
      var added = 0;
      await pumpBoth(
        tester,
        ColoredBox(
          color: Colors.black,
          child: SizedBox(
            width: 232,
            child: KitRailShelvesRow(
              active: true,
              count: '6',
              onTap: () {},
              onAdd: () => added++,
            ),
          ),
        ),
      );
      expect(find.text('Shelves'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('New shelf'));
      expect(added, 1);
    });
  });

  // ── §36–§39, §13 in D ─────────────────────────────────────────────────────
  group('§36–§39 and §13 in D', () {
    testWidgets(
      '§37: inside a D page the empty state is left-set, its offers ruled',
      (tester) async {
        await pumpBoth(
          tester,
          KitDScope(
            child: KitEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing is *waiting*',
              standfirst: 'When something needs you, it will be here.',
              suggestions: [
                KitSuggestion(
                  icon: Icons.add,
                  label: 'Add a source',
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
        final left = tester.getTopLeft(find.byType(KitEmptyState)).dx;
        final mark = tester.getTopLeft(find.byIcon(Icons.inbox_outlined)).dx;
        expect(mark - left, lessThan(30), reason: 'set on the leading edge');
        expect(find.bySemanticsLabel('Add a source'), findsOneWidget);
      },
    );

    testWidgets('§38: a grow field is one line tall empty and caps at 172', (
      tester,
    ) async {
      final c = TextEditingController();
      await pumpBoth(
        tester,
        SizedBox(
          width: 300,
          child: KitGrowField(
            controller: c,
            placeholder:
                'Ask anything of your library, at whatever length the question takes…',
          ),
        ),
      );
      final one = tester.getSize(find.byType(KitGrowField)).height;
      expect(one, lessThan(60));
      c.text = List.filled(40, 'a line of the question').join('\n');
      await tester.pump();
      expect(
        tester.getSize(find.byType(KitGrowField)).height,
        lessThanOrEqualTo(172),
      );
      expect(
        tester.getSize(find.byType(KitGrowField)).height,
        greaterThan(one),
      );
    });

    testWidgets('§13 in D: on the page ground, centred, the pill at 999+', (
      tester,
    ) async {
      await pumpBoth(tester, KitSupportFooter(onOpen: () {}, unread: 1500));
      expect(find.text('Bugs? Feature Requests?'), findsOneWidget);
      expect(find.text('Chat with support…'), findsOneWidget);
      expect(find.text('999+'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KitSupportFooter),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border != null,
          ),
        ),
        findsNothing,
        reason: 'no top rule, no band',
      );
      final t = Tokens.light;
      expect(t.chromeUnread, const Color(0xFFF8846A));
    });

    testWidgets('§1.2: the attention pill is nothing at 0', (tester) async {
      await pumpBoth(
        tester,
        const Row(children: [KitAttentionPill(0, label: 'unread')]),
      );
      expect(find.text('0'), findsNothing);
    });
  });
}
