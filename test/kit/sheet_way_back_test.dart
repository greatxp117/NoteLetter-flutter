// Kit §29 + §39 (5.60.0, ADR-214; spec/features/sheet-controls-and-way-back.md).
// Xavier, 2026-11-04: "if there is a back button, when the page is scrolled it
// should be at the top of the side panel, so the user doesn't have to scroll
// up to get to it."
//
// The port of the reference's `tests/contract/sheet-way-back.test.js`, case
// for case. Web's jsdom has no layout, so its cases pin wiring and its
// `gate:sheet-back` drives a real wheel; here the tester HAS layout, so each
// case scrolls with a real drag (a gesture, never a programmatic offset) and
// reads where the crumb went. The order the sheets lead with is pinned beside
// each page's own tests (`d_shelves_test`, `d_search_test`,
// `library_sheet_order_test`).
//
// Mutants each was run against (each turns this file red, 2026-11-04): `gone`
// negated in `_onCrumb`; the row dropped from the card's head; the row dropped
// from the running head; `KitSheetBack` never unmounting; its `IgnorePointer`
// left answering while it folds; the row put inside the sheet's own scroller
// (it scrolls away); the stacked sheet given a row; the sheet's grid cell a
// plain `SizedBox` again (a stuck sheet's controls stop answering a tap).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _wide = Size(1280, 800);
const _stacked = Size(900, 800);
const _phone = Size(390, 844);

final _row = find.byKey(const ValueKey('d-sheet-back'));

Future<void> _page(
  WidgetTester tester, {
  Size size = _wide,
  bool back = true,
  bool sheet = true,
  VoidCallback? onBack,
  List<(String, VoidCallback)> trail = const [],
  int sheetRows = 4,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: KitDPage(
        folio: 'A folio',
        title: 'A page',
        back: back
            ? KitDBackControl('All letters',
                onTap: onBack ?? () {}, trail: trail)
            : null,
        sheet: sheet
            ? KitDSheet(
                label: 'This letter',
                peek: const Text('The line'),
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const KitDLabel('Passages', first: true),
                    for (var i = 0; i < sheetRows; i++)
                      SizedBox(height: 60, child: Text('Sheet row $i')),
                  ],
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 60; i++)
              SizedBox(height: 60, child: Text('Column row $i')),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The page's own scroller: the outermost one.
Finder _pageScroll() => find.byType(Scrollable).first;

/// A real drag on the page — the crumb leaves the screen.
Future<void> _scrollDown(WidgetTester tester) async {
  await tester.drag(_pageScroll(), const Offset(0, -700));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _scrollUp(WidgetTester tester) async {
  await tester.drag(_pageScroll(), const Offset(0, 2000));
  await tester.pump();
}

int _backs() => find.byType(KitDBackControl).evaluate().length;

void main() {
  group('the way back at the head of the sheet', () {
    testWidgets('a page at its top draws one back control, in the masthead',
        (tester) async {
      await _page(tester);
      expect(_backs(), 1);
      expect(
          find.descendant(
              of: find.byType(KitMasthead), matching: find.byType(KitDBackControl)),
          findsOneWidget);
      expect(_row, findsNothing);
    });

    testWidgets('watches the masthead\'s crumb in the page\'s own scroller',
        (tester) async {
      await _page(tester);
      // A small scroll keeps the crumb on screen: no row.
      await tester.drag(_pageScroll(), const Offset(0, -10));
      await tester.pump();
      expect(_row, findsNothing);
      await _scrollDown(tester);
      expect(_row, findsOneWidget);
    });

    testWidgets(
        'once the crumb has gone it stands first in the sheet, and goes back '
        'the same way', (tester) async {
      var backs = 0;
      await _page(tester, onBack: () => backs++);
      await _scrollDown(tester);
      final offset = tester.state<ScrollableState>(_pageScroll()).position.pixels;
      expect(_row, findsOneWidget);
      // First in the sheet: above the sheet's own first label.
      expect(tester.getRect(_row).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('PASSAGES')).top));
      expect(find.descendant(of: _row, matching: find.text('ALL LETTERS')),
          findsOneWidget);
      // The row moves only the sheet: the page has not moved under it.
      expect(tester.state<ScrollableState>(_pageScroll()).position.pixels,
          offset);
      await tester.tap(find.descendant(of: _row, matching: find.text('ALL LETTERS')));
      expect(backs, 1);
    });

    testWidgets(
        'when the crumb returns the row stops answering at once and folds away',
        (tester) async {
      await _page(tester);
      await _scrollDown(tester);
      expect(_row, findsOneWidget);
      await _scrollUp(tester);
      expect(_row, findsOneWidget, reason: 'it folds, rather than jumping');
      final gate = tester.widget<IgnorePointer>(
          find.ancestor(of: _row, matching: find.byType(IgnorePointer)).first);
      expect(gate.ignoring, isTrue, reason: 'a folding row answers nothing');
      await tester.pump(const Duration(seconds: 1));
      expect(_row, findsNothing);
      expect(_backs(), 1);
    });

    testWidgets('a page with no back, or no sheet to carry it, draws no row',
        (tester) async {
      await _page(tester, back: false);
      await _scrollDown(tester);
      expect(_row, findsNothing);
      expect(_backs(), 0);
      await _page(tester, sheet: false);
      await _scrollDown(tester);
      expect(_row, findsNothing);
      expect(_backs(), 1);
    });

    testWidgets('a whole crumb trail comes with it (a sub-shelf\'s ancestors)',
        (tester) async {
      await _page(tester, trail: [('Philosophy', () {})]);
      await _scrollDown(tester);
      expect(
          find.descendant(of: _row, matching: find.text('ALL LETTERS')),
          findsOneWidget);
      expect(find.descendant(of: _row, matching: find.text('PHILOSOPHY')),
          findsOneWidget);
    });

    testWidgets(
        'on a phone it heads the running head\'s dropped sheet, under the line',
        (tester) async {
      await _page(tester, size: _phone);
      await _scrollDown(tester);
      await tester.tap(find.byKey(const ValueKey('d-peek')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
          find.descendant(of: find.byType(KitRunningHead), matching: _row),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('d-peek')),
              matching: find.byType(KitDBackControl)),
          findsNothing,
          reason: 'the line is one button already');
      expect(tester.getRect(_row).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('d-peek'))).bottom));
    });

    testWidgets(
        'a static sheet draws no row, and the row is pinned inside one that '
        'scrolls', (tester) async {
      await _page(tester, size: _stacked);
      await _scrollDown(tester);
      expect(_row, findsNothing, reason: 'a stacked sheet left with the crumb');

      await _page(tester, sheetRows: 30);
      await _scrollDown(tester);
      expect(_row, findsOneWidget);
      final before = tester.getRect(_row).top;
      final inner = find.descendant(
          of: find.byType(KitSheetCard), matching: find.byType(Scrollable));
      await tester.drag(inner.first, const Offset(0, -400));
      await tester.pump();
      expect(tester.getRect(_row).top, before,
          reason: 'the sheet scrolled under the row; the row stayed');
      expect(find.text('Sheet row 0').hitTestable(), findsNothing);
    });
  });
}
