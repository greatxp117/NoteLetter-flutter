// The §24 Relationship map's behaviour (component-kit §24, ADR-177), driven
// in-process through the pointer pipeline: a tap selects and lights the path,
// a drag pans and never selects, two pointers pinch, it opens fitted, search
// marks and Enter centres, full screen opens fitted too.
//
// Synthesised pointers prove the WIRING, not a device: "only a real gesture
// proves pan and pinch", so the device test named in QUEUE F-126 is still the
// acceptance gate for those two.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/shared/relmap_layout.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_test/flutter_test.dart';

MapGraph _graph() => buildShelfGraph(
      const [
        MapShelf('a', title: 'Catholic', color: 'sage-500'),
        MapShelf('b', title: 'Poetry', color: 'brick-700'),
      ],
      [
        for (var i = 0; i < 6; i++)
          MapDoc('$i', title: 'Volume $i', type: 'pdf', tagIds: [i.isEven ? 'a' : 'b']),
        const MapDoc('both', title: 'On both', type: 'web', tagIds: ['a', 'b']),
      ],
    );

Future<List<MapNode>> _pump(WidgetTester tester,
    {String? focus, Size size = const Size(1100, 800)}) async {
  final opened = <MapNode>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: KitRelationshipMap(
            graph: _graph(), focusKey: focus, onOpen: opened.add),
      ),
    ),
  ));
  // No looping animation here, but bounded pumps all the same.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return opened;
}

Finder _node(String key) => find.byKey(Key('relmap-node-$key'));
Rect _viewer(WidgetTester t) =>
    t.getRect(find.byKey(const Key('relmap-viewer')).first);
String _zoom(WidgetTester t) => t
    .widgetList<Text>(find.textContaining('%'))
    .map((w) => w.data!)
    .firstWhere((s) => RegExp(r'^\d+%$').hasMatch(s));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('opens fitted: every chip inside the canvas, never above 100%',
      (tester) async {
    await _pump(tester);
    expect(int.parse(_zoom(tester).replaceAll('%', '')), lessThanOrEqualTo(100));
    final box = _viewer(tester);
    for (final k in _graph().nodes.keys) {
      final r = tester.getRect(_node(k));
      expect(box.contains(r.topLeft) && box.contains(r.bottomRight), isTrue,
          reason: '$k at $r outside $box');
    }
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('VOLUMES'), findsOneWidget);
    expect(find.text('SHELVES'), findsOneWidget);
  });

  testWidgets('a tap selects, names the relations and opens; again clears',
      (tester) async {
    final opened = await _pump(tester);
    await tester.tap(_node(nodeKey('volume', 'both')));
    await _settle(tester);
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('ON SHELVES · 2'), findsOneWidget);
    await tester.tap(find.text('Open in reader'));
    expect(opened.single.id, 'both');
    await tester.tap(_node(nodeKey('volume', 'both')));
    await _settle(tester);
    expect(find.text('INSPECTOR'), findsOneWidget);
  });

  testWidgets('a drag pans and never selects; a pinch zooms', (tester) async {
    await _pump(tester);
    final key = nodeKey('shelf', 'a');
    final before = tester.getCenter(_node(key));
    // Starts ON a chip: the drag is a pan, so the chip must not be selected.
    await tester.dragFrom(before, const Offset(-120, 60));
    await _settle(tester);
    final after = tester.getCenter(_node(key));
    expect((after - before).dx, closeTo(-120, 30));
    expect(find.text('INSPECTOR'), findsOneWidget);

    final z0 = _zoom(tester);
    final c = _viewer(tester).center;
    final g1 = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final g2 = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await g1.moveTo(c - Offset(40.0 + i * 8, 0));
      await g2.moveTo(c + Offset(40.0 + i * 8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await _settle(tester);
    expect(_zoom(tester), isNot(z0));
    expect(find.text('INSPECTOR'), findsOneWidget, reason: 'a pinch selects nothing');
  });

  testWidgets('a nudge under the slop is still a tap', (tester) async {
    await _pump(tester);
    final at = tester.getCenter(_node(nodeKey('shelf', 'b')));
    final g = await tester.startGesture(at);
    await g.moveBy(const Offset(2, 1));
    await g.up();
    await _settle(tester);
    expect(find.text('SHELF'), findsOneWidget);
  });

  testWidgets('search marks matches; Enter selects the first in layout order',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'volume');
    await _settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(find.text('VOLUME'), findsOneWidget);
    // Esc clears the search first, then the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.text('VOLUME'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('INSPECTOR'), findsOneWidget);
  });

  testWidgets('focus on arrival selects the shelf and centres it',
      (tester) async {
    await _pump(tester, focus: nodeKey('shelf', 'b'));
    expect(find.text('SHELF'), findsOneWidget);
    final c = tester.getCenter(_node(nodeKey('shelf', 'b')));
    final v = _viewer(tester).center;
    expect((c - v).distance, lessThan(4));
  });

  testWidgets('full screen opens fitted, keeps the selection, and leaves',
      (tester) async {
    await _pump(tester);
    await tester.tap(_node(nodeKey('shelf', 'a')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('relmap-fullscreen')));
    await _settle(tester);
    // The full-screen page's own viewer, fitted, the selection still lit.
    final box = tester.getRect(find.byKey(const Key('relmap-viewer')).last);
    expect(box.width, greaterThan(1000));
    expect(find.text('SHELF'), findsWidgets);
    expect(int.parse(_zoom(tester).replaceAll('%', '')), lessThanOrEqualTo(100));
    for (final k in _graph().nodes.keys) {
      final r = tester.getRect(_node(k).last);
      expect(box.contains(r.topLeft) && box.contains(r.bottomRight), isTrue,
          reason: 'full screen: $k at $r outside $box');
    }
    await tester.tap(find.byKey(const Key('relmap-fullscreen')).last);
    await _settle(tester);
    expect(find.byKey(const Key('relmap-viewer')), findsOneWidget);
  });

  testWidgets('a phone stacks the toolbar and keeps the map usable',
      (tester) async {
    await _pump(tester, size: const Size(390, 760));
    expect(tester.takeException(), isNull);
    // A graph wider than a phone opens fitted BELOW 100%, and says so.
    expect(int.parse(_zoom(tester).replaceAll('%', '')), lessThan(100));
    final box = _viewer(tester);
    for (final k in _graph().nodes.keys) {
      final r = tester.getRect(_node(k));
      expect(box.contains(r.topLeft) && box.contains(r.bottomRight), isTrue,
          reason: 'phone: $k at $r outside $box');
    }
    final search = tester.getRect(find.byType(TextField));
    expect(search.width, greaterThan(300));
    await tester.tap(_node(nodeKey('volume', 'both')));
    await _settle(tester);
    expect(find.text('Open in reader'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
