import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/scripture_letter_notifier.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/pages/onboarding/wizard.dart';
import 'package:flutter_app/pages/reader/passage_mark.dart';
import 'package:flutter_app/pages/search/reading_pane.dart';
import 'package:flutter_app/pages/search/result_card.dart';
import 'package:flutter_app/pages/search/search_field.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The device run (../TODO.md). Drives the real app on a real renderer against
/// the emulator suite, because a whole class of this client's work is invisible
/// to the Tier-1 harness by construction:
///
///  - **the passage mark measures itself against scroll position**, and only a
///    REAL GESTURE proves it tracks — a programmatic `jumpTo` moves even a pane
///    that cannot be dragged, so it would prove nothing;
///  - the token-built `ColorScheme` and the curvature sweep recoloured and
///    reshaped nearly every control, and no assertion can say whether the
///    result renders;
///  - a bundled font that fails to load falls back SILENTLY.
///
/// Seed the scroll-length fixture FIRST, and again after every emulator
/// restart — the seed import does not carry it and no client may write it
/// (INV-04):
/// ```
/// FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_long_doc.py
/// ```
///
/// Run (ports per /emu, beside another workspace's suite on the defaults):
/// ```
/// flutter test integration_test/device_run_test.dart \
///   -d <device-id> \
///   --dart-define=USE_EMULATOR=true \
///   --dart-define=EMULATOR_FIRESTORE_PORT=8580 \
///   --dart-define=EMULATOR_AUTH_PORT=9599 \
///   --dart-define=EMULATOR_FUNCTIONS_PORT=5599 \
///   --dart-define=EMULATOR_FUNCTIONS_SHIM=true
/// ```
const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Refuse to run against prod. This client points at real noteletter-7a111
    // by default and writes real counters (INV-03a/03b) — a device run that
    // silently hit prod would inflate exactly the counters a backfill has
    // already corrected.
    if (!ApiService.useEmulator) {
      fail(
        'Refusing to run: pass --dart-define=USE_EMULATOR=true (umbrella law 1).',
      );
    }
    final host = ApiService.emulatorHost;
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      ApiService.firestorePort,
    );
    await FirebaseAuth.instance.useAuthEmulator(host, ApiService.authPort);
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: seedEmail,
      password: seedPassword,
    );
  });

  /// Bounded pumps, never `pumpAndSettle`.
  ///
  /// Two reasons, and the second is the one that bites. A screen listing live
  /// documents carries a looping indicator whenever one is processing, so a
  /// settle waits for a frame that never comes. And `pumpAndSettle`'s Duration
  /// is the **interval between pumps, not a timeout** — the default deadline is
  /// ten minutes, so the hang does not look like a hang, it looks like a slow
  /// test. Both cost this file a run each.
  Future<void> pumpFor(
    WidgetTester tester, {
    Duration total = const Duration(seconds: 4),
  }) async {
    final ticks = total.inMilliseconds ~/ 250;
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final auth = AuthNotifier();
    final router = createRouter(auth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthNotifier>.value(value: auth),
          ChangeNotifierProvider<UploadNotifier>(
            create: (_) => UploadNotifier(),
          ),
          ChangeNotifierProvider<SearchNotifier>(
            create: (_) => SearchNotifier(),
          ),
          ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
          ChangeNotifierProvider<ActivityNotifier>(
            create: (_) => ActivityNotifier(),
          ),
          ChangeNotifierProvider<DocumentsNotifier>(
            create: (_) => DocumentsNotifier(),
          ),
          ChangeNotifierProvider<SettingsNotifier>(
            create: (_) => SettingsNotifier(),
          ),
          ChangeNotifierProvider<NewsletterNotifier>(
            create: (_) => NewsletterNotifier(),
          ),
          // The readings letter's own settings document (ADR-029) — separate
          // from the daily letter's, exactly as its endpoint is. A provider
          // missing HERE does not fail the app: it fails the run, with a
          // ProviderNotFoundError wall where the screen should be.
          ChangeNotifierProvider<ScriptureLetterNotifier>(
            create: (_) => ScriptureLetterNotifier(),
          ),
          ChangeNotifierProvider<CloudNotifier>(create: (_) => CloudNotifier()),
          ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
          ChangeNotifierProvider<TagsNotifier>(create: (_) => TagsNotifier()),
          ChangeNotifierProvider<SupportNotifier>(
            create: (_) => SupportNotifier(),
          ),
          ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
        ],
        child: NoteLetterApp(router: router),
      ),
    );
    // Four seconds, not the two the settle here named: a settle's Duration is
    // the interval it advances the clock by on each pump, so `pumpAndSettle(2s)`
    // drained far more than two seconds of pending work. Startup loads still in
    // flight when a test ends resurface a test or two later as a notifier used
    // after disposal.
    await pumpFor(tester, total: const Duration(seconds: 4));
    return router;
  }

  testWidgets('signs in and reaches the library', (tester) async {
    await pumpApp(tester);
    expect(FirebaseAuth.instance.currentUser, isNotNull);
    // Landing must NOT be showing — the redirect sends a signed-in user to '/'.
    expect(
      find.text('Your Knowledge Base, Automatically Curated'),
      findsNothing,
    );
  });

  testWidgets('the library home composes from the kit and really scrolls', (
    tester,
  ) async {
    // `/` is the Library (screens/library.md). Composition is what no other
    // gate here looks at: tokens, data and behaviour were all green while this
    // screen was a different design (ADR-041), so the assertions below are
    // about PARTS BEING PRESENT, in the roles the kit gives them.
    await pumpApp(tester);
    // Bounded pumps rather than a settle: the library home lists live
    // documents, and a processing one carries a looping indicator. With one in
    // the feed a settle waits for a frame that never comes — this test hung for
    // the full ten-minute settle timeout on exactly that.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The chapter opening: folio, the greeting title with its accent clause,
    // and the chapter rule. The dropped folio and the dropped accent clause are
    // two of the four commonest ways a screen stops looking like this app.
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.byType(ChapterRule), findsWidgets);
    expect(
      find.textContaining(RegExp('Good (morning|afternoon|evening)')),
      findsOneWidget,
    );

    // Either the library has volumes — three sections, each opened by a
    // section header — or it is empty, and then the DROP ZONE leads. An empty
    // state that is a centred apology is a failed composition, not a state.
    final seeded = find.byType(SectionHeader).evaluate().isNotEmpty;
    if (seeded) {
      expect(
        find.byType(KitRowList),
        findsWidgets,
        reason: 'recently-read renders as source rows (kit §4.1)',
      );
      // The eyebrow renders its text UPPERCASED, so that is what is in the
      // tree — matching the sentence-case source string finds nothing.
      expect(find.textContaining('RECENTLY READ'), findsOneWidget);
      expect(find.textContaining('SHELVES'), findsWidgets);
    } else {
      expect(
        find.byType(KitDropZone),
        findsOneWidget,
        reason: 'the empty library leads with the drop zone, not a message',
      );
    }

    // Only a REAL gesture proves a pane scrolls — a programmatic offset moves
    // even one the user cannot drag. Four web pages shipped unscrollable for
    // their whole lives that way (4.3.1).
    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);
    final position = tester.widget<Scrollable>(scrollable.first).controller;
    final before = position?.offset ?? 0;
    await tester.drag(scrollable.first, const Offset(0, -400));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final after = tester.state<ScrollableState>(scrollable.first).position;
    // A page shorter than the viewport cannot scroll and must not be failed
    // for it; what would be a defect is a page with overflow that does not
    // move under a drag.
    if (after.maxScrollExtent > 0) {
      expect(
        after.pixels,
        greaterThan(before),
        reason: 'the library body did not move under a real drag',
      );
    }
  });

  testWidgets('the reader renders and the passage mark tracks a REAL drag', (
    tester,
  ) async {
    // A document that is LONG and UNCOUNTED, written by tool/seed_long_doc.py.
    // Neither property is incidental:
    //  - the canonical seed's complete documents are 9-54 words, shorter than
    //    the viewport, so nothing scrolls and every fill pins at 1.0 from the
    //    first frame;
    //  - a COUNTED passage renders full regardless of scroll (by design), so a
    //    counted fixture can never show the bar rising either.
    // With either one, this test passes or fails for reasons that have nothing
    // to do with whether the mark works.
    const docId = 'device-run-long-doc';
    // The catch is the whole point: rules L65 reads `resource.data.user_id`,
    // and `resource` is NULL for a document that does not exist, so a missing
    // fixture comes back as permission-denied rather than as an absent
    // document. Uncaught, that throws here and the reason below — the one that
    // names the fix — is never reached. Every emulator restart re-imports the
    // seed and drops this fixture, so it is the common case, not the rare one.
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('documents')
          .doc(docId)
          .get();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    expect(
      doc?.exists ?? false,
      isTrue,
      reason:
          'run tool/seed_long_doc.py against the emulator first '
          '(a denied read here means the document is absent, not that the '
          'rules changed)',
    );
    final chunks = await FirebaseFirestore.instance
        .collection('chunks')
        .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('document_id', isEqualTo: docId)
        .get();
    expect(chunks.docs, isNotEmpty);
    expect(
      chunks.docs.every((c) => (c.data()['view_count'] ?? 0) == 0),
      isTrue,
      reason: 'fixture chunks must be uncounted, or the fill is pinned full',
    );

    // Deep-link straight to the reader rather than tapping through the
    // library: what is under test is the mark, not the navigation.
    final router = await pumpApp(tester);
    router.go('/reader/$docId');
    await pumpFor(tester, total: const Duration(seconds: 3));

    // The header composes from the kit (§Composition): the Reading frame, a
    // back control naming the library, a §2.1 chapter opening led by the
    // document's file badge, and the §8 stat cluster. Asserted on the REAL
    // renderer because composition is precisely what no contract test sees —
    // this screen kept its own AppBar, its own `_metaRow` and six accent pills
    // through every green gate.
    expect(find.byType(KitBackControl), findsOneWidget);
    expect(find.byType(ChapterOpening), findsOneWidget,
        reason: 'the reader opens a chapter — one header, then body swaps');
    expect(
      find.descendant(
          of: find.byType(ChapterOpening), matching: find.byType(KitFileBadge)),
      findsOneWidget,
      reason: 'the file badge LEADS the header (§2.1 lead, §6.4)',
    );
    final cluster = tester.widget<KitStatCluster>(find.byType(KitStatCluster));
    expect(cluster.form, KitStatForm.separated,
        reason: 'the reader header draws the SEPARATED row (§8)');
    expect(cluster.ruled, isFalse,
        reason:
            'the --ruled modifier is a report treatment; a header inside a '
            'screen frame does not take it (4.46.0, ADR-084)');
    expect(
      cluster.stats.any((st) => st.label == 'Passages read'),
      isTrue,
      reason: 'coverage is rendered here and only here',
    );
    // The stat row must reflect the read it just logged: `doc_opened` is
    // written AFTER the document is fetched, so a client that renders the
    // snapshot unmodified shows "Views 0" for the whole session on a first
    // open (reader.md §Data).
    final views = cluster.stats.firstWhere((st) => st.label == 'Views');
    expect(int.parse(views.value), greaterThan(0),
        reason: 'Views must fold in what the doc_opened write committed');

    final manuscript = find.text('Manuscript');
    if (manuscript.evaluate().isNotEmpty) {
      await tester.tap(manuscript.first);
      await pumpFor(tester, total: const Duration(seconds: 2));
    }

    expect(
      find.byType(PassageMark),
      findsWidgets,
      reason: 'the manuscript must render the extent mark at rest',
    );

    // The mark's fill is the heightFactor of the FractionallySizedBox inside
    // it — read from the live tree rather than from any test-only hook.
    List<double> fills() => tester
        .widgetList<FractionallySizedBox>(
          find.descendant(
            of: find.byType(PassageMark),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .map((w) => w.heightFactor ?? 0)
        .toList();

    final before = fills();
    expect(before, isNotEmpty);

    // A REAL gesture. `drag` synthesises the same pointer stream a finger
    // produces, so the scroll position actually moves and the mark's listener
    // fires — unlike a programmatic jumpTo, which moves even an unscrollable
    // pane and would prove nothing (umbrella CLAUDE.md).
    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);
    var prev = before;
    var everRose = false;
    for (var i = 0; i < 5; i++) {
      await tester.drag(scrollable.first, const Offset(0, -320));
      await pumpFor(tester, total: const Duration(seconds: 1));
      final now = fills();
      // HIGH-WATER MARK: it may rise or hold, never retreat. A bar that went
      // down would say the reader had un-read something.
      for (var j = 0; j < now.length && j < prev.length; j++) {
        expect(
          now[j],
          greaterThanOrEqualTo(prev[j] - 0.001),
          reason: 'passage $j fill retreated: ${prev[j]} -> ${now[j]}',
        );
        if (now[j] > prev[j] + 0.001) everRose = true;
      }
      prev = now;
    }
    expect(
      everRose,
      isTrue,
      reason:
          'no passage fill rose across five real drags — the mark is '
          'not tracking scroll at all',
    );

    // Scroll back UP: re-reading is still reading, so the mark must hold.
    final atBottom = fills();
    for (var i = 0; i < 5; i++) {
      await tester.drag(scrollable.first, const Offset(0, 320));
      await pumpFor(tester, total: const Duration(seconds: 1));
    }
    final backAtTop = fills();
    for (var j = 0; j < backAtTop.length && j < atBottom.length; j++) {
      expect(
        backAtTop[j],
        greaterThanOrEqualTo(atBottom[j] - 0.001),
        reason: 'passage $j retreated on scrolling back up',
      );
    }
  });

  // F-10's device obligation. Listen, Original, SpeedRead and History had
  // never been opened on a device run at all — each is a body swap under the
  // reader's one header, so a run that only ever sees the Summary panel
  // exercises none of them, and a panel that throws on first build is
  // indistinguishable from a panel nobody looked at.
  testWidgets('the reader opens every panel', (tester) async {
    // The canonical seed's own complete document — this test is about the
    // sections building, not about length, so it needs no long-doc fixture.
    //
    // Since 4.64.0 (ADR-100) the six are STACKED and each control is a jump,
    // not a tab: tapping one scrolls to a section that is already mounted. The
    // test is unchanged in what it proves — that every section builds without
    // throwing — and `the reader scrolls from Summary to History without a
    // tap` is what proves they are reached by scrolling.
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await pumpFor(tester, total: const Duration(seconds: 3));

    // The labels exactly as `_railItems` spells them — 'Speed read', not
    // 'SpeedRead'. A list written from memory fails on the label rather than on
    // the section, which is a red test about nothing.
    for (final label in const [
      'Manuscript',
      'Speed read',
      'Listen',
      'Original',
      'History',
      'Summary',
    ]) {
      final tab = find.text(label);
      if (tab.evaluate().isEmpty) {
        fail('the reader draws no "$label" jump — reader.md §Continuous scroll '
            'lists six sections and this run found five');
      }
      // Printed per panel because the first run of this test timed out after
      // twelve minutes with no indication of WHERE: a hang reports the test,
      // never the step, and four of these six panels had never been opened on
      // a device at all.
      debugPrint('PANEL: jumping to $label');
      await tester.ensureVisible(tab.first);
      await tester.tap(tab.first, warnIfMissed: false);
      await pumpFor(tester, total: const Duration(seconds: 2));
      debugPrint('PANEL: $label built');
      // An exception during build is swallowed into the widget tree as an
      // ErrorWidget rather than failing the tap, so the tap alone proves
      // nothing: a panel that throws still "opens".
      expect(tester.takeException(), isNull,
          reason: 'the $label section threw while building');
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'the $label section built an ErrorWidget');
    }
  });

  // ── ADR-100 / ADR-051 ──────────────────────────────────────────────────────
  // The reader is one document on one scroll, and the acceptance test is the
  // DEEP LINK rather than the scroll: `?p=` scrolled into the manuscript, which
  // was not mounted until the reader picked its tab, so on the web reference
  // that link had never once fired from a cold open (CHANGELOG 4.64.0). This
  // client must not reproduce it — which is why the second half opens the link
  // cold and taps nothing.
  testWidgets("the reader scrolls from Summary to History without a tap, and "
      "the rail's current jump follows the scroll", (tester) async {
    const docId = 'device-run-long-doc';
    final router = await pumpApp(tester);
    router.go('/reader/$docId');
    await pumpFor(tester, total: const Duration(seconds: 4));

    String current() => tester
        .widget<KitSectionRail>(find.byType(KitSectionRail))
        .current;

    // Every section is MOUNTED on open — no tap, no reveal. This is the whole
    // of ADR-100: a section behind a control is a render target nobody mounts.
    expect(find.byType(KitSectionRail), findsOneWidget,
        reason: 'the reader draws no §19 rail');
    expect(current(), 'summary',
        reason: 'the reader opens at the top of the document');

    // A REAL gesture. Programmatic scrolling moves even a pane a reader cannot
    // scroll (umbrella traps), so this drags — repeatedly, because the long
    // document is several viewports tall — and watches the rail report.
    final seen = <String>{current()};
    for (var i = 0; i < 60 && current() != 'history'; i++) {
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -520),
        warnIfMissed: false,
      );
      await pumpFor(tester, total: const Duration(milliseconds: 750));
      seen.add(current());
    }
    final pos = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .position;
    debugPrint('DEVICE-RUN reader scroll: reported ${seen.toList()} '
        'offset=${pos.pixels.round()}/${pos.maxScrollExtent.round()}');
    expect(current(), 'history',
        reason: 'scrolling did not reach the last section — either a section '
            'is not mounted or the rail is not reporting position');
    // It passed through the middle rather than jumping end to end: the rail
    // REPORTS, and a report that only ever names the first and last section is
    // not following the scroll.
    expect(seen.length, greaterThan(2), reason: 'reported only $seen');

    // A JUMP arrives, and the rail reports where it arrived (§19). This is the
    // half nothing asserted: the drag above proves the report follows a real
    // scroll, and a jump is the other way the reader moves. It also pins the
    // landing — §19 is explicit that a jump leaving a section's header under
    // the sticky rail has not arrived at it.
    // The rail scrolls HORIZONTALLY (§19: labels are names and stay on one
    // line), so the jump being tapped has to be brought into the rail's own
    // viewport first — and `warnIfMissed` stays ON, because the first run of
    // this assertion tapped nothing, the scroll never moved, and the rail
    // answered `history` perfectly correctly from the end of the scroll. A
    // silent miss reads exactly like a rail that marks the wrong section.
    await tester.ensureVisible(find.text('Listen'));
    await tester.pump();
    await tester.tap(find.text('Listen'));
    await pumpFor(tester, total: const Duration(seconds: 2));
    // Both numbers BEFORE either assertion: a run that fails has to say where
    // the jump actually landed, or the next attempt is a guess.
    final railBottom = tester.getBottomLeft(find.byType(KitSectionRail)).dy;
    final head = tester.getTopLeft(find.text('LISTEN')).dy;
    debugPrint('DEVICE-RUN reader jump: current=${current()} '
        'head=$head railBottom=$railBottom');
    expect(current(), 'listen',
        reason: 'the rail marked a section the jump did not land on');
    expect(head, greaterThanOrEqualTo(railBottom - 1),
        reason: "the section's own header landed UNDER the rail, which §19 "
            'says is not arriving at it');

    // Cold open on a passage link — no tap anywhere, which is the condition
    // the web defect survived under for 49 versions.
    final chunks = await FirebaseFirestore.instance
        .collection('chunks')
        .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('document_id', isEqualTo: docId)
        .get();
    expect(chunks.docs.length, greaterThan(3),
        reason: 'run tool/seed_long_doc.py — a short document cannot show a '
            'scroll that had to happen');
    final target = chunks.docs.last.id;
    router.go('/reader/$docId?p=$target');
    await pumpFor(tester, total: const Duration(seconds: 6));
    // The link landed INSIDE the document, not at its top: the manuscript is
    // mounted on open, so the anchor exists for the scroll to reach.
    //
    // The OFFSET is the assertion, not the reported section — at the bottom of
    // the scroll the rail reports the last section whatever brought it there,
    // so `current != 'summary'` alone would also be true of a reader that did
    // not move at all if the document were short. This is a fresh route, so
    // its scroller starts at 0 and any offset is the anchor's doing.
    final after = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .position;
    debugPrint('DEVICE-RUN reader deep link: current=${current()} '
        'offset=${after.pixels.round()}');
    expect(after.pixels, greaterThan(100),
        reason: 'a `?p=` cold open left the reader at the top of the document '
            '— the passage link has not been honoured (ADR-051), which is the '
            'defect this whole item exists to avoid reproducing');
  });

  testWidgets('the reader opens the source file', (tester) async {
    // §15.1 (ADR-075) and §6.4.2. Two facts this asserts that nothing else
    // can, because both are about a REQUEST the client makes on a real
    // endpoint:
    //
    //  1. the Original panel reaches `fn_get_raw_document_url` at all — this
    //     client declared no builder for it until now, so the source viewer
    //     was unreachable rather than unbuilt;
    //  2. a successful answer carrying a URL renders the §15.1 VIEW, not the
    //     "no original file is stored" sentence. Those two are the same
    //     picture to every gate that does not run the request: the panel drew
    //     one sentence for a failure, an absent object and a link for its
    //     whole life.
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await pumpFor(tester, total: const Duration(seconds: 3));

    // The panel strip SCROLLS on a phone — `Original` is the fifth of six and
    // starts off-screen, so a bare tap lands on nothing, warns, and leaves the
    // Summary panel on screen. Ensure it is visible first, exactly as the
    // every-panel run does.
    await tester.ensureVisible(find.text('Original'));
    await tester.pump();
    await tester.tap(find.text('Original'), warnIfMissed: false);
    await pumpFor(tester, total: const Duration(seconds: 4));

    expect(tester.takeException(), isNull);
    expect(
      find.byType(KitSourceFileView),
      findsOneWidget,
      reason: 'the Original panel drew no §15.1 view. If the sentence below it '
          'says no file is stored, the object is missing from the Storage '
          'emulator — run tool/seed_recipe_and_sources.py; that is a real '
          'state, and not this one',
    );
    // A PDF is the branch that CANNOT be drawn here, and §15.1 rule 1 is that
    // what the client cannot draw is said rather than omitted: a stage that
    // renders nothing reads as a broken viewer.
    expect(find.textContaining('can’t be displayed here'), findsOneWidget);
    // The toolbar is what the sentence points AT, so its absence would make
    // the sentence a dead end.
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsWidgets);
  });

  testWidgets('sources composes from the kit, in the contract order', (
    tester,
  ) async {
    // Sources is the rail's *Library* (`/sources`) and screen 3/11 of the kit
    // rebuild. Same reasoning as the library test: these assertions are about
    // PARTS BEING PRESENT in the roles the kit gives them, which is the one
    // layer no other gate here looks at.
    final router = await pumpApp(tester);
    router.go('/sources');
    // Fixed pumps, not `pumpAndSettle`: this screen holds live subscriptions
    // (documents, cloud jobs, folders) and a settle waits for a quiet frame
    // that a screen with a spinner in it never has.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitConnectCard).evaluate().isNotEmpty) break;
    }
    // The route transition keeps the previous screen mounted for its duration,
    // so a screen that has appeared is not yet a screen that is alone.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The chapter opening, with its folio and its two-bar rule.
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.byType(ChapterRule), findsWidgets);
    expect(
      find.textContaining(RegExp('VOLUMES?')),
      findsWidgets,
      reason: 'the folio carries the screen count',
    );

    // The drop zone OPENS the screen (contract 4.5.3) — it is the first thing
    // under the header, not the last thing on the page. A reader with an empty
    // library must not have to scroll past a library they do not have.
    expect(find.byType(KitDropZone), findsOneWidget);
    final headerY = tester.getTopLeft(find.byType(ChapterOpening)).dy;
    final dropY = tester.getTopLeft(find.byType(KitDropZone)).dy;
    expect(dropY, greaterThan(headerY));

    // The three sections, in order.
    expect(find.textContaining('ADD TO YOUR LIBRARY'), findsOneWidget);
    expect(find.textContaining('CONNECT A SERVICE'), findsOneWidget);

    // Connect cards: the grid is the §5.1 variant, one per canonical provider.
    expect(find.byType(KitConnectCard), findsNWidgets(4));

    // Scroll to the browse section — the control bar and the row list are
    // below the fold on a phone, which is exactly why the drop zone is not.
    final scrollable = find.byType(Scrollable);
    for (var i = 0; i < 8; i++) {
      if (find.byType(KitControlBar).evaluate().isNotEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(
      find.byType(KitControlBar),
      findsOneWidget,
      reason: 'browse opens with the control bar (§6.6)',
    );
    expect(find.byType(KitFilterChip), findsWidgets);
    expect(
      find.byType(KitSegmented),
      findsWidgets,
      reason: 'the sort control is a segmented control (§6.8), not a menu',
    );

    // Either there are volumes, and they are §4.1 rows — never a table — or
    // the library is empty and the offer leads.
    final rows = find.byType(KitSourceRow).evaluate().isNotEmpty;
    if (rows) {
      expect(find.byType(KitRowList), findsWidgets);
      expect(
        find.byType(DataTable),
        findsNothing,
        reason: 'the volume list is the row list; there is no table pattern',
      );
    } else {
      expect(find.byType(KitEmptyState), findsOneWidget);
    }

    // ── F-13 ────────────────────────────────────────────────────────────
    // The drop zone says what it will take, from the ONE declaration. It
    // advertised `EPUB` — a kind nothing in the backend can write — and
    // promised a flat 100 MB, which is wrong for video by a factor of twenty.
    expect(find.text('EPUB'), findsNothing,
        reason: 'epub is advertised and unreachable — no document can have it');
    expect(find.textContaining('2 GB for video'), findsOneWidget,
        reason: 'the cap is per type (4.13.0); a flat 100 MB is a limit the '
            'server does not have');

    // Every processing row offers the SOURCE — failed, queued or uploading —
    // because `error_message` is a claim about a source and nothing else on
    // this screen shows the source. The seed carries a failed docx (`file`)
    // and a queued article (`link`), so both §6.4.2 branches are on screen.
    final procRows = find.byType(KitSourceRow).evaluate().length;
    debugPrint('DEVICE-RUN sources: $procRows §4.1 row(s), '
        'viewFile=${find.text('View file').evaluate().length}, '
        'openLink=${find.text('Open the link').evaluate().length}, '
        'retry=${find.text('Retry').evaluate().length}, '
        'indexAnyway=${find.text('Index it anyway').evaluate().length}');
    expect(
      find.text('View file').evaluate().isNotEmpty ||
          find.text('Open the link').evaluate().isNotEmpty ||
          find.text('View images').evaluate().isNotEmpty,
      isTrue,
      reason: 'no processing row offers its source (§6.4.2) — this is the '
          'affordance the tray exists to carry',
    );

    // **Retry is never on a skipped row** and the two branches are disjoint:
    // `fn_retry_document` refuses `skipped` by name, so a Retry there is a
    // control that could not once have worked.
    expect(
      find.text('Retry').evaluate().length +
          find.text('Index it anyway').evaluate().length,
      lessThanOrEqualTo(procRows),
      reason: 'one primary per row, never two',
    );
  });

  testWidgets('activity composes from the kit and is the MERGED feed', (
    tester,
  ) async {
    // Activity is screen 4/11 of the kit rebuild. Two things are under test and
    // only one of them is composition: this screen previously rendered the
    // DOCUMENTS half of the merge as a card grid, so an event with no document
    // behind it — a letter sent, a service connected, an organization move —
    // could not appear on the activity screen at all, while `subscribeActivity`
    // merged it correctly the whole time and every gate stayed green.
    //
    // First-run is NOT this test's subject, and it is a device-local flag: a
    // simulator that still carries `nl-onboarded: false` from an interrupted
    // run puts the wizard in front of the whole authenticated surface, and
    // every assertion below then fails describing a shell that is simply not
    // on screen. The wizard test sets the same flag the other way for the same
    // reason — its subject IS first-run.
    await LocalFlags.setOnboarded(true);
    final router = await pumpApp(tester);

    // ---- The rail, before the feed is opened (2.5.0, §Toasts and unread) ----
    //
    // On a phone the drawer IS the navigation, and it used to be a SECOND one:
    // its own labels, its own routes, no library card, no identity footer — and
    // it would have had no badge either, on the one viewport where the badge is
    // the only thing that says the feed has moved. It renders `RailContent`
    // now, so this asserts the rail through the drawer deliberately.
    // The Scaffold's own drawer button. By its ICON, not its tooltip: the
    // tooltip is a localization and this suite would then be asserting
    // MaterialLocalizations rather than the shell.
    // Wait for the SHELL, not a fixed number of frames. `OnboardingGate` wraps
    // the whole authenticated surface and decides on the first documents
    // snapshot, so for the first moments of a run there is no `AppLayout` in
    // the tree at all — no Scaffold, no app bar, no drawer button. A fixed
    // pump here read as "the compact shell has no navigation".
    for (var i = 0; i < 60; i++) {
      if (find.byIcon(Icons.menu).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byIcon(Icons.menu), findsOneWidget,
        reason: 'no drawer button — the compact shell has no navigation at all');
    await tester.tap(find.byIcon(Icons.menu));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(KitChromeRail), findsOneWidget,
        reason: 'the drawer is not the kit rail — the second nav is back');
    expect(find.byType(KitRailCard), findsOneWidget,
        reason: '§1.2s library card is missing from the compact rail');
    expect(find.byType(KitRailFooter), findsOneWidget,
        reason: '§1.2 requires a pinned identity footer');
    expect(find.text('Daily Digest'), findsNothing,
        reason: 'a nav vocabulary that is in no spec and no reference');

    // The badge agrees with the RULE over the live feed and the live mark —
    // asserted as agreement rather than as a fixed number, because the mark is
    // client-local and a simulator carries the previous run's. Both branches
    // are real: an untouched device shows the seed's events as unread, a
    // second run shows none, and the badge must be right either way.
    final ctx = tester.element(find.byType(KitChromeRail));
    final activityState = Provider.of<ActivityNotifier>(ctx, listen: false);
    // The rail opens the feed subscription itself; give it its first snapshot
    // before asking what it counts, or the agreement below is 0 == 0.
    for (var i = 0; i < 40; i++) {
      if (activityState.items.isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    final expected = activityState.unreadSince(LocalFlags.activityLastSeen.value);
    debugPrint('DEVICE-RUN activity: unread=$expected '
        'lastSeen=${LocalFlags.activityLastSeen.value} '
        'newestEvent=${activityState.newestEventAt}');
    if (expected > 0) {
      expect(find.text(kitBadgeLabel(expected)), findsWidgets,
          reason: 'the rail does not show the unread count it computes');
    }

    Navigator.of(ctx).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    router.go('/activity');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitTimeline).evaluate().isNotEmpty ||
          find.byType(KitEmptyState).evaluate().isNotEmpty) {
        break;
      }
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The chapter opening — title and standfirst, and NO folio: this screen
    // counts nothing, and a folio here would be a figure with no signal.
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);

    final seeded = find.byType(KitTimeline).evaluate().isNotEmpty;
    if (!seeded) {
      // The empty feed is an offer, not an apology (§7).
      expect(find.byType(KitEmptyState), findsOneWidget);
      expect(find.byType(KitSuggestion), findsWidgets);
      return;
    }

    // The control bar (§6.6) carries one chip per family, and the empty ones
    // are DISABLED, not dropped — the set of chips is a vocabulary.
    expect(find.byType(KitControlBar), findsOneWidget);
    // SIX: `All · Sources · Processing · Letters · Study · In the library`
    // (screens/activity.md §Filters), plus `Other` only when a row falls into
    // it. This asserted five — the set before Study had events (4.25.0) — and
    // the number went unchallenged because the count that would have failed it
    // needs a SEEDED feed, and an empty one returns from this test earlier.
    expect(find.byType(KitFilterChip), findsNWidgets(6));

    // Date buckets are section headers (§3); the eyebrow renders uppercased.
    expect(
      find.textContaining(RegExp('TODAY|YESTERDAY|THIS WEEK|EARLIER')),
      findsWidgets,
      reason: 'the feed is bucketed by day, each bucket opened by an eyebrow',
    );

    // The timeline, not a grid of cards. The spine and the 32px nodes are what
    // make it a record rather than a dashboard.
    expect(find.byType(KitTimelineRow), findsWidgets);
    expect(
      find.byType(GridView),
      findsNothing,
      reason: 'the feed is the §4.2 timeline; there is no card-grid pattern',
    );

    // Filtering narrows the feed rather than reordering it: pick a family chip
    // that is enabled and check the row count does not grow.
    final before = find.byType(KitTimelineRow).evaluate().length;
    final chips = find.byType(KitFilterChip);
    for (var i = 1; i < chips.evaluate().length; i++) {
      final chip = tester.widget<KitFilterChip>(chips.at(i));
      if (chip.onPressed == null) continue;
      await tester.tap(chips.at(i));
      // Bounded pumps, never `pumpAndSettle`: a **live** node carries a pulsing
      // ring (§4.2) that loops forever, so a settle here waits for a frame that
      // never comes. It hangs rather than fails, and only when the feed happens
      // to hold a processing document — which is why this test read as green.
      for (var j = 0; j < 8; j++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        find.byType(KitTimelineRow).evaluate().length,
        lessThanOrEqualTo(before),
      );
      break;
    }

    // ---- and the badge is CLEARED by having looked at the feed ----
    //
    // The mark is what the reader saw, not the clock: the newest event on the
    // screen. Written while the feed is open, so the count the rail shows next
    // is what arrived after this moment — not after some instant that may be
    // ahead of the snapshot.
    final ctx2 = tester.element(find.byType(KitTimeline));
    final act = Provider.of<ActivityNotifier>(ctx2, listen: false);
    if (act.newestEventAt > 0) {
      expect(LocalFlags.activityLastSeen.value, act.newestEventAt,
          reason: 'looking at the feed did not mark it seen');
      expect(act.unreadSince(LocalFlags.activityLastSeen.value), 0);
    }

    // The Scaffold's own drawer button. By its ICON, not its tooltip: the
    // tooltip is a localization and this suite would then be asserting
    // MaterialLocalizations rather than the shell.
    expect(find.byIcon(Icons.menu), findsOneWidget,
        reason: 'no drawer button — the compact shell has no navigation at all');
    await tester.tap(find.byIcon(Icons.menu));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final rail = find.byType(KitChromeRail);
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('9+')),
      findsNothing,
      reason: 'the badge survived the screen that clears it',
    );
    Navigator.of(tester.element(rail)).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });

  testWidgets('search composes from the kit and opens a reading pane', (
    tester,
  ) async {
    // Search is screen 5/11. Three specified parts did not exist here before
    // the rebuild — the big field, the control bar, and the reading pane — and
    // the pane is the whole reason this screen has a two-pane frame. None of
    // that is visible to Tier-1, which asserts request construction.
    final router = await pumpApp(tester);
    router.go('/search');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Idle: the bespoke header, and an offer rather than a blank page (§7).
    expect(find.byType(SearchBigField), findsOneWidget);
    expect(
      find.byType(ChapterOpening),
      findsNothing,
      reason: 'search has a bespoke header; the field IS the title (§2)',
    );
    expect(find.byType(KitEmptyState), findsOneWidget);
    expect(find.byType(KitSuggestion), findsWidgets);

    // Submit a query the seed can answer.
    await tester.enterText(find.byType(TextField).first, 'pasta');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // Wait generously: this is an embedding call plus a vector query, and a
    // cold first request runs to several seconds. A short wait does not fail —
    // it asserts the loading state and takes the no-results branch, which is
    // green for the wrong reason.
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(SearchResultCard).evaluate().isNotEmpty ||
          find.byType(KitEmptyState).evaluate().isNotEmpty) {
        break;
      }
    }
    // **Never `pumpAndSettle` on this screen.** Both loading states here are a
    // `CircularProgressIndicator`, which animates forever, so a settle waits
    // for a frame that never comes and the run hangs rather than failing.
    // Bounded pumps throughout.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The control bar appears with the query, carrying the type vocabulary —
    // all SIX kinds (§6.4.1). A chip set that is short of a kind is a bucket
    // nothing can reach, and it looks exactly like a complete vocabulary.
    expect(find.byType(KitControlBar), findsOneWidget);
    expect(find.byType(KitFilterChip), findsNWidgets(6));
    // **No counts** (ADR-065 §4): a count over one page of results is a
    // statement about that page, and it disabled chips that had matches. The
    // chips filter SERVER-side now, so none of them is ever disabled either.
    expect(
      find.descendant(
        of: find.byType(KitFilterChip),
        matching: find.textContaining(RegExp(r'^\d+$')),
      ),
      findsNothing,
      reason: 'search chips carry no count',
    );

    // Say which branch this run took. Without it a green run is ambiguous —
    // the failure branch below returns early and passes too, which is exactly
    // what happened while the shim carried a dummy embedding key: the cards,
    // the split pane and the context read had never rendered and the test was
    // green anyway.
    final searchState = Provider.of<SearchNotifier>(
      tester.element(find.byType(SearchBigField)),
      listen: false,
    );
    debugPrint(
      'DEVICE-RUN search: '
      '${find.byType(SearchResultCard).evaluate().length} result cards, '
      'notifier=${searchState.results.length} results, '
      'error=${searchState.error}',
    );

    if (find.byType(SearchResultCard).evaluate().isEmpty) {
      // Either nothing matched — which is the offer pattern (§7), not a bare
      // sentence — or the call failed and the screen says so. Under the `fn_*`
      // shim the failure is the expected one: the shim carries a dummy OpenAI
      // key, so the query cannot be embedded. What is NOT allowed is a blank
      // body: a search that answers with nothing at all.
      expect(
        find.byType(KitEmptyState).evaluate().isNotEmpty ||
            find.byType(KitCard).evaluate().isNotEmpty,
        isTrue,
        reason: 'no results still renders a state, never an empty page',
      );
      return;
    }

    // The second pane renders beside (or under) the results, and it opens on
    // the top result rather than waiting to be clicked.
    expect(find.byType(SearchReadingPane), findsOneWidget);
    expect(
      find.textContaining('similarity'),
      findsWidgets,
      reason: 'the pane names the measured score of what it is showing',
    );

    // §16 — the score meter is a CONTROL with an explainer behind it (4.44.0,
    // ADR-082), and the figures in it are measured. It carried `cursor: help`
    // on the reference for fifteen months with no popover behind it; this is
    // the assertion that there is one.
    await tester.tap(
      find.descendant(
        of: find.byType(SearchResultCard).first,
        matching: find.byType(KitAnchoredPopover),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('RELEVANCE'), findsOneWidget,
        reason: 'the score element opens the §16 explainer');
    expect(find.text('Similarity'), findsOneWidget);
    expect(find.text('Source priority'), findsOneWidget,
        reason: 'both components come off a live response — a missing row here '
            'means the client is on the derive path ADR-082 forbids');

    // Selecting a different result moves the pane to it.
    final cards = find.byType(SearchResultCard);
    if (cards.evaluate().length > 1) {
      await tester.tap(cards.at(1));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final selected = tester
          .widgetList<SearchResultCard>(cards)
          .where((c) => c.selected)
          .length;
      expect(selected, 1, reason: 'exactly one result is open at a time');
    }
  });

  // ── Ask (4.53.0/4.54.0, ADR-090) ───────────────────────────────────────────
  testWidgets('ask composes from the kit', (tester) async {
    // Ask is screen 7/11. Nothing here was visible to Tier-1: the rail is
    // composition, the route rename is a table, and "restoring a conversation
    // issues no request" is the ABSENCE of one.
    final router = await pumpApp(tester);
    router.go('/ask');
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The bespoke header (§2), its eyebrow, and the dock (§10).
    expect(find.byType(ScreenHeader), findsOneWidget);
    expect(
      find.byType(ChapterOpening),
      findsNothing,
      reason: 'ask has a bespoke header, not a chapter opening (§2)',
    );
    expect(find.text('GROUNDED IN YOUR LIBRARY'), findsOneWidget);
    expect(find.byType(KitComposerDock), findsOneWidget);

    // The rail is §9's PHONE form: an overlay, closed until asked for. A rail
    // drawn as a permanent column on a phone is a different pattern.
    expect(find.byType(KitInspectorRail), findsNothing);
    await tester.tap(find.text('History'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(KitInspectorRail), findsOneWidget);
    expect(
      find.text('CONVERSATIONS'),
      findsOneWidget,
      reason: 'the mono caps title is a required part of §9',
    );
    expect(
      find.text('New conversation'),
      findsOneWidget,
      reason: 'the dashed new-conversation control is the rail\'s own offer',
    );
    // Close it the way §9's phone form requires — a visible control, not only
    // the backdrop.
    await tester.tap(find.byIcon(Icons.close));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(KitInspectorRail), findsNothing);

    // Empty is an OFFER (§7), never a bare sentence.
    expect(find.byType(KitEmptyState), findsOneWidget);
    expect(find.byType(KitSuggestion), findsWidgets);

    // A turn. Generous wait: this is an embedding call plus a vector query,
    // and a cold first request runs to several seconds — a short wait takes
    // the failure branch and is green for the wrong reason.
    await tester.enterText(find.byType(TextField).last, 'pasta cooking');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // The SEND CONTROL, not a text-input action: §10's field takes
    // `TextInputAction.newline` because a prompt is written, not typed into a
    // form field — so `receiveAction(done)` inserts a line and sends nothing,
    // and the test reads as "the app did not answer".
    await tester.tap(find.bySemanticsLabel('Send'));
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Your library').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final ask = Provider.of<ChatNotifier>(
      tester.element(find.byType(KitComposerDock)),
      listen: false,
    );
    // Say which branch this run took. Without it a green run is ambiguous —
    // the rejection branch renders a state too, which is the defect the search
    // test above was green through for a whole release.
    debugPrint(
      'DEVICE-RUN ask: ${ask.messages.length} stored message(s), '
      'thread=${ask.activeId}, error=${ask.sentError}',
    );

    if (ask.sentError != null) {
      // The shim's dummy OpenAI key is the expected failure here. What is NOT
      // allowed is silence — and, since 4.61.0 (ADR-097), what is not allowed
      // either is the QUESTION disappearing: the turn stays on screen with the
      // server's sentence and a retry, and it is never put back in the
      // composer as though it had never been asked.
      expect(find.byType(KitFailureInline), findsWidgets,
          reason: 'a refused turn says so (§14.2) — never an empty answer');
      expect(
        find.text('pasta cooking'),
        findsOneWidget,
        reason: 'the sent turn STAYS on screen — it is the only record of '
            'what the reader did (ADR-097)',
      );
      expect(find.text('Try again'), findsOneWidget,
          reason: 'the retry re-sends THAT turn');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller?.text,
        '',
        reason: 'a refused question is never returned to the composer',
      );
      return;
    }

    // The turn was RECORDED, which is the whole of ADR-090: both messages came
    // back from the subscription, not from local state.
    expect(ask.messages.length, greaterThanOrEqualTo(2));
    expect(ask.activeId, isNotNull);
    expect(find.text('You'), findsWidgets);
    expect(find.text('Your library'), findsWidgets);

    // The thread is now in the rail, with the title and the preview the
    // BACKEND wrote — a second line this client cannot derive.
    await tester.tap(find.text('History'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(KitRailEntry), findsWidgets);
    expect(find.text('TODAY'), findsOneWidget,
        reason: 'entries are grouped under mono caps labels (§9)');
    final entry = tester.widgetList<KitRailEntry>(find.byType(KitRailEntry));
    expect(entry.first.active, isTrue,
        reason: 'the open conversation is the marked one');
    expect(entry.first.preview, isNotEmpty,
        reason: 'ask_threads.preview (4.54.0) backs the entry\'s second line');

    // Reopening a stored conversation issues NO request and must not draw the
    // searching state. The absence of a request is not observable, so this
    // asserts the thing that would be visible if one were made.
    await tester.tap(find.byType(KitRailEntry).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Searching…'), findsNothing,
        reason: 'restoring a thread is not thinking (screens/ask.md §States)');
    expect(find.text('Your library'), findsWidgets);

    // ── §9.1 entry actions (4.55.0, ADR-091) ────────────────────────────────
    // The two methods `fn_ask_threads` has always had and no client called.
    // A rendered cluster is not a working one, so this drives both, and it
    // reads the STORED title back out of the subscription rather than the one
    // the field was left holding — a rename that only painted passes every
    // other check on this screen.
    await tester.tap(find.text('History'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final threadId = ask.activeId!;
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    debugPrint('DEVICE-RUN ask §9.1 edit tapped: renaming=${ask.renamingId}, '
        'fields=${find.byType(TextField).evaluate().length}, '
        'rail=${find.byType(KitInspectorRail).evaluate().length}');
    expect(find.byType(TextField), findsWidgets,
        reason: '§9.1 renames IN PLACE — the title becomes a field');
    // The field INSIDE the rail, not `.first` of every TextField on the screen
    // — the composer is one too, and an ordering that happens to hold is not
    // an assertion about the entry.
    await tester.enterText(
        find.descendant(
            of: find.byType(KitInspectorRail), matching: find.byType(TextField)),
        'Pasta, from the top');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (ask.renamingId == null) break;
    }
    debugPrint('DEVICE-RUN ask §9.1 rename: '
        'error=${ask.entryError(threadId)}, '
        'stored=${ask.threads.where((t) => t.id == threadId).firstOrNull?.title}');
    expect(ask.entryError(threadId), isNull,
        reason: 'the rename was refused — §14.2 would be in the entry');
    expect(
      ask.threads.where((t) => t.id == threadId).firstOrNull?.title,
      'Pasta, from the top',
      reason: 'write before move: the STORED title is what moved, not a repaint',
    );

    // Delete confirms first, and the confirmation names what is lost AND what
    // is not.
    final before = ask.threads.length;
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.textContaining('Nothing leaves your library'), findsOneWidget,
        reason: 'a destructive action names what is NOT lost too (§9.1)');
    await tester.tap(find.text('Delete conversation'));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (ask.threads.length < before) break;
    }
    debugPrint('DEVICE-RUN ask §9.1 delete: ${ask.threads.length} thread(s) '
        'was $before, error=${ask.entryError(threadId)}');
    expect(ask.entryError(threadId), isNull,
        reason: 'the delete was refused — §14.2 would be in the entry');
    expect(ask.threads.length, before - 1);
    expect(ask.activeId, isNull,
        reason: 'deleting the OPEN conversation returns to new-conversation');
  });

  // ── ADR-097 / ADR-101 ──────────────────────────────────────────────────────
  // The two rules about a turn that did NOT come back, on the real renderer.
  // Neither is visible to Tier-1: one is what stays on SCREEN after a request
  // settles, the other is which ROUTE the screen is at afterwards.
  testWidgets('a refused turn stays on screen, with a retry', (tester) async {
    final router = await pumpApp(tester);
    // A shelf that does not exist. The queue wrote this as "with the network
    // off"; the endpoint's own 404 is better, because it is deterministic AND
    // it carries the SERVER's sentence, which is the half of §14.2 that a
    // connection failure cannot exercise (`api/ask.md` — a tagId that is not
    // the caller's is a 404).
    router.go('/ask/shelf/no-such-shelf');
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // The scope is NAMED, all through the screen — that is ADR-098's rule and
    // it holds for a shelf whose title is not known yet: the turn is scoped
    // either way, and dropping the scope from the copy would be the screen
    // claiming it searched the library.
    expect(find.text('GROUNDED IN ONE SHELF'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).last, 'Which of these recipes can use steak?');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.bySemanticsLabel('Send'));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Try again').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final ask = Provider.of<ChatNotifier>(
      tester.element(find.byType(KitComposerDock)),
      listen: false,
    );
    debugPrint('DEVICE-RUN ask refusal: err=${ask.sentError}, '
        'sent=${ask.sentQuestion}, thread=${ask.activeId}');
    expect(ask.sentError, isNotNull,
        reason: 'the turn was not refused — every assertion below would be '
            'green about the wrong state');
    // The question STAYS, in the transcript, with the server's own words and a
    // retry beside it — and NOT in the composer, which is where a client that
    // treats a refused question as a draft puts it back (ADR-097).
    expect(find.text('Which of these recipes can use steak?'), findsOneWidget);
    expect(find.byType(KitFailureInline), findsWidgets);
    expect(find.text('Shelf not found.'), findsOneWidget,
        reason: "§14.2 quotes the server verbatim — never our own copy");
    expect(find.text('Try again'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      '',
      reason: 'a refused question is never returned to the composer',
    );
    // And the screen stayed where it was: a refused turn records nothing, so
    // there is no thread to move to (ADR-101/ADR-022).
    expect(ask.activeId, isNull);
  });

  // ── INV-22 (4.18.0, ADR-054) ───────────────────────────────────────────────
  // The Tier-1 gate (`test/contract/support_footer_test.dart`) proves the route
  // TABLE nests every screen under the footer's shell, and that the footer
  // renders when the shell is mounted alone. What it cannot do is mount a real
  // screen — no Firebase in a plain widget test. This closes that: the real
  // app, on a real renderer, at routes composed three different ways.
  testWidgets('the support footer is under EVERY screen, reader included', (
    tester,
  ) async {
    final router = await pumpApp(tester);

    // '/' and '/settings' sit inside the rail-and-pane shell; '/reader/:docId'
    // deliberately does NOT, and is the route a footer composed in AppLayout
    // would have missed. '/support' is included because a screen does not stop
    // being a screen by being the one the footer opens.
    for (final route in ['/', '/settings', '/activity', '/support']) {
      router.go(route);
      await pumpFor(tester);
      expect(
        find.byType(KitSupportFooter),
        findsOneWidget,
        reason: '$route renders with no way to reach a human (INV-22)',
      );
      expect(
        find.text('Chat with support…'),
        findsOneWidget,
        reason: 'the normative copy on $route',
      );
    }

    // The same fixture the reader test uses; any real document would do, since
    // what is under test here is the shell, not the reader.
    router.go('/reader/device-run-long-doc');
    await pumpFor(tester, total: const Duration(seconds: 6));
    expect(
      find.byType(KitSupportFooter),
      findsOneWidget,
      reason:
          'the reader is outside AppLayout — this is the route the '
          'obvious implementation of INV-22 would have dropped',
    );
  });

  testWidgets('the footer opens support, and a send is write-before-move', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/activity');
    await pumpFor(tester);

    // A REAL tap on the control, not a router.go: what the invariant promises
    // is a way OUT of the screen the user is on, and only the tap proves the
    // control is hittable where it is laid out.
    await tester.tap(find.text('Chat with support…'));
    await pumpFor(tester);
    expect(
      find.text('SUPPORT'),
      findsOneWidget,
      reason: 'the eyebrow renders uppercased',
    );

    // Composition (QUEUE F-03, `screens/support.md` §Composition): the
    // required parts, in the kit's roles, in the spec's order — the one layer
    // no other gate looks at. §2.2 header · §7 offer (the seed holds no
    // thread, or the transcript) · §10 dock pinned below both · §13 footer
    // from the shell, still there.
    expect(find.byType(SubScreenHeader), findsOneWidget);
    expect(find.byType(ChapterOpening), findsNothing,
        reason: 'a sub-screen does not open a chapter');
    expect(find.byType(KitComposerDock), findsOneWidget);
    expect(find.byType(KitSupportFooter), findsOneWidget,
        reason: 'INV-22: the footer is the shell\'s and survives this screen');
    final headerY = tester.getTopLeft(find.byType(SubScreenHeader)).dy;
    final dockY = tester.getTopLeft(find.byType(KitComposerDock)).dy;
    expect(dockY, greaterThan(headerY));
    final hasThread = find.byType(KitMessageCard).evaluate().isNotEmpty;
    if (!hasThread) {
      expect(find.byType(KitEmptyState), findsOneWidget,
          reason: 'no thread is the §7 offer, not a failure');
      expect(find.byType(KitButton), findsNothing,
          reason: 'the composer IS the action; the offer carries no CTA');
    }

    // The route the user came from travels with the message — the shell
    // supplied it, which is the practical half of why the footer is the
    // shell's. It is in the URL the footer navigated to.
    expect(
      router.routerDelegate.currentConfiguration.uri.query,
      contains('activity'),
    );

    // A marker unique to this run. The probe STAYS in the thread — nothing a
    // client may do deletes it (INV-04) — so a fixed string is findsOneWidget
    // on the first run against a seed import and findsNWidgets(2) on the
    // second, a red that describes the run before it rather than the code.
    final probe =
        'Device-run probe ${DateTime.now().millisecondsSinceEpoch}: ignore.';
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, probe);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await tester.tap(find.bySemanticsLabel('Send'));
    // The send control spins while the request is in flight — another widget a
    // settle would wait on forever if the call never resolved.
    await pumpFor(tester, total: const Duration(seconds: 8));

    // Write BEFORE you move (ADR-022): the box clears only once the endpoint
    // has accepted. A composer that clears optimistically loses the user's bug
    // report on the one path where they most need it kept — and the failure is
    // invisible, because the screen looks identical either way.
    expect(
      find.text(probe),
      findsOneWidget,
      reason: 'the sent message is in the transcript',
    );
    expect(
      tester.widget<TextField>(composer).controller?.text,
      '',
      reason: 'the composer cleared only after the 201',
    );
    // The sent message is a §5.2 reduced-emphasis card on the trailing edge,
    // and the thread now awaits an answer (derived from last_sender).
    expect(find.byType(KitMessageCard), findsWidgets);
    expect(find.byType(KitEmptyState), findsNothing);
    expect(find.byType(KitThreadNote), findsOneWidget,
        reason: 'last_sender == user ⇒ the awaiting line, exactly once');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('notifications composes from the kit', (tester) async {
    // Screen 5/11 (QUEUE F-02). The assertions are about the REQUIRED PARTS
    // being present, in the roles the kit gives them and in the order the
    // spec lists them (`screens/notifications.md` §Composition) — the one
    // layer no other gate looks at.
    final router = await pumpApp(tester);
    router.go('/settings/notifications');
    // Bounded pumps: the channel list is a live subscription.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitSettingRow).evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // §2.2 — back control naming the parent · eyebrow · sans standfirst.
    expect(find.byType(SubScreenHeader), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(
      find.byType(ChapterOpening),
      findsNothing,
      reason: 'a sub-screen does not open a chapter',
    );

    // The channel list: one raised row list of setting rows — the seed holds
    // three channels, one per type, and the push one is DISABLED and says so.
    expect(find.byType(KitRowList), findsOneWidget);
    expect(find.byType(KitSettingRow), findsNWidgets(3));
    expect(find.textContaining('(paused)'), findsOneWidget);
    expect(find.byType(KitSwitch), findsNWidgets(3));
    expect(
      find.byType(KitSegmentedMulti),
      findsWidgets,
      reason: 'each row carries its level picker as a §6.8 track',
    );
    expect(
      find.byType(FilterChip),
      findsNothing,
      reason: 'levels are the segmented control, not Material chips',
    );
    final headerY = tester.getTopLeft(find.byType(SubScreenHeader)).dy;
    final listY = tester.getTopLeft(find.byType(KitRowList)).dy;
    expect(listY, greaterThan(headerY));

    // Scroll to the form — below the fold on a phone.
    final scrollable = find.byType(Scrollable);
    for (var i = 0; i < 8; i++) {
      if (find.byType(KitButton).evaluate().isNotEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('ADD A CHANNEL'), findsOneWidget);
    expect(find.byType(KitFieldGroup), findsWidgets);
    expect(
      find.byType(KitSegmented),
      findsOneWidget,
      reason: 'the type choice is a §6.8 segmented control',
    );
    expect(find.text('Add channel'), findsOneWidget);
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'a rejection is a §14.2 line beside the control, never a toast',
    );
  });

  testWidgets('settings shows the Summaries section', (tester) async {
    final router = await pumpApp(tester);
    router.go('/settings');
    await pumpFor(tester, total: const Duration(seconds: 3));

    // Scroll to it — 4.3.1 was a settings page that could not scroll to its own
    // new section, and the same section is the one being checked here.
    final scrollable = find.byType(Scrollable);
    for (var i = 0; i < 6; i++) {
      if (find.text('Summaries').evaluate().isNotEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -400));
      await pumpFor(tester, total: const Duration(seconds: 1));
    }
    expect(find.text('SUMMARIES'), findsOneWidget,
        reason: 'the section eyebrow renders uppercased');
    expect(find.text('Save style'), findsOneWidget);

    // Composition (QUEUE F-04, `screens/settings.md` §Composition): the
    // required parts, in the kit's roles, in the spec's order. §2.1 chapter
    // opening with the Account folio · §3 section headers · raised row lists
    // of setting rows · §6.8 segmented controls in the control strips · no
    // Material card, tile or switch anywhere on the screen.
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.textContaining('ACCOUNT ·'), findsOneWidget,
        reason: 'the folio carries the account');
    expect(find.byType(SectionHeader), findsWidgets);
    expect(find.byType(KitRowList), findsWidgets);
    expect(find.byType(KitSettingRow), findsWidgets);
    expect(find.byType(KitSegmented), findsWidgets,
        reason: 'summary style / length / tone are §6.8 tracks');
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing,
        reason: 'the style positions are a segmented control, not chips');
    expect(find.byType(SnackBar), findsNothing);

    // §Scripture (F-12, ADR-027 §7) — the control that writes the client-local
    // `nl-scripture` flag. Without it the flag has a reader and no writer, and
    // the whole citation branch on Search is code nothing can reach: the
    // dark-feature shape, in one screen. It sits below the fold, so the pair's
    // frame cannot show it and this is what says it is there.
    await tester.scrollUntilVisible(find.text('SCRIPTURE'), 300,
        scrollable: find.byType(Scrollable).first);
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.text('SCRIPTURE'), findsOneWidget);
    expect(find.text('Verse search'), findsOneWidget);
    expect(find.byType(KitSwitch), findsWidgets,
        reason: 'the flag has a control, not just a reader');
    // Off by default, as the reference has it — a citation is only a different
    // question for someone who reads scripture.
    expect(LocalFlags.scripture.value, isFalse);
  });

  testWidgets('letters composes from the kit and opens a letter', (
    tester,
  ) async {
    // Screen 7/11 (QUEUE F-05). Seed the letters FIRST — the canonical seed's
    // two records predate 2.0.0 and carry no `html_body`, so without this
    // there is no letter to open and nothing here is exercised:
    //   FIRESTORE_EMULATOR_HOST=localhost:8080 \
    //     ../NoteLetter-Firebase-Functions/functions/venv/bin/python \
    //     tool/seed_letters.py
    final router = await pumpApp(tester);
    router.go('/letters');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitSourceRow).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));

    // §Composition — the bespoke header (§2 names letters, ask and search as
    // the three that do not open a chapter), then §3 section headers over the
    // cards and the archive.
    expect(find.byType(ScreenHeader), findsOneWidget);
    expect(find.byType(ChapterOpening), findsNothing,
        reason: 'letters has a bespoke header, not a chapter opening');
    expect(find.text('Letters'), findsWidgets);
    expect(find.text('LATEST LETTER'), findsOneWidget);
    expect(find.byType(SectionHeader), findsWidgets);
    expect(find.byType(KitCard), findsWidgets);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);

    // 2.29.0 rule 3 — the schedule is STATED from what was read. The seed's
    // settings say 08:00 America/Chicago, so that is what the card says; a
    // client that had not read them would have to say nothing.
    expect(find.textContaining('ARRIVES EVERY DAY AT 08:00'), findsOneWidget);
    expect(find.byType(KitSwitch), findsWidgets);

    // The archive rows, and the two axes on them (INV-23). `delivered` is the
    // ONLY state that may read as "Delivered"; the deferred letter says it is
    // still going, and the `empty` row is informational and NOT openable.
    // The §6.3 pill sets its label in mono caps, so these are the rendered
    // strings, not the table's.
    expect(find.text('DELIVERED'), findsOneWidget);
    expect(find.text('STILL SENDING…'), findsOneWidget);
    expect(find.text('NOTHING NEW'), findsOneWidget);
    expect(find.text('FAILED'), findsNothing,
        reason: 'an empty result is not a failure (2.2.0, ADR-011)');

    // The readings letter — a SECOND letter beside the first, never a mode of
    // it, and with no send action of its own: its builder is an OIDC-only
    // worker that answers a client with 403 (the 1.5.1 defect).
    expect(find.text('THE READINGS LETTER'), findsOneWidget);
    expect(find.textContaining('Thursday of week 23'), findsWidgets);
    expect(find.text('Send now'), findsOneWidget,
        reason: 'exactly one Send now on this screen, and it is the daily '
            'letter\'s');

    // Open the letter. `warnIfMissed` stays on: a tap that lands on nothing
    // is silent, and everything below would then be asserting the LIST.
    await tester.tap(find.text('Preview').first);
    await pumpFor(tester, total: const Duration(seconds: 3));

    // The letter is hosted BARE (4.50.0, ADR-087) — the app draws no frame
    // around a body that brought its own, so the §11 sheet is ABSENT here and
    // the letter is the web view holding the object that was sent.
    expect(find.text('All letters'), findsOneWidget);
    expect(find.byType(KitLetterPaper), findsOneWidget);
    expect(find.byType(KitLetterSheet), findsNothing,
        reason: 'a letterheaded body is not framed — that would draw the '
            'app\'s masthead above the letter\'s own');

    // …and the way back out of it works.
    await tester.tap(find.text('All letters'));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.text('LATEST LETTER'), findsOneWidget);
  });

  testWidgets('shelves composes from the kit', (tester) async {
    // Screen 9/11 (QUEUE F-08). The seed holds three shelves — Recipes (2
    // volumes), Finance (1) and Stories (1, carrying a LEGACY HEX colour,
    // which is most of production and must still paint).
    final router = await pumpApp(tester);
    // The old route is a redirect, not a 404: `/tags` was this client's route
    // for the whole life of the screen.
    router.go('/tags');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitShelfCard).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));

    // §2.1 — folio, title, standfirst. The count in the folio is the shelves
    // subscription's, the one in the standfirst the documents subscription's.
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.textContaining('LIBRARY · 3 SHELVES'), findsOneWidget);
    expect(find.text('Shelves'), findsOneWidget);

    // §5.1 — one card per shelf, and the dashed slot that makes one.
    expect(find.byType(KitShelfCard), findsNWidgets(3));
    expect(find.byType(KitNewCard), findsOneWidget);
    expect(find.text('Recipes'), findsWidgets);
    // Stories is `auto_created`; provenance is a LABEL and nothing more.
    expect(find.text('AUTO'), findsOneWidget);
    // Nothing Material survived the recompose — this screen was a list of
    // `ListTile`-ish rows with a FAB until F-08.
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // ── the shelf's own page ────────────────────────────────────────────
    await tester.tap(find.text('Recipes').first);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/shelves/seed-tag-recipes');
    expect(find.text('All shelves'), findsOneWidget);
    expect(find.byType(KitStatCluster), findsOneWidget);
    expect(find.text('VOLUMES'), findsOneWidget);
    expect(find.text('PASSAGES'), findsWidgets);
    expect(find.text('SPAN'), findsOneWidget);
    expect(find.byType(KitSourceRow), findsNWidgets(2));

    // 2.20.0 (ADR-025) — the split control is ABSENT below five volumes, not
    // disabled: the endpoint 400s there, and a control that cannot work is
    // worse than no control.
    // The button, not the rail's nav item of the same name.
    await tester.tap(find.widgetWithText(KitButton, 'Settings'));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.byType(KitPanel), findsOneWidget);
    expect(find.text('Split this shelf'), findsNothing);
    expect(find.text('Delete shelf'), findsOneWidget);

    // §6.2 — ten swatches, each announced by its NAME, not its token.
    expect(find.byType(KitSwatch), findsNWidgets(10));
    expect(find.bySemanticsLabel('Deep plum'), findsOneWidget);
    expect(find.bySemanticsLabel('plum-600'), findsNothing);

    // Write before move: the swatch moves only once `fn_update_tag` has
    // answered, and what it then draws is what the SUBSCRIPTION carried back.
    // The web swatch moved first until 2.15.0, so a 400 on every colour change
    // looked like a success for months.
    // The seed shelf is `brick-400`, whose NAME is Vermilion.
    expect(
      tester
          .widgetList<KitSwatch>(find.byType(KitSwatch))
          .any((w) => w.label == 'Vermilion' && w.selected),
      isTrue,
    );
    try {
      await tester.tap(find.bySemanticsLabel('Deep plum'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (tester
            .widgetList<KitSwatch>(find.byType(KitSwatch))
            .any((w) => w.label == 'Deep plum' && w.selected)) {
          break;
        }
      }
      expect(
        tester.widgetList<KitSwatch>(find.byType(KitSwatch)).any(
            (w) => w.label == 'Deep plum' && w.selected),
        isTrue,
        reason: 'the stored colour came back on the tags subscription',
      );
      expect(find.byType(KitFailureInline), findsNothing);
    } finally {
      // Put the seed back, so the next run starts where this one did.
      await Api.instance
          .updateTag('seed-tag-recipes', {'color': 'brick-400'});
    }
  });

  testWidgets('study composes from the kit', (tester) async {
    // Screen 8/11 (QUEUE F-06). The seed holds no study program, so `/study`
    // is the EMPTY state by construction — the same state the web reference
    // frame shows. The program card is reached by CREATING one through the
    // endpoint (INV-04: no client writes `study_programs` directly), and it is
    // deleted again at the end so the next run starts from the same place.
    final router = await pumpApp(tester);
    router.go('/study');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitEmptyState).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));

    // §7 — an offer, not an apology: mark, title, standfirst, the rows, and
    // the action that makes one.
    expect(find.byType(KitEmptyState), findsOneWidget);
    expect(find.text('Go deeper on one subject'), findsOneWidget);
    expect(find.byType(KitNumberedMove), findsNWidgets(3));
    expect(find.text('New program'), findsWidgets);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    // ── a program, made the only way a client may make one ──────────────
    final created = await Api.instance.createStudyProgram({
      'title': 'Device run — braising',
      'documentIds': ['seed-doc-article-complete'],
      'deliveryTime': '07:00',
      // 2.29.0: a client that sends `deliveryTime` sends `timezone` with it.
      'timezone': 'America/Chicago',
      'frequency': 'daily',
    });
    // `{created: true, program: {...}}` — the id is the program's own, not a
    // `programId` at the top level (fixture `study-programs:create`).
    final programId = (created['program'] as Map?)?['id'] as String?;

    // The delete is in a finally that covers the id assertion too: a run that
    // creates a program and then fails before its teardown leaves the program
    // BEHIND, and the next run's empty state — which the seed guarantees — is
    // gone. That is not a flake in the next run, it is this one's litter.
    try {
      expect(programId, isNotNull,
          reason: 'the endpoint returns the new program');
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(ChapterOpening).evaluate().isNotEmpty) break;
      }
      await pumpFor(tester, total: const Duration(seconds: 1));

      // §Composition — chapter opening with the `Deep study · N programs`
      // folio, then one §5.1 card per program.
      expect(find.byType(ChapterOpening), findsOneWidget);
      expect(find.textContaining('DEEP STUDY · 1 PROGRAM'), findsOneWidget);
      expect(find.text('Study Programs'), findsOneWidget);
      expect(find.text('Device run — braising'), findsOneWidget);
      expect(find.byType(KitCard), findsWidgets);

      // Every figure is a STORED field: progress is introduced_count of
      // unit_count, and the schedule is rendered from what was read — the
      // seed program was created with 07:00 America/Chicago above.
      expect(find.textContaining('passages introduced'), findsOneWidget);
      expect(find.textContaining('Daily at 07:00 · Chicago'), findsOneWidget);

      // A just-created program has NO `material_runway`, so it carries no
      // §12 notice. Absent is not zero: a client defaulting it would put "no
      // new material left" on the first thing this reader ever sees.
      expect(find.byType(KitNotice), findsNothing,
          reason: 'absent runway ⇒ no notice (4.7.0, ADR-043)');

      expect(find.text('Study now'), findsOneWidget);
      expect(find.byType(KitSwitch), findsOneWidget);
      expect(find.byType(KitStatusPill), findsWidgets);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    } finally {
      if (programId != null) {
        await Api.instance.deleteStudyProgram(programId);
      }
    }

    // …and the empty state comes back, from the same subscription.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitEmptyState).evaluate().isNotEmpty) break;
    }
    expect(find.byType(KitEmptyState), findsOneWidget);
  });

  // ── First-run onboarding (2.27.0; `screens/onboarding.md`) ─────────────────
  //
  // LAST in the file, and it signs a DIFFERENT user in — a throwaway account
  // created here, because the gate's whole subject is an account with nothing
  // in it and the seed user has a library. Driving it with the replay control
  // instead would prove the replay door and say nothing about the gate, which
  // is the half that can be wrong in both directions: shown to a returning
  // reader for a frame, or never shown at all.
  //
  // `nl-onboarded` is a DEVICE flag, not an account one, so a fresh account on
  // a device that has onboarded correctly sees no wizard. The flag is cleared
  // here to put the device in first-run condition — that is the gate's stated
  // precondition, not a nudge toward green.
  testWidgets('a first-run account sees the wizard', (tester) async {
    final seed = FirebaseAuth.instance.currentUser;
    final email = 'firstrun-${DateTime.now().microsecondsSinceEpoch}@noteletter.test';
    await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'first-run-1');
    await LocalFlags.setOnboarded(false);
    try {
      await pumpApp(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(OnboardingWizard).evaluate().isNotEmpty) break;
      }

      expect(find.byType(OnboardingWizard), findsOneWidget,
          reason: 'an account with an empty first snapshot gets first-run');
      // Its OWN frame: the app shell is not under it, and neither is the
      // INV-22 footer — the wizard is composed around the shell, not inside
      // it (`router.dart`).
      expect(find.byType(KitSupportFooter), findsNothing);

      // The rail's required parts (§Composition): the brand lockup, and the
      // step list. Below the compact width the rail is a header carrying the
      // brand and a progress line, which is the reference's own <900px form.
      expect(find.byType(KitBrand), findsOneWidget);
      expect(find.textContaining('Step 1 of 5'), findsOneWidget);

      // The welcome step: mark, folio, the accent-claused title, standfirst,
      // the chapter rule, and the three moves.
      expect(find.byType(ChapterOpening), findsOneWidget);
      expect(find.byType(ChapterRule), findsWidgets);
      expect(find.textContaining('SETTING UP · A FEW MINUTES'), findsOneWidget);
      expect(find.textContaining('Welcome to'), findsWidgets);
      expect(find.byType(KitNumberedMove), findsNWidgets(3));

      // The footer: an escape and an advance, both required parts.
      expect(find.text('Skip setup'), findsOneWidget);
      expect(find.widgetWithText(KitButton, 'Begin'), findsOneWidget);

      // Advancing reaches step 01, and its real drop zone — the wizard adds
      // sources through the ingest path, not a simulated one.
      await tester.tap(find.widgetWithText(KitButton, 'Begin'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(KitDropZone), findsOneWidget);
      expect(find.textContaining('№ 01 · OF 03'), findsOneWidget);

      // Skipping is a decision: it sets the same flag finishing does, and the
      // app is behind it immediately. Nothing was written to the account.
      await tester.tap(find.text('Skip setup'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(OnboardingWizard).evaluate().isEmpty) break;
      }
      expect(find.byType(OnboardingWizard), findsNothing);
      expect(LocalFlags.onboarded.value, isTrue);
    } finally {
      // Put the device and the session back: this file's other tests are the
      // seed user's, and a left-over throwaway session would make whichever
      // ran next a test of an empty account.
      await FirebaseAuth.instance.currentUser?.delete();
      await LocalFlags.setOnboarded(false);
      if (seed != null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: seedEmail, password: seedPassword);
      }
    }
  });
}
