/// Every held button is dimmed, by the shared token (ruled 2026-10-07;
/// component-kit §6.1 State — Held, design-tokens.md `--held-opacity`;
/// draft 4.108.0, ADR-145).
///
/// This client dimmed a held [KitButton] to 0.5 from the day it shipped, as a
/// literal inside the widget — the value the ruling then gave web and iOS. A
/// literal on one client and a token on another agree only until one of them
/// moves, so the figure is [AppSpacing.heldOpacity] here and this file holds
/// it to the reference's own declaration in `theme.css`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_spacing.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
        of: find.byType(KitButton), matching: find.byType(Opacity)))
    .opacity;

void main() {
  test('the token is the reference\'s --held-opacity', () {
    final css =
        File('../NoteLetter-web/src/styles/theme.css').readAsStringSync();
    final m = RegExp(r'--held-opacity:\s*([0-9.]+)\s*;').firstMatch(css);
    expect(m, isNotNull, reason: 'theme.css declares --held-opacity');
    expect(AppSpacing.heldOpacity, double.parse(m!.group(1)!));
    expect(AppSpacing.heldOpacity, 0.5);
  });

  final variants = <String, KitButton Function(VoidCallback?, int)>{
    'primary': (f, w) => KitButton.primary('Study now', onPressed: f, wait: w),
    'secondary': (f, w) =>
        KitButton.secondary('Regenerate summary', onPressed: f, wait: w),
    'danger': (f, w) => KitButton.danger('Reset', onPressed: f, wait: w),
    'ghost': (f, w) => KitButton.ghost('Cancel', onPressed: f, wait: w),
  };

  for (final MapEntry(key: name, value: make) in variants.entries) {
    testWidgets('$name: live at full strength; disabled and waiting held',
        (tester) async {
      await tester.pumpWidget(_app(make(() {}, 0)));
      expect(_opacity(tester), 1);

      await tester.pumpWidget(_app(make(null, 0)));
      expect(_opacity(tester), AppSpacing.heldOpacity,
          reason: 'disabled (busy reads the same: its onPressed is null)');

      await tester.pumpWidget(_app(make(() {}, 42)));
      expect(_opacity(tester), AppSpacing.heldOpacity,
          reason: 'waiting out a cooldown — "· 0:42" on a held control');
    });
  }
}
