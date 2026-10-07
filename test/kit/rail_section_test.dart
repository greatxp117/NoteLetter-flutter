// §19's stacked sections (web `.src-section`, QUEUE F-77 4 and 5): every
// section after the first is ruled off from the one above, 40px below it (30
// on a phone); the last reaches the rail, or a jump to it bottoms out short
// and the rail marks the section above.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: w))));
  }

  BoxDecoration? decorationOf(WidgetTester tester, Key key) =>
      tester.widget<Container>(find.byKey(key)).decoration as BoxDecoration?;

  testWidgets('the first section has no rule; the next is ruled 40 below',
      (tester) async {
    const a = ValueKey('a'), b = ValueKey('b');
    await pump(
        tester,
        const Column(children: [
          KitRailSection(first: true, sectionKey: a, child: SizedBox(height: 50)),
          KitRailSection(first: false, sectionKey: b, child: SizedBox(height: 50)),
        ]));
    expect(decorationOf(tester, a), isNull);
    final rule = decorationOf(tester, b)!.border as Border;
    final ctx = tester.element(find.byKey(b));
    expect(rule.top.color, Tokens.of(ctx).rule);
    expect(rule.top.width, 1);
    // The keyed box STARTS at the rule: the gap above it is not the section's.
    final aBottom = tester.getBottomLeft(find.byKey(a)).dy;
    expect(tester.getTopLeft(find.byKey(b)).dy - aBottom, 40);
    // And the panel opens 22 under the 1px rule (`.src-panel`; the rule is
    // the border box's own, as CSS lays it out).
    expect(
        tester.getTopLeft(find.descendant(
                of: find.byKey(b), matching: find.byType(SizedBox)).first).dy -
            tester.getTopLeft(find.byKey(b)).dy,
        1 + 22);
  });

  testWidgets('on a phone the gap is 30', (tester) async {
    const a = ValueKey('a'), b = ValueKey('b');
    await pump(
        tester,
        const Column(children: [
          KitRailSection(first: true, sectionKey: a, child: SizedBox(height: 50)),
          KitRailSection(first: false, sectionKey: b, child: SizedBox(height: 50)),
        ]),
        width: 390);
    expect(
        tester.getTopLeft(find.byKey(b)).dy -
            tester.getBottomLeft(find.byKey(a)).dy,
        30);
  });

  testWidgets('the last section reaches the rail', (tester) async {
    const last = ValueKey('last');
    final reach = KitRailSection.lastReach(900);
    expect(reach, 900 - KitSectionRail.height - 72);
    await pump(
        tester,
        KitRailSection(
            first: false,
            sectionKey: last,
            minHeight: reach,
            child: const SizedBox(height: 40)));
    expect(tester.getSize(find.byKey(last)).height, reach,
        reason: 'a short last section is held open to the rail\'s reach');
    expect(KitRailSection.lastReach(100), 0, reason: 'never negative');
  });
}
