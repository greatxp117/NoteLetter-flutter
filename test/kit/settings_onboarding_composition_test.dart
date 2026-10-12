// F-80 — Settings' theme control and onboarding's head, against the
// reference (AppShell.jsx `ThemeToggle` + `.theme-toggle`;
// app-onboarding-wizard.css `.ob-title`, `.ob-stand`, `.ob-rule`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_colors.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _pump(WidgetTester tester, Widget w, {double width = 402}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
}

/// The largest size any span of a rich title sets — the display size, under
/// whatever default the root span inherits.
double _size(RichText r) {
  var max = 0.0;
  r.text.visitChildren((span) {
    final f = span.style?.fontSize ?? 0;
    if (f > max) max = f;
    return true;
  });
  return max;
}

void main() {
  testWidgets('the theme control is three glyphs named by their titles, no text',
      (tester) async {
    var chosen = 1;
    await _pump(
        tester,
        StatefulBuilder(
          builder: (context, set) => KitThemeToggle(
              selected: chosen, onChanged: (i) => set(() => chosen = i)),
        ));
    for (final word in ['Light', 'System', 'Dark']) {
      expect(find.text(word), findsNothing, reason: 'no label text');
      expect(find.byTooltip(word), findsOneWidget);
    }
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.byIcon(Icons.desktop_windows_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pump();
    expect(chosen, 2);
  });

  group('onboarding\'s head is its own, not §2.1\'s', () {
    const head = ChapterOpening(
      onboarding: true,
      folio: 'Setting up',
      title: 'Welcome to *your library.*',
      standfirst: 'Four steps and it’s yours.',
    );

    testWidgets('at a 402 phone: title 27, standfirst 17, the dash and tick',
        (tester) async {
      await _pump(tester, head);
      final title = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().startsWith('Welcome'));
      expect(_size(title), 27);
      expect(find.byType(ChapterRule), findsNothing,
          reason: 'not the two-bar chapter rule');
      final dash = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == AppColors.obRuleDash);
      expect(dash, findsOneWidget);
      expect(tester.getSize(dash), const Size(38, 2));
    });

    testWidgets('wide: 40', (tester) async {
      await _pump(tester, head, width: 1200);
      final title = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().startsWith('Welcome'));
      expect(_size(title), 40);
    });
  });
}
