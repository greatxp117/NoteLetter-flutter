// reader.md §Continuous scroll: Speed read's follow-along text is part of the
// section, in `.rsvp-text` — `overflow-y: auto`, which a browser CHAINS to the
// page once the box has spent a drag. Flutter keeps a nested scrollable's
// gesture at its end, so before this the reader's page stopped dead under a
// thumb that landed on the text (the device run stalled there at
// 13531/14024, 2026-10-05). The box must still scroll by hand: its words are
// tap targets and the text past its fold is reachable no other way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/reader/speed_read_panel.dart';
import 'package:flutter_app/theme/app_theme.dart';

final _paras = [
  for (var i = 0; i < 30; i++)
    'Paragraph $i of the source, long enough to wrap across several lines '
        'of the follow-along box so that the box has far more text than it '
        'can show and has to scroll on its own to reach the end of it.',
];

Future<ScrollController> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final page = ScrollController();
  addTearDown(page.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: CustomScrollView(controller: page, slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 600)),
        SliverToBoxAdapter(child: SpeedReadPanel(paras: _paras)),
        const SliverToBoxAdapter(child: SizedBox(height: 2400)),
      ]),
    ),
  ));
  await tester.pump();
  return page;
}

Finder get _box => find.descendant(
    of: find.byType(SpeedReadPanel),
    matching: find.byType(SingleChildScrollView));

ScrollPosition _inner(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(_box).controller!.position;

/// Bring the box to mid-screen, then let the page come to rest.
Future<Offset> _onScreen(WidgetTester tester, ScrollController page) async {
  final top = tester.getTopLeft(_box).dy;
  page.jumpTo(page.offset + top - 300);
  await tester.pumpAndSettle();
  return tester.getCenter(_box);
}

void main() {
  testWidgets('the box scrolls by hand first, and the page stays put',
      (tester) async {
    final page = await _pump(tester);
    final at = await _onScreen(tester, page);
    final before = page.offset;
    expect(_inner(tester).maxScrollExtent, greaterThan(400),
        reason: 'the fixture must overflow the box');

    await tester.dragFrom(at, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(_inner(tester).pixels, greaterThan(60),
        reason: 'the follow-along text cannot be scrolled by hand');
    expect(page.offset, before, reason: 'the page moved under a drag the box had room for');
  });

  testWidgets('a drag the box has spent at its end goes on to the page',
      (tester) async {
    final page = await _pump(tester);
    final at = await _onScreen(tester, page);
    final inner = _inner(tester);
    inner.jumpTo(inner.maxScrollExtent);
    await tester.pump();
    final before = page.offset;

    await tester.dragFrom(at, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(page.offset - before, greaterThan(150),
        reason: 'the page stopped under a thumb on the text — '
            'the spent drag was not chained');
    expect(inner.pixels, inner.maxScrollExtent);
  });

  testWidgets('and back up: at its top, a downward drag scrolls the page up',
      (tester) async {
    final page = await _pump(tester);
    final at = await _onScreen(tester, page);
    expect(_inner(tester).pixels, 0);
    final before = page.offset;

    await tester.dragFrom(at, const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(before - page.offset, greaterThan(150));
  });

  testWidgets('a fling released at the end carries on as the page\'s',
      (tester) async {
    final page = await _pump(tester);
    final at = await _onScreen(tester, page);
    final inner = _inner(tester);
    inner.jumpTo(inner.maxScrollExtent);
    await tester.pump();
    final before = page.offset;

    await tester.flingFrom(at, const Offset(0, -120), 2500);
    await tester.pumpAndSettle();

    // A drag of 120 moves the page at most 120; the rest is the momentum
    // handed over on release.
    expect(page.offset - before, greaterThan(240));
  });
}
