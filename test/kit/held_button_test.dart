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

import 'package:flutter_app/site/site_sheet.dart';
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

  // Ruled again 2026-10-13 (F-103): EVERY held control at the token, not only
  // KitButton. The send drew 0.45 (`.sup-send`'s old figure) and full strength
  // while busy; the sign-in and sign-up controls 0.6; the connect card and the
  // sync settings panel no token at all. Each is the one figure now.
  group('every held control, not only KitButton', () {
    double opacityIn(WidgetTester tester, Finder of) => tester
        .widget<Opacity>(
            find.descendant(of: of, matching: find.byType(Opacity)).first)
        .opacity;

    testWidgets('the composer send: live full, empty / waiting / busy held',
        (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      Future<void> dock({VoidCallback? onSend, bool busy = false, int wait = 0}) =>
          tester.pumpWidget(_app(SizedBox(
            width: 600,
            child: KitComposerDock(
                controller: c,
                placeholder: 'Ask',
                onSend: onSend,
                busy: busy,
                waitLeft: wait),
          )));
      // The send is the one Opacity under the arrow / spinner.
      double send() => tester
          .widget<Opacity>(find
              .ancestor(
                  of: find.byWidgetPredicate((w) =>
                      (w is Icon && w.icon == Icons.arrow_forward) ||
                      w is CircularProgressIndicator),
                  matching: find.byType(Opacity))
              .first)
          .opacity;

      await dock(onSend: () {});
      expect(send(), 1);
      await dock();
      expect(send(), AppSpacing.heldOpacity, reason: 'nothing to send');
      await dock(onSend: () {}, wait: 9);
      expect(send(), AppSpacing.heldOpacity, reason: 'waiting out a cooldown');
      await dock(onSend: () {}, busy: true);
      expect(send(), AppSpacing.heldOpacity,
          reason: 'busy is held — the reference disables its send in flight');
    });

    testWidgets('a connect card held while its own request runs', (tester) async {
      Widget card(VoidCallback? onTap) => SizedBox(
          width: 240,
          child: KitConnectCard(
              icon: Icons.cloud,
              title: 'Google Drive',
              subtitle: 'Connect',
              status: 'Not connected',
              onTap: onTap));
      await tester.pumpWidget(_app(card(() {})));
      expect(opacityIn(tester, find.byType(KitConnectCard)), 1);
      await tester.pumpWidget(_app(card(null)));
      expect(opacityIn(tester, find.byType(KitConnectCard)),
          AppSpacing.heldOpacity);
    });

    testWidgets('sign-in: submit, ghost and the text link held at the token',
        (tester) async {
      final style = AppTheme.light.textTheme.bodyMedium!;
      for (final (name, make) in <(String, Widget Function(VoidCallback?))>[
        ('SiteSubmit', (f) => SiteSubmit('Open the library', onPressed: f)),
        ('SiteGhost', (f) => SiteGhost('Continue with Google', onPressed: f)),
        ('SiteTextButton', (f) => SiteTextButton('Forgot it?', style: style, onTap: f)),
      ]) {
        await tester.pumpWidget(_app(SizedBox(width: 320, child: make(() {}))));
        expect(opacityIn(tester, find.byType(SizedBox).first), 1, reason: name);
        await tester.pumpWidget(_app(SizedBox(width: 320, child: make(null))));
        expect(opacityIn(tester, find.byType(SizedBox).first),
            AppSpacing.heldOpacity,
            reason: '$name held');
      }
    });
  });
}
