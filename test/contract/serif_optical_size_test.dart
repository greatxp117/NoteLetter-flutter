// F-100 — the serif's optical size (design-tokens.md; web theme.css,
// app-kit.css `font-variation-settings: "opsz" N`, and the browser's
// `font-optical-sizing: auto` everywhere else). Measured on the bundled face:
// a serif style that names no `opsz` draws the default outlines, 7% wider than
// any optical size web draws. The widths are the kit goldens' to show (they
// load the real faces); this asserts the axis is set, and where.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

double? _opsz(TextStyle? s) {
  for (final v in s?.fontVariations ?? const <FontVariation>[]) {
    if (v.axis == 'opsz') return v.value;
  }
  return null;
}

void main() {
  test('a serif style sets its optical size: the size, clamped to 8–60', () {
    expect(_opsz(AppTheme.serif(fontSize: 44, fontWeight: FontWeight.w600)), 44);
    expect(_opsz(AppTheme.serif(fontSize: 72)), 60);
    expect(_opsz(AppTheme.serif(fontSize: 6)), 8);
    expect(_opsz(AppTheme.serif(fontSize: 19, opsz: 18)), 18,
        reason: 'a role whose reference names its own optical size');
    expect(
        AppTheme.serif(fontSize: 20, fontWeight: FontWeight.w600)
            .fontVariations!
            .firstWhere((v) => v.axis == 'wght')
            .value,
        600,
        reason: 'the weight axis is still driven');
  });

  testWidgets('every kit serif role carries the axis; reading roles are 18',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    for (final (name, style) in [
      ('h1', KitText.h1(ctx)),
      ('h2', KitText.h2(ctx)),
      ('h3', KitText.h3(ctx)),
      ('h4', KitText.h4(ctx)),
      ('lede', KitText.lede(ctx)),
      ('reviewLede', KitText.reviewLede(ctx)),
      ('title', KitText.title(ctx, fontSize: 22)),
      ('pullQuote', KitText.pullQuote(ctx)),
    ]) {
      expect(_opsz(style), style.fontSize!.clamp(8, 60),
          reason: '$name: no explicit value on web, so the browser\'s auto');
    }
    // `.ms-body`, `.rd-body p`, `.sresult-passage` — 18 whatever the size.
    expect(_opsz(KitText.bodyReading(ctx, fontSize: 21)), 18);
    expect(_opsz(KitDropCap.capStyle(ctx)), 18,
        reason: '::first-letter inherits .ms-body\'s 18');
    expect(_opsz(KitText.bodyReading(ctx, sans: true)), isNull,
        reason: 'the reader\'s sans has no axis to set');
  });

  testWidgets('an html body inherits its optical size into every span',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
          body: KitLetterBody('<h2>A heading</h2><p>Words, <em>some</em> '
              '<b>bold</b>.</p>')),
    ));
    final roots = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.style)
        .toList();
    expect(roots, isNotEmpty);
    for (final s in roots) {
      expect(_opsz(s), 17,
          reason: 'flutter_html sets no variation; every Text.rich takes '
              'the wrapper\'s, so no span draws the default outlines');
    }
  });
}
