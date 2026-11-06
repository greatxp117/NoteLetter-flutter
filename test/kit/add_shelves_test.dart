import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/shared/chosen_shelves.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/add_shelves.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'shelves_harness.dart';

/// §20.1's panel: what holds its search field, in the overlay.
Finder _panel() => find.ancestor(
      of: find.byKey(const ValueKey('shelf-pick-search')),
      matching: find.byType(CompositedTransformFollower),
    );

/// Kit §20.3 Shelves at add (5.73.0, ADR-238; web `shared/AddShelves.jsx`): the
/// rule that tells a shelf gone from a shelf on its way, and the row.
void main() {
  group('ChosenShelves: gone vs just made', () {
    late ChosenShelves c;
    setUp(() => c = ChosenShelves());
    tearDown(() => c.dispose());

    test('nothing chosen is an empty list, never null', () {
      c.read([shelf('a', 'A')]);
      expect(c.ids, isEmpty);
      expect(c.chips, isEmpty);
    });

    test('a shelf chosen and then deleted draws nothing and is not sent', () {
      c.read([shelf('a', 'A'), shelf('b', 'B')]);
      c.add('a');
      c.add('b');
      expect(c.ids, ['a', 'b']);
      c.read([shelf('b', 'B')]);
      expect(c.ids, ['b']);
      expect(c.chips.map((s) => s.id), ['b']);
    });

    test('a shelf just made is sent before the read delivers it, with no chip',
        () {
      c.read([shelf('a', 'A')]);
      c.add('made');
      expect(c.ids, ['made'], reason: 'never seen, so it is on its way');
      expect(c.chips, isEmpty, reason: 'nothing to draw it with yet');
      c.read([shelf('a', 'A'), shelf('made', 'Made')]);
      expect(c.ids, ['made']);
      expect(c.chips.map((s) => s.id), ['made']);
    });

    test('a shelf made here draws its chip at once, from what its form knew', () {
      c.read([shelf('a', 'A')]);
      c.addMade(shelf('made', 'Made in the form'));
      expect(c.ids, ['made']);
      expect(c.chips.single.title, 'Made in the form');
      // The read's own row takes over once it arrives.
      c.read([shelf('a', 'A'), shelf('made', 'Renamed since')]);
      expect(c.chips.single.title, 'Renamed since');
      // And it can go like any other: what the form knew does not bring it back.
      c.read([shelf('a', 'A')]);
      expect(c.ids, isEmpty);
      expect(c.chips, isEmpty);
    });

    test('a shelf made here keeps its chip while a read never delivers it', () {
      c.addMade(shelf('made', 'Made'));
      c.read(const []);
      expect(c.chips.map((s) => s.id), ['made'],
          reason: 'on a failed read it would otherwise go out with no chip, on '
              'every add, with no way to take it off');
      c.remove('made');
      expect(c.ids, isEmpty);
    });

    test('a shelf just made, delivered, then deleted is gone like any other',
        () {
      c.add('made');
      c.read([shelf('made', 'Made')]);
      c.read(const []);
      expect(c.ids, isEmpty);
    });

    test('a delete that fails puts the shelf back, and it is sent again', () {
      c.read([shelf('a', 'A')]);
      c.add('a');
      c.read(const []);
      expect(c.ids, isEmpty);
      c.read([shelf('a', 'A')]);
      expect(c.ids, ['a']);
    });

    test('an empty read before any delivery does not count as deleted', () {
      c.add('made');
      c.read(const []);
      expect(c.ids, ['made']);
    });

    test('ids is a copy: a later chip cannot reach an add already pressed', () {
      c.read([shelf('a', 'A'), shelf('b', 'B')]);
      c.add('a');
      final pressed = c.ids;
      c.add('b');
      c.remove('a');
      expect(pressed, ['a']);
      expect(() => pressed.add('x'), throwsUnsupportedError);
    });

    test('a repeat is one chip; remove and clear; each says so once', () {
      var notified = 0;
      c.addListener(() => notified++);
      c.read([shelf('a', 'A')]);
      expect(notified, 0, reason: 'read runs in a build, so it never notifies');
      c.add('a');
      c.add('a');
      expect(c.ids, ['a']);
      expect(notified, 1);
      c.remove('nothing');
      expect(notified, 1);
      c.clear();
      expect(c.ids, isEmpty);
      expect(notified, 2);
      c.clear();
      expect(notified, 2);
    });
  });

  group('KitAddShelves', () {
    late ChosenShelves chosen;
    late List<String> created;
    setUp(() {
      chosen = ChosenShelves();
      created = [];
    });
    tearDown(() => chosen.dispose());

    Future<void> pump(
      WidgetTester tester, {
      List<Tag>? shelves,
      bool disabled = false,
      bool fillPhone = false,
      double width = 800,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: KitAddShelves(
                chosen: chosen,
                shelves: shelves ?? [shelf('a', 'Attention'), shelf('b', 'Birds')],
                disabled: disabled,
                fillPhone: fillPhone,
                onCreate: created.add,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Add a shelf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('its parts, in order, and the sentence verbatim', (tester) async {
      await pump(tester);
      final label = tester.getTopLeft(find.text('SHELVES'));
      final row = tester.getTopLeft(find.byType(KitShelfChipEditor));
      final said = tester.getTopLeft(find.text(
          'Optional. NoteLetter still adds its own as it reads.'));
      expect(label.dy, lessThan(row.dy), reason: 'the label sits above the row');
      expect(row.dy, lessThan(said.dy));
      expect(find.text('Shelf'), findsOneWidget, reason: 'the add control');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chip appears and goes at once; nothing waits on a write',
        (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text('Attention'));
      await tester.pump();
      expect(chosen.ids, ['a']);
      expect(find.text('Attention'), findsOneWidget, reason: 'the chip');
      expect(find.byType(KitBusyMark), findsNothing, reason: 'no chip is busy');

      await tester.tap(find.bySemanticsLabel('Take Attention off'));
      await tester.pump();
      expect(chosen.ids, isEmpty);
      expect(find.text('Attention'), findsNothing);
    });

    testWidgets('the picker offers only what is not chosen, in tree order',
        (tester) async {
      await pump(tester, shelves: [
        shelf('c', 'Child', parent: 'p'),
        shelf('p', 'Parent'),
        shelf('z', 'Zebra'),
      ]);
      chosen.add('z');
      await tester.pump();
      await open(tester);
      // Zebra is the chip's text alone; the panel's rows are the other two.
      expect(find.text('Zebra'), findsOneWidget);
      final parent = tester.getTopLeft(find.text('Parent')).dy;
      final child = tester
          .getTopLeft(find.textContaining('Child', findRichText: true))
          .dy;
      expect(parent, lessThan(child), reason: 'a parent above its child');
      expect(find.textContaining('Parent › Child', findRichText: true),
          findsOneWidget,
          reason: 'the path prefix (§20.1)');
    });

    testWidgets('the create row hands the host the query', (tester) async {
      await pump(tester);
      await open(tester);
      await tester.enterText(
          find.byKey(const ValueKey('shelf-pick-search')), ' Field notes ');
      await tester.pump();
      await tester.tap(find.textContaining('Create', findRichText: true));
      await tester.pump();
      expect(created, ['Field notes']);
      expect(chosen.ids, isEmpty, reason: 'nothing chosen until it is made');
    });

    testWidgets('a chosen shelf that goes draws nothing', (tester) async {
      await pump(tester);
      chosen.add('a');
      await tester.pump();
      expect(find.text('Attention'), findsOneWidget);
      await pump(tester, shelves: [shelf('b', 'Birds')]);
      expect(find.text('Attention'), findsNothing);
      expect(chosen.ids, isEmpty);
    });

    testWidgets('disabled holds the row, and no mark spins on what was pressed',
        (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text('Attention'));
      await tester.pump();
      // The press key is 'add' now: an add in flight must not spin + Shelf.
      await pump(tester, disabled: true);
      expect(find.byType(KitBusyMark), findsNothing);

      await tester.tap(find.bySemanticsLabel('Take Attention off'),
          warnIfMissed: false);
      await tester.pump();
      expect(chosen.ids, ['a'], reason: 'the remove is held');
      await tester.tap(find.bySemanticsLabel('Add a shelf'), warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('shelf-pick-search')), findsNothing,
          reason: 'the add control is held');
    });

    testWidgets('at ten chosen the add control is held, and the sentence says why',
        (tester) async {
      final ten = [for (var i = 0; i < 12; i++) shelf('s$i', 'Shelf $i')];
      await pump(tester, shelves: ten);
      for (var i = 0; i < 9; i++) {
        chosen.add('s$i');
      }
      await tester.pump();
      expect(find.text(KitAddShelves.sentence), findsOneWidget, reason: 'nine');
      await open(tester);
      expect(find.byKey(const ValueKey('shelf-pick-search')), findsOneWidget,
          reason: 'a tenth can still be chosen');
      await tester.tap(find.text('Shelf 9'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(chosen.ids.length, 10);

      expect(find.text('Ten is the most one add can carry.'), findsOneWidget);
      expect(find.text(KitAddShelves.sentence), findsNothing);
      await tester.tap(find.bySemanticsLabel('Add a shelf'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('shelf-pick-search')), findsNothing,
          reason: 'an eleventh is held here, not refused there');

      // Held, not the whole row: a chip still comes off, and that frees it.
      await tester.tap(find.bySemanticsLabel('Take Shelf 0 off'));
      await tester.pump();
      expect(chosen.ids.length, 9);
      expect(find.text(KitAddShelves.sentence), findsOneWidget);
      await open(tester);
      expect(find.byKey(const ValueKey('shelf-pick-search')), findsOneWidget);
    });

    testWidgets('the ten are what an add would send: gone and just made both count',
        (tester) async {
      final known = [for (var i = 0; i < 10; i++) shelf('s$i', 'Shelf $i')];
      await pump(tester, shelves: known);
      for (var i = 0; i < 9; i++) {
        chosen.add('s$i');
      }
      chosen.add('made'); // not delivered yet, and on its way out with the add
      await tester.pump();
      expect(find.text(KitAddShelves.sentenceFull), findsOneWidget);
      // A shelf deleted since it was chosen is not sent, so it holds nothing.
      await pump(tester, shelves: known.sublist(1));
      expect(chosen.ids.length, 9);
      expect(find.text(KitAddShelves.sentence), findsOneWidget);
    });

    testWidgets('fillPhone: the picker takes a phone, 16 inside each edge',
        (tester) async {
      await pump(tester, fillPhone: true, width: 390);
      await open(tester);
      final panel = _panel();
      expect(tester.getSize(panel).width, 358);
      // The follower's own offset from the control: a transform the test
      // binding never composites, so its drawn position reads 0.
      final control = tester.getTopLeft(find.bySemanticsLabel('Add a shelf')).dx;
      expect(tester.widget<CompositedTransformFollower>(panel).offset.dx,
          16 - control);
    });

    testWidgets('fillPhone: wider than a phone, §20.1 keeps its 288',
        (tester) async {
      await pump(tester, fillPhone: true, width: 800);
      await open(tester);
      expect(tester.getSize(_panel()).width, 288);
    });

    testWidgets('dark: no exception', (tester) async {
      await pump(tester, theme: AppTheme.dark);
      chosen.add('a');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('AddShelves', () {
    testWidgets('the row starts the read, and the live read reaches the choice',
        (tester) async {
      final tags = LiveTags([shelf('a', 'Attention')]);
      final docs = QuietDocs();
      final chosen = ChosenShelves();
      addTearDown(chosen.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TagsNotifier>.value(value: tags),
          ChangeNotifierProvider<DocumentsNotifier>.value(value: docs),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: AddShelves(chosen: chosen)),
        ),
      ));
      await tester.pump();
      expect(tags.starts, 1);
      expect(docs.starts, 1);

      chosen.add('a');
      tags.deliver(const []);
      await tester.pump();
      expect(chosen.ids, isEmpty);
    });
  });
}
