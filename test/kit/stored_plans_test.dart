// screens/review.md §Proposals (4.103.0, ADR-136): the syllabus plan editor
// and the reorganize sheet over a stored proposal. The editor sends the
// reader's EDITED plan (camelCase, as the decision is closed to) and drops what
// cannot be applied with a sentence; the reorganize sheet reads nothing, applies
// the operations through the seam, and answers a 409 STALE with Run again —
// `retry` — which closes the sheet.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/reader/reorganize_sheet.dart';
import 'package:flutter_app/pages/study/syllabus_plan_editor.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

import '../contract/sources_harness.dart' show SourcesStubService;

const _proposal = {
  'units': [
    {'topic': 'Espresso extraction basics', 'startsOn': '2026-01-05'},
    {'topic': 'Sourdough hydration', 'startsOn': null},
  ],
  'assessments': [
    {'title': 'Midterm', 'on': '2026-02-01', 'assessmentKind': 'exam', 'cumulative': false},
    {'title': 'Reflection paper', 'on': '2026-03-01', 'assessmentKind': 'paper', 'cumulative': false},
  ],
  'skipped': [
    {'label': 'Thanksgiving', 'on': '2026-01-15', 'reason': 'non_teaching'},
  ],
  'notes': '',
};

void main() {
  group('syllabus plan editor', () {
    Future<List<List<List<Map<String, dynamic>>>>> mount(WidgetTester tester,
        {Map<String, dynamic> proposal = _proposal}) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sent = <List<List<Map<String, dynamic>>>>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SyllabusPlanEditor(
              proposal: proposal,
              onApply: (u, a) => sent.add([u, a]),
              onDiscard: () {},
              discardLabel: 'Not now',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('seeds from the stored result and applies the edited plan',
        (tester) async {
      final sent = await mount(tester);
      expect(find.text('2026-01-05'), findsOneWidget, reason: 'startsOn read in camelCase');
      expect(find.text('A paper I hand in'), findsOneWidget);
      expect(find.textContaining('Thanksgiving · 2026-01-15 — a week that teaches nothing'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '  ');
      await tester.pump();
      await tester.tap(find.text('Apply this plan'));
      await tester.pump();
      expect(sent.single[0], [
        {'topic': 'Espresso extraction basics', 'startsOn': '2026-01-05'},
      ], reason: 'an emptied topic is not sent');
      expect(sent.single[1], [
        {'title': 'Midterm', 'on': '2026-02-01', 'assessmentKind': 'exam', 'cumulative': false},
        {'title': 'Reflection paper', 'on': '2026-03-01', 'assessmentKind': 'paper', 'cumulative': false},
      ]);
    });

    testWidgets('nothing read: the sentence, and Apply waits for a topic',
        (tester) async {
      final sent = await mount(tester,
          proposal: const {'units': [], 'assessments': [], 'skipped': [], 'notes': 'A photograph.'});
      expect(find.textContaining('Nothing usable could be read'), findsOneWidget);
      expect(find.textContaining('A photograph.'), findsOneWidget);
      await tester.tap(find.text('Apply this plan'));
      await tester.pump();
      expect(sent, isEmpty);
    });
  });

  group('reorganize sheet from a stored plan', () {
    const plan = {
      'plan_id': 'p1',
      'document_id': 'd1',
      'status': 'draft',
      'sections': [
        {
          'section_id': 's1',
          'title': 'Kitchen notes',
          'summary': '',
          'destinations': [
            {'kind': 'document', 'document_id': 'd2', 'title': 'Kitchen', 'score': 0.9},
          ],
        },
      ],
    };

    testWidgets('a 409 STALE offers Run again, which retries and closes',
        (tester) async {
      FirestoreService.instance = SourcesStubService();
      addTearDown(FirestoreService.resetInstance);
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final applied = <List<Map<String, dynamic>>>[];
      var reran = 0;
      late BuildContext host;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(builder: (c) {
          host = c;
          return const Scaffold();
        }),
      ));
      ReorganizeSheet.show(host, 'd1', () {},
          stored: StoredReorg(
            // As Firestore delivers it: untyped lists, never a const literal's.
            result: (jsonDecode(jsonEncode(plan)) as Map).cast<String, dynamic>(),
            apply: (ops) async {
              applied.add(ops);
              throw const ApiException(409,
                  'This document changed after the plan was made — analyze it again.',
                  errorCode: 'STALE');
            },
            rerun: () async => reran++,
          ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reading the document'), findsNothing,
          reason: 'a stored plan reads nothing');
      await tester.tap(find.text('Reorganize 1 section'));
      await tester.pumpAndSettle();
      if (find.text('Yes, reorganize').evaluate().isNotEmpty) {
        await tester.tap(find.text('Yes, reorganize'));
        await tester.pumpAndSettle();
      }
      expect(applied.single.single['section_id'], 's1');
      expect(find.textContaining('analyze it again'), findsOneWidget);
      await tester.tap(find.text('Run again'));
      await tester.pumpAndSettle();
      expect(reran, 1);
      expect(find.text('Run again'), findsNothing, reason: 'the sheet closed');
    });
  });
}
