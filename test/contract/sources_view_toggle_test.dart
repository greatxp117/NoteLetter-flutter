import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// F-65 — Sources' list / cards / shelf view toggle (web `SourcesBrowse.jsx`
/// `.view-toggle`, `pickView`, `ShelfView`).
///
/// Each case is one clause of what the reference does: the shelf is the
/// default, the choice is written per viewer under `nl-sources-view` BEFORE
/// the view moves, a stored choice is what the screen opens on, and each
/// position draws its own component — rows, cards, spines.

Document _doc(String id, String title, {String type = 'pdf', int n = 3}) =>
    Document.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'type': type,
      'status': 'complete',
      'chunk_count': n,
      'created_at': 1750000000000,
    });

final _docs = [
  _doc('d1', 'Quarterly Tax Summary'),
  _doc('d2', 'Espresso Article', type: 'article', n: 5),
  _doc('d3', 'Sourdough Notes', type: 'plain', n: 1),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpSources(tester, SourcesStubService(documents: Stream.value(_docs)));
  await tester.pump();
  await tester.pump();
}

Finder _toggle(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

void main() {
  setUp(() {
    LocalFlags.resetForTest();
    LocalFlags.sourcesView.value = 'shelf';
  });

  testWidgets('the shelf is the default — spines, not rows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    expect(find.byType(KitShelfView), findsOneWidget);
    expect(find.byType(KitBookSpine), findsNWidgets(3));
    expect(find.text('RECENTLY ADDED · 3'), findsOneWidget,
        reason: 'one ledge in the chosen order, labelled by it');
    expect(_toggle('Shelf view'), findsOneWidget);
    expect(_toggle('List view'), findsOneWidget);
    expect(_toggle('Card view'), findsOneWidget);
  });

  testWidgets('a pick is written under nl-sources-view, then drawn',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);

    await tester.tap(_toggle('List view'));
    await tester.pump();
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nl-sources-view'), 'list');
    expect(find.byType(KitBookSpine), findsNothing);
    expect(find.text('Espresso Article'), findsOneWidget);
    expect(find.byType(KitSourceRow), findsWidgets);

    await tester.tap(_toggle('Card view'));
    await tester.pump();
    await tester.pump();
    expect(prefs.getString('nl-sources-view'), 'cards');
    expect(find.byType(KitSourceCard), findsNWidgets(3));
    expect(find.text('WEB CLIPS'), findsOneWidget,
        reason: 'a card names its kind as the reference KIND_NAME spells it');
  });

  testWidgets('a stored choice is what the screen opens on', (tester) async {
    SharedPreferences.setMockInitialValues({'nl-sources-view': 'cards'});
    await _pump(tester);
    expect(find.byType(KitSourceCard), findsNWidgets(3));
    expect(find.byType(KitShelfView), findsNothing);
  });

  testWidgets('an unknown stored value reads as the shelf, not a blank',
      (tester) async {
    SharedPreferences.setMockInitialValues({'nl-sources-view': 'table'});
    await _pump(tester);
    expect(find.byType(KitShelfView), findsOneWidget);
  });

  testWidgets('Type groups the shelf by kind under the shelf\'s labels',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.tap(find.text('Type'));
    await tester.pump();
    expect(find.text('DOCUMENTS · 1'), findsOneWidget);
    expect(find.text('WEB CLIPS · 1'), findsOneWidget);
    expect(find.text('NOTES · 1'), findsOneWidget);
  });

  testWidgets('a spine pulls its detail card, and a second tap puts it back',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.tap(find.byType(KitBookSpine).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KitBookDetail), findsOneWidget);
    expect(find.text('Open in reader'), findsOneWidget);
    expect(find.text('Find a passage'), findsOneWidget);
    await tester.tap(find.byType(KitBookSpine).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KitBookDetail), findsNothing);
  });
}
