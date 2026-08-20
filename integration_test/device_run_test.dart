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
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
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
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return router;
  }

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
    final doc = await FirebaseFirestore.instance
        .collection('documents')
        .doc(docId)
        .get();
    expect(
      doc.exists,
      isTrue,
      reason: 'run tool/seed_long_doc.py against the emulator first',
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
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final manuscript = find.text('Manuscript');
    if (manuscript.evaluate().isNotEmpty) {
      await tester.tap(manuscript.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
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
    final router = await pumpApp(tester);
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
    expect(find.byType(KitFilterChip), findsNWidgets(5));

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

    // The control bar appears with the query, carrying the type vocabulary.
    expect(find.byType(KitControlBar), findsOneWidget);
    expect(find.byType(KitFilterChip), findsNWidgets(4));

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

    // The route the user came from travels with the message — the shell
    // supplied it, which is the practical half of why the footer is the
    // shell's. It is in the URL the footer navigated to.
    expect(
      router.routerDelegate.currentConfiguration.uri.query,
      contains('activity'),
    );

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Device-run probe: ignore.');
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
      find.text('Device-run probe: ignore.'),
      findsOneWidget,
      reason: 'the sent message is in the transcript',
    );
    expect(
      tester.widget<TextField>(composer).controller?.text,
      '',
      reason: 'the composer cleared only after the 201',
    );
  });

  testWidgets('settings shows the Summaries section', (tester) async {
    final router = await pumpApp(tester);
    router.go('/settings');
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Scroll to it — 4.3.1 was a settings page that could not scroll to its own
    // new section, and the same section is the one being checked here.
    final scrollable = find.byType(Scrollable);
    for (var i = 0; i < 6; i++) {
      if (find.text('Summaries').evaluate().isNotEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.text('Summaries'), findsOneWidget);
    expect(find.text('Save style'), findsOneWidget);
  });
}
