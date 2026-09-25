// screens/library.md §Creating a shelf §Backfill review (4.83.0, ADR-117,
// INV-29). One form for the rail sheet and the index card; the create resolves
// BEFORE the sheet moves; a failed suggest is never "nothing fits"; apply
// holds the sheet open — scrim included — until it resolves.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/tags/shelf_sheet.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

Future<void> _host(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

Map<String, dynamic> _two() => {
      'scanned': 12,
      'candidates': [
        {'documentId': 'd1', 'title': 'Sourdough notes', 'reason': 'About bread.'},
        {'documentId': 'd2', 'title': 'Rye ratios', 'reason': 'Also bread.'},
      ],
    };

void main() {
  group('the form', () {
    testWidgets('the backfill choice is absent with no complete source',
        (tester) async {
      await _host(
          tester,
          ShelfFormFields(
              canBackfill: false, onCreated: (_) {}, create: _never));
      expect(find.text('Find sources that belong here'), findsNothing);
      expect(find.text('WHAT BELONGS HERE?'), findsOneWidget);
    });

    testWidgets('write before move: nothing moves until create resolves',
        (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      ShelfCreated? got;
      String? sentDesc;
      await _host(
          tester,
          ShelfFormFields(
            canBackfill: true,
            onCreated: (c) => got = c,
            create: (title, {description, color}) {
              sentDesc = description;
              return pending.future;
            },
          ));
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('shelf-form-name')),
              matching: find.byType(TextField)),
          'Bread');
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('shelf-form-description')),
              matching: find.byType(TextField)),
          'Baking and starters');
      await tester.pump();
      await tester.tap(find.text('Create shelf'));
      await tester.pump();
      expect(find.text('Creating…'), findsOneWidget);
      expect(got, isNull);
      pending.complete({'tagId': 't1'});
      await tester.pumpAndSettle();
      expect(got?.tagId, 't1');
      expect(got?.backfill, isTrue);
      expect(sentDesc, 'Baking and starters');
    });

    testWidgets('a refusal stays on the form with the server sentence',
        (tester) async {
      ShelfCreated? got;
      await _host(
          tester,
          ShelfFormFields(
            canBackfill: true,
            onCreated: (c) => got = c,
            create: (title, {description, color}) async =>
                throw const ApiException(400, 'A shelf named Bread exists.'),
          ));
      await tester.enterText(find.byType(TextField).first, 'Bread');
      await tester.pump();
      await tester.tap(find.text('Create shelf'));
      await tester.pump();
      expect(got, isNull);
      expect(find.text('A shelf named Bread exists.'), findsOneWidget);
      expect(find.text('Create shelf'), findsOneWidget);
    });
  });

  group('the review', () {
    testWidgets('reading draws no figure; the proposal is all checked',
        (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await _host(
          tester,
          ShelfBackfillReview(
            tagId: 't1',
            title: 'Bread',
            onDone: () {},
            onCancel: () {},
            suggest: (_) => pending.future,
            apply: (_, __) async => {},
          ));
      expect(find.text('Reading your library…'), findsOneWidget);
      pending.complete(_two());
      await tester.pumpAndSettle();
      expect(find.text('File 2 sources'), findsOneWidget);
      expect(find.text('About bread.'), findsOneWidget);
      await tester.tap(find.text('Rye ratios'));
      await tester.pump();
      expect(find.text('File 1 source'), findsOneWidget);
    });

    testWidgets('nothing fits is a considered answer, not a failure',
        (tester) async {
      await _host(
          tester,
          ShelfBackfillReview(
            tagId: 't1',
            title: 'Bread',
            onDone: () {},
            onCancel: () {},
            suggest: (_) async => {'scanned': 12, 'candidates': []},
          ));
      expect(find.textContaining('looks like it belongs on'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('INV-29: a failed suggest is never the nothing-fits sentence',
        (tester) async {
      await _host(
          tester,
          ShelfBackfillReview(
            tagId: 't1',
            title: 'Bread',
            onDone: () {},
            onCancel: () {},
            suggest: (_) async =>
                throw const ApiException(502, 'Upstream down'),
          ));
      expect(find.textContaining('could not be matched against Bread'),
          findsOneWidget);
      expect(find.textContaining('looks like it belongs on'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('apply sends the checked ids in pool order; a refusal stays',
        (tester) async {
      List<String>? sent;
      var done = false;
      await _host(
          tester,
          ShelfBackfillReview(
            tagId: 't1',
            title: 'Bread',
            onDone: () => done = true,
            onCancel: () {},
            suggest: (_) async => _two(),
            apply: (tagId, ids) async {
              sent = ids;
              throw const ApiException(400, 'd2 is not complete.');
            },
          ));
      await tester.tap(find.text('File 2 sources'));
      await tester.pump();
      expect(sent, ['d1', 'd2']);
      expect(done, isFalse);
      expect(find.text('d2 is not complete.'), findsOneWidget);
    });
  });

  testWidgets('the sheet holds — scrim included — while filing',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final filing = Completer<Map<String, dynamic>>();
    String? landed;
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (c) {
        host = c;
        return const Scaffold();
      }),
    ));
    showShelfSheet(
      host,
      canBackfill: true,
      backfillFor: const BackfillFor('t1', 'Bread'),
      land: (id) => landed = id,
      suggest: (_) async => _two(),
      apply: (_, __) => filing.future,
    );
    await tester.pumpAndSettle();
    expect(find.text('Fill Bread'), findsOneWidget);
    await tester.tap(find.text('File 2 sources'));
    await tester.pump();
    // The scrim, while the call is in flight, does nothing.
    await tester.tapAt(const Offset(5, 1390));
    await tester.pumpAndSettle();
    expect(find.text('Fill Bread'), findsOneWidget);
    filing.complete({'filed': 2});
    await tester.pumpAndSettle();
    expect(find.text('Fill Bread'), findsNothing);
    expect(landed, 't1');
  });

  testWidgets('the rail sheet continues from the form into the review',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (c) {
        host = c;
        return const Scaffold();
      }),
    ));
    showShelfSheet(
      host,
      canBackfill: true,
      land: (_) {},
      create: (title, {description, color}) async => {'tagId': 't9'},
      suggest: (_) async => {'scanned': 3, 'candidates': []},
    );
    await tester.pumpAndSettle();
    expect(find.text('New shelf'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Bread');
    await tester.pump();
    await tester.tap(find.text('Create shelf'));
    await tester.pumpAndSettle();
    expect(find.text('Fill Bread'), findsOneWidget);
    expect(find.textContaining('looks like it belongs on'), findsOneWidget);
  });
}

Future<Map<String, dynamic>> _never(String title,
        {String? description, String? color}) =>
    Completer<Map<String, dynamic>>().future;
