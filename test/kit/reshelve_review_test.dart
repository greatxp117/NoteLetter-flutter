// screens/library.md §Re-shelve review (4.85.0, ADR-119, INV-29), over a
// stored `shelf_delete` proposal (4.101.0, ADR-136). Mirrors
// NoteLetter-web/tests/contract/reshelve-review.test.js: "nothing fits" and
// "nowhere to go" are different answers, every source gets a picker, and
// filing is ONE fn_resolve_task apply. The review reads nothing itself: the
// live fn_suggest_reshelve read and its per-shelf filing were retired in
// 5.36.0, and with them the tests of a failed read, of reading in slices and of
// a per-shelf retry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/reshelve_sheet.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _sources = [
  ReshelveItem('d1', 'Bread starter'),
  ReshelveItem('d2', 'Tax estimates'),
  ReshelveItem('d3', 'Dragon story'),
];
Tag _tag(String id, String title) =>
    Tag(id: id, userId: 'u', title: title, color: 'sage-500', documentCount: 1);
final _shelves = [_tag('t-bread', 'Bread'), _tag('t-tax', 'Taxes')];

StoredReshelve _stored(Map<String, dynamic> result,
        {Future<Map<String, dynamic>> Function(List<Map<String, String>>)?
            apply,
        int unconsidered = 0}) =>
    StoredReshelve(
      key: 'tsk-1:1',
      result: result,
      unconsidered: unconsidered,
      apply: apply ?? (_) async => const {'filed': 0, 'skipped': {}},
    );

Future<void> _mount(
  WidgetTester tester, {
  required Map<String, dynamic> result,
  Future<Map<String, dynamic>> Function(List<Map<String, String>>)? apply,
  VoidCallback? onDone,
  List<Tag>? shelves,
  List<ReshelveItem> sources = _sources,
  void Function(String name, ValueChanged<String> created)? create,
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ShelfReshelveReview(
          title: 'Misc',
          sources: sources,
          shelves: shelves ?? _shelves,
          onDone: onDone ?? () {},
          stored: _stored(result, apply: apply),
          create: create,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

List<String> _picks(WidgetTester tester) => tester
    .widgetList<KitShelfSelect>(find.byType(KitShelfSelect))
    .map((s) => s.value)
    .toList();

const _fitTwo = <String, dynamic>{
  'scanned': 3,
  'shelves': 2,
  'proposals': [
    {'documentId': 'd1', 'tagId': 't-bread', 'reason': ''},
    {'documentId': 'd2', 'tagId': 't-tax', 'reason': ''},
  ],
};

Future<void> _open(WidgetTester tester, String docId) async {
  await tester.tap(find.byKey(ValueKey('reshelve-pick-$docId')));
  await tester.pumpAndSettle();
}

/// The open panel's rows, top to bottom, as the text each draws.
List<String> _panelRows(WidgetTester tester) {
  final out = <String>[];
  for (var i = 0;; i++) {
    final row = find.byKey(ValueKey('shelf-pick-row-$i'));
    if (row.evaluate().isEmpty) return out;
    out.add(tester
        .widgetList<RichText>(find.descendant(of: row, matching: find.byType(RichText)))
        .map((r) => r.text.toPlainText().replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').trim())
        .where((t) => t.isNotEmpty)
        .join(' '));
  }
}

void main() {
  testWidgets('presets every row, including the one nothing fit',
      (tester) async {
    await _mount(tester, result: const {
      'scanned': 3,
      'shelves': 2,
      'proposals': [
        {'documentId': 'd1', 'tagId': 't-bread', 'tagTitle': 'Bread', 'reason': 'About bread.'},
        {'documentId': 'd2', 'tagId': 't-tax', 'tagTitle': 'Taxes', 'reason': 'About tax.'},
      ],
    });
    expect(_picks(tester), ['t-bread', 't-tax', '']);
    expect(find.text('File 2 sources'), findsOneWidget);
    expect(find.text('About bread.'), findsOneWidget);
  });

  testWidgets('nothing fits is not a failure, and still offers a picker per source',
      (tester) async {
    await _mount(tester,
        result: const {'scanned': 3, 'shelves': 2, 'proposals': []});
    expect(find.textContaining('None of your shelves looked like a clear fit'),
        findsOneWidget);
    expect(find.byType(KitShelfSelect), findsNWidgets(3));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('nowhere to go is its own sentence', (tester) async {
    await _mount(tester,
        result: const {'scanned': 3, 'shelves': 0, 'proposals': []});
    expect(find.text('You have no other shelves to move these sources to.'),
        findsOneWidget);
  });

  testWidgets('the lede: upright at fg, only the figures and the shelf are em',
      (tester) async {
    final many = [for (var i = 0; i < 320; i++) ReshelveItem('d$i', 'S$i')];
    await _mount(tester, sources: many, result: {
      'scanned': 320,
      'shelves': 2,
      'proposals': [
        for (final i in [0, 150, 300])
          {'documentId': 'd$i', 'tagId': 't-bread', 'reason': ''},
      ],
    });
    expect(find.text('3 of 320 sources from Misc have a suggested shelf.'),
        findsOneWidget);

    // `.bf-lede`: upright at fg, and only the figures and the shelf name are
    // the italic accent `em` — not the italic, muted standfirst `.lede`.
    final lede = tester.widget<Text>(
        find.text('3 of 320 sources from Misc have a suggested shelf.'));
    final ctx = tester.element(find.byType(ShelfReshelveReview));
    expect(lede.style, KitText.reviewLede(ctx));
    final em = [
      for (final s in (lede.textSpan! as TextSpan).children!.cast<TextSpan>())
        if (s.style == KitText.reviewEm(ctx)) s.text
    ];
    expect(em, ['3', '320', 'Misc']);
  });

  testWidgets('a refused apply stays, with its sentence (§18 rule 2)',
      (tester) async {
    var done = 0;
    await _mount(
      tester,
      result: _fitTwo,
      apply: (_) async =>
          throw const ApiException(409, 'This proposal was already answered.'),
      onDone: () => done++,
    );
    await tester.tap(find.text('File 2 sources'));
    await tester.pumpAndSettle();
    expect(find.text('This proposal was already answered.'), findsOneWidget);
    expect(find.text('File 2 sources'), findsOneWidget);
    expect(done, 0);
  });

  group('§20.2 Shelf select on each row (4.105.0)', () {
    testWidgets('the trigger draws the chosen shelf, or the none label',
        (tester) async {
      await _mount(tester, result: _fitTwo);
      final d1 = find.byKey(const ValueKey('reshelve-pick-d1'));
      final d3 = find.byKey(const ValueKey('reshelve-pick-d3'));
      expect(find.descendant(of: d1, matching: find.text('Bread')), findsOneWidget);
      expect(find.descendant(of: d3, matching: find.text('Leave unshelved')),
          findsOneWidget);
      expect(tester.getSize(d1).height, KitShelfSelect.height);
      expect(tester.getSize(d3).width, greaterThanOrEqualTo(KitShelfSelect.minWidth));
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final node = tester.getSemantics(find.bySemanticsLabel('Shelf for Bread starter'));
      expect(node.value, 'Bread');
      expect(tester.getSemantics(find.bySemanticsLabel('Shelf for Dragon story')).value,
          'Leave unshelved');
      semantics.dispose();
    });

    testWidgets(
        'opens over every shelf: the none row first, the chosen one checked, '
        'the create row last', (tester) async {
      await _mount(tester, result: _fitTwo);
      await _open(tester, 'd2');
      expect(_panelRows(tester), ['Leave unshelved', 'Bread 1', 'Taxes 1', 'New shelf…']);
      final check = find.byKey(const ValueKey('shelf-pick-check'));
      expect(check, findsOneWidget);
      expect(
          find.ancestor(of: check, matching: find.byKey(const ValueKey('shelf-pick-row-2'))),
          findsOneWidget,
          reason: 'Taxes is the chosen row');
    });

    testWidgets('choosing sets the value and closes; the none row sets none',
        (tester) async {
      await _mount(tester, result: _fitTwo);
      await _open(tester, 'd3');
      await tester.tap(find.byKey(const ValueKey('shelf-pick-row-2')));
      await tester.pumpAndSettle();
      expect(_picks(tester), ['t-bread', 't-tax', 't-tax']);
      expect(find.byKey(const ValueKey('shelf-pick-row-0')), findsNothing);
      expect(find.text('File 3 sources'), findsOneWidget);

      await _open(tester, 'd1');
      await tester.tap(find.byKey(const ValueKey('shelf-pick-row-0')));
      await tester.pumpAndSettle();
      expect(_picks(tester), ['', 't-tax', 't-tax']);
    });

    testWidgets('typing hides the none row; the create row hands on the query '
        'and the new shelf becomes the choice', (tester) async {
      String? asked;
      ValueChanged<String>? done;
      await _mount(tester, result: _fitTwo, create: (name, created) {
        asked = name;
        done = created;
      });
      await _open(tester, 'd3');
      await tester.enterText(find.byKey(const ValueKey('shelf-pick-search')), 'Sourdough');
      await tester.pump();
      expect(_panelRows(tester).first, isNot('Leave unshelved'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(asked, 'Sourdough');
      expect(_picks(tester)[2], '', reason: 'nothing moves until the create resolved');
      done!('t-new');
      await tester.pump();
      expect(_picks(tester)[2], 't-new');
    });

    testWidgets('a value that resolves to no shelf draws the none label',
        (tester) async {
      await _mount(tester, result: _fitTwo, shelves: [_tag('t-bread', 'Bread')]);
      final d2 = find.byKey(const ValueKey('reshelve-pick-d2'));
      expect(find.descendant(of: d2, matching: find.text('Leave unshelved')),
          findsOneWidget);
    });

    testWidgets('at phone width the select drops under the title, full width',
        (tester) async {
      await _mount(tester, result: _fitTwo, size: const Size(390, 1400));
      final pick = tester.getRect(find.byKey(const ValueKey('reshelve-pick-d1')));
      final title = tester.getRect(find.text('Bread starter'));
      expect(pick.top, greaterThan(title.bottom));
      expect(pick.left, title.left);
      expect(pick.width, greaterThan(300), reason: 'the whole line, not its 180 floor');
    });
  });

  group('from a stored proposal (4.101.0)', () {
    Future<List<List<Map<String, String>>>> mountStored(WidgetTester tester,
        {Map<String, dynamic> answer = const {'filed': 2, 'skipped': {}},
        int unconsidered = 0,
        VoidCallback? onDone}) async {
      final sent = <List<Map<String, String>>>[];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShelfReshelveReview(
              title: 'Misc',
              sources: _sources,
              shelves: _shelves,
              onDone: onDone ?? () {},
              stored: StoredReshelve(
                key: 'tsk-1:1',
                result: const {
                  'scanned': 3,
                  'shelves': 2,
                  'proposals': [
                    {'documentId': 'd1', 'tagId': 't-bread', 'reason': 'About bread.'},
                  ],
                },
                unconsidered: unconsidered,
                apply: (a) async {
                  sent.add(a);
                  return answer;
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('presets from the result and files in ONE apply', (tester) async {
      var done = 0;
      final sent = await mountStored(tester, onDone: () => done++);
      expect(_picks(tester), ['t-bread', '', '']);
      tester.widget<KitShelfSelect>(find.byKey(const ValueKey('reshelve-pick-d2'))).onChanged('t-tax');
      await tester.pump();
      await tester.tap(find.text('File 2 sources'));
      await tester.pumpAndSettle();
      expect(sent, [
        [
          {'documentId': 'd1', 'tagId': 't-bread'},
          {'documentId': 'd2', 'tagId': 't-tax'},
        ]
      ]);
      expect(done, 1);
    });

    testWidgets('what the writer skipped is said before Done; unconsidered is said',
        (tester) async {
      var done = 0;
      await mountStored(tester,
          unconsidered: 2,
          answer: const {
            'filed': 0,
            'skipped': {'deleted': ['d1'], 'not_ready': [], 'shelf_gone': []},
          },
          onDone: () => done++);
      expect(find.text('2 more sources on this shelf were not asked about.'), findsOneWidget);
      await tester.tap(find.text('File 1 source'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 was deleted since this was suggested'), findsOneWidget);
      expect(done, 0);
      await tester.tap(find.text('Done'));
      expect(done, 1);
    });
  });
}
