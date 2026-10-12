// F-89 — Suggest shelves (4.116.0, ADR-153; ruled 2026-10-08:
// screens/library.md §Suggesting shelves, screens/onboarding.md), over the
// captured `api/tags` answers, as web's tests/contract/suggest-shelves.test.js
// reads them. The request builders are the request suite's; this is what the
// screens do with the answers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/onboarding/steps.dart';
import 'package:flutter_app/pages/tags/suggest_shelves.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'fixtures.dart';

Map<String, dynamic> _case(String id) {
  final suite = loadSuite('api/tags')!;
  return ((suite['cases'] as List)
          .firstWhere((c) => (c as Map)['id'] == id) as Map)
      .cast<String, dynamic>();
}

Map<String, dynamic> _body(String id) =>
    ((_case(id)['response'] as Map)['body'] as Map).cast<String, dynamic>();

ApiException _refusal(String id) {
  final r = (_case(id)['response'] as Map).cast<String, dynamic>();
  final b = (r['body'] as Map).cast<String, dynamic>();
  return ApiException(r['status'] as int, b['error'] as String,
      errorCode: b['error_code'] as String?, requestId: 'req-1');
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(402, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
}

void main() {
  group('the shared state', () {
    test('asks with the words, keeps every proposal, says what was left out',
        () async {
      String? asked;
      final s = ShelfSuggestions(seed: 'food and where it comes from',
          suggest: (p) async {
        asked = p;
        return _body('tags:suggest');
      });
      await s.ask();
      expect(asked, 'food and where it comes from');
      expect(s.phase, SuggestPhase.review);
      expect([for (final t in s.tags) t.title], ['Food History', 'Nutrition']);
      expect(s.existing, ['Cooking']);
      expect(s.chosen, [
        {
          'title': 'Food History',
          'description': 'Where dishes and ingredients come from.',
          'color': 'sage-500',
        },
        {
          'title': 'Nutrition',
          'description': 'Dietary science and ingredient nutrition facts.',
          'color': 'brick-500',
        },
      ], reason: 'all ticked, in the order answered, {title, description, color}');
      s.toggle(0);
      expect([for (final c in s.chosen) c['title']], ['Nutrition']);
    });

    test('a colour outside the ten takes a swatch by position', () {
      expect(proposalColor('#6B7280', 0), 'sage-500');
      expect(proposalColor('#6B7280', 3), 'brick-500');
      expect(proposalColor('plum-600', 7), 'plum-600');
    });

    test('a 4xx is the reader\'s to correct; a 502 is a read that failed',
        () async {
      final bad = ShelfSuggestions(seed: 'x',
          suggest: (_) async => throw _refusal('tags:suggest-unknown-field'));
      await bad.ask();
      expect(bad.askError, 'Unknown field(s): bogus');
      expect(bad.readError, isNull);
      expect(bad.phase, SuggestPhase.ask);

      final down = ShelfSuggestions(seed: 'x',
          suggest: (_) async => throw _refusal('tags:suggest-model-failed'));
      await down.ask();
      expect(down.readError, isA<ApiException>());
      expect(down.askError, isNull,
          reason: 'never "no shelves to suggest" for a request that failed');
    });

    test('the seed holds until the reader types', () {
      final s = ShelfSuggestions(seed: 'first mission');
      s.seed('rewritten mission');
      expect(s.field.text, 'rewritten mission');
      s.typed();
      s.seed('another');
      expect(s.field.text, 'rewritten mission');
    });
  });

  group('the sheet', () {
    testWidgets('asks, reviews, and creates with ONE fn_approve_tags',
        (tester) async {
      List<Map<String, dynamic>>? sent;
      List<String>? made;
      var closed = false;
      await _pump(
          tester,
          SuggestShelvesBody(
            canBackfill: true,
            onBusy: (_) {},
            close: () => closed = true,
            onCreated: (titles, ids, backfill) => made = ids,
            suggest: (_) async => _body('tags:suggest-new-only'),
            approve: (tags) async {
              sent = tags;
              return _body('tags:approve');
            },
          ));
      expect(find.text('WHAT DO YOU READ ABOUT?'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('suggest-purpose')),
          'cooking and nutrition');
      await tester.pump();
      await tester.tap(find.text('Suggest shelves'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('for what you read about.', findRichText: true),
          findsOneWidget);
      expect(find.text('Also suggested, and already on your shelves: '
          'Food History.'), findsOneWidget);
      expect(find.text('Find sources that belong on them'), findsOneWidget);
      await tester.tap(find.text('Create 2 shelves'));
      await tester.pump();
      await tester.pump();
      expect(sent!.length, 2);
      expect(closed, isTrue);
      expect(made!.length, 2);
    });

    testWidgets('a refused create keeps the sheet open with its sentence',
        (tester) async {
      var closed = false;
      await _pump(
          tester,
          SuggestShelvesBody(
            canBackfill: false,
            onBusy: (_) {},
            close: () => closed = true,
            onCreated: (_, _, _) {},
            suggest: (_) async => _body('tags:suggest'),
            approve: (_) async => throw _refusal('tags:approve-existing-title'),
          ));
      await tester.enterText(
          find.byKey(const ValueKey('suggest-purpose')), 'food');
      await tester.pump();
      await tester.tap(find.text('Suggest shelves'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Find sources that belong on them'), findsNothing,
          reason: 'no complete source, no follow-on row');
      await tester.tap(find.text('Create 2 shelves'));
      await tester.pump();
      await tester.pump();
      expect(closed, isFalse);
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('a failed read is §14.1, never "nothing to suggest"',
        (tester) async {
      await _pump(
          tester,
          SuggestShelvesBody(
            canBackfill: false,
            onBusy: (_) {},
            close: () {},
            onCreated: (_, _, _) {},
            suggest: (_) async => throw _refusal('tags:suggest-model-failed'),
          ));
      await tester.enterText(
          find.byKey(const ValueKey('suggest-purpose')), 'food');
      await tester.pump();
      await tester.tap(find.text('Suggest shelves'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(find.text('Shelves could not be suggested.'), findsOneWidget);
      expect(find.textContaining('no shelves to suggest'), findsNothing);
    });
  });

  group('onboarding', () {
    testWidgets('the shelves step holds the ticks and says they wait for Finish',
        (tester) async {
      final s = ShelfSuggestions(seed: 'food',
          suggest: (_) async => _body('tags:suggest-first-shelves'));
      await _pump(tester, ShelvesStep(s: s));
      expect(find.textContaining('№ 03 · OF 04'), findsOneWidget);
      expect(find.textContaining('You can skip this'), findsOneWidget);
      await s.ask();
      await _pump(tester, ShelvesStep(s: s));
      expect(find.textContaining('will be created when you finish.'),
          findsOneWidget);
      expect(find.text('Create 2 shelves'), findsNothing,
          reason: 'the step has no create of its own');
    });

    testWidgets('the summary: Your sources, then Your shelves', (tester) async {
      await _pump(
          tester,
          DoneStep(
            documents: const [],
            preset: 'teacher',
            frequency: 'weekdays',
            time: '07:00',
            count: 3,
            readings: false,
            shelves: const ['Food History', 'Nutrition'],
            saving: false,
            error: null,
            goTo: (_) {},
          ));
      expect(find.text('Your sources'), findsOneWidget);
      expect(find.text('Your shelves'), findsOneWidget);
      expect(find.text('2 to create · Food History · Nutrition'), findsOneWidget);
    });
  });
}
