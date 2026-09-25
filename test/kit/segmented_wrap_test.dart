// F-46 — the §6.8 track filling a phone: `.seg` is flex-wrap over `flex: 1`
// buttons, so a segment is never narrower than its label, the rest share what
// is left, and a segment that cannot fit starts a new line. The kit used to
// share the track EQUALLY, which ellipsised "Successes" on a 390pt phone.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  const levels = ['Errors', 'Warnings', 'Successes', 'Info'];

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: KitSegmentedMulti(
              segments: [for (final l in levels) KitSegment(l)],
              selected: const {0, 1},
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    ));
  }

  bool ellipsised(WidgetTester tester, String label) {
    final p = tester.renderObject<RenderParagraph>(find.text(label));
    return p.didExceedMaxLines;
  }

  testWidgets('one line: no label is cut, the longest takes what it needs',
      (tester) async {
    // The test font draws every glyph a full em wide, so the four labels
    // need ~430 here where the real face needs ~290.
    await pumpAt(tester, 460);
    for (final l in levels) {
      expect(ellipsised(tester, l), isFalse, reason: '$l was cut');
    }
    final tops = {for (final l in levels) tester.getTopLeft(find.text(l)).dy};
    expect(tops.length, 1, reason: 'four levels fit one line');
    expect(tester.getSize(find.text('Successes')).width,
        greaterThan(tester.getSize(find.text('Info')).width));
  });

  testWidgets('too narrow for one line: the track wraps, nothing is cut',
      (tester) async {
    await pumpAt(tester, 200);
    for (final l in levels) {
      expect(ellipsised(tester, l), isFalse, reason: '$l was cut');
    }
    final tops = {for (final l in levels) tester.getTopLeft(find.text(l)).dy};
    expect(tops.length, greaterThan(1));
  });
}
