// F-45 — an import-activity row with controls keeps its title on one line on a
// phone. Seen on the folder-contents frame (iPhone 17 Pro, 402pt): View ·
// Import again and the status glyph beside the name left the title so little
// width that `taxes.pdf` broke as `taxes.pd` / `f`. The reference drops the
// strip under the title at ≤720 (`.proc-main { grid-template-columns: 32px 1fr
// }`, `.proc-actions { grid-column: 2 }`); this client does it at its one
// compact breakpoint. Bundled faces are loaded: the test font draws every
// glyph a full em wide and would wrap a title the real type fits.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _loadFonts() async {
  const faces = {
    'Geist': [
      'Geist-Light.ttf',
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'Geist-Bold.ttf',
    ],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Widget _row({required bool wide}) => KitSourceRow(
      leading: const KitFileBadge('pdf'),
      title: 'taxes.pdf',
      subtitle: 'Already imported · /Docs/Finance/taxes.pdf',
      wideTrailing: wide,
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          KitButton.ghost('View', onPressed: () {}),
          KitButton.ghost('Import again', onPressed: () {}),
          const SizedBox(width: 4),
          const Icon(Icons.remove_circle_outline, size: 16),
        ],
      ),
    );

Future<void> _pump(WidgetTester tester, double width, Widget row) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 874 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(
        // The page frame's phone gutter (§1.5, 20) and the list's border.
        padding: const EdgeInsets.symmetric(horizontal: 21),
        child: Align(alignment: Alignment.topCenter, child: row),
      ),
    ),
  ));
  await tester.pump();
}

int _lines(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(find.text(text));
  return p.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length))
      .map((b) => b.top.round())
      .toSet()
      .length;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('on a 402pt phone the controls go under the title, never the '
      'title into a sliver', (tester) async {
    await _pump(tester, 402, _row(wide: true));
    expect(tester.takeException(), isNull);
    expect(_lines(tester, 'taxes.pdf'), 1,
        reason: 'the title keeps the row\'s width (F-45: `taxes.pd` / `f`)');

    final title = tester.getRect(find.text('taxes.pdf'));
    final sub = tester.getRect(find.textContaining('Already imported'));
    final view = tester.getRect(find.text('View'));
    final again = tester.getRect(find.text('Import again'));
    expect(view.top, greaterThan(sub.bottom),
        reason: 'the strip sits under the title block');
    expect(view.left, greaterThanOrEqualTo(title.left - 16),
        reason: 'in the title\'s column (`grid-column: 2`), not under the '
            'badge');
    expect((again.center.dy - view.center.dy).abs(), lessThan(2),
        reason: 'the two controls share their own line');
  });

  testWidgets('wide, the controls stay beside the title', (tester) async {
    await _pump(tester, 1024, _row(wide: true));
    final title = tester.getRect(find.text('taxes.pdf'));
    final view = tester.getRect(find.text('View'));
    expect(view.left, greaterThan(title.right));
    expect(view.top, lessThan(title.bottom + 20));
  });

  testWidgets('without the flag the phone row is the defect itself',
      (tester) async {
    // The control: the same row inline at 402 wraps its title. If this ever
    // stops wrapping, the case above proves nothing.
    await _pump(tester, 402, _row(wide: false));
    expect(_lines(tester, 'taxes.pdf'), greaterThan(1));
  });
}
