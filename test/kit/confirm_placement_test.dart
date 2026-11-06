// F-173: a confirm stands where web's does (component-kit §18).
//
// Web's panel opens on §15's scrim, `.qs-backdrop`: across the middle, 11vh from
// the top, 8vh at 680 wide or narrower. Flutter's was Material's AlertDialog,
// halfway down the screen, so the same delete asked in a different place on each
// client. Nothing compared them: the pair check reads file names, and each frame
// was right on its own.
//
// Mutants this file was run against (each turns it red): the alignment back to
// `Alignment.center`; 11vh on a phone; 8vh on a wide window; `scrollable` off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<Rect> _panel(WidgetTester tester, Size size, {String? body}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => KitConfirm.show(
              context,
              title: 'Delete “Pasta, from the top”?',
              body: body ?? 'Its 12 passages are deleted for good.',
              confirmLabel: 'Delete source',
              cancelLabel: 'Keep it',
              onConfirm: () async => null,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.getRect(find
      .descendant(of: find.byType(AlertDialog), matching: find.byType(Material))
      .first);
}

void main() {
  testWidgets('on a phone it stands 8vh from the top, across the middle',
      (tester) async {
    const size = Size(390, 844);
    final r = await _panel(tester, size);
    expect(r.top, closeTo(size.height * 0.08, 0.5));
    expect(r.center.dx, closeTo(size.width / 2, 0.5));
  });

  testWidgets('at 680 wide it is still the phone rule', (tester) async {
    const size = Size(680, 900);
    final r = await _panel(tester, size);
    expect(r.top, closeTo(size.height * 0.08, 0.5));
  });

  testWidgets('wider than 680 it stands 11vh from the top', (tester) async {
    const size = Size(1024, 768);
    final r = await _panel(tester, size);
    expect(r.top, closeTo(size.height * 0.11, 0.5));
    expect(r.center.dx, closeTo(size.width / 2, 0.5));
  });

  testWidgets('its sides keep web\'s gutter on the narrowest phone',
      (tester) async {
    const size = Size(320, 568);
    final r = await _panel(tester, size);
    expect(r.left, greaterThanOrEqualTo(12));
    expect(r.right, lessThanOrEqualTo(size.width - 12));
  });

  // A panel that stands higher has less height. The first version overflowed on
  // a long body (F-160's disconnect), and only another screen's test said so.
  testWidgets('a long body scrolls, and its actions stay on the screen',
      (tester) async {
    const size = Size(320, 568);
    final r = await _panel(tester, size,
        body: List.filled(60, 'Files already downloaded finish.').join(' '));
    expect(tester.takeException(), isNull);
    expect(r.bottom, lessThanOrEqualTo(size.height));
    final keep = tester.getRect(find.widgetWithText(KitButton, 'Keep it'));
    expect(keep.bottom, lessThanOrEqualTo(size.height));
    await tester.tap(find.widgetWithText(KitButton, 'Keep it'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
