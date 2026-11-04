// Web's `.lx-cloud` (`app-library.css`), the scope around what a connected
// service brings in. F-160's first frame drew an import row as `.proc-row`'s
// card, with a filled pill and a sans eyebrow, while every test was green: the
// scope was never ported, because a scope is a fact about the HOST.
//
// Both directions are held: inside it the row is flat, and outside it the same
// widgets keep the card, as every other host of `.proc-row` does on web.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w) => tester.pumpWidget(
      MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: w))));

  Widget card({bool failed = false}) => KitProcCard(
        kind: 'pdf',
        title: 'old-notes.pdf',
        subtitle: 'Google Drive · /Docs/old-notes.pdf',
        failed: failed,
        pill: const KitProcPill('Waiting', tone: KitProcTone.wait),
        foot: const SizedBox.shrink(),
      );

  BoxDecoration rowDecoration(WidgetTester tester) => tester
      .widget<Container>(find
          .descendant(
              of: find.byType(KitProcCard), matching: find.byType(Container))
          .first)
      .decoration! as BoxDecoration;

  Container pillBox(WidgetTester tester) => tester.widget<Container>(find
      .descendant(
          of: find.byType(KitProcPill), matching: find.byType(Container))
      .first);

  Text pillWords(WidgetTester tester) => tester.widget<Text>(find.descendant(
      of: find.byType(KitProcPill), matching: find.text('WAITING')));

  Text head(WidgetTester tester) =>
      tester.widget<Text>(find.text('CLOUD IMPORTS · 1'));

  group('outside the scope, the card stands', () {
    testWidgets('a row is `.proc-row`: surface, a whole border, a shadow',
        (tester) async {
      await pump(tester, card());
      final d = rowDecoration(tester);
      expect(d.color, isNotNull);
      expect(d.boxShadow, isNotEmpty);
      expect(d.borderRadius, isNotNull);
      expect((d.border! as Border).top.style, BorderStyle.solid);
    });

    testWidgets('a pill has its fill and padding', (tester) async {
      await pump(tester, card());
      expect(pillBox(tester).decoration, isNotNull);
      expect(pillBox(tester).padding, isNot(EdgeInsets.zero));
      expect(pillWords(tester).style!.letterSpacing, closeTo(0.6, 0.001));
    });

    testWidgets('the eyebrow is not the scope\'s', (tester) async {
      await pump(tester, const SectionHeader('Cloud imports · 1'));
      expect(head(tester).style!.fontFamily, isNot(AppTheme.fontMono));
    });
  });

  group('inside `.lx-cloud`', () {
    testWidgets('a row is flat on a --rule edge, the title serif 16/21',
        (tester) async {
      await pump(tester, KitCloudScope(child: card()));
      final d = rowDecoration(tester);
      expect(d.color, isNull);
      expect(d.boxShadow, isNull);
      expect(d.borderRadius, isNull);
      final b = d.border! as Border;
      expect(b.top, BorderSide.none);
      final t = Tokens.of(tester.element(find.byType(KitProcCard)));
      expect(b.bottom.color, t.rule);
      final title = tester.widget<Text>(find.text('old-notes.pdf'));
      expect(title.style!.fontSize, 16);
      expect(title.style!.height, 21 / 16);
    });

    testWidgets('a failed row keeps the plain rule (the cascade\'s order)',
        (tester) async {
      await pump(tester, KitCloudScope(child: card(failed: true)));
      final t = Tokens.of(tester.element(find.byType(KitProcCard)));
      expect((rowDecoration(tester).border! as Border).bottom.color, t.rule);
    });

    testWidgets('a pill is its words: no fill, no padding, .12em',
        (tester) async {
      await pump(tester, KitCloudScope(child: card()));
      expect(pillBox(tester).decoration, isNull);
      expect(pillBox(tester).padding, EdgeInsets.zero);
      expect(pillWords(tester).style!.letterSpacing, closeTo(1.2, 0.001));
    });

    testWidgets('the eyebrow is mono 11/500 at .16em, in --fg', (tester) async {
      await pump(
          tester, const KitCloudScope(child: SectionHeader('Cloud imports · 1')));
      final s = head(tester).style!;
      expect(s.fontFamily, AppTheme.fontMono);
      expect(s.fontSize, 11);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.letterSpacing, closeTo(1.76, 0.001));
      expect(s.color,
          Tokens.of(tester.element(find.byType(SectionHeader))).fg);
    });

    Border? headEdge(WidgetTester tester) {
      final c = find.descendant(
          of: find.byType(SectionHeader), matching: find.byType(Container));
      if (c.evaluate().isEmpty) return null;
      final d = tester.widget<Container>(c.first).decoration as BoxDecoration?;
      return d?.border as Border?;
    }

    testWidgets('the Library rules over the head', (tester) async {
      await pump(
          tester, const KitCloudScope(child: SectionHeader('Cloud imports · 1')));
      final t = Tokens.of(tester.element(find.byType(SectionHeader)));
      expect(headEdge(tester)!.top.color, t.fg);
    });

    testWidgets('a service\'s page does not', (tester) async {
      await pump(
          tester,
          const KitCloudScope(
              ruled: false, child: SectionHeader('Cloud imports · 1')));
      expect(headEdge(tester), isNull);
    });
  });
}
