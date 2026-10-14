// F-78 — what the 2026-10-05 Ask and Search pairs found, each against the
// reference (MarkedText.jsx hosts, AskView.jsx + app-kit.css `.pact` /
// `.ask-title` / `.empty-state-row`, SearchView.jsx `.search-result-count`,
// `.sresult`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test('chunk text collapses its white space as an html host does', () {
    expect(KitMarkedText.collapse('Quarter | Invoice total\nQ2 | \$1,200'),
        'Quarter | Invoice total Q2 | \$1,200');
    expect(KitMarkedText.collapse('a \n\n  b'), 'a b');
  });

  testWidgets('a newline in chunk text is a space, not a line break',
      (tester) async {
    await _pump(
        tester,
        KitMarkedText('Quarter | Invoice total\nQ2 | \$1,200',
            style: const TextStyle(fontSize: 14)));
    expect(find.text('Quarter | Invoice total Q2 | \$1,200', findRichText: true),
        findsOneWidget);
  });

  group('the control bar\'s count line stays trailing', () {
    Widget bar() => KitControlBar(
          filters: const [KitFilterChip('All sources', selected: true)],
          trailing: [
            KitSegmented(groupLabel: 'Group', segments: const [
              KitSegment('Passages'),
              KitSegment('Cohesive'),
            ], selected: 0, onChanged: (_) {}),
          ],
          count: const Text('7 passages · ranked by meaning'),
        );

    testWidgets('stacked, on its own line at the trailing edge',
        (tester) async {
      await _pump(tester, bar());
      final count = tester.getRect(find.text('7 passages · ranked by meaning'));
      final seg = tester.getRect(find.text('Cohesive'));
      expect(count.top, greaterThan(seg.bottom));
      expect(count.right, closeTo(402, 1),
          reason: '`margin-left: auto` — the trailing edge, not the leading');
    });

    testWidgets('one line, last in the trailing row', (tester) async {
      await _pump(tester, bar(), width: 1200);
      final count = tester.getRect(find.text('7 passages · ranked by meaning'));
      final seg = tester.getRect(find.text('Cohesive'));
      expect(count.left, greaterThan(seg.right));
      expect((count.center.dy - seg.center.dy).abs(), lessThan(4));
    });
  });

  testWidgets('a header title states its phone size', (tester) async {
    await _pump(
        tester,
        const ScreenHeader(
            title: 'Ask your library', titleSize: 30, titleSizeCompact: 26));
    expect(tester.widget<Text>(find.text('Ask your library')).style?.fontSize,
        26);
    await _pump(
        tester,
        const ScreenHeader(
            title: 'Ask your library', titleSize: 30, titleSizeCompact: 26),
        width: 1200);
    expect(tester.widget<Text>(find.text('Ask your library')).style?.fontSize,
        30);
  });

  testWidgets('a suggestion draws the reference\'s sparkle at 15',
      (tester) async {
    await _pump(
        tester,
        const KitSuggestion(
            icon: KitSparkle.icon, label: 'What have I been reading about?'));
    final sparkle = tester.widget<KitSparkle>(find.byType(KitSparkle));
    expect(sparkle.size, 15);
    expect(find.byType(Icon), findsNothing,
        reason: 'not Material\'s filled twinkle');
  });

  // F-90 (5): a one-turn transcript sits against the composer on web
  // (`.ask-thread { margin: auto auto 0 }`), not under the header.
  testWidgets('an anchored page rests short content at its bottom',
      (tester) async {
    tester.view.physicalSize = const Size(402, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const turn = SizedBox(key: ValueKey('turn'), height: 100);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
          body: KitPage(anchorBottom: true, child: turn)),
    ));
    final bottomAnchored = tester.getRect(find.byKey(const ValueKey('turn')));
    expect(bottomAnchored.bottom, greaterThan(600),
        reason: 'the turn rests at the bottom, above the frame\'s foot');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: KitPage(child: turn)),
    ));
    expect(tester.getRect(find.byKey(const ValueKey('turn'))).top,
        lessThan(100), reason: 'the default page still starts at its top');
  });
}
