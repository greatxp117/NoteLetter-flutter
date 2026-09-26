// F-54 — the checklist strip and the search row at phone widths, with the
// BUNDLED faces (the test font would wrap what the real type fits).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _loadFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
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

const _steps = [
  KitSetupStep('Create your account', done: true),
  KitSetupStep('Add your first source', done: true),
  KitSetupStep('File a volume onto a shelf', done: true),
  KitSetupStep('Set up your daily letter', done: true),
  KitSetupStep('Ask your library a question', done: false),
];

Future<void> _at(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    ),
  ));
}

void main() {
  setUpAll(_loadFonts);

  for (final width in [390.0, 320.0]) {
    for (final open in [false, true]) {
      testWidgets('the strip at $width, ${open ? 'open' : 'closed'}',
          (tester) async {
        await _at(
            tester,
            width,
            KitSetupChecklist(
              steps: _steps,
              compact: true,
              expanded: open,
              onExpanded: (_) {},
              onHide: () {},
            ));
        expect(tester.takeException(), isNull);
        // `.onboard-chips { flex: 1 0 100% }` below 680: the pill takes its
        // own line UNDER the summary, and Hide stays beside the summary.
        final hide = tester.getRect(find.text('Hide'));
        final summary = tester.getRect(find.text('4 of 5 set up'));
        expect((hide.center.dy - summary.center.dy).abs(), lessThan(4));
        if (!open) {
          final pill = tester.getRect(find.text('Ask your library a question'));
          expect(pill.top, greaterThan(summary.bottom));
        } else {
          expect(find.text('Create your account'), findsOneWidget);
        }
      });
    }

    testWidgets('the search row stacks at $width, Add a source full width',
        (tester) async {
      await _at(tester, width,
          KitLibraryActions(onSearch: () {}, onAdd: () {}));
      expect(tester.takeException(), isNull);
      final field = tester
          .getRect(find.text('Search your library by meaning…'))
          .center;
      final add = tester.getRect(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Add a source'));
      expect(add.center.dy, greaterThan(field.dy));
      expect(add.width, closeTo(width - 40, 0.5), reason: 'full width');
      // The glyph and the label, centred together in the bar.
      final glyph = tester.getRect(find.byIcon(Icons.add));
      final label = tester.getRect(find.text('Add a source'));
      expect(((glyph.left + label.right) / 2 - width / 2).abs(), lessThan(1));
    });
  }

  testWidgets('the full card: N of M, the note, Hide, open by default',
      (tester) async {
    await _at(
        tester,
        390,
        KitSetupChecklist(
          steps: const [
            KitSetupStep('Create your account', done: true),
            KitSetupStep('Add your first source', done: false),
          ],
          expanded: true,
          onExpanded: (_) {},
          onHide: () {},
        ));
    expect(tester.takeException(), isNull);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(
        find.text('Your library is already underway — the account was the '
            'first step.'),
        findsOneWidget);
  });
}
