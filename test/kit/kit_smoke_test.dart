import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/search/score_explainer.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Every kit pattern, pumped in **both themes**.
///
/// This is a render gate, not a design gate: it proves each pattern builds,
/// lays out and paints without throwing. Composition fidelity is the
/// screenshot pair (`/design-fidelity` step 5); goldens come after the screens
/// are rebuilt, deliberately — applied now they would freeze the divergence
/// and certify it as the standard (ADR-041).
/// A 1×1 transparent PNG, served to every `Image.network` in this suite.
///
/// `NetworkImage` really reaches for the network in a widget test, and a
/// refused request throws out of the image service rather than out of the
/// widget — which reads as "the pattern threw" when the pattern is fine. The
/// patterns that draw a picture (§5.4's figures, §15.1's stage, §15.2's tiles)
/// are the ones whose layout most needs pumping, so the bytes are faked here
/// rather than the widgets being kept out of the suite.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _FakeImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeImageHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  Future<void> pumpBoth(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1200, 900),
  }) async {
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Unmount first: re-pumping MaterialApp with the other theme cross-fades
      // to it, so the light pass ran 50ms into a dark→light lerp (F-17).
      await tester.pumpWidget(const SizedBox.shrink());
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

  group('§5.4 recipe body', () {
    const recipe = Recipe(
      title: 'Cast-Iron Cornbread',
      yield_: 'Serves 8',
      prepTime: '10 min',
      // `cook_time` and `total_time` unstated by the source: the row must not
      // invent a cell for them.
      ingredients: [
        RecipeGroup(items: ['1 cup coarse yellow cornmeal']),
        RecipeGroup(group: 'To finish', items: ['Honey butter, to serve']),
      ],
      steps: [
        RecipeStep(text: 'Heat the skillet.', start: 42.0),
        RecipeStep(text: 'Swirl the fat.'),
      ],
      notes: ['Coarse cornmeal is the whole texture.'],
    );

    testWidgets('the required parts, in order, and only the stated stats',
        (tester) async {
      await pumpBoth(tester, const KitRecipeBody(recipe: recipe));

      expect(find.text('Cast-Iron Cornbread'), findsOneWidget);
      expect(find.text('Serves 8'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      // An unstated stat is ABSENT, never a dash or a zero — a placeholder
      // reads as a measured value (§8).
      expect(find.text('COOK'), findsNothing);
      expect(find.text('TOTAL'), findsNothing);
      expect(find.text('—'), findsNothing);

      // Ingredients BEFORE Method, always: a cook reads the whole list first,
      // and the order is the pattern, not a preference.
      final ing = tester.getTopLeft(find.text('INGREDIENTS')).dy;
      final method = tester.getTopLeft(find.text('METHOD')).dy;
      expect(ing, lessThan(method));

      // A group label only where the SOURCE grouped.
      expect(find.text('TO FINISH'), findsOneWidget);
    });

    testWidgets('a step time with nowhere to go is TEXT, not a control',
        (tester) async {
      await pumpBoth(tester, const KitRecipeBody(recipe: recipe));
      expect(find.text('0:42'), findsOneWidget);
      // Branch 3 of §Step jump: no audio and no time-parameter source, so the
      // chip renders plain. A control that looks live and does nothing is the
      // dead-endpoint defect in miniature.
      expect(find.byIcon(Icons.headset_outlined), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      // The step with no `start` grows no time of its own — INV-20(c) makes
      // the backend refuse to estimate, and a client must not fill the gap.
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('a tick is a cooking session — local, and nothing is written',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: KitRecipeBody(recipe: recipe)),
        ),
      ));
      final item = find.text('1 cup coarse yellow cornmeal');
      Text textOf() => tester.widget<Text>(item);
      expect(textOf().style?.decoration, isNot(TextDecoration.lineThrough));
      await tester.tap(item);
      await tester.pump();
      expect(textOf().style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('§15.1 / §15.2 source viewers', () {
    testWidgets('§15.1 names what it cannot draw rather than drawing nothing',
        (tester) async {
      await pumpBoth(
        tester,
        const KitSourceFileView(
          title: 'budget.docx',
          url: 'https://example.test/budget.docx',
          stage: KitStage.none,
          typeLabel: 'DOCX',
        ),
      );
      expect(find.text('budget.docx'), findsOneWidget);
      expect(
        find.textContaining('A DOCX can’t be displayed here'),
        findsOneWidget,
      );
    });

    testWidgets('§15.2 renders every member AT ITS OWN INDEX', (tester) async {
      await pumpBoth(
        tester,
        const KitSourceSetGallery(
          members: [
            KitSetMember(name: 'front.jpg', signedUrl: 'https://x.test/1.jpg'),
            // The middle page has not landed. Dropping it would renumber
            // `back.jpg` to 2 and tell the reader their 3-page set is 2 pages
            // long (§15.2 rule 1).
            KitSetMember(name: 'middle.png'),
            KitSetMember(name: 'back.jpg', signedUrl: 'https://x.test/3.jpg'),
          ],
        ),
        size: const Size(900, 1200),
      );
      expect(find.text('PAGES'), findsOneWidget);
      expect(find.text('2 of 3 uploaded'), findsOneWidget);
      expect(find.text('middle.png'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(
        find.textContaining('hasn’t finished uploading'),
        findsOneWidget,
      );
    });

    testWidgets('an empty set is a state, not an empty screen', (tester) async {
      await pumpBoth(tester, const KitSourceSetGallery(members: []));
      expect(find.textContaining('no pages stored'), findsOneWidget);
    });
  });

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

    testWidgets('KitProcNote is an italic serif sentence and NOTHING else',
        (tester) async {
      await pumpBoth(
        tester,
        const KitProcNote(
          'Auto-sync is on but no folders are chosen.',
        ),
      );
      final text = tester.widget<Text>(
        find.text('Auto-sync is on but no folders are chosen.').first,
      );
      expect(text.style!.fontStyle, FontStyle.italic);
      expect(text.style!.fontSize, 13);
      // The absent icon is a REQUIRED part of this pattern: the reference
      // draws the inert state as a bare sentence, and a triangle beside it
      // says something failed when nothing has (F-09).
      expect(find.byType(Icon), findsNothing);
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

    // 4.32.6 — the actions are the OPTIONAL part and they are the part that
    // yields. The reference's CSS had this backwards until then, and this
    // client was ported from that row: `Expanded(titleBlock)` took whatever a
    // non-shrinking action row left it, so four actions in an 860px column set
    // *Quarterly Tax Summary* as three stacked lines at 44px. No gate can see
    // a title that merely wraps — so the gate is the geometry.
    testWidgets('a wide action set drops to its own line; the title keeps its '
        'floor', (tester) async {
      await pumpBoth(
        tester,
        ChapterOpening(
          title: 'Quarterly Tax Summary',
          // Sized rather than measured: the branch turns on a WIDTH, and a
          // row of buttons whose width comes from font metrics would make
          // this test's subject the font.
          actions: [
            for (final label in const [
              'Open the source',
              'Speed read',
              'Summarize',
              'Delete',
            ])
              SizedBox(
                  width: 150, child: KitButton.ghost(label, onPressed: () {})),
          ],
        ),
        // Wide enough for §2.1's row branch (the compact branch stacks
        // unconditionally and would pass this for the wrong reason), narrow
        // enough that the actions cannot fit beside the title.
        size: const Size(800, 900),
      );

      final title = tester.getRect(find.byType(AccentTitle));
      final actions =
          tester.getRect(find.widgetWithText(KitButton, 'Speed read'));
      expect(actions.top, greaterThan(title.bottom),
          reason: 'the actions stayed beside the title and squeezed it');
      expect(title.width, greaterThanOrEqualTo(212),
          reason: 'the title fell below its 24ch floor');
    });

    testWidgets('and stays beside a title that leaves room for it',
        (tester) async {
      await pumpBoth(
        tester,
        ChapterOpening(
          title: 'Activity',
          actions: [
            SizedBox(
                width: 120, child: KitButton.primary('Add', onPressed: () {})),
          ],
        ),
        size: const Size(1200, 900),
      );

      final title = tester.getRect(find.byType(AccentTitle));
      final action = tester.getRect(find.widgetWithText(KitButton, 'Add'));
      expect(action.left, greaterThan(title.right),
          reason: 'one small action beside one word should not wrap — a row '
              'that always stacks is the other half of the same defect');
      expect(action.top, lessThan(title.bottom));
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

    testWidgets('a *clause* in the title is set, never drawn as asterisks',
        (tester) async {
      await pumpBoth(
        tester,
        const KitEmptyState(
          icon: Icons.timeline_outlined,
          title: 'Nothing has happened *yet.*',
          standfirst: 'This is the record of your account.',
        ),
      );
      final title = find.byType(AccentTitle);
      expect(title, findsOneWidget);
      final rich = tester.widget<Text>(
          find.descendant(of: title, matching: find.byType(Text)));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((s) => s.text).join(), 'Nothing has happened yet.');
      final clause = spans.singleWhere((s) => s.text == 'yet.');
      expect(clause.style!.fontStyle, FontStyle.italic);
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
                // The unread badge (screens/activity.md §Toasts and unread) —
                // the same trailing slot as the count, drawn as a pill.
                KitNavItem(
                  icon: Icons.timeline_outlined,
                  label: 'Activity',
                  badge: kitBadgeLabel(12),
                  onTap: () {},
                ),
                // Both given: the badge takes the slot. A count says how many
                // things there are, a badge says some of them are new.
                KitNavItem(
                  icon: Icons.mail_outlined,
                  label: 'Letters',
                  count: '4',
                  badge: kitBadgeLabel(2),
                  onTap: () {},
                ),
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
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('4'), findsNothing,
          reason: 'the count drew beside the badge instead of yielding to it');
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

  group('§19 section rail', () {
    testWidgets('one jump per section, the current one marked by TWO channels',
        (tester) async {
      await pumpBoth(
        tester,
        SizedBox(
          height: 120,
          child: KitSectionRail(
            items: const [
              KitSectionRailItem('summary', 'Summary', Icons.auto_awesome_outlined),
              KitSectionRailItem('manuscript', 'Manuscript', Icons.notes_outlined),
              KitSectionRailItem('original', 'Original',
                  Icons.insert_drive_file_outlined, count: 'PDF'),
            ],
            current: 'manuscript',
            onJump: (_) {},
            background: const Color(0xFFFFFFFF), // literal-ok: a test ground

          ),
        ),
      );
      expect(find.text('Summary'), findsWidgets);
      expect(find.text('Manuscript'), findsWidgets);
      // The Original jump carries the document's own type as a mono chip.
      expect(find.text('PDF'), findsWidgets);

      // Position AND weight, never hue alone (§19): the current jump owns the
      // 2px accent underline, and its label is `--fg` where the others are
      // `--fg-muted`. Both are read off the live tree.
      final marked = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(KitSectionRail), matching: find.byType(Container)))
          .where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.border is Border &&
            (d.border! as Border).bottom.width == 2 &&
            (d.border! as Border).bottom.color.a > 0;
      });
      expect(marked.length, 1,
          reason: 'exactly one jump is current, and it is marked by an '
              'underline — not by colour alone and not by none');
    });

    testWidgets('a jump reports the section it names', (tester) async {
      final jumped = <String>[];
      await pumpBoth(
        tester,
        SizedBox(
          height: 120,
          child: KitSectionRail(
            items: const [
              KitSectionRailItem('summary', 'Summary', Icons.auto_awesome_outlined),
              KitSectionRailItem('history', 'History', Icons.history),
            ],
            current: 'summary',
            onJump: jumped.add,
            background: const Color(0xFFFFFFFF), // literal-ok: a test ground

          ),
        ),
      );
      await tester.tap(find.text('History').first);
      await tester.pump();
      // ONE call, carrying the id — the rail does not set its own current
      // (§19: it is reported from scroll, and a tap marks it only because the
      // scroll it causes arrives there).
      expect(jumped, ['history']);
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

    testWidgets('§9.2 — a scoped entry names its shelf, an unscoped one is '
        'silent', (tester) async {
      // Both directions in one frame, because the defect is the pair: a
      // conversation scoped to a shelf and a library-wide one were identical
      // in the rail while being answers about different libraries (ADR-098) —
      // and a label on the unscoped one would put a word on every entry to
      // distinguish the few that have one.
      await pumpBoth(
        tester,
        SizedBox(
          height: 600,
          child: KitInspectorRail(
            title: 'Conversations',
            newLabel: 'New conversation',
            onNew: () {},
            groups: [
              KitRailGroup(
                label: 'Today',
                entries: [
                  KitRailEntry(
                    title: 'What should I cook?',
                    scope: 'Recipes',
                    time: '1:15 PM',
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
      // Mono CAPS, the rail's own idiom — the widget upper-cases it, so a
      // caller passing the shelf's stored title cannot get a lowercase label.
      expect(find.text('RECIPES'), findsWidgets);
      expect(find.text('Recipes'), findsNothing);
      // The unscoped entry renders no scope of any kind.
      expect(find.text('ALL'), findsNothing);
      expect(find.text('LIBRARY'), findsNothing);
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

    testWidgets('§9.1 — the cluster is present and the TIME yields to it', (
      tester,
    ) async {
      // Two entries, one with actions and one without, so the yield is read as
      // a difference rather than as an entry that happens to have no time. On
      // the reference the cluster is hover-revealed and unconditional under a
      // coarse pointer; this client is only ever the second case.
      await pumpBoth(
        tester,
        SizedBox(
          height: 600,
          child: KitInspectorRail(
            title: 'Conversations',
            groups: [
              KitRailGroup(
                label: 'Today',
                entries: [
                  KitRailEntry(
                    title: 'Pasta',
                    time: '8:18 PM',
                    onTap: () {},
                    actions: [
                      KitRailEntryAction(
                        icon: Icons.edit_outlined,
                        label: 'Rename “Pasta”',
                        onPressed: () {},
                      ),
                      KitRailEntryAction(
                        icon: Icons.delete_outline,
                        label: 'Delete “Pasta”',
                        danger: true,
                        onPressed: () {},
                      ),
                    ],
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
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
      // The entry WITH actions has dropped its time; the one without keeps it.
      expect(find.text('8:18 PM'), findsNothing);
      expect(find.text('Sep 3'), findsWidgets);
    });

    testWidgets('§9.1 — rename edits in place, and Escape ABANDONS', (
      tester,
    ) async {
      String? committed;
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: KitInspectorRail(
                title: 'Conversations',
                groups: [
                  KitRailGroup(
                    label: 'Today',
                    entries: [
                      KitRailEntry(
                        title: 'Pasta',
                        onTap: () {},
                        renaming: true,
                        onRenameCommit: (v) => committed = v,
                        onRenameCancel: () => cancelled++,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The field IS the title, seeded with it — not an empty box.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'Pasta');

      await tester.enterText(field, 'Pasta, from the top');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, 'Pasta, from the top');

      // Escape abandons — and must not then commit the draft it abandoned
      // through the focus loss it causes itself.
      committed = null;
      await tester.enterText(field, 'not this');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(cancelled, 1);
      expect(committed, isNull);
    });

    testWidgets('§9.1 — a rejection is §14.2 in THAT entry', (tester) async {
      await pumpBoth(
        tester,
        SizedBox(
          height: 600,
          child: KitInspectorRail(
            title: 'Conversations',
            groups: [
              KitRailGroup(
                label: 'Today',
                entries: [
                  KitRailEntry(
                    title: 'Pasta',
                    onTap: () {},
                    error: 'A title is required.',
                  ),
                  KitRailEntry(title: 'Systems thinking', onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      );
      // The server's sentence, verbatim, once — in the entry that was refused
      // and not as a rail-wide banner.
      expect(find.text('A title is required.'), findsWidgets);
      expect(find.byType(KitFailureInline), findsWidgets);
    });
  });

  group('§16 anchored popover', () {
    Widget anchored() => Builder(
          builder: (ctx) => Center(
            child: SearchScoreAnchor(
              score: 0.8123,
              cosine: 0.6120,
              sourcePriority: 0.5000,
              child: const Text('0.81'),
            ),
          ),
        );

    testWidgets('closed it is UNMOUNTED — no panel, nothing to read', (
      tester,
    ) async {
      await pumpBoth(tester, anchored());
      // `pointer-events: none` and `aria-hidden` while closed, in the form a
      // widget tree has one: the panel is not in the tree at all, so it is not
      // hit-testable, not readable and not a tab stop.
      expect(find.text('RELEVANCE'), findsNothing);
      expect(find.text('Similarity'), findsNothing);
    });

    testWidgets('the head, both rows in fixed order, and the foot', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: anchored()),
      ));
      await tester.tap(find.text('0.81'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('RELEVANCE'), findsOneWidget);
      expect(find.text('0.8123'), findsOneWidget,
          reason: 'the head figure is the blended score at 4dp');
      // Fixed order: Similarity, then Source priority.
      final sim = tester.getTopLeft(find.text('Similarity')).dy;
      final src = tester.getTopLeft(find.text('Source priority')).dy;
      expect(sim, lessThan(src));
      // Contribution is `weight × component`, at 4dp — arithmetic over a
      // returned value, not a reconstruction of one.
      expect(find.text('0.4896'), findsOneWidget);
      expect(find.text('0.1000'), findsOneWidget);
      expect(find.text('×0.8'), findsOneWidget);
      expect(find.text('×0.2'), findsOneWidget);
      expect(find.text('Measured by the server, not estimated.'),
          findsOneWidget);
    });

    testWidgets('a missing component renders NO ROW — never a derived one', (
      tester,
    ) async {
      // ADR-082, the whole point. `source_priority` is recoverable as
      // `(score − 0.8 × cosine) / 0.2` and that figure is an inference: both
      // inputs are already rounded, the division multiplies their error
      // fivefold, and the arithmetic keeps succeeding — wrongly — if the
      // weights ever change.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SearchScoreAnchor(
              score: 0.8123,
              cosine: 0.6120,
              sourcePriority: null,
              child: const Text('0.81'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('0.81'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Similarity'), findsOneWidget);
      expect(find.text('Source priority'), findsNothing);
      expect(find.text('This surface received only part of the breakdown.'),
          findsOneWidget);
    });

    testWidgets('with NO component it is inert — not even a control', (
      tester,
    ) async {
      // No popover, no focus stop, and no promise of an explanation that
      // cannot come. `cursor: help` over nothing is what this pattern's own
      // anchor shipped for fifteen months.
      await pumpBoth(
        tester,
        const Center(
          child: SearchScoreAnchor(
            score: 0.81,
            cosine: null,
            sourcePriority: null,
            child: Text('0.81'),
          ),
        ),
      );
      expect(find.byType(KitAnchoredPopover), findsNothing);
      expect(find.text('0.81'), findsOneWidget);
    });
  });

  group('§18 confirmation', () {
    testWidgets('the panel STAYS OPEN on a refusal, and answers inside it', (
      tester,
    ) async {
      // The whole reason this pattern exists. A confirmation that closes on
      // click has reported success for something that may not have happened —
      // and closing it on the REJECTION is worse than never catching one.
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => KitConfirm.show(
                  ctx,
                  title: 'Delete “Pasta”?',
                  body: 'The questions go. Nothing leaves your library.',
                  confirmLabel: 'Delete conversation',
                  cancelLabel: 'Keep it',
                  onConfirm: () async {
                    calls++;
                    return 'Conversation not found.';
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Pasta”?'), findsOneWidget);

      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      // Still open, with the server's sentence in it.
      expect(find.text('Delete “Pasta”?'), findsOneWidget);
      expect(find.text('Conversation not found.'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsOneWidget);

      // Cancel still works after a refusal — the reader is not trapped.
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Pasta”?'), findsNothing);
    });

    testWidgets('it closes and reports true only on SUCCESS', (tester) async {
      bool? outcome;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  outcome = await KitConfirm.show(
                    ctx,
                    title: 'Remove “Budget”?',
                    body: 'The original file is untouched.',
                    confirmLabel: 'Remove',
                    cancelLabel: 'Keep it',
                    onConfirm: () async => null,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove “Budget”?'), findsNothing);
      expect(outcome, isTrue);
    });

    testWidgets('a dismissal reports false, and never runs the action', (
      tester,
    ) async {
      var calls = 0;
      bool? outcome;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  outcome = await KitConfirm.show(
                    ctx,
                    title: 'Delete the “Recipes” shelf?',
                    body: 'Its volumes stay in your library.',
                    confirmLabel: 'Delete shelf',
                    cancelLabel: 'Keep it',
                    onConfirm: () async {
                      calls++;
                      return null;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(outcome, isFalse);
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

    // Onboarding's spelling of the same three parts (`.ob-move`): a ruled row
    // with a leading glyph. Both forms live in one widget so the second one
    // is not retyped on the screen that needs it (4.46.0).
    testWidgets('the ruled form keeps every part, and leads with a glyph', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const KitNumberedMove(
          number: 'II',
          icon: Icons.mail_outline,
          title: 'Receive a daily letter',
          description: 'A few passages from your own library.',
          ruled: true,
          last: true,
        ),
      );
      expect(find.text('II'), findsOneWidget);
      expect(find.text('Receive a daily letter'), findsOneWidget);
      expect(find.text('A few passages from your own library.'), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    });
  });

  group('§7 mark', () {
    testWidgets('the chrome tile, and the sealed form', (tester) async {
      await pumpBoth(tester, const KitMark(Icons.edit_note, size: 72));
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      await pumpBoth(tester, const KitMark.seal(Icons.edit_note));
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
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

  group('§1.3 utility bar', () {
    // A crumb squeezed to a stub is worse than no crumb — `§ LET…` and
    // `READI…` are what this bar drew on the readings day view at phone
    // width, where a back control and one action leave about six characters.
    // BOTH directions, because a rule that also hides a crumb which FITS is
    // the worse defect of the two (4.34.8).
    //
    // The width is set on the bar itself rather than by composing real
    // buttons: what the rule reads is the room the crumb GOT, and button
    // metrics in a test harness are not the app's — a case built from them
    // would be measuring the font fallback.
    Widget bar(double width) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: const KitUtilityBar(
                  crumb: 'Readings · Thursday, September 10'),
            ),
          ),
        );

    testWidgets('keeps a crumb there is room for', (tester) async {
      await tester.pumpWidget(bar(600));
      await tester.pumpAndSettle();
      expect(find.textContaining('READINGS'), findsOneWidget);
    });

    testWidgets('drops one there is not', (tester) async {
      await tester.pumpWidget(bar(80));
      await tester.pumpAndSettle();
      expect(find.textContaining('READINGS'), findsNothing);
    });
  });

  group('§8 unmeasured figure (4.75.0, ADR-109)', () {
    Color numeralColor(WidgetTester tester, String text) {
      final rich = tester
          .widgetList<RichText>(find.byWidgetPredicate((w) =>
              w is RichText && w.text.toPlainText().startsWith(text)))
          .first;
      return (rich.text as TextSpan).style!.color!;
    }

    test('the rule: null is the dash and unmeasured, 0 is a measurement', () {
      expect(kitFigure(null), (measured: false, text: '—'));
      expect(kitFigure('0'), (measured: true, text: '0'));
    });

    testWidgets('a null figure draws the dash, subtle, and no denominator', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        const KitStatCluster(stats: [
          KitStat(null, 'Volumes'),
          KitStat(null, 'Passages read', denominator: '12'),
        ]),
      );
      expect(find.text('—', findRichText: true), findsNWidgets(2));
      expect(find.text('0', findRichText: true), findsNothing,
          reason: 'a refused read is not a library of zero');
      expect(find.textContaining('/ 12', findRichText: true), findsNothing,
          reason: '"— / 12" is a claim about a total nothing read');
      expect(find.text('VOLUMES'), findsOneWidget, reason: 'label unchanged');
      final t = Tokens.of(tester.element(find.byType(KitStatCluster)));
      expect(numeralColor(tester, '—'), t.fgSubtle);
    });

    testWidgets('a measured zero keeps its figure and its denominator', (
      tester,
    ) async {
      // Both directions: a test that only checks the dash passes a call site
      // that writes `?? '0'`, and one that only checks zero passes a kit that
      // never draws the dash.
      await pumpBoth(
        tester,
        const KitStatCluster(stats: [
          KitStat('0', 'Volumes'),
          KitStat('0', 'Passages read', denominator: '12'),
        ]),
      );
      expect(find.text('—', findRichText: true), findsNothing);
      expect(find.text('0', findRichText: true), findsOneWidget);
      expect(find.text('0 / 12', findRichText: true), findsOneWidget);
      final t = Tokens.of(tester.element(find.byType(KitStatCluster)));
      expect(numeralColor(tester, '0 / 12'), t.fg);
    });

    testWidgets('the rail card runs the same rule; its highlight cannot fire',
        (tester) async {
      await pumpBoth(
        tester,
        const KitRailCard(
          icon: Icons.menu_book_outlined,
          label: 'Library',
          figures: [
            KitRailFigure(null, 'Volumes'),
            KitRailFigure(null, 'Unread', highlight: true),
            KitRailFigure('0', 'Passages'),
          ],
        ),
      );
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
      final t = Tokens.of(tester.element(find.byType(KitRailCard)));
      for (final dash in tester.widgetList<Text>(find.text('—'))) {
        expect(dash.style!.color, t.chromeSubtle,
            reason: 'an unread dash is neither the figure colour nor the '
                'unread highlight');
      }
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
