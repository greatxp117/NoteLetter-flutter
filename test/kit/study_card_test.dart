/// A study program on /study is web's `.st-prog` (StudyView.jsx ProgramCard):
/// the body (title and chip, the measured figure, a 2-high meter, the
/// schedule) beside — on a phone, above — the switch, Study now and Settings;
/// then the §12 notice and the hint, each across the whole card.
///
/// Found 2026-10-14 by the study-wait frame against web's phone frame: this
/// client drew the notice and the hint ABOVE the controls, the notice with
/// Material's circled "!" passed in over the pattern's own triangle, the hint
/// with no glyph and no rule, the chip on the title's right, and a 4-high
/// meter in the accent on the sunken ground.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/study_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Stub extends FirestoreService {
  _Stub(this.programs) : super.stub();
  final List<StudyProgram> programs;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => Stream.value(programs);

  @override
  Stream<List<StudySession>> subscribeStudySessions(
          {String? programId, int limit = 30}) =>
      Stream.value(const []);
}

StudyProgram _program({bool enabled = true}) =>
    StudyProgram.fromJson('p1', {
      'title': 'Cooking fundamentals',
      'document_ids': ['d1'],
      'enabled': enabled,
      'status': 'active',
      'introduced_count': 2,
      'unit_count': 5,
      'material_runway': 1,
    });

Future<void> _pump(WidgetTester tester, StudyProgram p,
    {double width = 402}) async {
  FirestoreService.instance = _Stub([p]);
  tester.view.physicalSize = Size(width * 3, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  addTearDown(FirestoreService.resetInstance);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: const StudyPage())),
  ));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  testWidgets('on a phone: body, then the switch / Study now / Settings, then '
      'the notice, then the hint', (tester) async {
    await _pump(tester, _program(enabled: false));
    final studyNow = find.widgetWithText(KitButton, 'Study now');
    final notice = find.byType(KitNotice);
    final hint = find.textContaining('Turning this on sends the first session');
    expect(notice, findsOneWidget);
    expect(hint, findsOneWidget);
    expect(_top(tester, find.text('OFF')),
        lessThanOrEqualTo(_top(tester, studyNow) + 12),
        reason: 'the switch leads the controls, as web\'s .st-sw does');
    expect(_top(tester, studyNow), lessThan(_top(tester, notice)),
        reason: 'the controls come before the notice');
    expect(_top(tester, notice), lessThan(_top(tester, hint)),
        reason: 'the hint closes the card');
    expect(
        _top(tester, find.textContaining('Daily at')) <
            _top(tester, studyNow),
        isTrue);
  });

  testWidgets('the notice draws the pattern\'s own glyph; the hint its alert '
      'glyph under a rule', (tester) async {
    await _pump(tester, _program(enabled: false));
    expect(
        find.descendant(
            of: find.byType(KitNotice),
            matching: find.byIcon(Icons.error_outline)),
        findsNothing,
        reason: 'KitNotice owns its glyph (the reference hardcodes IcoAlert)');
    expect(
        find.descendant(
            of: find.byType(KitNotice),
            matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    final hintRow = find.ancestor(
        of: find.textContaining('Turning this on sends the first session'),
        matching: find.byType(Row));
    expect(
        find.descendant(
            of: hintRow.first,
            matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
  });

  testWidgets('the chip is sunken mono caps with a dot; the meter is 2 high in '
      'the seal on the rule', (tester) async {
    await _pump(tester, _program());
    final chip = tester.widget<Text>(find.text('ACTIVE'));
    expect(chip.style?.fontFamily, AppTheme.fontMono);
    expect(chip.style?.fontSize, 10);
    final ctx = tester.element(find.text('ACTIVE'));
    final t = Tokens.of(ctx);
    final meter = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxHeight == 2 &&
        w.color == t.rule);
    expect(meter, findsOneWidget, reason: 'web .st-meter: 2px on --rule');
    expect(
        find.descendant(
            of: meter,
            matching: find.byWidgetPredicate(
                (w) => w is Container && w.color == t.seal)),
        findsOneWidget,
        reason: 'the filled part is --seal');
  });

  testWidgets('at 768 and up the controls are a side column beside the body',
      (tester) async {
    await _pump(tester, _program(), width: 1024);
    final studyNow = find.widgetWithText(KitButton, 'Study now');
    final title = find.text('Cooking fundamentals');
    expect(tester.getTopLeft(studyNow).dx,
        greaterThan(tester.getTopRight(title).dx),
        reason: 'beside the body, not under it');
    expect(_top(tester, studyNow), lessThan(_top(tester, find.byType(KitNotice))));
  });
}
