/// A held button's countdown is the number the refusal carried — it must not
/// be the part the row cuts off.
///
/// Found 2026-10-14 by the letter-send-wait frame: the Letters card drew
/// "Send now · 0:…". KitActionFlow gives a button whose natural width beats
/// the line's equal share exactly its natural width — then FLOORED it, and a
/// real font's natural width is fractional, so the label was a fraction of a
/// pixel short and ellipsised its last characters: the countdown. The test
/// font draws whole-pixel glyphs and can never show it, so this loads the
/// app's own faces (the loader is connect_card_test.dart's).
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

  testWidgets('a grown row never cuts a held label it gave its natural width',
      (tester) async {
    final cut = <String>[];
    // The Letters card's line on a phone: Send now (held), Preview,
    // Settings — at every quarter pixel from 280 to 380.
    for (var w = 280.0; w <= 380.0; w += 0.25) {
      for (final wait in [42, 59, 300]) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: w,
                child: KitActionFlow(grow: true, children: [
                  KitButton('Send now',
                      icon: Icons.arrow_forward,
                      center: true,
                      wait: wait,
                      onPressed: () {}),
                  KitButton('Preview',
                      icon: Icons.visibility_outlined,
                      variant: KitButtonVariant.secondary,
                      center: true,
                      onPressed: () {}),
                  KitButton('Settings',
                      icon: Icons.settings_outlined,
                      variant: KitButtonVariant.ghost,
                      center: true,
                      onPressed: () {}),
                ]),
              ),
            ),
          ),
        ));
        final p = tester.renderObject<RenderParagraph>(
            find.textContaining('Send now'));
        if (p.didExceedMaxLines) cut.add('$w/$wait');
      }
    }
    expect(cut, isEmpty,
        reason: 'the held label was ellipsised at width/wait $cut');
  });
}
