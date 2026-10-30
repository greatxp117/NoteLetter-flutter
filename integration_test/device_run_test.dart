import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/app_providers.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/pages/sources/folder_contents.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/pages/onboarding/wizard.dart';
import 'package:flutter_app/pages/reader/history_panel.dart';
import 'package:flutter_app/pages/reader/listen_panel.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/reader/passage_mark.dart';
import 'package:flutter_app/pages/reader/source_priority.dart';
import 'package:flutter_app/pages/reader/speed_read_panel.dart';
import 'package:flutter_app/pages/reader/summary_panel.dart';
import 'package:flutter_app/pages/search/result_d.dart';
import 'package:flutter_app/widgets/app_layout.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/support_shell.dart';
import 'package:flutter_app/site/signin_page.dart';
import 'package:flutter_app/site/landing_page.dart';
import 'package:flutter_app/site/auth_modal.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/models/newsletter_settings.dart';

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
        // The app's own list (lib/app_providers.dart). A provider missing
        // HERE does not fail the app: it fails the run, with a
        // ProviderNotFoundError wall where the screen should be.
        providers: appProviders(auth),
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
    // By type: the old page's headline string outlived the page (F-68).
    expect(find.byType(LandingPage), findsNothing);
  });

  // F-44a — `/signin` against the Auth emulator: a REAL refusal renders the
  // reference's sentence in the §14.2 slot, and a real sign-in leaves the page
  // through the router's redirect, with nothing on the page navigating.
  testWidgets('signs in through /signin against the emulator', (tester) async {
    await FirebaseAuth.instance.signOut();
    try {
      final router = await pumpApp(tester);
      router.go('/signin');
      await pumpFor(tester, total: const Duration(seconds: 2));
      expect(find.byType(SignInPage), findsOneWidget);

      final fields = find.descendant(
          of: find.byType(SignInPage), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), seedEmail);
      await tester.enterText(fields.at(1), 'not-the-password');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, total: const Duration(seconds: 1));
      await tester.tap(find.text('Sign in'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(KitFailureInline).evaluate().isNotEmpty) break;
      }
      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'the emulator refused and nothing was said');
      final said = tester.widget<KitFailureInline>(find.byType(KitFailureInline));
      expect(said.message,
          anyOf('Incorrect email or password.', 'Incorrect password.'));
      expect(FirebaseAuth.instance.currentUser, isNull);

      // Focus it first: the field lost its input connection with the unfocus
      // above, and a bare enterText then typed into nothing (seen 2026-09-26:
      // the second attempt sent the first password again).
      await tester.tap(fields.at(1));
      await pumpFor(tester, total: const Duration(milliseconds: 500));
      await tester.enterText(fields.at(1), seedPassword);
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, total: const Duration(seconds: 1));
      expect(tester.widget<TextField>(fields.at(1)).controller?.text,
          seedPassword);
      await tester.tap(find.text('Sign in'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(SignInPage).evaluate().isEmpty) break;
      }
      final left = find.byType(KitFailureInline).evaluate().map(
          (e) => (e.widget as KitFailureInline).message);
      expect(FirebaseAuth.instance.currentUser?.email, seedEmail,
          reason: 'not signed in; on screen: $left');
      expect(find.byType(SignInPage), findsNothing,
          reason: 'signed in, the redirect should have left /signin');
      expect(router.state.matchedLocation, '/');
    } finally {
      if (FirebaseAuth.instance.currentUser?.email != seedEmail) {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: seedEmail, password: seedPassword);
      }
    }
  });

  // F-44a — the sign-up modal's letter opt-in, end to end: stashed before the
  // account exists, replayed by the signed-in app through fn_newsletter_settings
  // (the shim), and read back from the settings document. A throwaway account,
  // deleted afterwards, so the kept-up emulator does not grow.
  testWidgets('sign-up replays the letter opt-in', (tester) async {
    await FirebaseAuth.instance.signOut();
    final email = 'f44a-${DateTime.now().millisecondsSinceEpoch}@noteletter.test';
    try {
      final router = await pumpApp(tester);
      router.go('/signin');
      await pumpFor(tester, total: const Duration(seconds: 2));
      await tester.tap(find.text('Start your library'));
      await pumpFor(tester, total: const Duration(seconds: 1));
      expect(find.byType(AuthModal), findsOneWidget);
      expect(find.text('Begin your subscription.'), findsOneWidget);

      final fields = find.descendant(
          of: find.byType(AuthModal), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), email);
      await tester.enterText(fields.at(1), 'f44a-password-1');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, total: const Duration(seconds: 1));
      // 7:00am, not the default, so the read-back proves the CHOICE travelled.
      await tester.tap(find.text('6:30am').last);
      await pumpFor(tester, total: const Duration(seconds: 1));
      await tester.tap(find.text('7:00am').last);
      await pumpFor(tester, total: const Duration(seconds: 1));
      final create = find.text('Create my library');
      await tester.ensureVisible(create);
      await tester.tap(create);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (FirebaseAuth.instance.currentUser != null &&
            find.byType(AuthModal).evaluate().isEmpty) {
          break;
        }
      }
      expect(FirebaseAuth.instance.currentUser?.email, email);
      // Two writes land here, not one: the replay ({enabled, deliveryTime,
      // timezone, emailAddress}) and sign-up's own recipient seed
      // ({emailAddress}, AuthService._seedRecipient), in either order. The
      // poll waits for the END state — breaking on `enabled` alone read the
      // document between the two and saw no address (2026-10-07: the
      // emulator then held the right one).
      NewsletterSettings? s;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final read = await FirestoreService.instance.getNewsletterSettings();
        s = read;
        if (read.enabled && read.emailAddress.isNotEmpty) break;
      }
      expect(s?.enabled, isTrue, reason: 'the opt-in was never replayed');
      expect(s?.deliveryTime, '07:00');
      expect(s?.emailAddress, email);
    } finally {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.email == email) await u.delete();
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: seedEmail, password: seedPassword);
    }
  });

  testWidgets('the library home composes from the kit and really scrolls', (
    tester,
  ) async {
    // `/` is Home (screens/library.md §Composition, direction D since F-141).
    // Composition is what no other gate here looks at: tokens, data and
    // behaviour were all green while this screen was a different design
    // (ADR-041), so the assertions below are about PARTS BEING PRESENT, in the
    // roles the kit gives them. F-141's own run drives its sections.
    await pumpApp(tester);
    // Bounded pumps rather than a settle: Home lists live documents, and a
    // processing one carries a looping indicator.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The D frame: the masthead (folio, the greeting with its accent clause,
    // the double rule) — never the pre-D chapter opening.
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.byType(KitMasthead), findsOneWidget);
    expect(find.byType(ChapterOpening), findsNothing);
    expect(
      find.textContaining(RegExp('Good (morning|afternoon|evening)'),
          findRichText: true),
      findsWidgets,
    );
    // Either the library has volumes — the letter, Recently added and the
    // shelves — or it is empty, and then Your first sources leads with its
    // drop zone. An empty state that is a centred apology is a failed
    // composition, not a state.
    if (find.text('Your first sources').evaluate().isEmpty) {
      expect(find.byType(KitSecPeek), findsOneWidget,
          reason: 'the sheet runs as the running head on a phone');
      final scrollableHome = find.byType(Scrollable);
      for (var i = 0; i < 8 && find.text('Recently added').evaluate().isEmpty; i++) {
        await tester.drag(scrollableHome.first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Recently added'), findsOneWidget);
    } else {
      expect(find.byKey(const ValueKey('d-first-dz')), findsOneWidget,
          reason: 'the empty library leads with the drop zone, not a message');
    }

    // Only a REAL gesture proves a pane scrolls — a programmatic offset moves
    // even one the user cannot drag. Four web pages shipped unscrollable for
    // their whole lives that way (4.3.1).
    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);
    final before =
        tester.state<ScrollableState>(scrollable.first).position.pixels;
    await tester.drag(scrollable.first, const Offset(0, -400));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final after = tester.state<ScrollableState>(scrollable.first).position;
    // A page shorter than the viewport cannot scroll and must not be failed
    // for it; what would be a defect is a page with overflow that does not
    // move under a drag.
    if (after.maxScrollExtent > before) {
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
    //  - the canonical seed's complete documents are 6-47 words, shorter than
    //    the viewport, so nothing scrolls and every fill pins at 1.0 from the
    //    first frame;
    //  - a COUNTED passage renders full regardless of scroll (by design), so a
    //    counted fixture can never show the bar rising either.
    const docId = 'device-run-long-doc';
    // The catch is the whole point: rules L65 reads `resource.data.user_id`,
    // and `resource` is NULL for a document that does not exist, so a missing
    // fixture comes back as permission-denied rather than as an absent
    // document. Every emulator restart re-imports the seed and drops this
    // fixture, so it is the common case, not the rare one.
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

    final router = await pumpApp(tester);
    router.go('/reader/$docId');
    await _readerLoaded(tester);

    // Direction D (screens/reader.md §Composition): the D frame — a crumb
    // whose back control names the screen it was opened from, the masthead,
    // and the sheet's catalogue card (the running head on a phone). Asserted
    // on the REAL renderer because composition is what no contract test sees.
    expect(find.byType(KitDBackControl), findsOneWidget);
    expect(find.byType(KitMasthead), findsOneWidget);
    // The catalogue card must reflect the read it just logged: `doc_opened`
    // is written AFTER the document is fetched, so a client that renders the
    // snapshot unmodified shows "Views 0" all session (reader.md §Data).
    final ledger = tester.widget<KitFigures>(
        find.byType(KitFigures, skipOffstage: false));
    final views = ledger.ledger!.firstWhere((r) => r.term == 'Views');
    expect(int.parse(views.value), greaterThan(0),
        reason: 'Views must fold in what the doc_opened write committed');
    expect(ledger.ledger!.any((r) => r.term == 'Passages read'), isTrue,
        reason: 'coverage is rendered here and only here');

    // To the manuscript by a Contents jump (the running head on a phone).
    await _readerJump(tester, 'Manuscript');
    expect(find.byType(PassageMark), findsWidgets,
        reason: 'the manuscript must render the extent mark at rest');

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

    // A REAL gesture: `drag` synthesises a finger's pointer stream, so the
    // scroll position actually moves — unlike a programmatic jumpTo, which
    // moves even an unscrollable pane and would prove nothing.
    var prev = before;
    var everRose = false;
    for (var i = 0; i < 5; i++) {
      await tester.drag(_readerScrollable, const Offset(0, -320));
      await pumpFor(tester, total: const Duration(seconds: 1));
      final now = fills();
      // HIGH-WATER MARK: it may rise or hold, never retreat.
      for (var j = 0; j < now.length && j < prev.length; j++) {
        expect(now[j], greaterThanOrEqualTo(prev[j] - 0.001),
            reason: 'passage $j fill retreated: ${prev[j]} -> ${now[j]}');
        if (now[j] > prev[j] + 0.001) everRose = true;
      }
      prev = now;
    }
    expect(everRose, isTrue,
        reason: 'no passage fill rose across five real drags — the mark is '
            'not tracking scroll at all');

    // Scroll back UP: re-reading is still reading, so the mark must hold.
    final atBottom = fills();
    for (var i = 0; i < 5; i++) {
      await tester.drag(_readerScrollable, const Offset(0, 320));
      await pumpFor(tester, total: const Duration(seconds: 1));
    }
    final backAtTop = fills();
    for (var j = 0; j < backAtTop.length && j < atBottom.length; j++) {
      expect(backAtTop[j], greaterThanOrEqualTo(atBottom[j] - 0.001),
          reason: 'passage $j retreated on scrolling back up');
    }
  });

  // F-10's device obligation: every section BUILDS on a device. A panel that
  // throws on first build is indistinguishable from one nobody looked at.
  testWidgets('the reader opens every panel', (tester) async {
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await _readerLoaded(tester);

    // The labels exactly as `readerSections` spells them — 'Speed read', not
    // 'SpeedRead'. Each is a Contents jump (kit §29), which MOUNTS the
    // section on its way (screens/reader.md §Continuous scroll).
    for (final label in const [
      'Manuscript',
      'Speed read',
      'Listen',
      'Original',
      'History',
      'Summary',
    ]) {
      debugPrint('PANEL: jumping to $label');
      await _readerJump(tester, label);
      debugPrint('PANEL: $label built');
      expect(tester.takeException(), isNull,
          reason: 'the $label section threw while building');
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'the $label section built an ErrorWidget');
      expect(_readerSections(tester).current,
          label == 'Speed read' ? 'speedread' : label.toLowerCase(),
          reason: 'Contents marked a section the jump did not land on');
    }
  });

  // ── ADR-100 / ADR-051 ──────────────────────────────────────────────────────
  // The reader is one document on one scroll. Sections below the manuscript
  // MOUNT ON APPROACH (direction D, web `useSectionRail`) — never on a click —
  // so scrolling alone reaches every one; and the acceptance test is the DEEP
  // LINK: `?p=` scrolls into the manuscript, which is mounted on open.
  testWidgets("the reader scrolls from Summary to History without a tap, and "
      "the rail's current jump follows the scroll", (tester) async {
    const docId = 'device-run-long-doc';
    final router = await pumpApp(tester);
    router.go('/reader/$docId');
    await _readerLoaded(tester);

    String? current() => _readerSections(tester).current;
    // The two anchors' hosts are mounted on open, unconditionally.
    for (final panel in [SummaryPanel, ManuscriptPanel]) {
      expect(find.byType(panel, skipOffstage: false), findsOneWidget,
          reason: '$panel is not mounted on open');
    }
    expect(current(), 'summary',
        reason: 'the reader opens at the top of the document');

    // A REAL gesture, repeatedly: the long document is several viewports
    // tall. Contents REPORTS, and each section mounts as it nears.
    final seen = <String?>{current()};
    for (var i = 0; i < 80 && current() != 'history'; i++) {
      await tester.drag(_readerScrollable, const Offset(0, -520),
          warnIfMissed: false);
      await pumpFor(tester, total: const Duration(milliseconds: 750));
      seen.add(current());
    }
    final pos = tester.state<ScrollableState>(_readerScrollable).position;
    debugPrint('DEVICE-RUN reader scroll: reported ${seen.toList()} '
        'offset=${pos.pixels.round()}/${pos.maxScrollExtent.round()}');
    expect(current(), 'history',
        reason: 'scrolling did not reach the last section — either a section '
            'never mounted or Contents is not reporting position');
    expect(seen.length, greaterThan(2), reason: 'reported only $seen');
    for (final panel in [SpeedReadPanel, ListenPanel, HistoryPanel]) {
      expect(find.byType(panel, skipOffstage: false), findsOneWidget,
          reason: '$panel never mounted on the way down');
    }

    // A JUMP arrives, and Contents reports where it arrived: the section's
    // head 24 under the top of the page's scroller (kit §29).
    await _readerJump(tester, 'Listen');
    final top = tester.getTopLeft(_readerScrollable).dy;
    final head = tester
        .getTopLeft(find.byKey(_readerSections(tester).keyOf('listen')))
        .dy;
    debugPrint('DEVICE-RUN reader jump: current=${current()} '
        'head=${head.round()} top=${top.round()}');
    expect(current(), 'listen',
        reason: 'Contents marked a section the jump did not land on');
    expect(head - top, closeTo(24, 3),
        reason: 'the jump did not land the section 24 under the top');

    // Cold open on a passage link — no tap anywhere.
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
    await _readerLoaded(tester);
    await pumpFor(tester, total: const Duration(seconds: 4));
    // The OFFSET is the assertion: a fresh route's scroller starts at 0, so
    // any offset is the anchor's doing.
    final after = tester.state<ScrollableState>(_readerScrollable).position;
    debugPrint('DEVICE-RUN reader deep link: current=${current()} '
        'offset=${after.pixels.round()}');
    expect(after.pixels, greaterThan(100),
        reason: 'a `?p=` cold open left the reader at the top of the document '
            '— the passage link has not been honoured (ADR-051)');
  });

  testWidgets('the reader opens the source file', (tester) async {
    // §15.1 (ADR-075) and §6.4.2: the Original section reaches
    // `fn_get_raw_document_url` and a URL renders the §15.1 VIEW, not the
    // "no original file is stored" sentence.
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await _readerLoaded(tester);
    await _readerJump(tester, 'Original');
    await pumpFor(tester, total: const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    expect(
      find.byType(KitSourceFileView),
      findsOneWidget,
      reason: 'the Original panel drew no §15.1 view. If the sentence below it '
          'says no file is stored, the object is missing from the Storage '
          'emulator — run tool/seed_recipe_and_sources.py; that is a real '
          'state, and not this one',
    );
    // F-124: the PDF is DRAWN — its pages rendered by the platform (PDFKit
    // here) from the bytes the signed URL serves.
    final page1 = find.byKey(const ValueKey('kit-pdf-page-1'));
    for (var i = 0; i < 40; i++) {
      final drawn = find.descendant(of: page1, matching: find.byType(Image));
      if (drawn.evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.textContaining('can’t be displayed here'), findsNothing,
        reason: 'the PDF fell back to rule 1 — the platform could not open it');
    expect(page1, findsOneWidget, reason: 'no first page on the stage');
    expect(find.descendant(of: page1, matching: find.byType(Image)),
        findsOneWidget,
        reason: 'the first page was never rendered');
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsWidgets);
    expect(find.byTooltip('Share original'), findsOneWidget);
  });

  testWidgets("the reader sets a source's priority", (tester) async {
    // reader.md §Source priority (4.118.0, ADR-155). The WRITE: a real
    // fn_update_document through the shim, the stamp it leaves, and the reset
    // Default sends — leaving the seed as it found it (no stamp, 0.5). In
    // direction D the row is in Source details, the page's settings panel.
    const docId = 'seed-doc-pdf-complete';
    final ref = FirebaseFirestore.instance.collection('documents').doc(docId);
    final router = await pumpApp(tester);
    router.go('/reader/$docId');
    await _readerLoaded(tester);
    await _openSourceDetails(tester);

    final label = find.text('PRIORITY');
    expect(label, findsOneWidget,
        reason: 'Source details draws no Priority row under its Shelves row');
    final track = find.descendant(
        of: find.byType(SourcePriorityRow),
        matching: find.byType(KitSlideSwitch<String>));
    String lit() {
      final sw = tester.widget<KitSlideSwitch<String>>(track);
      return sw.options.firstWhere((o) => o.value == sw.value).label;
    }

    expect(lit(), 'Default', reason: 'the seed carries no stamp');
    expect((await ref.get()).data()?['source_priority_set_at'], isNull);

    await tester.tap(find.descendant(of: track, matching: find.text('High')));
    for (var i = 0; i < 40 && lit() != 'High'; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(lit(), 'High', reason: 'the write was not accepted, or never moved');
    expect(find.text('0.80'), findsOneWidget);
    final high = (await ref.get()).data()!;
    expect(high['source_priority'], 0.8);
    expect(high['source_priority_set_at'], isNotNull,
        reason: 'a number the reader sends is stamped (ADR-155)');

    await tester.tap(find.descendant(of: track, matching: find.text('Default')));
    for (var i = 0; i < 40 && lit() != 'Default'; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(lit(), 'Default');
    expect(find.text('0.50'), findsOneWidget);
    final reset = (await ref.get()).data()!;
    expect(reset['source_priority'], 0.5);
    expect(reset.containsKey('source_priority_set_at'), isFalse,
        reason: 'Default (null) deletes the stamp');
    expect(tester.takeException(), isNull);
  });

  // F-142 (direction D, screens/reader.md §Composition): the source page on
  // a phone — the six sections under their §31 heads, the running head that
  // says where the reader is with its reading-progress rule, and Source
  // details dropping from the app header.
  testWidgets(
      "the six sections, the running head '§ II · Manuscript · 2 of 6' and its "
      "progress rule, Source details in the panel", (tester) async {
    KitPageTools.instance.reset();
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await _readerLoaded(tester);

    // ── the masthead: crumb (back, then the folio under it), title ──
    final back = find.byType(KitDBackControl);
    expect(back, findsOneWidget, reason: 'the crumb draws the way back');
    final folio = find.textContaining(RegExp(r'^FINANCE · DOCUMENT · ADDED '));
    expect(folio, findsOneWidget, reason: 'the folio is {shelf} · {kind} · Added');
    expect(tester.getTopLeft(folio).dy,
        greaterThan(tester.getTopLeft(back).dy + 10),
        reason: 'on a phone the folio stands UNDER the back control');
    expect(find.text('Quarterly Tax Summary'), findsWidgets);
    // The page's one action at the tab bar's centre, by its short label.
    expect(
        find.descendant(
            of: find.byType(KitTabBar), matching: find.text('To letter')),
        findsOneWidget,
        reason: "the tab bar's centre is the page's action, *To letter*");

    // ── the running head: § I · Summary · 1 of 6 ──
    final peek = find.byKey(const ValueKey('d-peek'));
    expect(peek, findsOneWidget, reason: 'a phone runs the sheet as a head');
    String line() => [
          for (final w in tester.widgetList<Text>(find.descendant(
              of: peek, matching: find.byType(Text))))
            w.data ?? w.textSpan?.toPlainText() ?? '',
        ].join(' · ');
    debugPrint('DEVICE-RUN F-142 running head at rest: "${line()}"');
    expect(line(), contains('§ I'));
    expect(line(), contains('Summary'));
    expect(line(), contains('1 of 6'));
    double progress() => tester
        .widget<FractionallySizedBox>(find.byKey(const ValueKey('rx-progress')))
        .widthFactor!;
    expect(progress(), closeTo(0, 0.01), reason: 'nothing read at the top');

    // Dropped, Contents lists the six sections in their normative order.
    await tester.tap(peek);
    await pumpFor(tester, total: const Duration(milliseconds: 750));
    final rows = [
      for (final s in const [
        'Summary', 'Manuscript', 'Speed read', 'Listen', 'Original', 'History',
      ])
        find.descendant(of: find.byType(KitContents), matching: find.text(s)),
    ];
    for (final r in rows) {
      expect(r, findsOneWidget, reason: 'Contents lacks a row: $r');
    }
    for (var i = 1; i < rows.length; i++) {
      expect(tester.getTopLeft(rows[i]).dy,
          greaterThan(tester.getTopLeft(rows[i - 1]).dy),
          reason: 'Contents is out of the normative order');
    }
    // The identity block is the sheet's on a desk; the running head drops it.
    expect(find.byKey(const ValueKey('rx-identity')), findsNothing);
    // Re-process is offered (the seed PDF has a stored original), Delete last.
    final also = tester
        .widgetList<KitAlsoButton>(find.byType(KitAlsoButton))
        .map((b) => b.label)
        .toList();
    debugPrint('DEVICE-RUN F-142 Also: $also');
    expect(also, contains('Re-process'));
    expect(also.last, 'Delete', reason: 'Delete is the last of Also');

    // A Contents row folds the head and lands Manuscript under it.
    await tester.tap(rows[1]);
    await pumpFor(tester, total: const Duration(seconds: 2));
    // Folded, the body stays mounted but inert: nothing in it takes a tap.
    expect(rows[1].hitTestable(), findsNothing,
        reason: 'choosing a row folds the head');
    debugPrint('DEVICE-RUN F-142 running head after the jump: "${line()}" '
        'progress=${progress().toStringAsFixed(3)}');
    expect(line(), contains('§ II'));
    expect(line(), contains('Manuscript'));
    expect(line(), contains('2 of 6'));
    expect(progress(), greaterThan(0),
        reason: 'the progress rule did not fill as the page scrolled');
    final p1 = progress();

    // ── the six sections: a real scroll mounts and reaches each ──
    for (var i = 0; i < 40 && _readerSections(tester).current != 'history';
        i++) {
      await tester.drag(_readerScrollable, const Offset(0, -520),
          warnIfMissed: false);
      await pumpFor(tester, total: const Duration(milliseconds: 600));
    }
    for (final t in const [
      'Summary', 'Manuscript', 'Speed read', 'Listen', 'Original', 'History',
    ]) {
      expect(
          find.descendant(
              of: find.byType(KitSecHead, skipOffstage: false),
              matching: find.text(t, skipOffstage: false)),
          findsOneWidget,
          reason: 'no §31 head for $t');
    }
    for (final panel in [
      SummaryPanel, ManuscriptPanel, SpeedReadPanel, ListenPanel, HistoryPanel,
    ]) {
      expect(find.byType(panel, skipOffstage: false), findsOneWidget,
          reason: '$panel never mounted');
    }
    expect(tester.takeException(), isNull);
    expect(line(), contains('6 of 6'));
    expect(progress(), greaterThan(p1), reason: 'the rule did not keep filling');
    // On to the scroll's end (the footer): the rule is then whole.
    final pos = tester.state<ScrollableState>(_readerScrollable).position;
    for (var i = 0; i < 20 && pos.pixels < pos.maxScrollExtent - 1; i++) {
      await tester.drag(_readerScrollable, const Offset(0, -520),
          warnIfMissed: false);
      await pumpFor(tester, total: const Duration(milliseconds: 600));
    }
    debugPrint('DEVICE-RUN F-142 at the end: "${line()}" '
        'progress=${progress().toStringAsFixed(3)} '
        'offset=${pos.pixels.round()}/${pos.maxScrollExtent.round()}');
    expect(progress(), closeTo(1, 0.02), reason: 'the end is the whole rule');

    // ── Source details: the header's gear drops the page's panel ──
    await _openSourceDetails(tester);
    final headerBottom = tester.getBottomLeft(find.byType(KitAppHeader)).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('d-panel'))).dy,
        closeTo(headerBottom, 1),
        reason: 'the panel drops from the app header');
    for (final t in const ['FILING', 'SHELVES', 'PRIORITY', 'SUMMARY STYLE']) {
      expect(find.text(t), findsOneWidget, reason: 'Source details lacks $t');
    }
    // The shelves as §35 tags: no chip, the shelf's name underlined.
    expect(find.descendant(
            of: find.byType(KitShelfChipEditor),
            matching: find.byType(KitShelfTag)),
        findsOneWidget,
        reason: 'Filing draws the document shelf as a §35 tag');
    // On a phone the panel runs to the page's foot, so it closes by its own
    // Close (Escape and the scrim are the other two, kit §28).
    await tester.tap(find.byKey(const ValueKey('d-panel-close')));
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('d-panel')), findsNothing,
        reason: 'Close closes the panel');
    expect(tester.takeException(), isNull);
  });

  // F-132 (folded into F-142): moving a passage boundary on a phone
  // (screens/reader.md §Moving a passage boundary). The grip takes the
  // gesture, the drop line follows the finger to the nearest offered cut, the
  // page scrolls by itself at the scroller's edge, a release re-cuts both
  // passages locally (nothing written until Save — this Discards), and Up /
  // Down on the focused grip move one offered cut with focus kept.
  testWidgets(
      "drag a passage's grip on the phone: the line follows, the page scrolls "
      "at the edge, the release re-cuts; Up/Down on a hardware keyboard",
      (tester) async {
    final router = await pumpApp(tester);
    router.go('/reader/seed-doc-pdf-complete');
    await _readerLoaded(tester);
    await _readerJump(tester, 'Manuscript');
    await tester.tap(find.text('Edit text'));
    await pumpFor(tester, total: const Duration(seconds: 1));

    final grip = find.byKey(const ValueKey('ms-grip-2'));
    expect(grip, findsOneWidget, reason: 'no grip on passage 2');
    expect(find.byKey(const ValueKey('ms-grip-1')), findsNothing,
        reason: "the first passage's start is the document's start");
    expect(
        find.descendant(
            of: grip,
            matching: find.byWidgetPredicate((w) =>
                w is Semantics &&
                w.properties.label == 'Move where passage 2 begins')),
        findsOneWidget,
        reason: 'the grip is named for the passage it moves');
    final picture = find.descendant(
        of: find.byType(ManuscriptPanel), matching: find.byType(Image));
    expect(picture, findsWidgets, reason: "passage 1's picture is not drawn");
    await Scrollable.ensureVisible(tester.element(picture.first),
        alignment: 0.3, duration: Duration.zero);
    await pumpFor(tester, total: const Duration(milliseconds: 600));

    // ── the line follows, and the release re-cuts ──
    final unsaved = find.text('unsaved edits', skipOffstage: false);
    Future<void> discard() async {
      final d = find.text('Discard', skipOffstage: false);
      await tester.ensureVisible(d);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(d);
      await pumpFor(tester, total: const Duration(milliseconds: 800));
      expect(unsaved, findsNothing, reason: 'Discard left the edit');
    }

    // Discard also leaves editing: back in, for the next part.
    Future<void> editAgain() async {
      final e = find.text('Edit text', skipOffstage: false);
      await tester.ensureVisible(e);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(e);
      await pumpFor(tester, total: const Duration(seconds: 1));
    }

    final from = tester.getCenter(grip);
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 100));
    final line = find.byKey(const ValueKey('ms-dropline'));
    expect(line, findsOneWidget, reason: 'no drop line while dragging');
    final y0 = tester.getTopLeft(line).dy;
    final to = Offset(from.dx, tester.getTopLeft(picture.first).dy + 6);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 200));
    final y1 = tester.getTopLeft(line).dy;
    debugPrint('DEVICE-RUN F-132 drop line ${y0.round()} -> ${y1.round()} '
        '(picture top ${tester.getTopLeft(picture.first).dy.round()})');
    expect(y1, lessThan(y0 - 20), reason: 'the line did not follow the finger');
    expect(find.text('PASSAGE BEGINS HERE'), findsOneWidget);
    await g.up();
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    expect(line, findsNothing, reason: 'the line outlived the release');
    expect(unsaved, findsOneWidget, reason: 'the release re-cut nothing');
    expect(tester.getTopLeft(picture.first).dy,
        greaterThan(tester.getTopLeft(grip).dy),
        reason: 'passage 2 does not begin at the picture');
    await discard();
    await editAgain();

    // ── the page scrolls at the edge; Escape then changes nothing ──
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('ms-grip-2'), skipOffstage: false)),
        alignment: 0.6, duration: Duration.zero);
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final pos = tester.state<ScrollableState>(_readerScrollable).position;
    final before = pos.pixels;
    final top = tester.getTopLeft(_readerScrollable).dy;
    final from2 = tester.getCenter(grip);
    final g2 = await tester.startGesture(from2);
    await g2.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 100));
    await g2.moveTo(Offset(from2.dx, top + 20));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('DEVICE-RUN F-132 edge scroll ${before.round()} -> '
        '${pos.pixels.round()}');
    expect(pos.pixels, lessThan(before - 20),
        reason: 'the page did not scroll by itself at the top edge');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    await g2.up();
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(line, findsNothing);
    expect(unsaved, findsNothing, reason: 'Escape re-cut the passages');

    // ── Up / Down on the focused grip ──
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('ms-grip-2'), skipOffstage: false)),
        alignment: 0.5, duration: Duration.zero);
    await tester.pump(const Duration(milliseconds: 300));
    final node = tester
        .widget<Focus>(find
            .descendant(of: grip, matching: find.byType(Focus))
            .first)
        .focusNode!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(unsaved, findsOneWidget, reason: 'Up moved no boundary');
    expect(node.hasFocus, isTrue, reason: 'focus left the grip');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(node.hasFocus, isTrue, reason: 'focus left the grip on Down');
    debugPrint('DEVICE-RUN F-132 Up re-cut, focus kept through Up and Down');
    await discard();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sources composes from the kit, in the contract order', (
    tester,
  ) async {
    // Sources is the rail's *Library* (`/sources`; screens/sources.md
    // §Composition, direction D since F-141). Same reasoning as the library
    // test: PARTS BEING PRESENT in the roles the kit gives them, in order.
    final router = await pumpApp(tester);
    router.go('/sources');
    // Fixed pumps, not `pumpAndSettle`: this screen holds live subscriptions
    // (documents, cloud jobs, folders) and a settle waits for a quiet frame
    // that a screen with a spinner in it never has.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('Correspondence').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The D frame: the masthead with its folio, The Library, the running head.
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.byType(ChapterOpening), findsNothing);
    expect(find.text('The Library'), findsOneWidget);
    expect(find.textContaining(RegExp('VOLUMES?'), findRichText: true),
        findsWidgets,
        reason: 'the folio carries the volumes');

    // The column, in order: Correspondence, then Being catalogued while the
    // pipeline holds something (the seed's), then the catalogue.
    Future<double> yOf(String text) async {
      final f = find.text(text);
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 12 && f.evaluate().isEmpty; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(f, findsWidgets, reason: 'no "$text"');
      await tester.ensureVisible(f.first);
      await tester.pump(const Duration(milliseconds: 300));
      final y = tester.getTopLeft(f.first).dy;
      final pos = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      return y + pos;
    }

    final corr = await yOf('Correspondence');
    final being = await yOf('Being catalogued');
    final cat = await yOf('The catalogue');
    expect(corr < being && being < cat, isTrue,
        reason: 'Correspondence, Being catalogued, the catalogue — in order');

    // Every processing row offers the SOURCE — failed, queued or uploading —
    // because `error_message` is a claim about a source and nothing else on
    // this screen shows the source. The seed carries a failed docx (`file`)
    // and a queued article (`link`), so both §6.4.2 branches are on screen.
    await yOf('Being catalogued');
    final procRows = find.byType(ProcessingRow).evaluate().length;
    debugPrint('DEVICE-RUN sources: $procRows processing row(s), '
        'viewFile=${find.text('View file').evaluate().length}, '
        'openLink=${find.text('Open the link').evaluate().length}, '
        'retry=${find.text('Retry').evaluate().length}, '
        'indexAnyway=${find.text('Index it anyway').evaluate().length}');
    expect(procRows, greaterThan(0));
    expect(
      find.text('View file').evaluate().isNotEmpty ||
          find.text('Open the link').evaluate().isNotEmpty ||
          find.text('View images').evaluate().isNotEmpty,
      isTrue,
      reason: 'no processing row offers its source (§6.4.2)',
    );
    // **Retry is never on a skipped row** and the two branches are disjoint:
    // one primary per row, never two.
    expect(
      find.text('Retry').evaluate().length +
          find.text('Index it anyway').evaluate().length,
      lessThanOrEqualTo(procRows),
      reason: 'one primary per row, never two',
    );

    // The catalogue is the register in List — never a table.
    await LocalFlags.setSourceView('list');
    await yOf('The catalogue');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KitLibRegister), findsOneWidget);
    expect(find.byType(DataTable), findsNothing,
        reason: 'the volume list is the register; there is no table pattern');
  });

  testWidgets(
      'a folder row in the import picker expands and reports its contents', (
    tester,
  ) async {
    // screens/sources.md §Folder contents (4.59.0, ADR-096; QUEUE F-23). The
    // seed carries a connected Google Drive and the shim's provider fake lists
    // folders, so this is the real picker, the real endpoint and the real
    // scan — never scanned on open, only on the disclosure.
    final router = await pumpApp(tester);
    router.go('/sources');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('Browse files…').evaluate().isNotEmpty) break;
    }
    await tester.ensureVisible(find.text('Browse files…').first);
    await tester.tap(find.text('Browse files…').first);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(FolderContents).evaluate().isNotEmpty) break;
    }
    expect(find.byType(FolderContents), findsWidgets,
        reason: 'the picker listed no folder row to disclose');
    // Nothing was scanned by listing the rows.
    expect(find.textContaining(RegExp(r'^scanned \d')), findsNothing);

    final open = find.text('What’s in here?').first;
    await tester.ensureVisible(open);
    await tester.tap(open);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining(RegExp(r'^scanned \d')).evaluate().isNotEmpty ||
          find.byType(KitFailureInline).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(KitFailureInline), findsNothing,
        reason: 'the scan was refused — the answer is a hole, not contents');
    expect(find.textContaining(RegExp(r'^scanned \d')), findsOneWidget,
        reason: 'the row did not report what it scanned');
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
    // Direction D: the pinned identity is the Reader's card (kit §1.2), and
    // its stub carries the unread count the old Activity row did.
    expect(find.byType(KitReaderCard), findsOneWidget,
        reason: '§1.2 requires the Reader\'s card in the pinned bottom region');
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
          find.text('Nothing of that kind yet.').evaluate().isNotEmpty) {
        break;
      }
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Direction D (F-145, activity.md §Composition): the masthead, its folio
    // the rows the feed read — `Activity · {N} events`.
    expect(find.byType(KitMasthead), findsOneWidget);
    expect(find.textContaining('ACTIVITY\u00a0· '), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);

    final seeded = find.byType(KitTimeline).evaluate().isNotEmpty;
    if (!seeded) {
      // An answered feed with nothing in it says so in one line.
      expect(find.text('Nothing of that kind yet.'), findsOneWidget);
      return;
    }

    // The sheet's Kind facet carries one row per family, and the empty ones
    // are HELD, not dropped — the set is a vocabulary. SIX: `All · Sources ·
    // Processing · Letters · Study · In the library` (activity.md §Filters),
    // plus `Other` only when a row falls into it.
    final facet = tester.widget<KitFacet>(find.byType(KitFacet));
    expect(facet.items.length, 6);

    // Each day is a small section head (§31) over its rows.
    expect(
      find.textContaining(RegExp(r'^(Today|Yesterday|This week|Earlier)$')),
      findsWidgets,
      reason: 'the feed is bucketed by day, each bucket opened by its head',
    );

    // The timeline, not a grid of cards. The spine and the 32px nodes are what
    // make it a record rather than a dashboard.
    expect(find.byType(KitTimelineRow), findsWidgets);
    expect(
      find.byType(GridView),
      findsNothing,
      reason: 'the feed is the §4.2 timeline; there is no card-grid pattern',
    );

    // Filtering narrows the feed rather than reordering it: pick a family
    // that is not held — in the dropped running head on a phone — and check
    // the row count does not grow.
    final before = find.byType(KitTimelineRow).evaluate().length;
    final pick = facet.items
        .where((i) => i.id != 'all' && !i.disabled)
        .firstOrNull;
    if (pick != null) {
      final head = find.byKey(const ValueKey('d-peek'));
      final docked = head.evaluate().isNotEmpty;
      if (docked) {
        await tester.tap(head);
        await pumpFor(tester, total: const Duration(seconds: 1));
      }
      await tester.tap(find.descendant(
          of: find.byType(KitFacet), matching: find.text(pick.label)));
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
      if (docked) {
        // A kind does not fold the head (web `foldOn: '.rx-nav-b'`); the
        // line does.
        await tester.tap(head);
        await pumpFor(tester, total: const Duration(seconds: 1));
      }
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
    // Search is screen 5/11, in direction D since F-143 (search.md
    // §Composition): the page's own field in the masthead, the Filters sheet
    // (the running head on a phone), and a result that opens IN PLACE among
    // its neighbours — the "reading pane" this test is named for is the
    // opened row now; the split pane retired with web's. None of it is
    // visible to Tier-1, which asserts request construction.
    final router = await pumpApp(tester);
    router.go('/search');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Idle: the field stays in the masthead on a phone, and the column offers
    // what to search for rather than a blank page.
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Try searching for'), findsOneWidget);

    // The Filters sheet carries the kind vocabulary — All sources and every
    // LIVE kind (§6.4.1; nine since 4.13.0's video, which `doc_kind_check`
    // holds both ways). A facet that is short of a kind is a bucket nothing
    // can reach, and it looks exactly like a complete vocabulary.
    final facet = find.byType(KitFacet);
    expect(facet, findsOneWidget);
    final kinds = tester.widget<KitFacet>(facet).items.map((i) => i.label);
    expect(kinds.toList(), [
      'All sources', 'Books & PDFs', 'My notes', 'Web', 'YouTube',
      'Instagram', 'TikTok', 'Audio', 'Video',
    ]);
    // **No counts** (ADR-065 §4): a count over one page of results is a
    // statement about that page, not about the library.
    expect(tester.widget<KitFacet>(facet).items.every((i) => i.count == null),
        isTrue, reason: 'search kinds carry no count');

    // Submit a query the seed can answer.
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'pasta');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // Wait generously: this is an embedding call plus a vector query, and a
    // cold first request runs to several seconds. **Never `pumpAndSettle`
    // here**: the skeleton's shimmer animates forever.
    final rows = find.byType(SearchResultD);
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (rows.evaluate().isNotEmpty ||
          find.byType(KitFailureBlock).evaluate().isNotEmpty ||
          find.textContaining('No passages found').evaluate().isNotEmpty) {
        break;
      }
    }
    await pumpFor(tester, total: const Duration(seconds: 2));

    // Say which branch this run took. Without it a green run is ambiguous —
    // the failure branch below returns early and passes too.
    final searchState = Provider.of<SearchNotifier>(
      tester.element(find.byType(KitDPage)),
      listen: false,
    );
    debugPrint(
      'DEVICE-RUN search: ${rows.evaluate().length} result rows, '
      'notifier=${searchState.results.length} results, '
      'error=${searchState.error}',
    );

    if (rows.evaluate().isEmpty) {
      // Either nothing matched — the column's own sentence — or the call
      // failed and the §14.1 block says so. What is NOT allowed is a blank
      // body: a search that answers with nothing at all.
      expect(
        find.byType(KitFailureBlock).evaluate().isNotEmpty ||
            find.textContaining('No passages found').evaluate().isNotEmpty,
        isTrue,
        reason: 'no results still renders a state, never an empty page',
      );
      return;
    }

    // §16 — the score meter is a CONTROL with an explainer behind it (4.44.0,
    // ADR-082), and the figures in it are measured.
    final meter = find.descendant(
        of: rows.first, matching: find.byType(KitAnchoredPopover));
    await tester.ensureVisible(meter);
    await pumpFor(tester, total: const Duration(milliseconds: 400));
    await tester.tap(meter);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('RELEVANCE'), findsOneWidget,
        reason: 'the score element opens the §16 explainer');
    expect(find.text('Similarity'), findsOneWidget);
    expect(find.text('Source priority'), findsOneWidget,
        reason: 'both components come off a live response — a missing row here '
            'means the client is on the derive path ADR-082 forbids');
    await tester.tapAt(const Offset(8, 400));
    await pumpFor(tester, total: const Duration(milliseconds: 600));

    // Opened in place: the passage whole among its neighbours, *Fold it
    // away*; one row open at a time.
    final toggle = find.byKey(const ValueKey('search-toggle-1'));
    await tester.ensureVisible(toggle);
    await pumpFor(tester, total: const Duration(milliseconds: 400));
    await tester.tap(toggle);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Fold it away').evaluate().isNotEmpty) break;
    }
    expect(find.text('Fold it away'), findsOneWidget,
        reason: 'the row opens in place');
    if (rows.evaluate().length > 1) {
      final second = find.byKey(const ValueKey('search-toggle-2'));
      await tester.ensureVisible(second);
      await pumpFor(tester, total: const Duration(milliseconds: 400));
      await tester.tap(second);
      await pumpFor(tester, total: const Duration(seconds: 2));
      expect(find.text('Fold it away'), findsOneWidget,
          reason: 'exactly one result is open at a time');
    }
  });

  // ── Ask (4.53.0/4.54.0, ADR-090) ───────────────────────────────────────────
  testWidgets('ask composes from the kit', (tester) async {
    // Ask is screen 7/11, in direction D since F-143 (ask.md §Composition):
    // the conversation is the page, the conversations are the sheet — on a
    // phone its running head — and the composer docks at the column's foot.
    // Nothing here was visible to Tier-1: the sheet is composition, the route
    // rename is a table, and "restoring a conversation issues no request" is
    // the ABSENCE of one.
    final router = await pumpApp(tester);
    router.go('/ask');
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The D frame, its folio, the dock (§38).
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.textContaining('GROUNDED IN YOUR LIBRARY'), findsOneWidget);
    expect(find.byType(KitAskComposer), findsOneWidget);
    expect(find.text('Ask Your Library'), findsOneWidget);

    // The conversations are the running head: folded, its rows are not
    // reachable; dropped, *New conversation* heads the list.
    final newConvo = find.byKey(const ValueKey('ask-new'));
    expect(newConvo.hitTestable(), findsNothing,
        reason: 'folded, the running head is inert');
    await _dropHead(tester);
    expect(newConvo.hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d-peek')));
    await pumpFor(tester, total: const Duration(milliseconds: 750));

    // The empty state (§37): the offers are the suggested prompts.
    expect(find.byType(KitEmptyState), findsOneWidget);
    expect(find.byType(KitSuggestion), findsWidgets);

    // A turn. Generous wait: this is an embedding call, a vector query and
    // the written answer, and a cold first request runs to several seconds —
    // a short wait takes the failure branch and is green for the wrong
    // reason.
    final field = find.byKey(const ValueKey('ask-field'));
    await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        'pasta cooking');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // The SEND CONTROL: a soft keyboard's return is a new line (§38).
    await tester.tap(find.byKey(const ValueKey('ask-send')));
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('YOUR LIBRARY').evaluate().isNotEmpty &&
          find.text('Reading your notes…').evaluate().isEmpty) {
        break;
      }
      if (find.text('Try again').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final ask = Provider.of<ChatNotifier>(
      tester.element(find.byType(KitAskComposer)),
      listen: false,
    );
    // Say which branch this run took. Without it a green run is ambiguous —
    // the rejection branch renders a state too.
    debugPrint(
      'DEVICE-RUN ask: ${ask.messages.length} stored message(s), '
      'thread=${ask.activeId}, error=${ask.sentError}, '
      'answer=${find.byType(KitAskAnswer).evaluate().length}, '
      'citations=${find.byType(KitAskCitation).evaluate().length}',
    );

    if (ask.sentError != null) {
      // Since 4.61.0 (ADR-097) the QUESTION never disappears: the turn stays
      // on screen with the server's sentence and a retry, and it is never put
      // back in the composer as though it had never been asked.
      expect(find.byType(KitFailureInline), findsWidgets,
          reason: 'a refused turn says so (§14.2) — never an empty answer');
      expect(find.text('pasta cooking'), findsOneWidget,
          reason: 'the sent turn STAYS on screen (ADR-097)');
      expect(find.text('Try again'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
                find.descendant(of: field, matching: find.byType(TextField)))
            .controller
            ?.text,
        '',
        reason: 'a refused question is never returned to the composer',
      );
      return;
    }

    // The turn was RECORDED (ADR-090): both messages came back from the
    // subscription, not from local state.
    expect(ask.messages.length, greaterThanOrEqualTo(2));
    expect(ask.activeId, isNotNull);
    expect(find.text('YOU'), findsWidgets);
    expect(find.text('YOUR LIBRARY'), findsWidgets);
    expect(find.byType(KitAskCitation), findsWidgets,
        reason: 'the citations, as a ruled register');

    // The thread is now in the running head, with the title and the preview
    // the BACKEND wrote; *New* is the tab bar's centre while it is open.
    expect(
        find.descendant(
            of: find.byType(KitTabBar), matching: find.text('New')),
        findsOneWidget);
    await _dropHead(tester);
    final entries = find.byType(KitAskConvo);
    expect(entries.hitTestable(), findsWidgets);
    expect(find.text('TODAY').hitTestable(), findsOneWidget,
        reason: 'entries are grouped under mono caps labels (§9)');
    final entry = tester.widgetList<KitAskConvo>(entries).first;
    expect(entry.active, isTrue,
        reason: 'the open conversation is the marked one');
    expect(entry.preview, isNotEmpty,
        reason: 'ask_threads.preview (4.54.0) backs the entry\'s second line');

    // Reopening a stored conversation issues NO request and must not draw the
    // thinking state; choosing an entry folds the head.
    await tester.tap(entries.first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Reading your notes…'), findsNothing,
        reason: 'restoring a thread is not thinking (screens/ask.md §States)');
    expect(find.text('YOUR LIBRARY'), findsWidgets);
    expect(entries.hitTestable(), findsNothing,
        reason: 'choosing an entry folds the running head');

    // ── §9.1 entry actions (4.55.0, ADR-091) ────────────────────────────────
    // Both are driven, and the STORED title is read back out of the
    // subscription — a rename that only painted passes every other check.
    await _dropHead(tester);
    final threadId = ask.activeId!;
    await tester.tap(find
        .descendant(
            of: entries.first, matching: find.byIcon(Icons.edit_outlined))
        .first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final renameField =
        find.descendant(of: entries.first, matching: find.byType(TextField));
    debugPrint('DEVICE-RUN ask §9.1 edit tapped: renaming=${ask.renamingId}, '
        'fields=${renameField.evaluate().length}');
    expect(renameField, findsOneWidget,
        reason: '§9.1 renames IN PLACE — the title becomes a field');
    await tester.enterText(renameField, 'Pasta, from the top');
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
    if (find.byIcon(Icons.delete_outline).hitTestable().evaluate().isEmpty) {
      await _dropHead(tester);
    }
    await tester.tap(find
        .descendant(
            of: entries.first, matching: find.byIcon(Icons.delete_outline))
        .first);
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
    expect(find.textContaining('GROUNDED IN ONE SHELF'), findsOneWidget);

    final field = find.descendant(
        of: find.byKey(const ValueKey('ask-field')),
        matching: find.byType(TextField));
    await tester.enterText(field, 'Which of these recipes can use steak?');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.byKey(const ValueKey('ask-send')));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Try again').evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final ask = Provider.of<ChatNotifier>(
      tester.element(find.byType(KitAskComposer)),
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
      tester.widget<TextField>(field).controller?.text,
      '',
      reason: 'a refused question is never returned to the composer',
    );
    // And the screen stayed where it was: a refused turn records nothing, so
    // there is no thread to move to (ADR-101/ADR-022).
    expect(ask.activeId, isNull);
  });

  // ── INV-22 (4.18.0, ADR-054; placement 5.19.0, ADR-173) ─────────────────
  // The Tier-1 gate (`test/contract/support_footer_test.dart`) proves the route
  // TABLE nests every screen under the footer's shell, that every routed screen
  // scrolls through the kit, and the placement on the kit's own containers.
  // What it cannot do is mount every real screen — no Firebase in a plain
  // widget test. This closes that: the real app, on a real renderer, at routes
  // composed different ways, reached with REAL drags (only a real gesture
  // proves scrollability).
  testWidgets('the support footer ENDS every screen, reader included', (
    tester,
  ) async {
    final router = await pumpApp(tester);

    // '/' and '/settings' sit inside the rail-and-pane shell; '/reader/:docId'
    // deliberately does NOT, and is the route a footer composed in AppLayout
    // would have missed. '/support' and '/ask' end their scroll above a docked
    // composer. '/support' is included because a screen does not stop being a
    // screen by being the one the footer opens.
    for (final route in [
      '/',
      '/settings',
      '/activity',
      '/sources',
      '/letters',
      '/ask',
      '/support',
    ]) {
      router.go(route);
      await pumpFor(tester);
      expect(
        find.byType(KitSupportFooter),
        findsOneWidget,
        reason: '$route renders with no way to reach a human (INV-22)',
      );
      await _dragToFooter(tester, route);
      expect(
        find.text('Chat with support…').hitTestable(),
        findsOneWidget,
        reason: 'the normative copy, reachable at the end of $route',
      );
    }

    // The long screens keep it out of the way: below the fold until the end.
    router.go('/activity');
    await pumpFor(tester);
    expect(find.byType(KitSupportFooter).hitTestable(), findsNothing,
        reason: 'ADR-173: not a strip pinned over every screen');

    // The same fixture the reader test uses; any real document would do, since
    // what is under test here is the shell, not the reader.
    router.go('/reader/device-run-long-doc');
    await pumpFor(tester, total: const Duration(seconds: 6));
    expect(find.byType(KitSupportFooter).hitTestable(), findsNothing,
        reason: 'the reader keeps it for the end of the document');
    await _dragToFooter(tester, '/reader/device-run-long-doc',
        scrollable: _readerScrollable);
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
    // control is hittable where it is laid out — at the end of the scroll,
    // reached by real drags (ADR-173).
    await _dragToFooter(tester, '/activity');
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
      if (find.byType(KitLetterRow).evaluate().isNotEmpty) break;
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

  testWidgets('the readings day view opens from a letter and composes from '
      'the kit', (tester) async {
    // QUEUE F-33. The live "See all" (ADR-029 §5) — the screen this client did
    // not have. Needs the same `tool/seed_letters.py` run the letters test
    // above documents: the canonical seed holds no `kind: "scripture"` record,
    // so without it there is no readings letter to open and nothing here runs.
    final router = await pumpApp(tester);
    router.go('/letters');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('THE READINGS LETTER').evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));

    // Open the readings letter from its ARCHIVE ROW — by the row's own type,
    // not by the text, which also appears in the card above it and is not a
    // control there. The row is far down a phone screen, and a tap at an
    // off-screen offset lands on whatever IS there, silently.
    final row = find.byWidgetPredicate((w) =>
        w is KitLetterRow && w.title.contains('Thursday of week 23'));
    expect(row, findsOneWidget,
        reason: 'run tool/seed_letters.py first — no readings letter to open');
    await tester.ensureVisible(row);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await tester.tap(row);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(find.text('All letters'), findsOneWidget,
        reason: 'the letter did not open — everything below would be the list');

    // The control that did not exist here. The seed's letter found 6.
    final seeAll = find.textContaining('See all 6 passages for this day');
    expect(seeAll, findsOneWidget,
        reason: 'the letter offers its live day (ADR-029 §5)');
    await tester.ensureVisible(seeAll);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await tester.tap(seeAll);
    // Three live searches, not a replay of the stored passages.
    await pumpFor(tester, total: const Duration(seconds: 6));

    // §Composition — §1.3 utility bar naming where it returns to, then the
    // chapter opening. Not the bespoke Letters header: this is a document
    // view, not an index.
    expect(find.text('Back to the letter'), findsOneWidget);
    expect(find.byType(ChapterOpening), findsOneWidget);
    expect(find.textContaining('Thursday of week 23'), findsWidgets);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);

    // The Live statement is present and states a MEASURED count — the page
    // says what it just found, never what the letter stored.
    // The tag is set in caps by its source string (`.sc-live-tag`), so the
    // tree holds `LIVE` — matching the sentence-case word finds nothing.
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('passages'), findsWidgets);

    // One section per reading, each naming its own citation.
    expect(find.text('Col 3:12-17'), findsOneWidget);
    expect(find.text('Ps 150'), findsOneWidget);
    expect(find.text('Lk 6:27-38'), findsOneWidget);

    // …and the way back out of it returns to the LETTER, not the index.
    await tester.tap(find.text('Back to the letter'));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(find.text('All letters'), findsOneWidget);
  });

  testWidgets('shelves composes from the kit', (tester) async {
    // Screen 9/11 (QUEUE F-08), in direction D since F-143 (library.md
    // §Composition — Shelves and a shelf). The seed holds four shelves —
    // Recipes (2 volumes, Baking inside it with none), Finance (1) and
    // Stories (1, carrying a LEGACY HEX colour, which is most of production
    // and must still paint).
    final router = await pumpApp(tester);
    // The old route is a redirect, not a 404: `/tags` was this client's route
    // for the whole life of the screen.
    router.go('/tags');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitShelfCatalogue).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(router.state.matchedLocation, '/shelves');

    // §26 — folio, title; the counts are the two subscriptions'.
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.text('THE SHELVES · 4 SHELVES · 4 VOLUMES'),
        findsOneWidget);
    expect(find.text('Shelves'), findsOneWidget);
    // §42 — the catalogue over the top-level shelves; the sheet lists them.
    expect(find.byType(KitShelfCatalogue), findsOneWidget);
    for (final id in ['recipes', 'finance', 'stories']) {
      expect(find.byKey(ValueKey('shelves-sheet-seed-tag-$id')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('shelves-sheet-seed-tag-baking')),
        findsNothing, reason: 'the sheet lists top-level shelves only');
    // Nothing Material survived the recompose — this screen was a list of
    // `ListTile`-ish rows with a FAB until F-08.
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // ── the shelf's own page ────────────────────────────────────────────
    router.go('/shelves/seed-tag-recipes');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('ALL SHELVES').evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.text('ALL SHELVES'), findsOneWidget);
    expect(find.text('SHELF · 2 VOLUMES · 4 PASSAGES'),
        findsOneWidget);
    expect(find.byType(KitRegisterRow), findsNWidgets(2));

    // Shelf settings, from the app header's gear (kit §28, §30). 2.20.0
    // (ADR-025): the split control is ABSENT below five volumes, not
    // disabled: the endpoint 400s there, and a control that cannot work is
    // worse than no control. Delete is the sheet's Also, never the panel's.
    await _openPageSettings(tester, 'Shelf settings');
    final panel = find.byKey(const ValueKey('d-panel'));
    expect(panel, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Split this shelf')),
        findsNothing);
    expect(find.descendant(of: panel, matching: find.text('Delete shelf')),
        findsNothing);

    // §6.2 — twenty swatches (5.41.0, ADR-196), each announced by its NAME,
    // not its token.
    expect(find.descendant(of: panel, matching: find.byType(KitSwatch)),
        findsNWidgets(20));
    expect(find.bySemanticsLabel('Deep plum'), findsOneWidget);
    expect(find.bySemanticsLabel('plum-600'), findsNothing);

    // Write before move: the swatch moves only once `fn_update_tag` has
    // answered, and what it then draws is what the SUBSCRIPTION carried back.
    // The web swatch moved first until 2.15.0, so a 400 on every colour change
    // looked like a success for months. The seed shelf is `brick-400`, whose
    // NAME is Vermilion.
    expect(
      tester
          .widgetList<KitSwatch>(find.byType(KitSwatch))
          .any((w) => w.label == 'Vermilion' && w.selected),
      isTrue,
    );
    try {
      final plum = find.bySemanticsLabel('Deep plum');
      await tester.ensureVisible(plum);
      await pumpFor(tester, total: const Duration(milliseconds: 400));
      await tester.tap(plum);
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

  testWidgets('shelf map composes from the kit, opens fitted, pans, pinches, '
      'selects', (tester) async {
    // QUEUE F-126 (5.25.0, ADR-177, kit §24). The seed holds four shelves —
    // Baking inside Recipes since 5.28.0 (INV-33), so the map draws a
    // Sub-shelves column — and four shelved, complete volumes (Recipes 2,
    // Finance 1, Stories 1). Every
    // gesture below is a REAL pointer sequence: a programmatic transform moves
    // even a viewer that cannot be dragged, so it would prove nothing.
    final router = await pumpApp(tester);
    router.go('/shelves');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitShelfCatalogue).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    // library.md §The shelf map (direction D) — the entry point is the
    // Shelves sheet's *Also*, which on a phone is in the running head: not an
    // address a reader has to know. Choosing it folds the head first.
    await _dropHead(tester);
    final entry = find.widgetWithText(KitAlsoButton, 'The shelf map');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    final viewer = find.byKey(const Key('relmap-viewer'));
    for (var i = 0; i < 40 && viewer.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(router.state.matchedLocation, '/shelves/map');

    // Composition (direction D): the D frame, the crumb, one §24 map; the
    // sheet is the running head, the map glyph and `{N} shelves`.
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.text('ALL SHELVES'), findsOneWidget);
    expect(find.text('SHELF MAP\u00a0· 4 SHELVES'), findsOneWidget);
    expect(find.text('The Shelf Map'), findsOneWidget);
    expect(_peekText(tester), contains('4 shelves'));
    expect(find.byType(KitRelationshipMap), findsOneWidget);
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('Find a shelf or volume…'), findsOneWidget);
    // The column headers, inside the canvas.
    expect(find.descendant(of: viewer, matching: find.text('VOLUMES')),
        findsOneWidget);
    expect(find.descendant(of: viewer, matching: find.text('SUB-SHELVES')),
        findsOneWidget);
    expect(find.descendant(of: viewer, matching: find.text('SHELVES')),
        findsOneWidget);

    // Every chip, or one kind's (`relmap-node-{kind}:{id}`).
    Finder nodes([String kind = '']) => find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>)
            .value
            .startsWith(kind.isEmpty ? 'relmap-node-' : 'relmap-node-$kind:'));
    expect(nodes('shelf'), findsNWidgets(4));
    // Shelved, complete volumes only; an unshelved one is counted, not drawn.
    expect(nodes('volume').evaluate().length, greaterThanOrEqualTo(4));
    final recipes =
        find.byKey(const Key('relmap-node-shelf:seed-tag-recipes'));
    expect(recipes, findsOneWidget);

    await Scrollable.ensureVisible(tester.element(viewer), alignment: 0.0);
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final tc = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    double zoom() => tc.value.getMaxScaleOnAxis();
    Offset shift() {
      final t = tc.value.getTranslation();
      return Offset(t.x, t.y);
    }

    // ── opens fitted: the whole graph in the box, never above 100% ────────
    final box = tester.getRect(viewer);
    final fitted = zoom();
    expect(fitted, lessThanOrEqualTo(1.0001));
    for (final e in nodes().evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(box.inflate(1).contains(r.topLeft) &&
              box.inflate(1).contains(r.bottomRight), isTrue,
          reason: 'a fitted map shows every chip; $r is outside $box');
    }
    expect(find.text('${(fitted * 100).round()}%'), findsOneWidget);

    // A point on the empty canvas: below the view controls, on no chip.
    Offset emptyPoint() {
      final b = tester.getRect(viewer);
      final chips = [
        for (final e in nodes().evaluate())
          tester.getRect(find.byElementPredicate((x) => x == e)).inflate(16),
      ];
      for (var y = b.bottom - 24; y > b.top + 80; y -= 24) {
        for (var x = b.left + 24; x < b.right - 24; x += 24) {
          final p = Offset(x, y);
          if (chips.every((c) => !c.contains(p))) return p;
        }
      }
      fail('no empty point on the canvas');
    }

    // ── pans: a one-finger drag moves the graph, not the page ─────────────
    final before = shift();
    final recipesAt = tester.getCenter(recipes);
    await tester.timedDragFrom(emptyPoint(), const Offset(-70, -50),
        const Duration(milliseconds: 500));
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final moved = shift() - before;
    expect(moved.distance, greaterThan(40),
        reason: 'a drag on the canvas pans it (it moved $moved)');
    expect(zoom(), closeTo(fitted, 1e-6), reason: 'a pan never zooms');
    expect(tester.getRect(viewer), box,
        reason: 'the page scrolled instead: the viewer must win the drag');
    expect((tester.getCenter(recipes) - recipesAt - moved).distance,
        lessThan(1.5),
        reason: 'the chips move with the transform');
    expect(find.text('Open shelf'), findsNothing,
        reason: 'a drag that moved is a pan, never a selection');

    // ── pinches: two fingers spreading zoom in ────────────────────────────
    final c = tester.getRect(viewer).center;
    final f1 = await tester.startGesture(c - const Offset(30, 0), pointer: 41);
    final f2 = await tester.startGesture(c + const Offset(30, 0), pointer: 42);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await f1.moveBy(const Offset(-6, 0));
      await f2.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await f1.up();
    await f2.up();
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final pinched = zoom();
    expect(pinched, greaterThan(fitted * 1.5),
        reason: 'a pinch zooms ($fitted → $pinched)');
    expect(pinched, lessThanOrEqualTo(4.0001), reason: 'zoom clamps at 4×');
    expect(find.text('${(pinched * 100).round()}%'), findsOneWidget);

    // Activating the zoom figure re-fits.
    await tester.tap(find.text('${(pinched * 100).round()}%'));
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(zoom(), closeTo(fitted, 1e-6));

    // ── selects: a chip lights its path and fills the inspector ───────────
    await tester.tap(recipes);
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    expect(find.text('SHELF'), findsOneWidget);
    // Read the way the arrows read: Inside, Sub-shelves, then Volumes.
    expect(find.text('INSIDE · 0'), findsOneWidget);
    expect(find.text('SUB-SHELVES · 1'), findsOneWidget);
    expect(find.text('VOLUMES · 2'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Open shelf'), findsOneWidget);
    expect(find.text('INSPECTOR'), findsNothing);

    // A relation chip moves the selection (and centres it).
    final pasta = find.text('Pasta Fundamentals');
    final onCanvas =
        find.descendant(of: viewer, matching: pasta).evaluate().toSet();
    final relation = pasta.evaluate().where((e) => !onCanvas.contains(e));
    expect(relation, hasLength(1), reason: 'the inspector lists Pasta');
    // The relation row scrolls sideways (§1.4); Volumes is its third section.
    final relationChip = find.byElementPredicate((x) => x == relation.first);
    await tester.ensureVisible(relationChip);
    await pumpFor(tester, total: const Duration(milliseconds: 400));
    await tester.tap(relationChip);
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('ON SHELVES · 1'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Open in reader'), findsOneWidget);

    // Activating the empty canvas clears.
    await tester.tapAt(emptyPoint());
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Open in reader'), findsNothing);

    // ── leaving, and focus on arrival ─────────────────────────────────────
    // Re-fit first: the relation chip centred Pasta, and Recipes sits a
    // column to its right, past a phone's canvas.
    await tester.tap(find.textContaining(RegExp(r'^\d+%$')));
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    await tester.tap(recipes);
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    await tester.tap(find.widgetWithText(KitButton, 'Open shelf'));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/shelves/seed-tag-recipes');
    // *See on map* is the shelf sheet's first *Also*: in the running head.
    await _dropHead(tester);
    final seeOnMap = find.widgetWithText(KitAlsoButton, 'See on map');
    expect(seeOnMap, findsOneWidget);
    await tester.tap(seeOnMap);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/shelves/map');
    // The focus rode navigation state, never the address (INV-25b).
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/shelves/map');
    expect(find.text('SHELF'), findsOneWidget);
    expect(find.text('VOLUMES · 2'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Open shelf'), findsOneWidget);
  });

  testWidgets("shelves List/Grid, a shelf's sheet, Search's filters sheet, "
      "Ask's composer growing to seven lines", (tester) async {
    // F-143 (direction D: library.md §Composition — Shelves and a shelf,
    // search.md and ask.md §Composition; kit §30 §32 §38). Real taps on the
    // phone's chrome: the tab bar's centre, the running heads, the switches.
    final router = await pumpApp(tester);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;

    // ── Shelves: List / Grid, the running head ─────────────────────────────
    router.go('/shelves');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitShelfCatalogue).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(milliseconds: 800));
    expect(
        find.descendant(
            of: find.byType(KitTabBar), matching: find.text('New shelf')),
        findsOneWidget,
        reason: "the page's action is the tab bar's centre");
    debugPrint('DEVICE-RUN F-143 shelves head "${_peekText(tester)}"');
    expect(_peekText(tester), contains('Recipes'),
        reason: 'the shelf in view, first');
    expect(_peekText(tester), contains('1 of 4'),
        reason: 'three shelves and Unshelved');

    // List → Grid → List: one app-wide choice, written before it moves.
    final toggle = find.byType(KitViewToggle);
    await tester.ensureVisible(toggle);
    await pumpFor(tester, total: const Duration(milliseconds: 400));
    await tester.tap(find.descendant(of: toggle, matching: find.text('Grid')));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.byType(KitShelfCovers), findsOneWidget);
    expect(find.byType(KitShelfCatalogue), findsNothing);
    expect(LocalFlags.sourceView.value, 'grid');
    debugPrint('DEVICE-RUN F-143 shelves Grid: '
        '${find.byType(KitCover).evaluate().length} covers');
    await tester.tap(find.descendant(of: toggle, matching: find.text('List')));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.byType(KitShelfCatalogue), findsOneWidget);
    expect(LocalFlags.sourceView.value, 'list');

    // The running head drops; choosing Stories moves the page and folds it.
    await _dropHead(tester);
    final stories =
        find.byKey(const ValueKey('shelves-sheet-seed-tag-stories'));
    expect(stories.hitTestable(), findsOneWidget,
        reason: 'the dropped sheet lists the shelves');
    await tester.tap(stories);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(stories.hitTestable(), findsNothing,
        reason: 'choosing a shelf folds the running head');
    debugPrint('DEVICE-RUN F-143 shelves head after Stories '
        '"${_peekText(tester)}"');
    expect(_peekText(tester), isNot(contains('1 of 4')),
        reason: 'the page moved on from Recipes');

    // ── A shelf's sheet ────────────────────────────────────────────────────
    router.go('/shelves/seed-tag-recipes');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('ALL SHELVES').evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(
        find.descendant(
            of: find.byType(KitTabBar), matching: find.text('Ask shelf')),
        findsOneWidget);
    debugPrint('DEVICE-RUN F-143 shelf head "${_peekText(tester)}"');
    expect(_peekText(tester), contains('Recipes'));
    expect(_peekText(tester), contains('RECENT'));
    await _dropHead(tester);
    // In the running head the mark is not drawn (the masthead says it);
    // Order, Sub-shelves, The shelf and Also are, in that order.
    expect(find.byKey(const ValueKey('shelf-identity')), findsNothing);
    final order = ['ORDER', 'SUB-SHELVES', 'THE SHELF', 'ALSO'];
    for (var i = 1; i < order.length; i++) {
      expect(tester.getTopLeft(find.text(order[i]).hitTestable()).dy,
          greaterThan(tester.getTopLeft(find.text(order[i - 1])).dy));
    }
    expect(find.byKey(const ValueKey('sub-shelf-seed-tag-baking')),
        findsOneWidget);
    // Delete shelf is the last Also, in the critical ink.
    final also = tester
        .widgetList<KitAlsoButton>(find.byType(KitAlsoButton))
        .map((b) => b.label)
        .toList();
    debugPrint('DEVICE-RUN F-143 shelf Also: $also');
    expect(also.last, 'Delete shelf');
    expect(
        tester
            .widget<KitAlsoButton>(
                find.widgetWithText(KitAlsoButton, 'Delete shelf'))
            .danger,
        isTrue);
    // Order: A–Z moves the volumes and the head's meta; the switch stays
    // where the reader is (it is not a row the page folds on).
    await tester.tap(find.text('A–Z').hitTestable());
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(_peekText(tester), contains('A–Z'));
    // New sub-shelf opens the create form ABOVE the running head (W3's
    // FOUND 1: a sheet under the head took no taps), with Inside set.
    await tester.tap(find.text('New sub-shelf').hitTestable());
    await pumpFor(tester, total: const Duration(seconds: 1));
    final nameField = find.byType(TextField).hitTestable();
    expect(nameField, findsWidgets,
        reason: "the create form's field is on top and takes a tap");
    expect(find.textContaining('Recipes').hitTestable(), findsWidgets,
        reason: 'Inside is this shelf');
    await tester.tap(find.text('Cancel').hitTestable().first);
    await pumpFor(tester, total: const Duration(seconds: 1));

    // ── Nested shelves (F-131's device proof, folded into F-143) ───────────
    // A sub-shelf from the sheet's Sub-shelves; its crumb names the parent.
    await _dropHead(tester);
    await tester.tap(find
        .byKey(const ValueKey('sub-shelf-seed-tag-baking'))
        .hitTestable());
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/shelves/seed-tag-baking');
    expect(find.text('RECIPES'), findsOneWidget,
        reason: 'the crumb: All shelves, then Recipes');
    debugPrint('DEVICE-RUN F-143 sub-shelf head "${_peekText(tester)}"');
    // Move into, write before you move: Finance into Recipes, and back.
    router.go('/shelves/seed-tag-finance');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('ALL SHELVES').evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(find.text('RECIPES'), findsNothing, reason: 'Finance is top level');
    try {
      await _openPageSettings(tester, 'Shelf settings');
      final select = find.byType(KitShelfSelect);
      await tester.ensureVisible(select);
      await pumpFor(tester, total: const Duration(milliseconds: 400));
      await tester.tap(select);
      await pumpFor(tester, total: const Duration(milliseconds: 800));
      await tester.tap(find.text('Recipes').hitTestable().last);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('RECIPES').evaluate().isNotEmpty) break;
      }
      debugPrint('DEVICE-RUN F-143 move into: crumb '
          '${find.text('RECIPES').evaluate().length}, refusal '
          '${find.byType(KitFailureInline).evaluate().length}');
      expect(find.text('RECIPES'), findsOneWidget,
          reason: 'the stored parent came back on the subscription: the '
              'crumb names it');
      await tester.tap(select);
      await pumpFor(tester, total: const Duration(milliseconds: 800));
      await tester.tap(find.text('Top level').hitTestable().last);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('RECIPES').evaluate().isEmpty) break;
      }
      expect(find.text('RECIPES'), findsNothing,
          reason: 'back to the top level');
    } finally {
      // Put the seed back, whatever happened above.
      await Api.instance.updateTag('seed-tag-finance', {'parentTagId': null});
    }

    // ── Search's Filters sheet ─────────────────────────────────────────────
    router.go('/search');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey('search-field')).evaluate().isNotEmpty) {
        break;
      }
    }
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    // The field stays in the masthead on a phone, under the standfirst.
    final field = find.byKey(const ValueKey('search-field'));
    expect(field.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(field).dy, lessThan(view.height / 2));
    debugPrint('DEVICE-RUN F-143 search head "${_peekText(tester)}"');
    expect(_peekText(tester), contains('All sources'));
    await _dropHead(tester);
    final youtube = find
        .descendant(of: find.byType(KitFacet), matching: find.text('YouTube'))
        .hitTestable();
    expect(youtube, findsOneWidget, reason: 'the Kind facet, dropped');
    expect(find.text('READ AS').hitTestable(), findsOneWidget,
        reason: 'Read as, while generative AI is on');
    await tester.tap(youtube);
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(youtube, findsNothing, reason: 'choosing a kind folds the head');
    debugPrint('DEVICE-RUN F-143 search head after YouTube '
        '"${_peekText(tester)}"');
    expect(_peekText(tester), contains('YouTube'));
    // Put the kind back for whoever searches next.
    await _dropHead(tester);
    await tester.tap(find
        .descendant(
            of: find.byType(KitFacet), matching: find.text('All sources'))
        .hitTestable());
    await pumpFor(tester, total: const Duration(seconds: 1));

    // ── Ask's composer: one line, then up to 172 and no further ────────────
    router.go('/ask');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(KitGrowField).evaluate().isNotEmpty) break;
    }
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final grow = find.byType(KitGrowField);
    expect(grow, findsOneWidget);
    final input = find.descendant(of: grow, matching: find.byType(TextField));
    double h() => tester.getSize(input).height;
    final one = h();
    final heights = <int, double>{};
    for (final n in [1, 3, 5, 7, 9]) {
      await tester.enterText(
          input, [for (var i = 1; i <= n; i++) 'Line $i of a question'].join('\n'));
      await pumpFor(tester, total: const Duration(milliseconds: 500));
      heights[n] = h();
    }
    debugPrint('DEVICE-RUN F-143 ask composer heights one=$one $heights');
    expect(one, lessThan(48), reason: 'one line tall while empty');
    expect(heights[3]!, greaterThan(heights[1]!));
    expect(heights[5]!, greaterThan(heights[3]!));
    expect(heights[7]!, lessThanOrEqualTo(172.5),
        reason: 'it grows to about seven lines, 172px');
    expect(heights[9]!, lessThanOrEqualTo(172.5),
        reason: 'then scrolls inside');
    // The composer docks above the tab bar.
    final bar = tester.getTopLeft(find.byType(KitTabBar)).dy;
    expect(tester.getBottomLeft(input).dy, lessThanOrEqualTo(bar),
        reason: 'the composer docks above the tab bar');
    await tester.enterText(input, '');
    await pumpFor(tester, total: const Duration(milliseconds: 400));
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
    // The three moves, by what they say: in D a ruled list of each move's
    // CONTENT (kit_empty `_MoveGroup.row`), so the KitNumberedMove widgets
    // themselves are never in the tree.
    for (final title in ['One subject at a time',
        'It arrives as its own session', 'Recall first, then grade yourself']) {
      expect(find.text(title), findsOneWidget, reason: 'no "$title" move');
    }
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
        if (find.text('Device run — braising').evaluate().isNotEmpty) break;
      }
      await pumpFor(tester, total: const Duration(seconds: 1));

      // §Composition in D (F-145) — the masthead with the `Deep study · N
      // programs · N on` folio, then the programs as a ruled register: no
      // card.
      expect(find.byType(KitMasthead), findsOneWidget);
      expect(find.textContaining('DEEP STUDY\u00a0· 1 PROGRAM'), findsOneWidget);
      expect(find.text('Study Programs'), findsOneWidget);
      expect(find.text('Device run — braising'), findsOneWidget);
      expect(find.byType(KitCard), findsNothing);

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
      // The card is web's `.st-prog` (68a3c0d): its status is `.st-chip`
      // (KitStudyChip), not the generic §6.2 pill.
      expect(find.byType(KitProgramCard), findsOneWidget);
      expect(find.byType(KitStudyChip), findsOneWidget);
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
  // F-72 (4.100.0, ADR-135, INV-30): For your review is reached from the
  // drawer — under Home, carrying §1.2's attention count — and a failed source
  // leaves it by DISMISS, which changes nothing but `review_dismissed_at`. The
  // row leaves when the subscription says so, never on the press (write before
  // you move). Mutates the seed: run it after the screenshot holds.
  testWidgets('signs in, opens For your review from the drawer, dismisses a failed source',
      (tester) async {
    final router = await pumpApp(tester);
    router.go('/');
    for (var i = 0; i < 60; i++) {
      if (find.byIcon(Icons.menu).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.byIcon(Icons.menu));
    await pumpFor(tester, total: const Duration(seconds: 2));
    final item = find.widgetWithText(KitNavItem, 'For your review');
    expect(item, findsOneWidget,
        reason: 'For your review is not in the rail under Home');
    // The rail's count is measured (the dash is INV-30's unmeasured state).
    final countBefore = tester.widget<KitNavItem>(item).badge;
    expect(countBefore, isNotNull,
        reason: 'the seed has sources that need the reader; the rail says none');
    await tester.tap(item);
    await pumpFor(tester, total: const Duration(seconds: 3));
    expect(router.state.matchedLocation, '/review');
    expect(find.textContaining(RegExp(r'^Sources that need you', caseSensitive: false)),
        findsOneWidget);

    final rows = find.byType(ProcessingRow);
    for (var i = 0; i < 40; i++) {
      if (rows.evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(rows, findsWidgets, reason: 'no source needs the reader — check the seed');
    final first = tester.widget<ProcessingRow>(rows.first);
    final key = find.byKey(ValueKey('review-src-${first.doc.id}'));
    final dismiss = find.descendant(of: key, matching: find.text('Dismiss'));
    await tester.ensureVisible(dismiss);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await tester.tap(dismiss);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (key.evaluate().isEmpty) break;
    }
    expect(key, findsNothing,
        reason: 'the dismissed source is still on For your review');
    expect(find.byType(KitFailureInline), findsNothing,
        reason: 'the dismiss was refused');
    // Dismissing never deletes: the source is still in the Library.
    final stillThere = await FirebaseFirestore.instance
        .collection('documents')
        .doc(first.doc.id)
        .get();
    expect(stillThere.exists, isTrue);
    expect(stillThere.data()?['review_dismissed_at'], isNotNull);
  });

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
      expect(find.textContaining('Step 1 of 6'), findsOneWidget);

      // The welcome step: mark, folio, the accent-claused title, standfirst,
      // onboarding's own `.ob-rule` (not §2.1's two bars, F-80 (4)), and the
      // three moves.
      expect(find.byType(ChapterOpening), findsOneWidget);
      expect(find.byType(ChapterRule), findsNothing);
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
      expect(find.textContaining('№ 01 · OF 04'), findsOneWidget);

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

  // F-36 · settings.md §Plan row (4.79.0, ADR-113, INV-28). The Tier-1 suite
  // proves the WORDS over the captured fixtures; this proves the row is on the
  // screen, drawing what the endpoint measured, and that the §12 notice's one
  // action goes where it says.
  //
  // The cap is driven by writing `config/plans` — a document no client may read
  // or write (INV-28), so it goes in through the emulator's REST API with the
  // `owner` bearer, the same bypass the harness and theme-shots.mjs use.
  //
  // `_plan_limits()` caches that document for 60s PER BACKEND INSTANCE, so a
  // write is not visible to the next request: the poll below is that TTL, not
  // slack. Racing it would make this test pass or fail on where in the minute
  // it happened to start.
  testWidgets(
      "Settings shows the Plan row with the endpoint's figures; a free account "
      'at a cap of 1 shows the §12 notice and its one action opens support',
      (tester) async {
    const port = String.fromEnvironment('EMULATOR_FIRESTORE_PORT',
        defaultValue: '8080');
    final rest = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:$port/v1/projects/noteletter-7a111'
          '/databases/(default)/documents',
      headers: {'Authorization': 'Bearer owner'},
      validateStatus: (_) => true,
    ));
    Future<void> writeCap(int maxDocuments) => rest.patch('/config/plans', data: {
          'fields': {
            'free': {
              'mapValue': {
                'fields': {
                  'max_documents': {'integerValue': '$maxDocuments'},
                  'max_ingests_per_month': {'integerValue': '40'},
                  'audio_narration': {'booleanValue': false},
                },
              },
            },
          },
        });

    try {
      final router = await pumpApp(tester);
      router.go('/settings');
      await tester.pump(const Duration(milliseconds: 400));

      // The row, with figures the endpoint measured. `\d+ of \d+ sources` is
      // the assertion that matters: the unanswered state draws the title
      // `Plan` and NO figures (ADR-109), so a row that never got an answer
      // cannot satisfy this.
      final figures = find.textContaining(RegExp(r'\d+ of \d+ sources'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (figures.evaluate().isNotEmpty) break;
      }
      expect(figures, findsOneWidget,
          reason: 'the Plan row drew no measured figure — fn_plan_status did '
              'not answer, or the row counted nothing of its own');
      expect(find.text('Free plan'), findsOneWidget);
      await tester.ensureVisible(figures);
      await tester.pump(const Duration(milliseconds: 200));

      // Now the cap. One source is below the seed library, so the condition is
      // real rather than simulated.
      await writeCap(1);
      final notice = find.textContaining("Your library is at the free plan's");
      // Up to ~75s: the 60s limits cache plus a margin. Each pass remounts the
      // row by leaving the screen and coming back, which re-issues the request
      // — the row does not poll, and nothing else would make it ask again.
      for (var i = 0; i < 15 && notice.evaluate().isEmpty; i++) {
        router.go('/');
        await tester.pump(const Duration(milliseconds: 600));
        router.go('/settings');
        for (var j = 0; j < 18; j++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (notice.evaluate().isNotEmpty) break;
        }
      }
      expect(notice, findsOneWidget,
          reason: 'at the cap the §12 notice is the surface that says why — '
              'the row alone states a figure and no consequence');
      expect(find.byType(KitNotice), findsWidgets);

      // Its ONE action, and where it goes. There is no checkout, so support is
      // the honest destination (§13) — and a notice whose action went nowhere
      // would look identical on a screenshot.
      final action = find.widgetWithText(KitButton, 'Ask about upgrading');
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(action);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (router.routerDelegate.currentConfiguration.uri.path == '/support') {
          break;
        }
      }
      expect(router.routerDelegate.currentConfiguration.uri.path, '/support');
    } finally {
      // Put the plan back. A left-over cap of 1 would refuse every ingest in
      // whichever test ran next, and the emulator suite outlives this file.
      await rest.delete('/config/plans');
    }
  });
  // F-140 (5.42.0, direction D; kit §1.2, §26–§30): the D shell on a phone.
  // The first half drives the REAL app: the app header (menu, Search pill, no
  // wordmark), the tab bar and its default middle action, and the drawer's
  // compact rail with the Reader's card. The second half mounts a D page inside
  // the real shell widgets (SupportShell → AppLayout) with the app's own
  // providers, because no screen is ported to D yet (F-141..F-145): the page's
  // registered action reaches the tab bar's centre, its settings panel drops
  // from the header, and the running head opens and folds by real taps.
  testWidgets(
      "the app header, the tab bar's middle action, the running head opening "
      "and folding, the drawer's compact rail and Reader's card",
      (tester) async {
    await LocalFlags.setOnboarded(true);
    KitPageTools.instance.reset();
    final router = await pumpApp(tester);
    router.go('/');
    for (var i = 0; i < 60; i++) {
      if (find.byType(KitAppHeader).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    await pumpFor(tester, total: const Duration(seconds: 1));

    // ── the app header (§30): menu · Search pill · (the page's settings) ──
    expect(find.byType(KitAppHeader), findsOneWidget,
        reason: 'the D app header replaces the pre-D phone app bar');
    expect(tester.getSize(find.byType(KitAppHeader)).height,
        greaterThanOrEqualTo(54));
    expect(find.byType(KitBrand), findsNothing,
        reason: 'the D app header draws no wordmark');
    final pill = find.byKey(const ValueKey('d-header-search'));
    expect(pill, findsOneWidget);
    expect(find.text('Search your library…'), findsOneWidget);

    // ── the tab bar (§30): Home, Library, the action, Letters, Ask ──
    final bar = find.byType(KitTabBar);
    expect(bar, findsOneWidget);
    for (final l in ['Home', 'Library', 'Add', 'Letters', 'Ask']) {
      expect(find.descendant(of: bar, matching: find.text(l)), findsOneWidget,
          reason: 'the tab bar has no "$l"');
    }
    final barRect = tester.getRect(bar);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(barRect.bottom, closeTo(view.height, 1),
        reason: 'the tab bar is fixed at the foot');
    debugPrint('DEVICE-RUN F-140 header ${tester.getSize(find.byType(KitAppHeader))} '
        'tabbar $barRect view $view');

    // The Search pill opens Search (this client has no quick-search overlay).
    await tester.tap(pill);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/search');

    // A destination tab, and the active tab's colour.
    await tester.tap(find.byKey(const ValueKey('d-tab-Letters')));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/letters');

    // The middle action: no page registers one yet, so it is Add — named
    // "Add a source" — and it opens Add a source (the Library's uploader).
    final centre = find.byKey(const ValueKey('d-tab-action'));
    expect(find.descendant(of: centre, matching: find.text('Add')),
        findsOneWidget);
    await tester.tap(centre);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/sources',
        reason: "the tab bar's default action is Add a source");

    // ── the drawer: the compact rail and the Reader's card (§1.2) ──
    Future<void> openDrawer() async {
      await tester.tap(find.byIcon(Icons.menu));
      await pumpFor(tester, total: const Duration(seconds: 2));
      expect(find.byType(KitChromeRail), findsOneWidget);
    }

    await openDrawer();
    final rail = find.byType(KitChromeRail);
    Finder inRail(String t) =>
        find.descendant(of: rail, matching: find.text(t));
    for (final l in [
      'Home',
      'For your review',
      'KNOWLEDGE',
      'Library',
      'Ask',
      'Shelves',
      'PRACTICE',
      'Letters',
      'Study',
    ]) {
      expect(inRail(l), findsWidgets, reason: 'the compact rail has no "$l"');
    }
    for (final gone in ['Search', 'All shelves', 'Settings', 'Letter settings']) {
      expect(inRail(gone), findsNothing,
          reason: 'the compact rail draws no "$gone" row');
    }
    expect(find.descendant(of: rail, matching: find.byType(KitRailShelfRow)),
        findsNothing,
        reason: 'the compact rail draws no shelf tree');
    expect(find.bySemanticsLabel('New shelf'), findsOneWidget,
        reason: "the Shelves row's + is drawn whatever the library holds");
    final card = find.byType(KitReaderCard);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('READER’S CARD')),
        findsOneWidget);
    // Its stub: the count from the ONE activity subscription — measured once
    // the feed has answered (a number), the dash before it and when refused.
    final ctx = tester.element(rail);
    final activity = Provider.of<ActivityNotifier>(ctx, listen: false);
    for (var i = 0; i < 40 && !activity.answered; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    final count = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('reader-card-count')),
        matching: find.byType(Text)));
    final expected = activity.error != null || !activity.answered
        ? '—'
        : (() {
            final n = activity.unreadSince(LocalFlags.activityLastSeen.value);
            return n > 999 ? '999+' : '$n';
          })();
    debugPrint('DEVICE-RUN F-140 reader card count="${count.data}" '
        'expected="$expected" answered=${activity.answered} '
        'latest="${activity.latestEvent?.title}"');
    expect(count.data, expected,
        reason: 'the stub shows the count the feed computes (the dash, never 0, '
            'when it cannot)');

    // The main part opens Settings; the stub opens Activity.
    await tester.tap(find.byKey(const ValueKey('reader-card-settings')));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/settings');
    await openDrawer();
    await tester.tap(find.byKey(const ValueKey('reader-card-activity')));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/activity');

    // ── a D page in the real shell: the action, the panel, the running head ──
    final sec = KitSections(['first', 'second']);
    const items = [
      KitContentsItem('first', 'First section', count: '12'),
      KitContentsItem('second', 'Second section'),
    ];
    var acted = 0;
    final auth = AuthNotifier();
    final dRouter = GoRouter(routes: [
      ShellRoute(
        builder: (context, state, child) =>
            SupportShell(route: state.matchedLocation, child: child),
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppLayout(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => KitDPage(
                  folio: '§ Device run · two sections',
                  title: 'The *running* head',
                  stand: 'A D page inside the real shell.',
                  action: KitPageAction(
                      label: 'Write a letter',
                      short: 'Write',
                      icon: Icons.edit_outlined,
                      onPressed: () => acted++),
                  settings: KitPageSettings(
                    label: 'Page settings',
                    body: (context, close) => const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KitDLabel('Show sources as', top: 18),
                        KitViewToggle(),
                      ],
                    ),
                  ),
                  sections: sec,
                  sheet: KitDSheet(
                    label: 'On this page',
                    foldOnPick: true,
                    peek: KitSecPeek(items: items, sections: sec),
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KitDLabel('Contents', first: true),
                        KitContents(items: items, sections: sec),
                        const KitFigures(
                            rows: [('Sources', '41'), ('Unread', '—')]),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KitSecHead(
                          key: sec.keyOf('first'), n: 0, title: 'First section'),
                      const SizedBox(height: 1400),
                      KitSecHead(
                          key: sec.keyOf('second'),
                          n: 1,
                          title: 'Second section'),
                      const SizedBox(height: 1400),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(auth),
      child: NoteLetterApp(router: dRouter),
    ));
    await pumpFor(tester, total: const Duration(seconds: 3));
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.byType(KitSearchField), findsNothing,
        reason: 'at 1024 and under the masthead rail keeps only its folio');
    expect(find.text('§ DEVICE RUN · TWO SECTIONS'), findsOneWidget);

    // The page's action at the tab bar's centre, by its short label.
    expect(find.descendant(of: centre, matching: find.text('Write')),
        findsOneWidget,
        reason: "the tab bar's centre is the page's registered action");
    await tester.tap(centre);
    await tester.pump();
    expect(acted, 1, reason: "the centre called the page's handler");

    // Its settings: the gear in the header opens the panel; the scrim closes.
    final gear = find.descendant(
        of: find.byType(KitAppHeader),
        matching: find.bySemanticsLabel('Page settings'));
    expect(gear, findsOneWidget,
        reason: "the header draws the page's settings it registered");
    await tester.tap(gear);
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('d-panel')), findsOneWidget);
    expect(find.byType(KitViewToggle), findsOneWidget);
    final panelTop = tester.getTopLeft(find.byKey(const ValueKey('d-panel'))).dy;
    final headerBottom = tester.getBottomLeft(find.byType(KitAppHeader)).dy;
    expect(panelTop, closeTo(headerBottom, 1),
        reason: 'the panel drops from the app header, full width');
    await tester.tapAt(Offset(view.width / 2, view.height - 140));
    await pumpFor(tester, total: const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('d-panel')), findsNothing,
        reason: 'the scrim closes the panel');

    // The running head: one line under the header, `§ I · … · 1 of 2`.
    final peek = find.byKey(const ValueKey('d-peek'));
    expect(peek, findsOneWidget);
    expect(tester.getTopLeft(peek).dy, closeTo(headerBottom, 1),
        reason: 'the running head is fixed under the app header');
    expect(tester.getSize(peek).height, greaterThanOrEqualTo(46));
    expect(find.textContaining('1 of 2', findRichText: true), findsOneWidget);
    final row2 = find.bySemanticsLabel('II Second section');
    expect(row2, findsNothing, reason: 'folded, its body is inert');

    Future<void> drop() async {
      await tester.tap(peek);
      await pumpFor(tester, total: const Duration(milliseconds: 750));
      expect(row2, findsOneWidget, reason: 'tapping the line drops the sheet');
    }

    // The line folds it.
    await drop();
    await tester.tap(peek);
    await pumpFor(tester, total: const Duration(milliseconds: 750));
    expect(row2, findsNothing, reason: 'the line folds it');

    // The scrim folds it.
    await drop();
    await tester.tapAt(Offset(view.width / 2, view.height - 140));
    await pumpFor(tester, total: const Duration(milliseconds: 750));
    expect(row2, findsNothing, reason: 'the scrim folds it');

    // A Contents row folds it AND moves the page to its section.
    await drop();
    await tester.tap(row2);
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(row2, findsNothing, reason: 'choosing a row the page names folds it');
    expect(sec.current, 'second');
    expect(find.textContaining('2 of 2', findRichText: true), findsOneWidget,
        reason: 'the line says where the reader is now');
    expect(tester.takeException(), isNull);
  });

  // F-141 (5.42.0, direction D; screens/library.md and sources.md
  // §Composition): Home, the Library and their states on the REAL app, by
  // real taps. Home: the edition's masthead, the running head's Contents
  // moving the page, the desk ledger, the sections in order. The Library: a
  // Kind facet narrowing the catalogue and the peek saying so, the A–Z order,
  // List ↔ Grid following across Home and the Library. Then a fresh account:
  // the empty state on both pages, and — one document arriving — the
  // first-reading state on both, with nothing claimed that was not measured.
  testWidgets(
      "Home's sections, the Library's facets and List/Grid, empty and "
      'first-reading states', (tester) async {
    await LocalFlags.setOnboarded(true);
    await LocalFlags.setSourceView('list');
    KitPageTools.instance.reset();
    final router = await pumpApp(tester);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    final peek = find.byKey(const ValueKey('d-peek'));
    // Home's section head, never its Contents row of the same name.
    final recentHead = find.descendant(
        of: find.byType(KitSectionHead), matching: find.text('Recently added'));
    Finder byType(String name) =>
        find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
    Future<void> waitFor(Finder f, String what, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 4 && f.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(f, findsWidgets, reason: 'never drew $what');
    }

    // A route change keeps the page it leaves mounted until its transition
    // ends — two running heads, two scrims — so every step waits for one.
    Future<void> oneHead() async {
      for (var i = 0; i < 40 && peek.evaluate().length != 1; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(peek, findsOneWidget, reason: 'the page change never finished');
    }

    // The running head's body stays mounted folded (inert, kit §30): its
    // state is the scrim's — live only while the head is dropped.
    bool dropped() => !tester
        .widget<IgnorePointer>(find
            .ancestor(
                of: find.byKey(const ValueKey('d-dock-scrim')),
                matching: find.byType(IgnorePointer))
            .first)
        .ignoring;
    Future<void> drop() async {
      if (!dropped()) await tester.tap(peek);
      await pumpFor(tester, total: const Duration(milliseconds: 750));
      expect(dropped(), isTrue, reason: 'tapping the line drops the sheet');
    }

    Future<void> fold() async {
      if (dropped()) {
        await tester.tapAt(Offset(view.width / 2, view.height - 140));
        await pumpFor(tester, total: const Duration(milliseconds: 750));
      }
      expect(dropped(), isFalse, reason: 'the scrim folds the sheet');
    }

    // ── Home ──
    router.go('/');
    await waitFor(find.byType(KitDPage), 'the D page on Home');
    await waitFor(find.textContaining(kitGreeting(), findRichText: true),
        'the greeting');
    await oneHead();
    final folio = find.textContaining('SOURCES ·', findRichText: true);
    await waitFor(folio, "the folio's figures");
    final folioText = tester.widget<KitMasthead>(find.byType(KitMasthead)).folio;
    debugPrint('DEVICE-RUN F-141 home folio "$folioText"');
    expect(folioText, matches(RegExp(r' · [\d,]+ sources? · [\d,]+ passages?$')),
        reason: 'the documents read answered: the folio is measured');
    // The running head: § I · The letter, and its Contents.
    expect(peek, findsOneWidget);
    expect(tester.getTopLeft(peek).dy,
        closeTo(tester.getBottomLeft(find.byType(KitAppHeader)).dy, 1));
    expect(find.descendant(of: peek, matching: find.textContaining('The letter')),
        findsWidgets, reason: 'Home opens at § I, the letter');
    await drop();
    for (final l in ['The letter', 'Recently added', 'The shelves']) {
      expect(find.descendant(of: find.byType(KitContents), matching: find.text(l)),
          findsOneWidget, reason: 'Contents lacks "$l"');
    }
    expect(find.text('ON YOUR DESK'), findsOneWidget,
        reason: 'the desk ledger is the sheet’s figures');
    debugPrint('DEVICE-RUN F-141 ledger: review '
        '${find.text('set aside for your review').evaluate().isNotEmpty ? 'drawn' : 'absent'}'
        ', being read '
        '${find.textContaining('being read').evaluate().isNotEmpty ? 'drawn' : 'absent'}');
    // Choosing The shelves folds the head and moves the page there.
    await tester.tap(find.descendant(
        of: find.byType(KitContents), matching: find.text('The shelves')));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(dropped(), isFalse,
        reason: 'choosing a Contents row folds the running head');
    expect(find.descendant(of: peek, matching: find.textContaining('The shelves')),
        findsWidgets, reason: 'the line says the page is at The shelves');
    expect(find.text('Suggest shelves'), findsOneWidget);
    expect(find.text('All shelves →'), findsOneWidget);
    // Home's action is Add a source, at the tab bar's centre.
    final centre = find.byKey(const ValueKey('d-tab-action'));
    expect(find.descendant(of: centre, matching: find.text('Add')), findsOneWidget);
    await tester.tap(centre);
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(router.state.matchedLocation, '/sources/add');
    await oneHead();
    expect(find.text('Add to Your Library'), findsOneWidget);

    // ── the Library: a facet, an order, List ↔ Grid ──
    router.go('/sources');
    await waitFor(find.text('The Library'), 'the Library');
    await waitFor(find.textContaining('VOLUMES ·', findRichText: true),
        "the Library's folio");
    await waitFor(find.text('The catalogue'), 'the catalogue');
    await oneHead();
    expect(find.text('Correspondence'), findsOneWidget);
    expect(find.descendant(of: peek, matching: find.text('All volumes')),
        findsOneWidget, reason: 'the peek names what is showing');
    await drop();
    final youtube = find.descendant(
        of: find.byType(KitFacet), matching: find.textContaining('YouTube'));
    expect(youtube, findsWidgets, reason: 'the Kind facet lacks YouTube');
    await tester.tap(youtube.first);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await fold();
    expect(find.descendant(of: peek, matching: find.text('YouTube')),
        findsOneWidget, reason: 'the peek names the facet chosen');
    await tester.ensureVisible(find.text('The catalogue'));
    await pumpFor(tester, total: const Duration(milliseconds: 500));
    expect(find.text('Dragon Story Readthrough'), findsWidgets);
    expect(find.text('Quarterly Tax Summary'), findsNothing,
        reason: 'the facet narrows the catalogue');
    // Back to every kind, then A–Z: the jump letters.
    await drop();
    await tester.tap(find
        .descendant(of: find.byType(KitFacet), matching: find.textContaining('All'))
        .first);
    await pumpFor(tester, total: const Duration(milliseconds: 750));
    await drop();
    await tester.tap(find.text('A–Z').first);
    await pumpFor(tester, total: const Duration(seconds: 1));
    await fold();
    expect(find.bySemanticsLabel('Jump to a letter'), findsWidgets,
        reason: 'ordered A–Z, the register files under initials');
    // Grid: the wall, and the choice follows to Home.
    await tester.ensureVisible(find.text('The catalogue'));
    await pumpFor(tester, total: const Duration(milliseconds: 500));
    await tester.tap(find.descendant(
        of: find.byType(KitViewToggle), matching: find.bySemanticsLabel('Grid')).first);
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(LocalFlags.sourceView.value, 'grid');
    expect(byType('KitLibWall'), findsOneWidget, reason: 'Grid is the wall');
    router.go('/');
    await waitFor(recentHead, 'Recently added');
    await oneHead();
    await tester.ensureVisible(recentHead);
    await pumpFor(tester, total: const Duration(milliseconds: 500));
    expect(find.byType(KitCoverStrip), findsOneWidget,
        reason: 'List / Grid is one choice: Home follows the Library');
    await LocalFlags.setSourceView('list');
    await pumpFor(tester, total: const Duration(milliseconds: 500));

    // ── a fresh account: empty, then first reading ──
    final email =
        'f141-${DateTime.now().microsecondsSinceEpoch}@noteletter.test';
    await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'f141-run-1');
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      KitPageTools.instance.reset();
      // Firestore takes the new user's credential a beat after the switch: a
      // listener opened in that beat is refused as the OLD user. A reader
      // signs in through a screen, never in the same instant as a read.
      await FirebaseAuth.instance.currentUser!.getIdToken(true);
      await pumpFor(tester, total: const Duration(seconds: 2));
      final fresh = await pumpApp(tester);
      fresh.go('/sources');
      await waitFor(find.textContaining('Nothing here yet.'), 'the empty standfirst');
      await oneHead();
      expect(find.descendant(of: peek, matching: find.text('What you can add')),
          findsOneWidget, reason: 'an empty library offers what it can take');
      expect(find.textContaining('0 VOLUMES', findRichText: true), findsWidgets,
          reason: 'a measured 0 is drawn');
      await waitFor(find.text('Drop files to begin'), 'the drop zone');
      expect(byType('KitLibRegister'), findsNothing);
      fresh.go('/');
      KitMasthead? mast() {
        final m = find.byType(KitMasthead).evaluate();
        return m.length == 1 ? m.single.widget as KitMasthead : null;
      }

      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final m = mast();
        if (m != null && (m.stand ?? '').startsWith('Your library is empty')) {
          break;
        }
      }
      final ctx = tester.element(find.byType(KitMasthead).first);
      final d = Provider.of<DocumentsNotifier>(ctx, listen: false);
      final tg = Provider.of<TagsNotifier>(ctx, listen: false);
      debugPrint('DEVICE-RUN F-141 fresh Home folio "${mast()?.folio}" '
          'stand "${mast()?.stand}" docs loading=${d.loading} '
          'error=${d.error} n=${d.documents.length} tags loading=${tg.loading} '
          'error=${tg.error} uid=${FirebaseAuth.instance.currentUser?.uid}');
      expect(mast()?.stand,
          startsWith('Your library is empty for now. Bring in what you’ve read'),
          reason: "Home's empty standfirst");
      await oneHead();
      expect(
          find.descendant(
              of: find.byType(KitSectionHead),
              matching: find.text('Your first sources')),
          findsOneWidget);
      expect(find.text('Your first letter is waiting on your library'),
          findsOneWidget);
      expect(recentHead, findsNothing,
          reason: 'an empty library draws no Recently added');

      // One document arrives (the rules let its owner create it): the
      // library is reading, and nothing has finished.
      final ref = FirebaseFirestore.instance.collection('documents').doc();
      await ref.set({
        'user_id': uid,
        'title': 'F-141 Arrival',
        'type': 'pdf',
        'status': 'processing',
        'processing_stage': 'embedding',
        'created_at': FieldValue.serverTimestamp(),
        'view_count': 0,
        'tag_ids': <String>[],
      });
      await waitFor(recentHead, 'Recently added while reading');
      await tester.ensureVisible(recentHead);
      await pumpFor(tester, total: const Duration(milliseconds: 500));
      expect(find.text('F-141 Arrival'), findsWidgets,
          reason: 'before anything finished, Recently added lists arrivals');
      expect(find.text('ONE BEING READ'), findsOneWidget,
          reason: "Recently added's meta counts what is being read");
      expect(find.byKey(const ValueKey('d-first-dz')), findsNothing,
          reason: 'a reading library offers no first sources');
      fresh.go('/sources');
      await waitFor(find.textContaining('Nothing has finished reading yet.'),
          'the reading catalogue');
      await oneHead();
      expect(find.textContaining('One volume is being read now.'), findsOneWidget);
      expect(find.text('Being catalogued'), findsOneWidget);
      expect(find.text('Drop files to begin'), findsNothing,
          reason: 'a reading library is not empty');
      debugPrint('DEVICE-RUN F-141 fresh account $uid: empty → reading');
    } finally {
      await FirebaseAuth.instance.currentUser?.delete();
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
    }
    expect(tester.takeException(), isNull);
  });

  // F-145 (5.42.0, ADR-197; screens/study.md, activity.md, review.md
  // §Composition): the three pages in direction D on a phone, by real taps —
  // Study programs (a program made through the endpoint, a session of it
  // written as the build writes one), the session's sheet in the running head
  // (Answered, the questions with the NEXT one marked, the keys; a question
  // row jumping the column), Activity's When rows jumping to a day while a
  // Kind keeps the head open, and For your review's empty state in a fresh
  // account.
  testWidgets(
      "study programs and a session's sheet, Activity's When filter, the "
      'review empty state', (tester) async {
    final head = find.byKey(const ValueKey('d-peek'));
    Future<void> waitFor(Finder f, String what, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 4 && f.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(f, findsWidgets, reason: 'never drew $what');
    }

    Future<void> toggleHead() async {
      await tester.tap(head);
      await pumpFor(tester, total: const Duration(milliseconds: 1200));
    }

    bool headOpen() =>
        find.byKey(const ValueKey('d-dock-scrim')).hitTestable().evaluate()
            .isNotEmpty;

    /// The top of [f] below the top of the primary scroller it sits in.
    double underTop(Finder f) {
      // The nearest scroller: the page's primary one.
      final sc = find.ancestor(of: f, matching: find.byType(Scrollable)).first;
      return tester.getTopLeft(f).dy - tester.getTopLeft(sc).dy;
    }

    const port = String.fromEnvironment('EMULATOR_FIRESTORE_PORT',
        defaultValue: '8080');
    final rest = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:$port/v1/projects/noteletter-7a111'
          '/databases/(default)/documents',
      headers: {'Authorization': 'Bearer owner'},
      validateStatus: (_) => true,
    ));
    Map<String, dynamic> fs(Object? v) => switch (v) {
          null => {'nullValue': null},
          bool b => {'booleanValue': b},
          int n => {'integerValue': '$n'},
          DateTime d => {'timestampValue': d.toUtc().toIso8601String()},
          String t => {'stringValue': t},
          List l => {
              'arrayValue': {
                'values': [for (final e in l) fs(e)],
              },
            },
          Map m => {
              'mapValue': {
                'fields': {for (final e in m.entries) '${e.key}': fs(e.value)},
              },
            },
          _ => {'stringValue': '$v'},
        };

    KitPageTools.instance.reset();
    final router = await pumpApp(tester);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // ── Study programs ──
    router.go('/study');
    await waitFor(find.textContaining('DEEP STUDY'), 'the study masthead');
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(KitPageTools.instance.action?.short, 'New program',
        reason: "New program is the tab bar's centre");
    final created = await Api.instance.createStudyProgram({
      'title': 'F-145 — braising',
      'documentIds': ['seed-doc-article-complete'],
      'deliveryTime': '07:00',
      'timezone': 'America/Chicago',
      'frequency': 'daily',
    });
    final programId = (created['program'] as Map?)?['id'] as String?;
    final sessionId = 'f145-${DateTime.now().millisecondsSinceEpoch}';
    try {
      expect(programId, isNotNull);
      await waitFor(find.text('F-145 — braising'), 'the program');
      expect(find.byType(KitCard), findsNothing,
          reason: 'the programs are a ruled register in D');
      // A session as the build writes one: sent, three questions, one graded.
      final wrote = await rest.patch('/study_sessions/$sessionId', data: {
        'fields': {
          'user_id': fs(uid),
          'program_id': fs(programId),
          'program_title': fs('F-145 — braising'),
          'status': fs('sent'),
          'trigger': fs('manual'),
          'generated_at': fs(DateTime.now()),
          'new_count': fs(2),
          'review_count': fs(1),
          'responses': fs({
            'f145-q1': {'grade': 'good'},
          }),
          'items': fs([
            {
              'item_id': 'f145-i1',
              'chunk_id': '',
              'document_id': 'seed-doc-article-complete',
              'kind': 'new',
              'title': 'Pasta Fundamentals',
              'excerpt_html': '',
              'questions': [
                {'qid': 'f145-q1', 'question': 'When is the water salted?', 'answer': 'Before the pasta goes in.'},
                {'qid': 'f145-q2', 'question': 'How salty?', 'answer': 'Like the sea.'},
              ],
            },
            {
              'item_id': 'f145-i2',
              'chunk_id': '',
              'document_id': 'seed-doc-article-complete',
              'kind': 'review',
              'title': 'Household budget 2026',
              'excerpt_html': '',
              'questions': [
                {'qid': 'f145-q3', 'question': 'How far ahead?', 'answer': 'A month.'},
              ],
            },
          ]),
        },
      });
      expect(wrote.statusCode, 200, reason: 'the session was not written');

      // Today: the newest session's ungraded questions, from the sheet.
      await waitFor(find.text('questions waiting'), "Today's row");
      final peek = tester.widget<KitSecPeek>(find.byType(KitSecPeek));
      expect([for (final i in peek.items) i.label], ['Programs', 'Sessions']);
      await toggleHead();
      expect(headOpen(), isTrue);
      expect(find.text('TODAY'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KitDeskLedger),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('questions waiting'));
      await waitFor(find.byType(KitStudyQuestionCard), 'the session');
      expect(router.state.matchedLocation, '/study/session/$sessionId');
      await pumpFor(tester, total: const Duration(seconds: 1));

      // ── a session's sheet ──
      var line = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
      expect((line.mark as KitPeekMark?)?.text, '№ 2');
      expect((line.title, line.count, line.tail),
          ('Pasta Fundamentals', '1', ' of 3'));
      final bar = tester.widget<KitPeekBar>(find.byType(KitPeekBar));
      expect(bar.fraction, closeTo(1 / 3, 1e-9),
          reason: "the head's rule is the answered fraction");
      final barBox = tester.getSize(
          find.byKey(const ValueKey('d-peek-bar')));
      debugPrint('DEVICE-RUN F-145 session head: "№ 2 · ${line.title} · '
          '${line.count}${line.tail}" rule=${barBox.width.toStringAsFixed(1)}');
      await toggleHead();
      expect(find.text('THIS SESSION'), findsOneWidget);
      expect(find.text('QUESTIONS'), findsOneWidget);
      expect(find.text('KEYS'), findsOneWidget);
      final qs = tester.widget<KitStudyQuestions>(
          find.byType(KitStudyQuestions));
      expect(qs.marked, 1, reason: 'the marked row is the question to answer '
          'NEXT, not the one in view');
      expect(qs.items.first.grade, 'Good');
      await tester.tap(find.byKey(const ValueKey('d-q-2')));
      await pumpFor(tester, total: const Duration(seconds: 2));
      expect(headOpen(), isFalse, reason: 'a question row folds the head');
      final third = find.byType(KitStudyQuestionCard).at(2);
      final top = underTop(third);
      debugPrint('DEVICE-RUN F-145 question 3 lands ${top.toStringAsFixed(1)} '
          'under the scroller top');
      expect(top, closeTo(24, 6), reason: 'a question row jumps 24 under the top');
    } finally {
      await rest.delete('/study_sessions/$sessionId');
      if (programId != null) await Api.instance.deleteStudyProgram(programId);
    }

    // ── Activity's When filter ──
    router.go('/activity');
    await waitFor(find.byType(KitTimelineRow), 'the feed');
    await pumpFor(tester, total: const Duration(seconds: 1));
    var line = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
    expect(line.title, 'All activity');
    final all = line.count;
    await toggleHead();
    expect(find.text('KIND'), findsOneWidget);
    expect(find.text('WHEN'), findsOneWidget);
    final when = tester
        .widgetList<KitContents>(find.byType(KitContents))
        .single
        .items;
    expect(when, isNotEmpty);
    final day = when.last;
    await tester.tap(find.descendant(
        of: find.byType(KitContents), matching: find.text(day.label)));
    await pumpFor(tester, total: const Duration(seconds: 2));
    expect(headOpen(), isFalse, reason: 'a day row folds the head');
    final dayHead = find.ancestor(
        of: find.text(day.label).hitTestable(),
        matching: find.byType(KitSectionHead));
    final dayTop = underTop(dayHead.first);
    debugPrint('DEVICE-RUN F-145 When "${day.label}" (${day.count}) lands '
        '${dayTop.toStringAsFixed(1)} under the scroller top; all=$all');
    expect(dayTop, lessThan(80), reason: 'the day came to the top of the page');
    // A kind narrows the feed and keeps the head open: the days under it
    // change with it.
    await toggleHead();
    final facet = tester.widget<KitFacet>(find.byType(KitFacet));
    final kind = facet.items
        .firstWhere((i) => i.id != 'all' && !i.disabled);
    await tester.tap(find.descendant(
        of: find.byType(KitFacet), matching: find.text(kind.label)));
    await pumpFor(tester, total: const Duration(seconds: 1));
    expect(headOpen(), isTrue, reason: 'a kind keeps the head open');
    line = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
    debugPrint('DEVICE-RUN F-145 Kind "${kind.label}": head '
        '"${line.title} · ${line.count}${line.tail ?? ''}"');
    expect((line.title, line.count, line.tail),
        (kind.label, kind.count, ' of $all'));
    await toggleHead();

    // ── For your review's empty state, in a fresh account ──
    final email =
        'f145-${DateTime.now().microsecondsSinceEpoch}@noteletter.test';
    await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'f145-run-1');
    try {
      KitPageTools.instance.reset();
      await FirebaseAuth.instance.currentUser!.getIdToken(true);
      await pumpFor(tester, total: const Duration(seconds: 2));
      final fresh = await pumpApp(tester);
      fresh.go('/review');
      await waitFor(find.text('Nothing waiting for you'), 'the empty state');
      expect(find.text('FOR YOUR REVIEW\u00a0· NOTHING WAITING'),
          findsOneWidget);
      for (final offer in ['Add to your library',
          'Ask before importing large files']) {
        expect(find.text(offer), findsOneWidget);
      }
      line = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
      expect((line.title, line.meta), ('For your review', 'Nothing waiting'));
      await toggleHead();
      expect(find.text('Nothing is waiting on you.'), findsOneWidget);
      debugPrint('DEVICE-RUN F-145 review empty: "${line.title} '
          '${line.meta}"; sheet says "Nothing is waiting on you."');
      await tester.tap(find.descendant(
          of: find.byType(KitSheetAlso),
          matching: find.text('See what happened recently')));
      await pumpFor(tester, total: const Duration(seconds: 2));
      expect(fresh.state.matchedLocation, '/activity');
    } finally {
      await FirebaseAuth.instance.currentUser?.delete();
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
    }
    expect(tester.takeException(), isNull);
  });
}

/// The source page's primary scroller — the first Scrollable under its D page
/// (the running head's dropped body comes after it in the page's stack).
final Finder _readerScrollable = find
    .descendant(
        of: find.byKey(const ValueKey('rx-page')),
        matching: find.byType(Scrollable))
    .first;

/// Wait for the source page to have read its document (the loading page is
/// `rx-loading`).
Future<void> _readerLoaded(WidgetTester tester) async {
  final page = find.byKey(const ValueKey('rx-page'));
  for (var i = 0; i < 80 && page.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(page, findsOneWidget, reason: 'the source page never loaded');
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The source page's sections (kit §29) — read off the running head's line.
KitSections _readerSections(WidgetTester tester) => tester
    .widget<KitSecPeek>(find.byType(KitSecPeek, skipOffstage: false))
    .sections;

/// A Contents jump (kit §29/§30): on a phone, drop the running head and tap
/// the section's row, which folds it and scrolls there.
Future<void> _readerJump(WidgetTester tester, String label) async {
  final peek = find.byKey(const ValueKey('d-peek'));
  if (peek.evaluate().isNotEmpty) {
    await tester.tap(peek);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }
  final row = find.descendant(
      of: find.byType(KitContents), matching: find.text(label));
  expect(row, findsWidgets, reason: 'no Contents row for $label');
  await tester.tap(row.last);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The page's settings panel, from the app header's gear (kit §28, §30).
Future<void> _openSourceDetails(WidgetTester tester) async {
  final gear = find.descendant(
      of: find.byType(KitAppHeader),
      matching: find.byWidgetPredicate((w) =>
          w is KitSettingsButton && w.settings.label == 'Source details'));
  expect(gear, findsOneWidget, reason: 'the header draws Source details');
  await tester.tap(gear);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  expect(find.byKey(const ValueKey('d-panel')), findsOneWidget,
      reason: 'Source details did not open');
}

/// A D page's settings panel, from the app header's gear named [label]
/// (kit §28, §30) — the same press a reader makes on a phone.
Future<void> _openPageSettings(WidgetTester tester, String label) async {
  final gear = find.descendant(
      of: find.byType(KitAppHeader),
      matching: find.byWidgetPredicate(
          (w) => w is KitSettingsButton && w.settings.label == label));
  expect(gear, findsOneWidget, reason: 'the header draws $label');
  await tester.tap(gear);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  expect(find.byKey(const ValueKey('d-panel')), findsOneWidget,
      reason: '$label did not open');
}

/// A D page's running head (kit §30), dropped by a tap on its line.
Future<void> _dropHead(WidgetTester tester) async {
  final peek = find.byKey(const ValueKey('d-peek'));
  expect(peek, findsOneWidget, reason: 'no running head on this page');
  await tester.tap(peek);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// The running head's line as text (its peek, folded or dropped).
String _peekText(WidgetTester tester) => find
    .descendant(
        of: find.byKey(const ValueKey('d-peek')),
        matching: find.byType(RichText))
    .evaluate()
    .map((e) => (e.widget as RichText).text.toPlainText())
    .where((t) => t.trim().isNotEmpty)
    .join(' · ');

/// Drags the screen with REAL gestures until its primary scroll is at the end
/// (INV-22, ADR-173), lets the bounce settle, and asserts the support footer is
/// the LAST thing in that scroll: on screen, its bottom on the scroll
/// viewport's bottom, and above any docked composer. The drag starts
/// mid-screen, which is the primary column on every screen this is used on.
///
/// [scrollable] names the primary scroll when the footer is not built until
/// the end is near — the reader's is a sliver, laid out lazily.
Future<void> _dragToFooter(WidgetTester tester, String route,
    {Finder? scrollable}) async {
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final footer = find.byType(KitSupportFooter);
  final scroller = scrollable ??
      find.ancestor(of: footer, matching: find.byType(Scrollable)).first;
  ScrollPosition pos() => tester.state<ScrollableState>(scroller).position;
  for (var i = 0; i < 40; i++) {
    await tester.dragFrom(Offset(view.width / 2, view.height * 0.45),
        const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    if (pos().pixels >= pos().maxScrollExtent - 1) break;
  }
  // Let an iOS overscroll bounce come back to rest before measuring.
  double? last;
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final p = pos().pixels;
    if (last != null && (p - last).abs() < 0.01) break;
    last = p;
  }
  expect(pos().pixels, closeTo(pos().maxScrollExtent, 1.0),
      reason: '$route: the primary scroll reached its end by real drags');
  expect(footer.hitTestable(), findsOneWidget,
      reason: '$route: the footer is reached at the end of the scroll');
  final r = tester.getRect(footer);
  final viewport = tester.getRect(scroller);
  final dock = find.byType(KitComposerDock);
  if (dock.evaluate().isNotEmpty) {
    expect(r.bottom, lessThanOrEqualTo(tester.getRect(dock).top + 0.5),
        reason: '$route: above the docked composer, which stays docked');
  } else {
    expect(r.bottom, closeTo(viewport.bottom, 1.0),
        reason: '$route: the last thing in the screen\'s scroll');
  }
}
