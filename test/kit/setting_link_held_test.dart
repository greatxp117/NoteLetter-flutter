/// A held link reads held (web `03c8f27`, `.set-link:disabled`).
///
/// `.set-link` sets its colour, cursor and brick underline OVER the browser's
/// disabled styling, so a waiting "Rescan all · 5:00" drew exactly as a live
/// link and only the suffix said it waited. The reference now gives a link
/// that cannot act — waiting out a cooldown, or its own write in flight — the
/// quiet text tier (`--fg-subtle`), a neutral `--border-strong` underline, a
/// plain cursor and no hover. KitSettingLink drew the live look in both cases,
/// under a doc comment that said it matched the reference.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

final _link = find.byType(KitSettingLink);

TextStyle _label(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _link, matching: find.byType(Text)))
    .style!;

Color? _chevron(WidgetTester tester) => tester
    .widget<Icon>(find.descendant(of: _link, matching: find.byType(Icon)))
    .color;

MouseCursor _cursor(WidgetTester tester) => tester
    .widget<MouseRegion>(
        find.descendant(of: _link, matching: find.byType(MouseRegion)).first)
    .cursor;

Tokens _t(WidgetTester tester) => Tokens.of(tester.element(_link));

/// One mouse per test: a second `addPointer` for the same device while the
/// first is still attached is an assertion in the mouse tracker.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Off the link, then onto it — an enter every time, whatever came before.
Future<void> _hover(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(Offset.zero);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(_link));
  await tester.pump();
}

void main() {
  testWidgets('a live link is the reference’s live link', (tester) async {
    await tester.pumpWidget(_app(KitSettingLink('Rescan all', onTap: () {})));
    final t = _t(tester);
    expect(_label(tester).color, t.fgMuted);
    expect(_label(tester).decorationColor, t.linkDecor);
    expect(_chevron(tester), t.fgMuted);
    expect(_cursor(tester), SystemMouseCursors.click);
    // …and it answers a hover, which a held one must not.
    await _hover(tester, await _mouse(tester));
    expect(_label(tester).color, t.accentText);
  });

  for (final (name, link) in [
    ('waiting out a cooldown',
        KitSettingLink('Rescan all', wait: 300, onTap: () {})),
    ('with nothing to follow (a write in flight)',
        const KitSettingLink('Rescan all', onTap: null)),
  ]) {
    testWidgets('a held link, $name, reads held in both themes',
        (tester) async {
      final mouse = await _mouse(tester);
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(_app(link, theme: theme));
        final t = _t(tester);
        expect(_label(tester).color, t.fgSubtle,
            reason: 'the quiet text tier, not the live link’s --fg-muted');
        expect(_label(tester).decorationColor, t.borderStrong,
            reason: 'a neutral underline, not the brick --link-decor');
        expect(_label(tester).decoration, TextDecoration.underline,
            reason: 'still underlined: it is the control that acts at zero');
        expect(_chevron(tester), t.fgSubtle,
            reason: 'the chevron is currentColor on the reference');
        expect(_cursor(tester), SystemMouseCursors.basic);
        await _hover(tester, mouse);
        expect(_label(tester).color, t.fgSubtle, reason: 'no hover colour');
        // The held tier really is a different colour from the live one in
        // this theme, or the colour assertions above could not fail.
        expect(t.fgSubtle, isNot(t.fgMuted));
      }
    });
  }
}
