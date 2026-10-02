// 4.105.1 (search.md §Action glyphs) — one action, one glyph. *Open source*
// wears the book and *Open in context* the eye, on every card that offers
// them. Until 4.105.1 three call sites spelled the action by hand and drew it
// with three glyphs; the kit now owns both (KitPassageAction.openSource /
// .openInContext), and this test holds every page to them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: Center(child: w))));

  testWidgets('Open source draws the book', (tester) async {
    await pump(tester, KitPassageAction.openSource(onTap: () {}));
    expect(find.text('Open source'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('Open in context draws the eye, never the book', (tester) async {
    await pump(tester, KitPassageAction.openInContext(onTap: () {}));
    expect(find.text('Open in context'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
  });

  test('no page spells either action by hand', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('kit/kit_cards.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue;
        if (RegExp(r"""['"]Open (source|in context)['"]""").hasMatch(l)) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use KitPassageAction.openSource / .openInContext — the glyph is the action\'s');
  });
}
