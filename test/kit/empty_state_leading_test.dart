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
String _lineHeight(String sheet, String sel) => _prop(sheet, sel, 'line-height');

/// [prop] in the last rule whose selector is exactly [sel].
String _prop(String sheet, String sel, String prop) {
  final esc = RegExp.escape(sel);
  final rules = RegExp('(?:^|[}\\n])\\s*$esc\\s*\\{([^}]*)\\}')
      .allMatches(sheet)
      .toList();
  // Read at load, outside any test, so a missing rule is an error, not an
  // expect (which may not run there).
  if (rules.isEmpty) throw StateError('$sel has no rule');
  final m = RegExp('(?:^|[;{\\s])${RegExp.escape(prop)}:\\s*([^;]+);')
      .firstMatch(rules.last.group(1)!);
  if (m == null) throw StateError('$sel sets no $prop');
  return m.group(1)!.trim();
}

/// `44ch` → 44.
double _chs(String v) {
  if (!v.endsWith('ch')) throw StateError('$v is not in ch');
  return double.parse(v.replaceAll('ch', ''));
}

/// `24px` (or a bare `0`) → 24.
double _pxOnly(String v) {
  if (v == '0') return 0;
  if (!v.endsWith('px')) throw StateError('$v is not in px');
  return double.parse(v.replaceAll('px', ''));
}

/// A `margin` shorthand's four sides, top first (`4px 0 26px`).
List<double> _margin(String v) {
  final p = v.split(RegExp(r'\s+')).map(_pxOnly).toList();
  return switch (p.length) {
    1 => [p[0], p[0], p[0], p[0]],
    2 => [p[0], p[1], p[0], p[1]],
    3 => [p[0], p[1], p[2], p[1]],
    _ => p,
  };
}

/// The `maxWidth` of the nearest [ConstrainedBox] above [text].
double _cap(WidgetTester tester, String text) {
  final box =
      find.ancestor(of: find.text(text), matching: find.byType(ConstrainedBox));
  return tester.widget<ConstrainedBox>(box.first).constraints.maxWidth;
}

/// CSS `ch` in [style]: the advance of `0`.
double _ch(TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: '0', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
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

  // The standfirst's measure and the gaps around Study's moves, read from the
  // reference (TODO 2026-10-13: Flutter capped every standfirst at 420 against
  // web's 44ch — 366 in the italic at "opsz" 18 — and put Study's moves 26
  // under it, where web's flex column adds the standfirst's 24 to the moves'
  // own 4, measured 28 in Chromium).
  final subCap = _chs(_prop(kit, '.empty-state-sub', 'max-width'));
  final quietCap =
      _chs(_prop(kit, '.empty-state-quiet .empty-state-sub', 'max-width'));
  final subGap = _margin(_prop(kit, '.empty-state-sub', 'margin'))[2];
  final studySubGap =
      _pxOnly(_prop(study, '.st-empty .empty-state-sub', 'margin-bottom'));
  final moves = _margin(_prop(study, '.st-moves', 'margin'));
  final movesGap = _pxOnly(_prop(study, '.st-moves', 'gap'));

  test('the reference caps at 44ch (48ch quiet) with 26 under it, and puts '
      'Study\'s moves 24 + 4 under it, 2 apart, 26 over its action', () {
    expect(subCap, 44);
    expect(quietCap, 48);
    expect(subGap, 26);
    expect(studySubGap, 24);
    expect(moves[0], 4);
    expect(moves[2], 26);
    expect(movesGap, 2);
  });

  testWidgets('the standfirst is capped at 44ch of its own face, 48ch quiet',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const line = 'Failed and skipped sources land here.';
    await tester.pumpWidget(_app(KitEmptyState(
      icon: Icons.inbox_outlined,
      title: 'Nothing waiting',
      standfirst: line,
      suggestions: [
        KitSuggestion(icon: Icons.add, label: 'Add a source', onTap: () {}),
      ],
    )));
    double? opsz(TextStyle st) =>
        st.fontVariations?.firstWhere((v) => v.axis == 'opsz').value;
    double named(String sel) => double.parse(RegExp(r'"opsz"\s*(\d+)')
        .firstMatch(_prop(kit, sel, 'font-variation-settings'))!
        .group(1)!);
    final s = _style(tester, line);
    // `.empty-state-sub` / `.empty-state-title` name their optical sizes.
    expect(opsz(s), named('.empty-state-sub'));
    expect(opsz(_style(tester, 'Nothing waiting')),
        named('.empty-state-title'));
    expect(_cap(tester, line), closeTo(subCap * _ch(s), 0.001));

    await tester.pumpWidget(_app(const KitEmptyState(
      quiet: true,
      icon: Icons.forum_outlined,
      title: 'Start a conversation',
      standfirst: line,
    )));
    final q = _style(tester, line);
    expect(_cap(tester, line), closeTo(quietCap * _ch(q), 0.001));
  });

  testWidgets('rows sit 26 under the standfirst; Study\'s moves 24 + 4, '
      '2 apart, with 26 to its action', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const line = 'Failed and skipped sources land here.';
    await tester.pumpWidget(_app(KitEmptyState(
      icon: Icons.inbox_outlined,
      title: 'Nothing waiting',
      standfirst: line,
      suggestions: [
        KitSuggestion(icon: Icons.add, label: 'Add a source', onTap: () {}),
      ],
    )));
    expect(
        tester.getTopLeft(find.byType(KitSuggestion)).dy -
            tester.getBottomLeft(find.text(line)).dy,
        subGap);

    const studyLine = 'One set of documents, learned properly.';
    await tester.pumpWidget(_app(KitEmptyState(
      icon: Icons.style_outlined,
      title: 'Go deeper on one subject',
      standfirst: studyLine,
      suggestions: const [
        KitNumberedMove(number: 'I', title: 'One subject', description: 'd1'),
        KitNumberedMove(
            number: 'II', title: 'Its own session', description: 'd2'),
      ],
      actions: [KitButton('New program', onPressed: () {})],
    )));
    // The group is the outermost Container over a move; a row the innermost.
    final group =
        find.ancestor(of: find.text('I'), matching: find.byType(Container)).last;
    final rect = tester.getRect(group);
    expect(rect.top - tester.getBottomLeft(find.text(studyLine)).dy,
        studySubGap + moves[0]);
    expect(tester.getTopLeft(find.byType(KitButton)).dy - rect.bottom, moves[2]);
    Rect row(String d) => tester.getRect(
        find.ancestor(of: find.text(d), matching: find.byType(Container)).first);
    expect(row('d2').top - row('d1').bottom, movesGap);
  });

  testWidgets('Study\'s move rows draw `.st-move`\'s own type', (tester) async {
    double size(String sel) => _pxOnly(_prop(study, sel, 'font-size'));
    await tester.pumpWidget(_app(const KitEmptyState(
      icon: Icons.style_outlined,
      title: 'Go deeper on one subject',
      standfirst: 'One set of documents, learned properly.',
      suggestions: [
        KitNumberedMove(number: 'I', title: 'One subject', description: 'd1'),
      ],
    )));
    final no = _style(tester, 'I');
    expect(no.fontSize, size('.st-move-no'));
    final em = double.parse(
        _prop(study, '.st-move-no', 'letter-spacing').replaceAll('em', ''));
    expect(no.letterSpacing, closeTo(em * no.fontSize!, 0.001));
    final t = _style(tester, 'One subject');
    expect(t.fontSize, size('.st-move-t'));
    expect(t.fontSize! * t.height!,
        closeTo(_px(_lineHeight(study, '.st-move-t'), t.fontSize!), 0.01));
    final d = _style(tester, 'd1');
    expect(d.fontSize, size('.st-move-d'));
    expect(d.fontSize! * d.height!,
        closeTo(_px(_lineHeight(study, '.st-move-d'), d.fontSize!), 0.01));
  });
}
