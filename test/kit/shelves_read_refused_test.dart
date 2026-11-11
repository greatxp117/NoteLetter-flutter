/// F-196 — a refused tags read is §14, never *No shelves yet.* (INV-24,
/// ADR-071; web 97b4b85: shared/shelvesRead.js, shelfPick.js, ShelfPicker,
/// AddShelves, ReaderView; tests/contract/shelves-read-refused.test.js).
///
/// The tags subscription refused hands every §20 host the rows it read before
/// (none, on a first read), and each host read that as an answer: §20.1's
/// panel said *No shelves yet.* of a library nobody had read and offered to
/// create a shelf whose name nobody could check, §20.3's row offered its
/// choice over nothing, and the reader showed a shelved source as
/// *Unshelved*. The read's STATE now travels beside the rows (the app's
/// [ShelvesReadScope] over [TagsNotifier]), and every host says the read was
/// refused, in §14.3's words.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/reader_page.dart'
    show readerFilingError, readerFolio;
import 'package:flutter_app/shared/chosen_shelves.dart';
import 'package:flutter_app/shared/shelf_pick.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/shelves_read_scope.dart';

const _denied = 'NoteLetter could not read this. Sign out and back in, or '
    'contact support.';
const _line = 'Your shelves could not be read — $_denied';

Tag _s(String id, String title) =>
    Tag(id: id, userId: 'u', title: title, color: 'sage-500');

final _pasta = _s('t1', 'Pasta');

/// The tags read as the test says it is: [failure] a refusal (§14.3's
/// sentence, as TagsNotifier stores it), [out] a read not yet answered.
class _Tags extends TagsNotifier {
  _Tags({this.failure, this.out = false, this.rows = const []});
  final String? failure;
  final bool out;
  final List<Tag> rows;

  @override
  void start() {}
  @override
  bool get loading => out;
  @override
  String? get error => failure;
  @override
  List<Tag> get tags => rows;
}

Future<void> _host(WidgetTester tester, _Tags tags, Widget child) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<TagsNotifier>.value(
      value: tags,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => ShelvesReadScope(child: child!),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(40), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _open(WidgetTester tester, String control) async {
  await tester.tap(find.text(control));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('pickState reads the read', () {
    PickState state(List<Tag> addable, String q, ShelvesRead read) => pickState(
        onItem: const [],
        addable: addable,
        q: q,
        rows: pickRows(addable, q),
        read: read);

    test('refused: no sentence and no create row', () {
      final none = state(const [], '', ShelvesRead.failed);
      expect(none.empty, isNull);
      expect(none.createName, isNull);
      final typed = state(const [], 'Tax', ShelvesRead.failed);
      expect(typed.empty, isNull, reason: 'not "No shelf matches"');
      expect(typed.createName, isNull,
          reason: 'a name cannot be checked against shelves nobody read');
    });

    test('loading: no sentence yet; the create row stays', () {
      final s = state(const [], '', ShelvesRead.loading);
      expect(s.empty, isNull);
      expect(s.createName, '');
    });

    test('answered: §20.1 as before', () {
      expect(state(const [], '', ShelvesRead.answered).empty, 'No shelves yet.');
    });
  });

  group('§20.1 the picker panel', () {
    late List<String> added;
    late List<String> created;

    Widget editor(List<Tag> addable) => KitShelfChipEditor(
          label: 'Shelves',
          chips: const [],
          addable: addable,
          onAdd: added.add,
          onRemove: (_) {},
          onCreate: created.add,
          removeLabel: (s) => 'Take this source off ${s.title}',
        );

    setUp(() {
      added = [];
      created = [];
    });

    testWidgets('refused with nothing read: the line, no sentence, no create '
        'row, and Enter chooses nothing', (tester) async {
      await _host(tester, _Tags(failure: _denied), editor(const []));
      await _open(tester, 'Shelf');
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text('No shelves yet.'), findsNothing);
      expect(find.text('New shelf…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(created, isEmpty);
      expect(added, isEmpty);

      await tester.enterText(
          find.byKey(const ValueKey('shelf-pick-search')), 'Tax');
      await tester.pump();
      expect(find.textContaining('No shelf matches'), findsNothing);
      expect(find.textContaining('Create'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(created, isEmpty);
    });

    testWidgets('refused after rows were read: the rows stay, under the line',
        (tester) async {
      await _host(tester, _Tags(failure: _denied, rows: [_pasta]),
          editor([_pasta]));
      await _open(tester, 'Shelf');
      expect(find.textContaining('Pasta'), findsOneWidget);
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text('New shelf…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(added, ['t1'], reason: 'a row read before is still a shelf');
    });

    testWidgets('loading: no sentence about shelves nobody has read yet',
        (tester) async {
      await _host(tester, _Tags(out: true), editor(const []));
      await _open(tester, 'Shelf');
      expect(find.text('No shelves yet.'), findsNothing);
      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.text('New shelf…'), findsOneWidget);
    });

    testWidgets('answered and empty: No shelves yet., as before',
        (tester) async {
      await _host(tester, _Tags(), editor(const []));
      await _open(tester, 'Shelf');
      expect(find.text('No shelves yet.'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
    });

    testWidgets('§20.2 a select\'s panel says it too', (tester) async {
      await _host(
        tester,
        _Tags(failure: _denied),
        KitShelfSelect(
          value: '',
          shelves: const [],
          none: 'No parent',
          label: 'Parent shelf',
          onChanged: (_) {},
          onCreate: created.add,
        ),
      );
      await _open(tester, 'No parent');
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text('New shelf…'), findsNothing);
    });
  });

  group('§20.3 Shelves at add', () {
    testWidgets('refused: the line in the sentence\'s place', (tester) async {
      final chosen = ChosenShelves();
      addTearDown(chosen.dispose);
      await _host(
        tester,
        _Tags(failure: _denied),
        KitAddShelves(chosen: chosen, shelves: const [], onCreate: (_) {}),
      );
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text(KitAddShelves.sentence), findsNothing);
    });

    testWidgets('answered: its sentence', (tester) async {
      final chosen = ChosenShelves();
      addTearDown(chosen.dispose);
      await _host(
        tester,
        _Tags(),
        KitAddShelves(chosen: chosen, shelves: const [], onCreate: (_) {}),
      );
      expect(find.text(KitAddShelves.sentence), findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
    });
  });

  group('the reader', () {
    Document doc(List<String> tags) => Document.fromJson('d1', {
          'user_id': 'u1',
          'title': 'Stew',
          'type': 'pdf',
          'status': 'complete',
          'tag_ids': tags,
        });

    test('the folio: a shelved source is a dash, never Unshelved, while the '
        'read is refused', () {
      expect(readerFolio(doc(['t9']), null, refused: true),
          startsWith('— · '));
      expect(readerFolio(doc(const []), null, refused: true),
          startsWith('Unshelved · '),
          reason: 'the document says it is on no shelf');
      expect(readerFolio(doc(['t9']), null), startsWith('Unshelved · '),
          reason: 'answered and not found: as before');
      expect(readerFolio(doc(['t1']), _pasta, refused: true),
          startsWith('Pasta · '));
    });

    test('the Filing row carries the line; its own refused write is newer '
        'and wins the slot', () {
      expect(readerFilingError(null, _denied), _line);
      expect(readerFilingError('That shelf is gone.', _denied),
          'That shelf is gone.');
      expect(readerFilingError(null, null), isNull);
    });

    testWidgets('the identity block says the same', (tester) async {
      await _host(tester, _Tags(failure: _denied),
          KitReaderIdentity(doc: doc(['t9'])));
      expect(find.text('DOCUMENT · —'), findsOneWidget);
      expect(find.textContaining('UNSHELVED'), findsNothing);
    });
  });
}
