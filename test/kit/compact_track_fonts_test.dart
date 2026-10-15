/// §6.8's compact variant (the Aa popover, ruled 2026-10-14) never cuts a
/// label and never wraps: the segments share the track, but none is narrower
/// than its own label (web `.seg button { flex: 1 }` at `white-space:
/// nowrap`). Equal shares drew "Mediur" in the 268 popover — found by the
/// reader-type frame. Real faces: the test font's glyphs are 1em wide and
/// measure nothing a phone draws.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _loadRealFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
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

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('every label whole, every track one line, on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: KitTypeControls(groups: [
            KitTypeGroup(
              label: 'Text size',
              options: const ['Small', 'Medium', 'Large', 'X-large'],
              selected: 1,
              onChanged: (_) {},
            ),
            KitTypeGroup(
              label: 'Line width',
              options: const ['Narrow', 'Normal', 'Wide'],
              selected: 1,
              onChanged: (_) {},
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    for (final label in ['Small', 'Medium', 'Large', 'X-large', 'Narrow']) {
      final p = tester.renderObject<RenderParagraph>(find.text(label));
      expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(1e9) - 0.01),
          reason: '"$label" was cut');
    }
    final row = ['Small', 'Medium', 'Large', 'X-large']
        .map((l) => tester.getCenter(find.text(l)).dy)
        .toSet();
    expect(row.length, 1, reason: 'the track wrapped');
  });
}
