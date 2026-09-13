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

  group('§17 extraction marker', () {
    testWidgets('aside and inline render in both themes, no brackets', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KitMarkerAside(
              label: 'On screen',
              body: '10 habits of well-spoken people',
            ),
            const KitMarkerInline(
              label: 'Image',
              body: 'a laptop',
              hostFontSize: 16,
            ),
            Builder(
              builder: (context) => KitMarkedText(
                'said [Video: a person typing]. and then',
                style: KitText.body(context),
              ),
            ),
          ],
        ),
      );
      // The label replaces the brackets; a rendered `[` is the defect.
      expect(find.text('ON SCREEN'), findsOneWidget);
      expect(find.textContaining('['), findsNothing);
    });
  });

  group('§5.2 reduced emphasis (support)', () {
    testWidgets('message cards on both edges and the thread note', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitMessageCard(
              meta: ['You', '9:41 AM', '/activity'],
              body: 'The reader lost my place.',
              mine: true,
            ),
            KitMessageCard(
              meta: ['Support', 'Sep 12 · 10:02 AM'],
              body: 'Thanks — looking now.',
              mine: false,
            ),
            KitThreadNote('Received.'),
          ],
        ),
      );
      expect(find.text('YOU · 9:41 AM · /ACTIVITY'), findsOneWidget);
      expect(find.text('Received.'), findsOneWidget);
    });
  });

  group('settings rows', () {
    testWidgets('setting link, avatar, notes, stepper, select and stamp', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitRowList(
              raised: true,
              rows: [
                KitSettingRow(
                  icon: Icons.person_outline,
                  leading: KitAvatarPlate(
                    KitAvatarPlate.initialsOf('Ada Lovelace'),
                  ),
                  title: 'Ada Lovelace',
                  description: 'ada@example.test',
                  trailing: [KitSettingLink('Sign out', icon: Icons.logout)],
                ),
                KitSettingRow(
                  icon: Icons.schedule_outlined,
                  title: 'Rest a passage for',
                  below: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KitStepper(
                        value: 7,
                        min: 0,
                        max: 90,
                        unit: 'days',
                        onChanged: (_) {},
                      ),
                      KitSelect<String>(
                        value: 'a',
                        options: const ['a', 'b'],
                        label: (s) => s,
                      ),
                      const KitSunkenNote('a composed instruction'),
                      const KitRowNote('Letter settings saved.'),
                    ],
                  ),
                ),
              ],
            ),
            const KitBuildStamp(contract: '4.4.0', platform: 'flutter'),
          ],
        ),
      );
      expect(find.text('AL'), findsOneWidget);
      expect(KitAvatarPlate.initialsOf('ada@example.test'), 'AD');
      expect(KitAvatarPlate.initialsOf(''), '?');
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

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
    testWidgets('switch, text field, field group and the multi track', (
      tester,
    ) async {
      final ctrl = TextEditingController(text: 'you@example.com');
      addTearDown(ctrl.dispose);
      await pumpBoth(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitFieldGroup(
              label: 'Type',
              first: true,
              child: KitSegmented(
                expand: true,
                segments: const [KitSegment('On-screen'), KitSegment('Email')],
                selected: 0,
                onChanged: (_) {},
              ),
            ),
            KitFieldGroup(
              label: 'Send to',
              child: KitTextField(
                controller: ctrl,
                icon: Icons.mail_outline,
                placeholder: 'you@example.com',
              ),
            ),
            KitFieldGroup(
              label: 'Label',
              note: 'optional',
              child: KitSegmentedMulti(
                segments: const [
                  KitSegment('Errors'),
                  KitSegment('Warnings'),
                  KitSegment('Info'),
                ],
                selected: const {0, 1},
                onToggle: (_) {},
              ),
            ),
            Row(
              children: [
                KitSwitch(value: false, onChanged: (_) {}),
                const KitSwitch(value: true),
              ],
            ),
          ],
        ),
      );
      expect(find.text('SEND TO'), findsOneWidget);
      expect(find.text('optional'), findsOneWidget);
      expect(find.byType(KitSwitch), findsNWidgets(2));
    });

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

    testWidgets('setting rows, the raised list and the row slot', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        KitRowList(
          raised: true,
          rows: [
            KitSettingRow(
              icon: Icons.mail_outline,
              title: 'Work inbox',
              description: 'seed@noteletter.test',
              below: KitSegmentedMulti(
                expand: true,
                segments: const [KitSegment('Errors'), KitSegment('Info')],
                selected: const {0},
                onToggle: (_) {},
              ),
              trailing: [
                KitSwitch(value: true, onChanged: (_) {}),
                KitIconButton(Icons.delete_outline, onPressed: () {}),
              ],
            ),
            const KitSettingRow(
              icon: Icons.notifications_none,
              title: 'Push channel',
              titleNote: '(paused)',
              description: 'Pushed to your devices',
            ),
            const KitRowSlot(child: KitFailureInline('Could not be read.')),
          ],
        ),
      );
      expect(find.text('Work inbox'), findsOneWidget);
      expect(find.textContaining('(paused)'), findsOneWidget);
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

  group('shelf pieces (§5.1, §6.2)', () {
    testWidgets('the shelf card carries every required part', (tester) async {
      await pumpBoth(
        tester,
        SizedBox(
          width: 280,
          child: KitShelfCard(
            title: 'Recipes',
            colorToken: 'brick-500',
            meta: '4 volumes · 213 passages',
            volumes: 4,
            volumeTitles: const ['Pasta Fundamentals', 'Legacy Coffee Notes'],
            moreCount: 2,
            badge: 'auto',
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Recipes'), findsOneWidget);
      expect(find.text('4 volumes · 213 passages'), findsOneWidget);
      expect(find.text('Pasta Fundamentals'), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      expect(find.text('AUTO'), findsOneWidget);
    });

    testWidgets('an empty shelf says so, and a legacy hex still paints', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        SizedBox(
          width: 280,
          child: const KitShelfCard(
            title: 'Unread',
            // Every auto-created tag holds a hex, and there is no backfill.
            colorToken: '#6B7280',
            meta: '0 volumes · 0 passages',
            volumes: 0,
          ),
        ),
      );
      expect(find.text('Empty shelf'), findsOneWidget);
    });

    testWidgets('swatch, plate, panel and the new-card slot', (tester) async {
      await pumpBoth(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: const [
                KitSwatch(
                    color: Color(0xFF6F8A52), label: 'Moss', selected: true),
                // A swatch with no handler is the write-in-flight state: it
                // must still paint, at reduced opacity.
                KitSwatch(color: Color(0xFF3F2A3C), label: 'Deep plum'),
              ],
            ),
            const KitShelfPlate('plum-600'),
            KitPanel(
              children: [
                KitPanelRow(
                  label: 'Color',
                  alignTop: true,
                  child: KitSwatch(
                      color: const Color(0xFF6F8A52),
                      label: 'Moss',
                      onTap: () {}),
                ),
                KitPanelRow(
                  label: 'Danger',
                  child: KitButton.danger('Delete shelf', onPressed: () {}),
                ),
              ],
            ),
            SizedBox(
              width: 280,
              child: KitNewCard(
                title: 'New shelf',
                subtitle: 'Group volumes by subject or project',
                onTap: () {},
              ),
            ),
          ],
        ),
      );
      expect(find.text('COLOR'), findsOneWidget);
      expect(find.text('New shelf'), findsOneWidget);
      // The swatch names the COLOUR, not the token — a control announced as
      // `sage-500` names a variable.
      expect(find.bySemanticsLabel('Moss'), findsWidgets);
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

  group('§9 inspector rail', () {
    testWidgets('header, group labels, entries — and the active marker', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        SizedBox(
          height: 600,
          child: KitInspectorRail(
            title: 'Conversations',
            onClose: () {},
            newLabel: 'New conversation',
            newActive: false,
            onNew: () {},
            groups: [
              KitRailGroup(
                label: 'Today',
                entries: [
                  KitRailEntry(
                    title: 'What have I been reading about pasta?',
                    time: '8:18 PM',
                    preview: 'and about tax invoices?',
                    active: true,
                    onTap: () {},
                  ),
                  KitRailEntry(
                    title: 'Systems thinking',
                    time: 'Sep 3',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      // Required parts: the mono caps title, the close control (the phone
      // form's — an overlay a reader cannot dismiss is a trap), the group
      // label, and the entry's three lines.
      expect(find.text('CONVERSATIONS'), findsWidgets);
      expect(find.byIcon(Icons.close), findsWidgets);
      expect(find.text('TODAY'), findsWidgets);
      expect(find.text('New conversation'), findsWidgets);
      expect(find.text('and about tax invoices?'), findsWidgets);
      expect(find.text('8:18 PM'), findsWidgets);
    });

    testWidgets('the notice stands INSTEAD of the entries', (tester) async {
      // INV-24: a rail that could not be READ is not an empty rail. If both
      // rendered, the failure would sit above a list asserting there is
      // nothing to list.
      await pumpBoth(
        tester,
        SizedBox(
          height: 600,
          child: KitInspectorRail(
            title: 'Conversations',
            notice: const KitFailureBlock(
              sentence: 'Your conversations could not be read.',
              detail: 'permission-denied',
            ),
            groups: [
              KitRailGroup(
                label: 'Today',
                entries: [
                  KitRailEntry(title: 'Should not render', onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      );
      expect(find.text('Your conversations could not be read.'), findsWidgets);
      expect(find.text('Should not render'), findsNothing);
      expect(find.text('TODAY'), findsNothing);
    });
  });

  group('§12 notice', () {
    testWidgets('glyph, measured copy, one action — and no dismiss', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        KitNotice(
          icon: Icons.error_outline,
          text: 'About 2 more sessions of new material.',
          actionLabel: 'Open settings',
          onAction: () {},
        ),
      );
      expect(
        find.text('About 2 more sessions of new material.'),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
      // Its lifecycle belongs to the condition: it leaves when the backend
      // says so. A close control would hide a live state and put the surface
      // in disagreement with the notification already sent.
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('a notice with no remedy is still a notice', (tester) async {
      await pumpBoth(
        tester,
        const KitNotice(
          icon: Icons.error_outline,
          text: 'No new material left.',
        ),
      );
      expect(find.text('No new material left.'), findsOneWidget);
    });
  });

  group('§7 numbered move', () {
    testWidgets('numeral, title and copy — the explainer row form', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const KitNumberedMove(
          number: 'I',
          title: 'One subject at a time',
          description: 'Up to ten finished documents.',
        ),
      );
      expect(find.text('I'), findsOneWidget);
      expect(find.text('One subject at a time'), findsOneWidget);
      // The copy is the offer — an empty state whose rows drop it is the
      // apology §7 exists to avoid.
      expect(find.text('Up to ten finished documents.'), findsOneWidget);
    });
  });

  group('§11 letter sheet', () {
    testWidgets('the frame this client draws: masthead, rule, body, seal', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const KitLetterSheet(
          title: 'A Letter.',
          marker: 'On Quiet Rooms',
          standfirst: 'Three passages found each other today.',
          sealText: '3 passages · Sent on request',
          children: [
            RuledSectionLabel('§ 01'),
            KitLetterBody('<p>Brown the meat before adding liquid.</p>'),
            KitLetterAttribution('— The Craft of Braising'),
          ],
        ),
      );
      // The versal raises the opening capitals and sets the rest uppercase —
      // which letters rise is not a detail (4.50.1 shipped `NOteLETTER`).
      expect(find.text('ON QUIET ROOMS'), findsOneWidget);
      expect(find.text('3 passages · Sent on request'), findsOneWidget);
    });

    test('a letterheaded body is wrapped and NOT edited', () {
      // The bare letter is a platform view — a widget test cannot prove it
      // renders, and pretending otherwise is what a fake WebViewPlatform would
      // do. The device run and the screenshot pair prove the render; what is
      // provable here is the only thing this widget does to the letter, which
      // is wrap it.
      const body =
          '<div data-nl-letterhead="1" style="background:#FAFAF7">'
          '<table><tr><td>A letter.</td></tr></table></div>';
      final doc = KitLetterPaper.documentFor(body);
      // The letter's own markup, byte for byte. A client hosting it bare may
      // not rewrite it to suit a renderer (ADR-087) — the reader would be
      // looking at something nobody was sent.
      expect(doc, contains(body));
      // What we add: a viewport, so a 640px mail sheet fits a phone instead of
      // scrolling sideways, and the letter's own frozen ground behind it.
      expect(doc, contains('width=device-width'));
      expect(doc, contains('#FAFAF7'));
      // …and no font, colour or metric of ours: every one of those is inline
      // in the letter and must win.
      expect(doc, isNot(contains('Source Serif')));
      expect(doc, isNot(contains('font-size')));
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
