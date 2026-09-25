// screens/library.md §Re-shelve review (4.85.0, ADR-119, INV-29). Mirrors
// NoteLetter-web/tests/contract/reshelve-review.test.js: three answers that
// must never be merged, every source gets a picker, and filing is one
// fn_apply_shelf_backfill per destination — a shelf already filed is not
// re-sent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/tags/reshelve_sheet.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _sources = [
  ReshelveItem('d1', 'Bread starter'),
  ReshelveItem('d2', 'Tax estimates'),
  ReshelveItem('d3', 'Dragon story'),
];
const _shelves = [ReshelveItem('t-bread', 'Bread'), ReshelveItem('t-tax', 'Taxes')];

Future<void> _mount(
  WidgetTester tester, {
  required SuggestReshelve suggest,
  ApplyBackfill? apply,
  VoidCallback? onDone,
}) async {
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
          suggest: suggest,
          apply: apply ?? (_, __) async => {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

List<String> _picks(WidgetTester tester) => tester
    .widgetList<KitSelect<String>>(find.byType(KitSelect<String>))
    .map((s) => s.value)
    .toList();

void main() {
  testWidgets('presets every row, including the one nothing fit',
      (tester) async {
    List<String>? sent;
    await _mount(tester, suggest: (ids) async {
      sent = ids;
      return {
        'scanned': 3,
        'shelves': 2,
        'proposals': [
          {'documentId': 'd1', 'tagId': 't-bread', 'tagTitle': 'Bread', 'reason': 'About bread.'},
          {'documentId': 'd2', 'tagId': 't-tax', 'tagTitle': 'Taxes', 'reason': 'About tax.'},
        ],
      };
    });
    expect(_picks(tester), ['t-bread', 't-tax', '']);
    expect(find.text('File 2 sources'), findsOneWidget);
    expect(find.text('About bread.'), findsOneWidget);
    expect(sent, ['d1', 'd2', 'd3']);
  });

  testWidgets('nothing fits is not a failure, and still offers a picker per source',
      (tester) async {
    await _mount(tester,
        suggest: (_) async => {'scanned': 3, 'shelves': 2, 'proposals': []});
    expect(find.textContaining('None of your shelves looked like a clear fit'),
        findsOneWidget);
    expect(find.byType(KitSelect<String>), findsNWidgets(3));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('nowhere to go is its own sentence', (tester) async {
    await _mount(tester,
        suggest: (_) async => {'scanned': 3, 'shelves': 0, 'proposals': []});
    expect(find.text('You have no other shelves to move these sources to.'),
        findsOneWidget);
  });

  testWidgets('a failed read is a failure, never "nothing fits"',
      (tester) async {
    await _mount(tester,
        suggest: (_) async => throw const ApiException(502, 'Upstream down'));
    expect(find.textContaining('could not be suggested'), findsOneWidget);
    expect(find.textContaining('clear fit'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('reads in slices of 150 and merges them', (tester) async {
    final many = [for (var i = 0; i < 320; i++) ReshelveItem('d$i', 'S$i')];
    final calls = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ShelfReshelveReview(
            title: 'Misc',
            sources: many,
            shelves: _shelves,
            onDone: () {},
            suggest: (ids) async {
              calls.add(ids.length);
              return {
                'scanned': ids.length,
                'shelves': 2,
                'proposals': [
                  {'documentId': ids.first, 'tagId': 't-bread', 'reason': ''}
                ],
              };
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, [150, 150, 20]);
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

  testWidgets('files per shelf, and a retry does not re-send a shelf already filed',
      (tester) async {
    final applied = <List<Object>>[];
    var failNext = false;
    var done = 0;
    await _mount(
      tester,
      suggest: (_) async => {
        'scanned': 3,
        'shelves': 2,
        'proposals': [
          {'documentId': 'd1', 'tagId': 't-bread', 'reason': ''},
          {'documentId': 'd2', 'tagId': 't-tax', 'reason': ''},
        ],
      },
      apply: (tagId, ids) async {
        applied.add([tagId, ids]);
        if (tagId == 't-tax' && failNext) {
          failNext = false;
          throw const ApiException(400, 'Not in your library: d2');
        }
        return {'filed': ids.length, 'unchanged': 0};
      },
      onDone: () => done++,
    );
    // Choose Bread for the story, which nothing fit.
    final third = tester.widget<KitSelect<String>>(
        find.byKey(const ValueKey('reshelve-pick-d3')));
    third.onChanged!('t-bread');
    await tester.pumpAndSettle();

    failNext = true;
    await tester.tap(find.text('File 3 sources'));
    await tester.pumpAndSettle();
    expect(find.text('Taxes: Not in your library: d2'), findsOneWidget);
    expect(applied[0], ['t-bread', ['d1', 'd3']]);
    expect(applied[1], ['t-tax', ['d2']]);
    expect(done, 0);
    expect(find.text('Filed'), findsNWidgets(2));

    await tester.tap(find.text('File 1 source'));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(applied, hasLength(3));
    expect(applied.last, ['t-tax', ['d2']]);
  });
}
