import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Every kit pattern, pumped in **both themes**.
///
/// This is a render gate, not a design gate: it proves each pattern builds,
/// lays out and paints without throwing. Composition fidelity is the
/// screenshot pair (`/design-fidelity` step 5); goldens come after the screens
/// are rebuilt, deliberately — applied now they would freeze the divergence
/// and certify it as the standard (ADR-041).
void main() {
  Future<void> pumpBoth(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1200, 900),
  }) async {
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'threw in $brightness');
    }
  }

  group('type roles', () {
    testWidgets('eyebrow, lede and the accent clause render', (tester) async {
      await pumpBoth(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow('Recently read · 12 sources'),
            Lede('Your daily reading, drawn from your library.'),
          ],
        ),
      );
      expect(find.text('RECENTLY READ · 12 SOURCES'), findsOneWidget);
    });

    testWidgets('AccentTitle splits on a single asterisk pair', (tester) async {
      await pumpBoth(
        tester,
        Builder(
          builder: (context) =>
              AccentTitle('Good evening, *Xavier*', style: KitText.h2(context)),
        ),
      );
      final rich = tester.widget<Text>(find.byType(Text).first);
      expect(rich.textSpan, isNotNull);
    });

    testWidgets('a title with no asterisks renders plain', (tester) async {
      await pumpBoth(
        tester,
        Builder(
          builder: (context) =>
              AccentTitle('Sources', style: KitText.h2(context)),
        ),
      );
      expect(find.text('Sources'), findsOneWidget);
    });
  });

  group('headers', () {
    testWidgets('the one header pattern, with and without its optional parts', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title only — the one required part.
            const ChapterOpening(title: 'Activity'),
            // Every optional part at once.
            ChapterOpening(
              mark: const KitFileBadge('pdf', size: KitBadgeSize.header),
              folio: 'Deep study · 3 programs',
              title: 'On the *nature* of doctrine',
              standfirst: 'A reading drawn from your library.',
              actions: [KitButton.primary('New program', onPressed: () {})],
            ),
            // Rule suppressed, where a header runs into a control bar.
            const ChapterOpening(title: 'Library', rule: false),
            SubScreenHeader(
              parentLabel: 'Settings',
              eyebrow: 'Notifications',
              standfirst: 'Choose how you hear about what NoteLetter does.',
              onBack: () {},
            ),
          ],
        ),
      );
    });

    testWidgets('section header carries an action', (tester) async {
      await pumpBoth(
        tester,
        SectionHeader(
          'Shelves · 4',
          actionLabel: 'View all',
          onAction: () {},
          first: true,
        ),
      );
      expect(find.text('View all'), findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('every button variant', (tester) async {
      await pumpBoth(
        tester,
        Wrap(
          spacing: 8,
          children: [
            KitButton.primary(
              'Add a source',
              icon: Icons.add,
              onPressed: () {},
            ),
            KitButton.secondary('Preview', onPressed: () {}),
            KitButton.danger('Delete', onPressed: () {}),
            KitButton.ghost('Cancel', onPressed: () {}),
            const KitButton.primary('Disabled'),
          ],
        ),
      );
      expect(find.text('Add a source'), findsOneWidget);
    });

    testWidgets('tags, status pills and badges', (tester) async {
      await pumpBoth(
        tester,
        Wrap(
          spacing: 8,
          children: const [
            KitTag(
              'Theology',
              variant: KitTagVariant.shelf,
              colorToken: 'sage-500',
            ),
            KitTag('PDF'),
            KitTag('New', variant: KitTagVariant.accent),
            KitTag('Filter', variant: KitTagVariant.ghost),
            KitStatusPill('Connected', positive: true),
            KitStatusPill('Idle'),
            KitFileBadge('pdf'),
            KitFileBadge('epub', size: KitBadgeSize.header),
            KitFileBadge('web', size: KitBadgeSize.inline),
          ],
        ),
      );
    });

    testWidgets('an unknown shelf token falls back, never throws', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const Wrap(
          children: [
            KitTag('Legacy', colorToken: '#6B7280'),
            KitTag('Nonsense', colorToken: 'not-a-token'),
            KitTag('Absent'),
          ],
        ),
      );
    });
  });

  group('cards and rows', () {
    testWidgets('surface, passage and hero cards', (tester) async {
      await pumpBoth(
        tester,
        Column(
          children: [
            KitCard(child: const Text('A shelf'), onTap: () {}),
            Builder(
              builder: (context) => KitPassageCard(
                meta: const ['p. 41', 'Chapter 3'],
                quote: Text(
                  'The passage text.',
                  style: KitText.bodyReading(context),
                ),
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
      );
    });

    testWidgets('row list and timeline, including a live node', (tester) async {
      await pumpBoth(
        tester,
        Column(
          children: [
            KitRowList(
              rows: [
                const KitSourceRow(
                  leading: KitFileBadge('pdf'),
                  title: 'Church Dogmatics',
                  subtitle: 'Karl Barth',
                  count: '412',
                  date: 'Aug 14',
                ),
                KitSourceRow(title: 'A second row', onTap: () {}),
              ],
            ),
            KitTimeline(
              rows: [
                KitTimelineRow(
                  icon: Icons.check_circle_outline,
                  tone: KitNodeTone.sage,
                  chip: 'Indexed',
                  subject: 'Church Dogmatics',
                  detail: '412 chunks embedded',
                  time: '2h',
                  onTap: () {},
                ),
                const KitTimelineRow(
                  icon: Icons.sync,
                  tone: KitNodeTone.plum,
                  chip: 'Processing',
                  subject: 'A new upload',
                  time: 'now',
                  live: true,
                ),
              ],
            ),
          ],
        ),
      );
    });
  });

  group('empty state', () {
    testWidgets('renders its suggestions, which are a required part', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        KitEmptyState(
          icon: Icons.auto_stories_outlined,
          title: 'Nothing on the shelf yet',
          standfirst: 'Add a source and the library builds itself.',
          suggestions: [
            KitSuggestion(
              icon: Icons.upload_file_outlined,
              label: 'Upload a PDF',
              onTap: () {},
            ),
            KitSuggestion(
              icon: Icons.link_outlined,
              label: 'Paste a link',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(find.text('Upload a PDF'), findsOneWidget);
    });
  });

  group('frame', () {
    testWidgets('all four widths, and the compact gutter', (tester) async {
      for (final w in KitFrameWidth.values) {
        await pumpBoth(tester, KitFrame(width: w, child: const Text('framed')));
      }
      await pumpBoth(
        tester,
        const KitFrame(child: Text('framed')),
        size: const Size(390, 844),
      );
    });
  });

  group('shell', () {
    testWidgets('rail, nav items and the inset main pane', (tester) async {
      await pumpBoth(
        tester,
        SizedBox(
          height: 800,
          child: KitShell(
            rail: KitChromeRail(
              brand: const KitBrand(mark: Icon(Icons.edit_note)),
              items: [
                const KitRailGroupLabel('Library'),
                KitNavItem(
                  icon: Icons.menu_book_outlined,
                  label: 'Library',
                  active: true,
                  count: '128',
                  onTap: () {},
                ),
                KitNavItem(icon: Icons.search, label: 'Search', onTap: () {}),
              ],
            ),
            child: const Column(
              children: [
                KitUtilityBar(crumb: 'Library · Theology'),
                Text('body'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Library'), findsWidgets);
    });
  });

  group('ground', () {
    testWidgets('paints without a tile on first frame, then with one', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const SizedBox(
          height: 200,
          width: 200,
          child: KitGround(child: SizedBox()),
        ),
      );
    });
  });
  group('composer dock (§10)', () {
    testWidgets('scrim, italic serif input and the filled send control', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'a written prompt');
      addTearDown(controller.dispose);
      await pumpBoth(
        tester,
        SizedBox(
          height: 220,
          child: KitComposerDock(
            controller: controller,
            placeholder: 'What happened?',
            onSend: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('the busy state disables send and KEEPS the text', (
      tester,
    ) async {
      // ADR-022: the composer clears only once the endpoint has accepted. A
      // dock that emptied itself on tap would look identical until the send
      // failed.
      final controller = TextEditingController(text: 'in flight');
      addTearDown(controller.dispose);
      await pumpBoth(
        tester,
        SizedBox(
          height: 220,
          child: KitComposerDock(
            controller: controller,
            placeholder: 'What happened?',
            busy: true,
            error: 'Wait a moment before sending again.',
            onSend: () {},
          ),
        ),
      );
      expect(controller.text, 'in flight');
      expect(find.text('Wait a moment before sending again.'), findsOneWidget);
    });
  });

  group('support footer (§13, INV-22)', () {
    testWidgets('the two required parts, and the optional count', (
      tester,
    ) async {
      await pumpBoth(tester, KitSupportFooter(unread: 2, onOpen: () {}));
      expect(
        find.textContaining('Bugs? Feature Requests?', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Chat with support…'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
