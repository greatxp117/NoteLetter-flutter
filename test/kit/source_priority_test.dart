// screens/reader.md §Source priority (4.118.0, ADR-155; ruled into the reader
// 2026-10-13), mirroring web's tests/contract/source-priority-control.test.js.
// Default sends `sourcePriority: null`, every other segment a number; the lit
// segment is read off the STAMP, never the number; and the segment moves only
// once fn_update_document has accepted the write.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/source_priority.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _stamp = 1760000000000;

/// A document as Firestore hands it over: `source_priority_set_at` present
/// only once the reader chose (the model reads it through tsMs, INV-06).
Document _doc({Object? priority = 0.5, Object? stamp}) =>
    Document.fromJson('d1', {
      'user_id': 'u',
      'title': 'Quarterly Tax Summary',
      'type': 'pdf',
      'status': 'complete',
      'source_priority': ?priority,
      'source_priority_set_at': ?stamp,
    });

void main() {
  group('which segment is lit', () {
    test('reads the stamp, never the number: no stamp is Default whatever the value', () {
      expect(priorityChoice(_doc()), 'default');
      expect(priorityChoice(_doc(priority: 0.9)), 'default');
      expect(priorityChoice(_doc(priority: 0.5, stamp: _stamp)), 'normal');
    });

    test('a number another client chose lights the band it falls in', () {
      String at(double v) => priorityChoice(_doc(priority: v, stamp: _stamp));
      expect([at(0), at(0.2), at(0.3)], ['low', 'low', 'low']);
      expect([at(0.31), at(0.65), at(0.79)], ['normal', 'normal', 'normal']);
      expect([at(0.8), at(1)], ['high', 'high']);
    });

    test('every segment it can send lights itself', () {
      for (final c in priorityChoices) {
        final doc = c.value == null
            ? _doc()
            : _doc(priority: c.value, stamp: _stamp);
        expect(priorityChoice(doc), c.id);
      }
    });

    test('the values are the reference\'s: Default null, Low 0.2, Normal 0.5, High 0.8', () {
      expect([for (final c in priorityChoices) (c.label, c.value)], [
        ('Default', null),
        ('Low', 0.2),
        ('Normal', 0.5),
        ('High', 0.8),
      ]);
    });

    test('an absent number is null on the model — nothing is solved for', () {
      final d = _doc(priority: null);
      expect(d.sourcePriority, isNull);
      expect(priorityChoice(d), 'default');
    });

    test('an accepted write commits what was sent: a number stamps, null resets', () {
      final high = _doc().withSourcePriority(0.8);
      expect((high.sourcePriority, high.sourcePrioritySetAt != null), (0.8, true));
      expect(priorityChoice(high), 'high');
      final back = high.withSourcePriority(null);
      expect((back.sourcePriority, back.sourcePrioritySetAt), (0.5, null));
      expect(priorityChoice(back), 'default');
      // A stamp already read is kept: the screen draws whether there is one,
      // never the moment.
      final again = _doc(priority: 0.2, stamp: _stamp).withSourcePriority(0.5);
      expect(again.sourcePrioritySetAt, _stamp);
    });
  });

  group('the Priority row', () {
    late List<(String, double?)> calls;
    late List<double?> saved;
    late Future<void> Function() answer;

    setUp(() {
      calls = [];
      saved = [];
      answer = () async {};
    });

    Future<void> mount(WidgetTester tester, Document doc) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SourcePriorityRow(
            docId: 'd1',
            doc: doc,
            onSaved: saved.add,
            update: (id, v) {
              calls.add((id, v));
              return answer();
            },
          ),
        ),
      ));
    }

    // Kit §34's switch in direction D (§6.8's segmented control before it).
    KitSlideSwitch<String> sw(WidgetTester tester) => tester
        .widget<KitSlideSwitch<String>>(find.byType(KitSlideSwitch<String>));

    String lit(WidgetTester tester) {
      final s = sw(tester);
      return priorityChoices.firstWhere((c) => c.id == s.value).label;
    }

    testWidgets('draws Default lit and the stored number beside it while unset',
        (tester) async {
      await mount(tester, _doc());
      expect(lit(tester), 'Default');
      expect(find.text('0.50'), findsOneWidget);
      expect(find.text('PRIORITY'), findsOneWidget);
      expect(
          find.text('How much this source weighs in search and your letters — '
              'a nudge, not a guarantee.'),
          findsOneWidget);
    });

    testWidgets('draws no figure for a document with no number', (tester) async {
      await mount(tester, _doc(priority: null));
      expect(find.textContaining(RegExp(r'^\d\.\d\d$')), findsNothing);
    });

    testWidgets('High sends 0.8 and commits only after the server accepts it',
        (tester) async {
      final gate = Completer<void>();
      answer = () => gate.future;
      await mount(tester, _doc());
      await tester.tap(find.text('High'));
      await tester.pump();
      expect(calls, [('d1', 0.8)]);
      // In flight: nothing has moved, the pressed segment says so, and the
      // track is held.
      expect(saved, isEmpty);
      expect(find.text('Saving…'), findsOneWidget);
      expect(lit(tester), 'Default');
      expect(sw(tester).held, isTrue);
      await tester.tap(find.text('Low'));
      await tester.pump();
      expect(calls, [('d1', 0.8)], reason: 'a held track sends nothing');
      gate.complete();
      await tester.pumpAndSettle();
      expect(saved, [0.8]);
      expect(find.text('Saving…'), findsNothing);
    });

    testWidgets('Default sends null — the reset ADR-155 defines', (tester) async {
      await mount(tester, _doc(priority: 0.8, stamp: _stamp));
      expect(lit(tester), 'High');
      expect(find.text('0.80'), findsOneWidget);
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      expect(calls, [('d1', null)]);
      expect(saved, [null]);
    });

    testWidgets('pressing the lit segment sends nothing', (tester) async {
      await mount(tester, _doc());
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(saved, isEmpty);
    });

    testWidgets('a refusal stays under the row (§14.2) and nothing moves',
        (tester) async {
      answer = () async => throw const ApiException(
          400, 'sourcePriority must be a number between 0.0 and 1.0, or null.');
      await mount(tester, _doc());
      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(
          find.text('sourcePriority must be a number between 0.0 and 1.0, or null.'),
          findsOneWidget);
      expect(saved, isEmpty);
      expect(lit(tester), 'Default');
    });
  });
}
