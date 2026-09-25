// F-57 — §1.2's brand lockup is the reference's: the quill mark and the
// small-caps wordmark, owned by the pattern; and the phone app bar carries the
// trailing search control `.app-mobile-header` draws.
//
// Every caller used to pass Material's `edit_note` beside a plain serif
// `NoteLetter`, so the lockup was a caller's choice three times over — and all
// three chose the same wrong glyph, which is why no frame looked "off" alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/app_layout.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The wordmark's own span — `Text.rich` wraps it in the ambient style's root.
TextSpan wordmarkSpan(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(KitWordmark), matching: find.byType(RichText)));
  return (rich.text as TextSpan).children!.single as TextSpan;
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('the lockup is the quill + NOTELETTER with raised initials',
      (tester) async {
    await pump(tester, const KitBrand());

    expect(find.byType(KitQuill), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsNothing,
        reason: 'the notepad glyph is not the mark');

    final root = wordmarkSpan(tester);
    expect(root.toPlainText(), 'NOTELETTER');
    final spans = root.children!.cast<TextSpan>();
    final base = root.style!.fontSize!;
    expect(base, 15);
    expect(spans[0].text, 'N');
    expect(spans[0].style!.fontSize, closeTo(base * 1.24, 0.001));
    expect(spans[2].text, 'L');
    expect(spans[2].style!.fontSize, closeTo(base * 1.24, 0.001));
    // Tracked by the BASE size's em, initials included (CSS inherits pixels).
    expect(spans[0].style!.letterSpacing, closeTo(0.12 * base, 0.001));
    expect(root.style!.fontWeight, FontWeight.w600);
  });

  testWidgets('each surface keeps its reference metrics', (tester) async {
    await pump(tester, const KitBrand.appBar());
    expect(tester.getSize(find.byType(KitQuill)), const Size(20, 20));

    await pump(tester, const KitBrand.onboarding());
    expect(tester.getSize(find.byType(KitQuill)), const Size(24, 24));
    expect(wordmarkSpan(tester).style!.fontSize, 19);
  });

  testWidgets('KitGlyph draws the quill for its sentinel, Material otherwise',
      (tester) async {
    await pump(
      tester,
      const Column(mainAxisSize: MainAxisSize.min, children: [
        KitMark(KitQuill.icon),
        KitGlyph(Icons.search, size: 20, color: Color(0xFF000000)),
      ]),
    );
    expect(find.byType(KitQuill), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('the phone app bar draws the lockup and a search control',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const AppLayout(child: Text('library'))),
      GoRoute(path: '/search', builder: (_, _) => const Text('search page')),
    ]);
    await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(KitBrand), findsOneWidget);
    expect(find.byType(KitQuill), findsOneWidget);
    final search = find.byType(KitAppBarButton);
    expect(search, findsOneWidget);
    expect(tester.getSize(search), const Size(36, 36));

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.text('search page'), findsOneWidget);
  });
}
