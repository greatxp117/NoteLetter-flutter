/// KitStepper draws web's `.stepper` (app-responsive.css), read from the
/// stylesheet: it drew a 32 pill and the number in mono 15 until 2026-10-14,
/// found composing the program editor's session caps — no frame had shown
/// one (letter settings' steppers sit below a phone frame's fold).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

String _rule(String sheet, String sel) {
  final m = RegExp('(?:^|\\n)${RegExp.escape(sel)}\\s*\\{([^}]*)\\}')
      .firstMatch(sheet);
  if (m == null) throw StateError('$sel has no rule');
  return m.group(1)!;
}

String _prop(String rule, String prop) =>
    RegExp('(?:^|[;\\s])${RegExp.escape(prop)}:\\s*([^;]+);')
        .firstMatch(rule)!
        .group(1)!
        .trim();

double _px(String v) => double.parse(v.replaceAll('px', ''));

void main() {
  final css = File('../NoteLetter-web/src/styles/app-responsive.css')
      .readAsStringSync();
  final button = _rule(css, '.stepper button');
  final num = _rule(css, '.stepper .num');
  final stepper = _rule(css, '.stepper');

  testWidgets('buttons, number and gap are .stepper\'s', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: KitStepper(value: 5, min: 1, max: 20, onChanged: (_) {}),
        ),
      ),
    ));
    final minus = tester.getSize(find.ancestor(
        of: find.text('−'), matching: find.byType(Container)).first);
    expect(minus.width, _px(_prop(button, 'width')));
    expect(minus.height, _px(_prop(button, 'height')));
    final n = tester.widget<Text>(find.text('5'));
    expect(n.style!.fontSize, _px(_prop(num, 'font-size')));
    expect(n.style!.fontWeight!.value, int.parse(_prop(num, 'font-weight')));
    expect(n.style!.fontFamily, contains('Serif'));
    final wrap = tester.widget<Wrap>(find.descendant(
        of: find.byType(KitStepper), matching: find.byType(Wrap)));
    expect(wrap.spacing, _px(_prop(stepper, 'gap')));
  });
}
