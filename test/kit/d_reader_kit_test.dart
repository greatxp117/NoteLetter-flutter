import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The source page's D parts (F-142; screens/reader.md §Composition, kit
/// §26 byline slot, §29 Figures meter and skeleton, §30 running head's foot,
/// §31 the wrapping section, §35 the Filing form) — each pumped in BOTH
/// themes, and the behaviour its required parts name: the identity block
/// absent from the running head, the meter one count over its total, a
/// section that has not mounted draws nothing in its reserve, a jump mounts
/// what it passes, and the progress rule is the scroll's own fraction.

const _finance = Tag(id: 't1', userId: 'u1', title: 'Finance', color: 'teal');

Document _doc({String type = 'pdf', String title = 'Quarterly Tax Summary'}) =>
    Document.fromJson('d1', {
      'user_id': 'u1',
      'title': title,
      'type': type,
      'status': 'complete',
      'chunk_count': 2,
      'view_count': 1,
      'created_at': DateTime(2026, 7, 1).millisecondsSinceEpoch,
    });

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
  });

  Future<void> pumpBoth(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 900),
    bool scroll = true,
    Future<void> Function(Brightness b)? check,
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
      if (check != null) await check(b);
    }
  }

  group('the identity block', () {
    testWidgets('a 52px cover, {kind} · {shelf} in caps, two lines of title',
        (tester) async {
      await pumpBoth(
        tester,
        SizedBox(
          width: 300,
          child: KitReaderIdentity(doc: _doc(), shelf: _finance),
        ),
      );
      expect(find.text('DOCUMENT · FINANCE'), findsOneWidget);
      // The cover draws its own title too; the block's is two lines at most.
      expect(tester.getSize(find.byType(KitCover)).width, 52);
      final titles = tester
          .widgetList<Text>(find.text('Quarterly Tax Summary'))
          .where((t) => t.maxLines == 2);
      expect(titles, hasLength(1));
    });

    testWidgets('unshelved, and absent from the dropped running head',
        (tester) async {
      await pumpBoth(tester, KitReaderIdentity(doc: _doc()));
      expect(find.text('DOCUMENT · UNSHELVED'), findsOneWidget);
      await pumpBoth(
        tester,
        KitSheetScope(dock: true, child: KitReaderIdentity(doc: _doc())),
      );
      expect(find.byKey(const ValueKey('rx-identity')), findsNothing,
          reason: 'the masthead above says it; the running head drops it');
    });
  });

  group('§29 Figures meter', () {
    testWidgets('one count over its own total, and the tail subtler',
        (tester) async {
      await pumpBoth(
        tester,
        const SizedBox(
          width: 300,
          child: KitFigures.ledger(
            label: 'The catalogue card',
            ledger: [
              KitFigureRow('Passages', '64'),
              KitFigureRow('Words', '—'),
              KitFigureRow('Passages read', '20', of: ' of 64', meter: 20 / 64),
            ],
          ),
        ),
        check: (b) async {
          final fill = tester.widget<FractionallySizedBox>(
              find.byType(FractionallySizedBox));
          expect(fill.widthFactor, closeTo(20 / 64, 1e-9));
          final ink = tester
              .widgetList<ColoredBox>(find.descendant(
                  of: find.byType(FractionallySizedBox),
                  matching: find.byType(ColoredBox)))
              .single
              .color;
          expect(ink, (b == Brightness.dark ? Tokens.dark : Tokens.light).accent);
        },
      );
      expect(find.text('THE CATALOGUE CARD'), findsOneWidget);
      expect(find.text('20 of 64', findRichText: true), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget,
          reason: 'only the row that carries a meter draws one');
    });
  });

  group('§26 the byline slot and the stacked crumb', () {
    testWidgets('the byline stands between the title and the rule',
        (tester) async {
      await pumpBoth(
        tester,
        const KitMasthead(
          folio: 'Finance · Document · Added Jul 1, 2026',
          title: 'Quarterly Tax Summary',
          byline: KitReaderByline(
            author: 'A. Writer',
            published: '3 January 2026',
            readingTime: '1 min read',
          ),
        ),
      );
      final by = find.textContaining('1 min read', findRichText: true);
      expect(by, findsOneWidget);
      expect(tester.getTopLeft(by).dy,
          greaterThan(tester.getBottomLeft(find.text('Quarterly Tax Summary')).dy));
    });

    testWidgets('on a phone the folio stands under the back control',
        (tester) async {
      await pumpBoth(
        tester,
        KitMasthead(
          folio: 'Finance · Document',
          title: 'Quarterly Tax Summary',
          back: KitDBackControl('Library', onTap: () {}),
          crumbStacks: true,
        ),
        size: const Size(390, 844),
      );
      final back = tester.getTopLeft(find.text('LIBRARY'));
      final folio = tester.getTopLeft(find.text('FINANCE\u00a0· DOCUMENT'));
      expect(folio.dy, greaterThan(back.dy + 10));
      expect(folio.dx, lessThan(back.dx),
          reason: 'the folio starts the line, under the chevron');
    });

    testWidgets('a byline with nothing to say draws nothing', (tester) async {
      await pumpBoth(tester, const KitReaderByline());
      expect(find.byType(RichText), findsNothing);
    });
  });

  group('§31 the wrapping section', () {
    testWidgets('unmounted: the head, then a reserve with nothing in it',
        (tester) async {
      final key = GlobalKey();
      await pumpBoth(
        tester,
        KitReaderSection(
          sectionKey: key,
          n: 2,
          title: 'Speed read',
          mounted: false,
          builder: (_) => const Text('the panel'),
        ),
        size: const Size(390, 800),
      );
      expect(find.text('§ III'), findsOneWidget);
      expect(find.text('the panel'), findsNothing);
      expect(tester.getSize(find.byKey(key)).height, greaterThan(400),
          reason: 'half the window is reserved');
    });

    testWidgets('mounted: the panel under the head, at most 940 wide',
        (tester) async {
      final key = GlobalKey();
      await pumpBoth(
        tester,
        KitReaderSection(
          sectionKey: key,
          n: 0,
          title: 'Summary',
          mounted: true,
          builder: (_) => const SizedBox(width: 2000, height: 10),
        ),
        size: const Size(1600, 900),
      );
      expect(tester.getSize(find.byType(SizedBox).last).width,
          lessThanOrEqualTo(940));
    });
  });

  group('KitSections, mounting on approach', () {
    testWidgets('only the eager ones at first; a scroll or a jump mounts',
        (tester) async {
      final sec = KitSections(['a', 'b', 'c'], eager: ['a']);
      final sc = ScrollController();
      addTearDown(sc.dispose);
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KitDPage(
            folio: 'F',
            title: 'T',
            sections: sec,
            controller: sc,
            child: ListenableBuilder(
              listenable: sec,
              builder: (context, _) => Column(children: [
                for (final (i, id) in const ['a', 'b', 'c'].indexed)
                  KitReaderSection(
                    sectionKey: sec.keyOf(id),
                    n: i,
                    title: id,
                    mounted: sec.isMounted(id),
                    builder: (_) => SizedBox(
                        height: 1500, child: Text('body $id')),
                  ),
              ]),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sec.isMounted('a'), isTrue);
      // b's head is within NEAR of the viewport's foot once a is drawn.
      expect(sec.isMounted('c'), isFalse,
          reason: 'a section far below is a reserve until approached');
      sec.jump('c');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sec.isMounted('b'), isTrue, reason: 'a jump mounts what it passes');
      expect(sec.isMounted('c'), isTrue);
      expect(find.text('body c', skipOffstage: false), findsOneWidget);
      expect(sec.current, 'c');
    });
  });

  group('§30 the running head\'s reading-progress rule', () {
    testWidgets('the scroll\'s own fraction, nothing under it', (tester) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(children: [
            SizedBox(height: 2, child: KitReadProgress(controller: sc)),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                child: const SizedBox(height: 1600),
              ),
            ),
          ]),
        ),
      ));
      double f() => tester
          .widget<FractionallySizedBox>(find.byKey(const ValueKey('rx-progress')))
          .widthFactor!;
      expect(f(), 0);
      sc.jumpTo(sc.position.maxScrollExtent / 2);
      await tester.pump();
      expect(f(), closeTo(0.5, 0.01));
      sc.jumpTo(sc.position.maxScrollExtent);
      await tester.pump();
      expect(f(), closeTo(1, 0.001));
    });
  });

  group('§35 the Filing form of the chip editor', () {
    testWidgets('on a D page a chip is a shelf TAG, the add plain',
        (tester) async {
      await pumpBoth(
        tester,
        KitDScope(
          child: KitShelfChipEditor(
            label: 'Shelves',
            chips: const [KitShelfChip(_finance)],
            addable: const [],
            onAdd: (_) {},
            onRemove: (_) {},
            onCreate: (_) {},
            removeLabel: (s) => 'Take this source off ${s.title}',
          ),
        ),
      );
      expect(find.byType(KitShelfTag), findsOneWidget);
      expect(find.bySemanticsLabel('Take this source off Finance'),
          findsOneWidget);
      expect(find.text('Shelf'), findsOneWidget);
    });

    testWidgets('off a D page it stays the chip', (tester) async {
      await pumpBoth(
        tester,
        KitShelfChipEditor(
          chips: const [KitShelfChip(_finance)],
          addable: const [],
          onAdd: (_) {},
          onRemove: (_) {},
          onCreate: (_) {},
          removeLabel: (s) => 'Take this source off ${s.title}',
        ),
      );
      expect(find.byType(KitShelfTag), findsNothing);
    });
  });

  group('§28 a Settings section reused in the panel', () {
    testWidgets('drops its header and row icon, and its rows go flat',
        (tester) async {
      Widget section() => const Column(children: [
            SectionHeader('Summaries'),
            KitRowList(raised: true, rows: [
              KitSettingRow(
                  icon: Icons.edit_outlined,
                  title: 'Summary style',
                  description: 'How each new source’s summary is written.'),
            ]),
          ]);
      await pumpBoth(tester, section());
      expect(find.text('SUMMARIES'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      await pumpBoth(tester, KitPanelScope(child: section()));
      expect(find.text('SUMMARIES'), findsNothing,
          reason: "the panel's own label names the group");
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Summary style'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).boxShadow != null),
          findsNothing,
          reason: 'no card in the panel');
    });
  });

  group('§29 skeleton lines', () {
    testWidgets('the theme\'s own ink as an overlay — never --surface-sunken',
        (tester) async {
      await pumpBoth(
        tester,
        const SizedBox(width: 300, child: KitSkeletonLines()),
        check: (b) async {
          final t = b == Brightness.dark ? Tokens.dark : Tokens.light;
          final bars = tester
              .widgetList<Container>(find.descendant(
                  of: find.byType(KitSkeletonLines),
                  matching: find.byType(Container)))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .where((d) => d.gradient != null)
              .toList();
          expect(bars, isNotEmpty);
          final colors = (bars.first.gradient! as LinearGradient).colors;
          expect(colors, [t.hoverStrong, t.hover, t.hoverStrong]);
          expect(colors, isNot(contains(t.surfaceSunken)));
        },
      );
    });
  });

  testWidgets('the wait peek: In this volume in --fg-muted', (tester) async {
    await pumpBoth(tester, const KitPeekWait('In this volume'),
        check: (b) async {
      final t = b == Brightness.dark ? Tokens.dark : Tokens.light;
      expect(tester.widget<Text>(find.text('In this volume')).style!.color,
          t.fgMuted);
    });
  });

  testWidgets('Finish: full-width secondary, its note, its refusal',
      (tester) async {
    var pressed = 0;
    await pumpBoth(
      tester,
      SizedBox(
        width: 300,
        child: KitReaderFinish(
          label: 'Mark finished',
          note: 'Reaching the end marks this for you.',
          error: 'That did not save. Try again.',
          onPressed: () => pressed++,
        ),
      ),
    );
    final button = find.byType(KitButton);
    expect(tester.widget<KitButton>(button).variant, KitButtonVariant.secondary,
        reason: "the page's one brick button is its action");
    expect(tester.getSize(button).width, 300);
    expect(find.byType(KitFailureInline), findsOneWidget);
    await tester.tap(button);
    expect(pressed, 1);
  });
}
