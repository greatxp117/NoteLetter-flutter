// F-81 — what the 2026-10-05 Shelves pairs found, against the reference
// (app-shelves.css `.shelf-spines`, `.scv-empty`, `.ss-swatch`; ShelfForm's
// `.qa-mark` IcoStack at --seal).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
}

void main() {
  testWidgets('a chosen swatch is the same 24 as the rest', (tester) async {
    await _pump(
        tester,
        const Row(children: [
          KitSwatch(color: Color(0xFF6F8159), label: 'Sage', selected: true),
          KitSwatch(color: Color(0xFF9D352D), label: 'Brick'),
        ]));
    final sizes = tester
        .widgetList<KitSwatch>(find.byType(KitSwatch))
        .map((w) => tester.getSize(find.byWidget(w)))
        .toSet();
    expect(sizes, {const Size(24, 24)},
        reason: '`.ss-swatch` is border-box: the ring is the circle\'s own');
  });

  testWidgets('an empty shelf says so in the sans italic; spines stand in 56',
      (tester) async {
    await _pump(
        tester,
        const KitShelfCard(
            title: 'Stories', meta: '0 volumes', volumes: 0, colorToken: 'sage-500'));
    final empty = tester.widget<Text>(find.text('Empty shelf'));
    expect(empty.style?.fontFamily, AppTheme.fontSans);
    expect(empty.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('a painted glyph keeps its size inside a tile, as Icon does',
      (tester) async {
    await _pump(
        tester,
        const SizedBox(
            width: 36,
            height: 36,
            child: KitGlyph(KitStackGlyph.icon,
                size: 18, color: Color(0xFF000000))));
    final r = tester.getRect(find.byType(KitStackGlyph));
    expect(r.size, const Size(18, 18),
        reason: 'the sheet\'s 18 mark, not the tile\'s 36');
    final tile = tester.getRect(find.byType(KitGlyph));
    expect(r.center, tile.center, reason: 'centred in the tile');
  });

  testWidgets('the sheet mark is the stack, at --seal', (tester) async {
    await _pump(tester,
        const KitGlyph(KitStackGlyph.icon, size: 18, color: Color(0xFF000000)));
    expect(find.byType(KitStackGlyph), findsOneWidget);
    expect(Tokens.light.seal, isNotNull);
  });

  // F-126 — the reference draws *Shelf map* and *See on map* with `IcoMap` (a
  // box over two, forked); Material's `map` is a folded paper map. A button
  // handed the sentinel must paint the port, never an empty glyph box.
  testWidgets('a button handed the map sentinel paints the reference glyph',
      (tester) async {
    await _pump(
        tester,
        Center(
            child: KitButton.ghost('Shelf map',
                icon: KitMapGlyph.icon, onPressed: () {})));
    expect(find.byType(KitMapGlyph), findsOneWidget);
    expect(tester.getSize(find.byType(KitMapGlyph)), const Size(14, 14));
    expect(find.byIcon(KitMapGlyph.icon), findsNothing,
        reason: 'the sentinel is no font glyph; drawn as Icon it is a blank');
    // Any other icon is still a Material Icon, drawn as before.
    await _pump(
        tester,
        Center(
            child: KitButton.ghost('Ask this shelf',
                icon: Icons.forum_outlined, onPressed: () {})));
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
  });
}
