import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Goldens over the kit — the standard, now that every screen above F-17 is
/// recomposed from it (ADR-041).
///
/// `kit_smoke_test.dart` proves each pattern builds and keeps its required
/// parts; it cannot see a pattern that still builds but LOOKS different. This
/// can: a changed metric, weight or token in a kit file moves pixels here and
/// nowhere else in the suite. Screens are not golden-tested — the screenshot
/// pair against the web frame is their gate, and a screen golden would only
/// agree with itself.
///
/// The bundled faces are loaded, so a golden is the real type and not the
/// test font's boxes. Pixels differ across machines and engine versions: the
/// files are this Mac's. A change you meant is
/// `flutter test --update-goldens test/kit/kit_golden_test.dart`, then LOOK at
/// every PNG it rewrote before committing it.
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

void main() {
  setUpAll(_loadFonts);

  Future<void> golden(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = const Size(720, 480),
  }) async {
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Unmount first. Re-pumping MaterialApp with the other theme CROSS-FADES
      // to it (AnimatedTheme), so the second brightness was photographed 50ms
      // into a dark→light lerp: a grey ground under light text, named light.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/$name.${brightness.name}.png'),
      );
    }
  }

  testWidgets('type roles', (tester) async {
    await golden(
      tester,
      'type_roles',
      Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Heading three', style: KitText.h3(context)),
            Text('Heading four', style: KitText.h4(context)),
            const Eyebrow('Recently read · 12 sources'),
            const Lede('Your daily reading, drawn from your library.'),
            Text('Body — the UI default.', style: KitText.body(context)),
            Text('Meta — a date, a count.', style: KitText.meta(context)),
            Text('CAPS LABEL', style: KitText.capsLabel(context)),
            Text('ui — a panel sentence', style: KitText.ui(context)),
            Text('small — a secondary line', style: KitText.small(context)),
            Text('fine — a count beside a control',
                style: KitText.fine(context)),
            Text('Reading prose in the serif.',
                style: KitText.bodyReading(context)),
            const KitProcNote('An imported copy outlived its original.'),
          ],
        ),
      ),
      size: const Size(720, 560),
    );
  });

  testWidgets('headers', (tester) async {
    await golden(
      tester,
      'headers',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChapterOpening(
            folio: 'Deep study · 3 programs',
            title: 'On the *nature* of doctrine',
            standfirst: 'A reading drawn from your library.',
            actions: [KitButton.primary('New program', onPressed: () {})],
          ),
          SubScreenHeader(
            parentLabel: 'Settings',
            eyebrow: 'Notifications',
            standfirst: 'Choose how you hear about what NoteLetter does.',
            onBack: () {},
          ),
        ],
      ),
      size: const Size(900, 520),
    );
  });

  testWidgets('controls', (tester) async {
    await golden(
      tester,
      'controls',
      Wrap(
        spacing: 8,
        runSpacing: 12,
        children: [
          KitButton.primary('Add a source', icon: Icons.add, onPressed: () {}),
          KitButton.secondary('Preview', onPressed: () {}),
          KitButton.danger('Delete', onPressed: () {}),
          KitButton.ghost('Cancel', onPressed: () {}),
          const KitButton.primary('Disabled'),
          const KitTag('Theology',
              variant: KitTagVariant.shelf, colorToken: 'sage-500'),
          const KitTag('PDF'),
          const KitTag('New', variant: KitTagVariant.accent),
          const KitTag('Filter', variant: KitTagVariant.ghost),
          const KitStatusPill('Connected', positive: true),
          const KitStatusPill('Idle'),
          const KitFileBadge('pdf'),
          const KitFileBadge('epub', size: KitBadgeSize.header),
        ],
      ),
      size: const Size(720, 200),
    );
  });

  testWidgets('cards', (tester) async {
    await golden(
      tester,
      'cards',
      Column(
        children: [
          KitCard(child: const Text('A shelf'), onTap: () {}),
          Builder(
            builder: (context) => KitPassageCard(
              meta: const ['p. 41', 'Chapter 3'],
              quote: Text('The passage text.',
                  style: KitText.bodyReading(context)),
              actions: [KitButton.ghost('Copy', onPressed: () {})],
            ),
          ),
          KitHeroCard(
            title: "Today's *letter*",
            marker: 'No. 128',
            standfirst: 'Drawn from what you added this week.',
            stats: const [KitStat('7', 'sources'), KitStat('12m', 'read')],
            actions: [KitButton.primary('Read', onPressed: () {})],
          ),
        ],
      ),
      size: const Size(720, 720),
    );
  });

  testWidgets('notice and failure', (tester) async {
    await golden(
      tester,
      'notice_failure',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KitNotice(
            icon: Icons.error_outline,
            text: 'About 2 more sessions of new material.',
            actionLabel: 'Open settings',
            onAction: () {},
          ),
          const SizedBox(height: 16),
          const KitFailureInline('Couldn’t save — the server refused it.'),
        ],
      ),
      size: const Size(720, 240),
    );
  });
}
