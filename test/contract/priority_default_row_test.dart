// F-104 — 4.118.0 (ADR-155): every search result carries
// `source_priority_set`, the SERVER's answer to "did the reader weight this
// source?", and the score explainer's Source-priority row reads *default*
// while it is false (screens/search.md; web SearchView `PRIORITY_HINT`,
// `.pop-default`). A stored 0.5 is the default or a choice, and the number
// cannot say which: nothing here is inferred from it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cohesive_reading.dart';
import 'package:flutter_app/models/search_result.dart';
import 'package:flutter_app/pages/search/score_explainer.dart';
import 'package:flutter_app/theme/app_theme.dart';

import 'fixtures.dart';

Map<String, dynamic> _body(String suite, String id) {
  final s = loadSuite('api/$suite')!;
  final c = (s['cases'] as List).firstWhere((c) => (c as Map)['id'] == id)
      as Map;
  return ((c['response'] as Map)['body'] as Map).cast<String, dynamic>();
}

Future<void> _open(WidgetTester tester, bool? set) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SearchScoreAnchor(
          score: 0.8543,
          cosine: 0.9428,
          sourcePriority: 0.5,
          sourcePrioritySet: set,
          child: const Text('0.85'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('0.85'));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  test('the captured answers carry the flag, read as the server says', () {
    final raw = ((_body('search', 'search:recipes-query')['results'] as List)
            .first as Map)
        .cast<String, dynamic>();
    final r = SearchResult.fromJson(raw);
    expect(r.sourcePriority, 0.5);
    expect(r.sourcePrioritySet, isFalse,
        reason: 'the seed weights nothing: every result is at the default');
    expect(SearchResult.fromJson({...raw, 'source_priority_set': true})
            .sourcePrioritySet,
        isTrue);
    expect(SearchResult.fromJson({...raw}..remove('source_priority_set'))
            .sourcePrioritySet,
        isNull,
        reason: 'absent is an older response, never false');
  });

  test('the cohesive passages carry it too', () {
    final sections = _body('search-cohesive', 'cohesive:normal')['sections']
        as List;
    final p = (((sections.first as Map)['passages'] as List).first as Map)
        .cast<String, dynamic>();
    expect(p['source_priority_set'], isFalse);
    expect(CohesivePassage.fromJson(p).sourcePrioritySet, isFalse);
  });

  testWidgets('unweighted: the row says default, not a half-full bar',
      (tester) async {
    await _open(tester, false);
    expect(find.text('default · 0.50'), findsOneWidget);
    expect(
        find.text(
            'You have not weighted this source, so it counts at the default.'),
        findsOneWidget);
    expect(find.text('0.1000'), findsOneWidget,
        reason: 'the contribution is still the measured arithmetic');
  });

  testWidgets('weighted: the bar, and the weight is the reader\'s',
      (tester) async {
    await _open(tester, true);
    expect(find.textContaining('default ·'), findsNothing);
    expect(find.text('The weight you gave this source.'), findsOneWidget);
  });

  testWidgets('an older response draws as before', (tester) async {
    await _open(tester, null);
    expect(find.textContaining('default ·'), findsNothing);
    expect(
        find.text('The weight you gave this source. Defaults to 0.50 when '
            'you have not set one.'),
        findsOneWidget);
  });
}
