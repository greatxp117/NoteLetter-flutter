// component-kit §20 Shelf chip editor + §20.1 Shelf picker (4.104.0, ADR-137).
// The matching rules are the reference's `shared/shelfPick.js` case for case
// (web `tests/contract/shelf-picker.test.js`), because §20.1 makes the ranking
// normative: a search that orders differently here is a different app. Then
// the widget: always reachable, filter + Enter, arrows onto the create row,
// Esc writes nothing, the create row hands its query on — and the sheet hands
// the new id back only once the create resolved.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/shelf_sheet.dart';
import 'package:flutter_app/shared/shelf_pick.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Tag _s(String id, String title, [int? n]) => Tag(
      id: id,
      userId: 'u',
      title: title,
      color: 'sage-500',
      documentCount: n ?? 0,
      documentCountStored: n != null,
    );

final _pasta = _s('t1', 'Pasta', 3);
final _stories = _s('t2', 'Stories', 1);
final _postwar = _s('t3', 'Post-war Studies', 0);
final _finance = _s('t4', 'Finance', 2);

void main() {
  group('matching', () {
    test('folds case and accents, keeping a map to the original characters',
        () {
      final f = fold('Café Ärzte');
      expect(f.text, 'cafe arzte');
      expect(f.map.sublist(0, 5), [0, 1, 2, 3, 4]);
    });

    test('ranks a title start, then a word start, then anywhere', () {
      final rows = pickRows([_pasta, _postwar, _stories], 'st');
      expect(rows.map((r) => r.shelf.title),
          ['Stories', 'Post-war Studies', 'Pasta']);
      expect(rows.map((r) => r.match.rank), [0, 1, 2]);
    });

    test('draws the run it ranked — the word start, not the first occurrence',
        () {
      final m = matchShelf('Post-war Studies', 'st')!;
      expect('Post-war Studies'.substring(m.start, m.end), 'St');
    });

    test('highlights the accented characters a folded query matched', () {
      final m = matchShelf('Notes au café', 'CAFE')!;
      expect('Notes au café'.substring(m.start, m.end), 'café');
    });

    test('keeps arrival order among equals; an empty query lists everything',
        () {
      expect(pickRows([_pasta, _stories, _finance], '  ').map((r) => r.shelf.id),
          ['t1', 't2', 't4']);
    });
  });

  group('the create row and the empty line', () {
    PickState state(List<Tag> onItem, List<Tag> addable, String q) => pickState(
        onItem: onItem, addable: addable, q: q, rows: pickRows(addable, q));

    test('offers to create the query when no shelf is named by it', () {
      final s = state([], [_pasta], ' Tax records ');
      expect(s.createName, 'Tax records');
      expect(s.empty, 'No shelf matches “Tax records”.');
    });

    test('never offers a second shelf with a name that exists', () {
      expect(state([], [_pasta], 'pasta').createName, '');
      final here = state([_finance], [_pasta], 'FINANCE');
      expect(here.createName, '');
      expect(here.empty, '“Finance” is already here.');
    });

    test('says why the list is empty with no query', () {
      expect(state([], [], '').empty, 'No shelves yet.');
      expect(state([_pasta], [], '').empty, 'Every shelf is already here.');
      expect(state([], [_pasta], '').empty, isNull);
    });
  });

  group('the picker', () {
    late List<String> added;
    late List<String> created;

    Future<void> host(WidgetTester tester,
        {List<KitShelfChip> chips = const [],
        List<Tag>? addable,
        double width = 900}) async {
      added = [];
      created = [];
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: KitShelfChipEditor(
              label: 'Shelves',
              chips: chips,
              addable: addable ?? [_pasta, _stories],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: created.add,
              removeLabel: (s) => 'Take this source off ${s.title}',
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Shelf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    Finder field() => find.byKey(const ValueKey('shelf-pick-search'));

    testWidgets('the add control sits on the chips\' line, at its own width',
        (tester) async {
      // The first device frame drew it as a full-width dashed bar on a line of
      // its own: a Container with `alignment` takes every pixel a Wrap offers.
      await host(tester, chips: [KitShelfChip(_finance)]);
      final plus = tester.getRect(find
          .ancestor(of: find.text('Shelf'), matching: find.byType(Container))
          .first);
      final chip = tester.getRect(find.text('Finance'));
      expect(plus.width, lessThan(100));
      expect((plus.center.dy - chip.center.dy).abs(), lessThan(2));
      expect(plus.left, greaterThan(chip.right));
    });

    testWidgets('is reachable with nothing left to add — it still creates',
        (tester) async {
      await host(tester,
          chips: [KitShelfChip(_pasta)], addable: const []);
      await open(tester);
      expect(find.text('Every shelf is already here.'), findsOneWidget);
      expect(find.text('New shelf…'), findsOneWidget);
    });

    testWidgets('filters as you type; Enter chooses the active row',
        (tester) async {
      await host(tester);
      await open(tester);
      await tester.enterText(field(), 'sto');
      await tester.pump();
      expect(find.byKey(const ValueKey('shelf-pick-row-0')), findsOneWidget);
      expect(find.textContaining('Pasta'), findsNothing);
      expect(find.textContaining('Create'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(added, ['t2']);
      expect(field(), findsNothing);
    });

    testWidgets('the arrows move the active row, stopping at the create row',
        (tester) async {
      await host(tester);
      await open(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(added, isEmpty);
      expect(created, ['']);
    });

    testWidgets('the search field is a bare input — no border, focused or not',
        (tester) async {
      // The first device frame drew the theme's focused outline round it:
      // `InputDecoration.collapsed` clears only the resting border.
      await host(tester);
      await open(tester);
      final d = tester.widget<TextField>(field()).decoration!;
      expect(d.focusedBorder, InputBorder.none);
      expect(d.enabledBorder, InputBorder.none);
      expect(d.border, InputBorder.none);
    });

    testWidgets('Esc closes it and writes nothing', (tester) async {
      await host(tester);
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field(), findsNothing);
      expect(added, isEmpty);
      expect(created, isEmpty);
    });

    testWidgets('the create row hands on what was typed', (tester) async {
      await host(tester);
      await open(tester);
      await tester.enterText(field(), 'Tax records');
      await tester.pump();
      expect(find.text('No shelf matches “Tax records”.'), findsOneWidget);
      await tester.tap(find.textContaining('Create'));
      await tester.pump();
      expect(created, ['Tax records']);
    });

    testWidgets('a count is drawn only when it was stored', (tester) async {
      await host(tester, addable: [_pasta, _s('t9', 'Legacy')]);
      await open(tester);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('on a phone the panel stays 16px inside the viewport',
        (tester) async {
      await host(tester,
          chips: [KitShelfChip(_finance), KitShelfChip(_stories)],
          width: 390);
      await open(tester);
      final panel = tester.getRect(find
          .ancestor(of: field(), matching: find.byType(Material))
          .first);
      expect(panel.left, greaterThanOrEqualTo(16));
      expect(panel.right, lessThanOrEqualTo(390 - 16));
    });
  });

  group('the sheet, from a picker', () {
    testWidgets(
        'opens named by the query and hands the id back only after the create',
        (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final handed = <String>[];
      var closed = false;
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShelfSheetBody(
              canBackfill: false,
              onBusy: (_) {},
              onHeading: (_) {},
              close: () => closed = true,
              land: (_) => closed = true,
              initialName: '  Tax records  ',
              onCreated: handed.add,
              create: (title, {description, color}) => pending.future,
            ),
          ),
        ),
      ));
      await tester.pump();
      final name = tester.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey('shelf-form-name')),
          matching: find.byType(TextField)));
      expect(name.controller!.text, 'Tax records');
      await tester.tap(find.text('Create shelf'));
      await tester.pump();
      expect(handed, isEmpty);
      pending.complete({'tagId': 't9'});
      await tester.pumpAndSettle();
      expect(handed, ['t9']);
      expect(closed, isTrue);
    });
  });
}
