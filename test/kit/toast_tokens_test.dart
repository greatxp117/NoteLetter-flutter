// The toast's level colours are the reference's LEVEL_COLOR (src/shell/
// notify.jsx): success --positive, error --critical-text, info --fg-muted, on
// a --surface card — and all of them FLIP with the theme. It drew
// Colors.green/red.shade400 in both themes, and --accent for info, until
// 2026-10-05.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/app_toast.dart';

Future<BuildContext> _host(WidgetTester tester, ThemeData theme) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })),
  ));
  return ctx;
}

/// The 3px level rule down the toast's leading edge.
Color _rule(WidgetTester tester) => tester
    .widget<ColoredBox>(find.descendant(
        of: find.byType(SnackBar), matching: find.byType(ColoredBox)))
    .color;

Color _glyph(WidgetTester tester) => tester
    .widget<Icon>(find.descendant(
        of: find.byType(SnackBar), matching: find.byType(Icon)))
    .color!;

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? AppTheme.dark : AppTheme.light;
    final name = dark ? 'dark' : 'light';

    testWidgets('each level draws its token ($name)', (tester) async {
      final ctx = await _host(tester, theme);
      final t = Tokens.of(ctx);
      final cases = {
        ToastType.success: t.positive,
        ToastType.error: t.criticalText,
        ToastType.info: t.fgMuted,
      };
      for (final e in cases.entries) {
        AppToast.show(ctx, 'Saved.', type: e.key);
        await tester.pumpAndSettle();
        expect(_rule(tester), e.value, reason: '${e.key} rule');
        expect(_glyph(tester), e.value, reason: '${e.key} glyph');
        final card = tester.widget<Container>(find
            .descendant(of: find.byType(SnackBar), matching: find.byType(Container))
            .first);
        final deco = card.decoration! as BoxDecoration;
        expect(deco.color, t.surface);
        expect((deco.border! as Border).top.color, t.border);
        expect(tester.widget<Text>(find.text('Saved.')).style!.color, t.fg);
      }
    });
  }

  testWidgets('success and error are not one hue, and info is not the accent',
      (tester) async {
    final ctx = await _host(tester, AppTheme.light);
    final t = Tokens.of(ctx);
    AppToast.show(ctx, 'x', type: ToastType.info);
    await tester.pumpAndSettle();
    expect(_rule(tester), isNot(t.accent));
  });
}
