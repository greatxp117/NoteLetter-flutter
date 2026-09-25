// F-56 — `.ss-row` is flex-wrap: a control sized by its content wraps WHOLE
// under its label when it does not fit beside it; a `flex: 1` control never
// wraps. On a phone the ten swatches (312px) drop under COLOR as one row of
// ten — the kit used to wrap them 7 + 3 inside the control column.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  const control = Key('control');
  const swatches = SizedBox(key: control, width: 312, height: 28);

  Future<void> pumpAt(WidgetTester tester, double width, Widget row) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: row),
        ),
      ),
    ));
  }

  Rect labelRect(WidgetTester tester) =>
      tester.getRect(find.byType(KitControlLabel));

  testWidgets('a content-sized control that does not fit drops under the label',
      (tester) async {
    // 350 - 64 label - 16 gap = 270 < 312.
    await pumpAt(tester, 350,
        const KitPanelRow(label: 'Color', sizedByContent: true, child: swatches));
    final c = tester.getRect(find.byKey(control));
    expect(c.left, 0, reason: 'the control starts at the row edge, not the column');
    expect(c.top, greaterThanOrEqualTo(labelRect(tester).bottom + 8));
    expect(c.width, 312, reason: 'wrapped whole — one row, its own width');
  });

  testWidgets('a content-sized control that fits stays beside the label',
      (tester) async {
    await pumpAt(tester, 600,
        const KitPanelRow(label: 'Color', sizedByContent: true, child: swatches));
    final c = tester.getRect(find.byKey(control));
    expect(c.left, 64 + 16);
    expect(c.top, lessThan(labelRect(tester).bottom));
  });

  testWidgets('a flex control never wraps — it shrinks beside the label',
      (tester) async {
    await pumpAt(
        tester,
        350,
        const KitPanelRow(
            label: 'Name', child: SizedBox(key: control, height: 28)));
    final c = tester.getRect(find.byKey(control));
    expect(c.left, 64 + 16);
    expect(c.width, 350 - 64 - 16);
  });
}
