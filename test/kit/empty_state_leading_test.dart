/// §7 Empty state's leading: the kit and web stand (ruled 2026-10-13).
///
/// The title is serif 28/1.1 and the standfirst italic 16/24 (component-kit
/// §7, web `.empty-state-title` / `.empty-state-sub`); only Study's offer
/// keeps its documented 28/34 and 16/25 (`.st-empty`). This widget drew 34/25
/// on every screen, so Flutter matched web nowhere but Study. The figures
/// are read from the reference's stylesheets, not restated here.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

String _css(String f) =>
    File('../NoteLetter-web/src/styles/$f').readAsStringSync();

/// The `line-height` of the last rule whose selector is exactly [sel].
String _lineHeight(String sheet, String sel) {
  final esc = RegExp.escape(sel);
  final rules = RegExp('(?:^|[}\\n])\\s*$esc\\s*\\{([^}]*)\\}')
      .allMatches(sheet)
      .toList();
  // Read at load, outside any test, so a missing rule is an error, not an
  // expect (which may not run there).
  if (rules.isEmpty) throw StateError('$sel has no rule');
  final m = RegExp(r'line-height:\s*([^;]+);').firstMatch(rules.last.group(1)!);
  if (m == null) throw StateError('$sel sets no line-height');
  return m.group(1)!.trim();
}

/// A line-height in px for a [size]px face: `1.1` or `24px`.
double _px(String v, double size) =>
    v.endsWith('px') ? double.parse(v.replaceAll('px', '')) : double.parse(v) * size;

TextStyle _style(WidgetTester tester, String text) {
  final rich = find.byWidgetPredicate((w) =>
      (w is RichText && w.text.toPlainText() == text) ||
      (w is Text && (w.data == text || w.textSpan?.toPlainText() == text)));
  expect(rich, findsWidgets, reason: text);
  final w = tester.widget(rich.first);
  if (w is RichText) return w.text.style!;
  return (w as Text).style!;
}

void main() {
  final kit = _css('app-kit.css');
  final study = _css('app-study.css');
  final title = _px(_lineHeight(kit, '.empty-state-title'), 28);
  final sub = _px(_lineHeight(kit, '.empty-state-sub'), 16);
  final studyTitle = _px(_lineHeight(study, '.st-empty .empty-state-title'), 28);
  final studySub = _px(_lineHeight(study, '.st-empty .empty-state-sub'), 16);

  test('the reference still says 28/1.1 · 16/24, and Study 28/34 · 16/25', () {
    expect(title, closeTo(30.8, 0.01));
    expect(sub, 24);
    expect(studyTitle, 34);
    expect(studySub, 25);
  });

  testWidgets('every §7 but Study draws the kit\'s leading', (tester) async {
    await tester.pumpWidget(_app(KitEmptyState(
      icon: Icons.inbox_outlined,
      title: 'Nothing waiting',
      standfirst: 'Failed and skipped sources land here.',
      suggestions: [
        KitSuggestion(icon: Icons.add, label: 'Add a source', onTap: () {}),
      ],
    )));
    final t = _style(tester, 'Nothing waiting');
    expect(t.fontSize! * t.height!, closeTo(title, 0.01));
    final s = _style(tester, 'Failed and skipped sources land here.');
    expect(s.fontSize! * s.height!, closeTo(sub, 0.01));
  });

  testWidgets('Study\'s offer keeps its documented 28/34 · 16/25',
      (tester) async {
    await tester.pumpWidget(_app(const KitEmptyState(
      icon: Icons.style_outlined,
      title: 'Go deeper on one subject',
      standfirst: 'One set of documents, learned properly.',
      suggestions: [
        KitNumberedMove(number: 'I', title: 'One subject', description: 'd'),
      ],
    )));
    final t = _style(tester, 'Go deeper on one subject');
    expect(t.fontSize! * t.height!, closeTo(studyTitle, 0.01));
    final s = _style(tester, 'One set of documents, learned properly.');
    expect(s.fontSize! * s.height!, closeTo(studySub, 0.01));
  });
}
