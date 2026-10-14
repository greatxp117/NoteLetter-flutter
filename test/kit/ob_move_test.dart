/// Onboarding's numbered move draws web's `.ob-move`, read from the
/// reference's stylesheet rather than restated here.
///
/// It drew 11/0.12em at `--fg-muted`, a 17/22 title, a 4 gap and a 13/19
/// line (found 2026-10-13, TODO "Found by Flutter") — the move's third
/// spelling, the reference's neither. Measured in Chromium over web's CSS:
/// the numeral sits on the body's 24 line, so a one-line move is 107.6px
/// (16 + 24 + 4 + 24 + 3 + 19.6 + 16 and a 1px rule), and moves are 2 apart.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

String _css(String f) =>
    File('../NoteLetter-web/src/styles/$f').readAsStringSync();

/// [prop] in the last rule whose selector is exactly [sel].
String _prop(String sheet, String sel, String prop) {
  final esc = RegExp.escape(sel);
  final rules = RegExp('(?:^|[}\\n])\\s*$esc\\s*\\{([^}]*)\\}')
      .allMatches(sheet)
      .toList();
  if (rules.isEmpty) throw StateError('$sel has no rule');
  final m = RegExp('(?:^|[;{\\s])${RegExp.escape(prop)}:\\s*([^;]+);')
      .firstMatch(rules.last.group(1)!);
  if (m == null) throw StateError('$sel sets no $prop');
  return m.group(1)!.trim();
}

double _num(String v, [String unit = 'px']) {
  if (!v.endsWith(unit)) throw StateError('$v is not in $unit');
  return double.parse(v.substring(0, v.length - unit.length));
}

TextStyle _style(WidgetTester tester, String text) {
  final f = find.byWidgetPredicate((w) => w is Text && w.data == text);
  expect(f, findsOneWidget, reason: text);
  return tester.widget<Text>(f).style!;
}

void main() {
  final ob = _css('app-onboarding-wizard.css');
  final theme = _css('theme.css');
  // `.ob-move-no` and `.ob-move-t` set no line-height: they take the body's,
  // `line-height: var(--lh-base)`.
  final bodyLine = _num(RegExp(r'--lh-base:\s*([^;]+);')
      .firstMatch(theme)!
      .group(1)!
      .trim());

  test('the reference still says what this test asserts', () {
    expect(_prop(ob, '.ob-move-no', 'color'), 'var(--fg-subtle)');
    expect(_prop(ob, '.ob-move-d', 'color'), 'var(--fg-muted)');
    expect(bodyLine, 24);
  });

  testWidgets('the ruled move draws .ob-move-no / -t / -d', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: KitNumberedMove(
          number: 'II',
          icon: Icons.mail_outline,
          title: 'Receive a daily letter',
          description: 'Each morning.',
          ruled: true,
          last: true,
        ),
      ),
    ));
    final ctx = tester.element(find.byType(KitNumberedMove));
    final t = Tokens.of(ctx);

    final no = _style(tester, 'II');
    expect(no.fontSize, _num(_prop(ob, '.ob-move-no', 'font-size')));
    expect(no.letterSpacing,
        closeTo(_num(_prop(ob, '.ob-move-no', 'letter-spacing'), 'em') * 11, 1e-9));
    expect(no.color, t.fgSubtle);
    expect(no.fontSize! * no.height!, closeTo(bodyLine, 1e-9));

    final title = _style(tester, 'Receive a daily letter');
    expect(title.fontSize, _num(_prop(ob, '.ob-move-t', 'font-size')));
    expect(title.fontWeight!.value,
        int.parse(_prop(ob, '.ob-move-t', 'font-weight')));
    expect(title.fontSize! * title.height!, closeTo(bodyLine, 1e-9));

    final d = _style(tester, 'Each morning.');
    expect(d.fontSize, _num(_prop(ob, '.ob-move-d', 'font-size')));
    expect(d.height, double.parse(_prop(ob, '.ob-move-d', 'line-height')));
    expect(d.color, t.fgMuted);

    // The gaps: the numeral's 4 bottom margin, the line's 3 top margin.
    final noBox = tester.getRect(find.text('II'));
    final tBox = tester.getRect(find.text('Receive a daily letter'));
    final dBox = tester.getRect(find.text('Each morning.'));
    expect(tBox.top - noBox.bottom,
        _num(_prop(ob, '.ob-move-no', 'margin-bottom')));
    expect(dBox.top - tBox.bottom, _num(_prop(ob, '.ob-move-d', 'margin-top')));
  });

  test('onboarding stacks its moves the .ob-moves gap apart', () {
    final steps = File('lib/pages/onboarding/steps.dart').readAsStringSync();
    final gap = _num(_prop(ob, '.ob-moves', 'gap'));
    expect(steps, contains('if (i > 0) const SizedBox(height: ${gap.toInt()})'),
        reason: '.ob-moves { gap: ${gap}px } between the welcome step\'s moves');
  });
}
