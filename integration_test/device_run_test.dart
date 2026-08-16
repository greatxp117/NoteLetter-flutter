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
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/pages/reader/passage_mark.dart';

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
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Refuse to run against prod. This client points at real noteletter-7a111
    // by default and writes real counters (INV-03a/03b) — a device run that
    // silently hit prod would inflate exactly the counters a backfill has
    // already corrected.
    if (!ApiService.useEmulator) {
      fail('Refusing to run: pass --dart-define=USE_EMULATOR=true (umbrella law 1).');
    }
    final host = ApiService.emulatorHost;
    FirebaseFirestore.instance
        .useFirestoreEmulator(host, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(host, ApiService.authPort);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  });

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final auth = AuthNotifier();
    final router = createRouter(auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<UploadNotifier>(create: (_) => UploadNotifier()),
        ChangeNotifierProvider<SearchNotifier>(create: (_) => SearchNotifier()),
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
        ChangeNotifierProvider<ActivityNotifier>(create: (_) => ActivityNotifier()),
        ChangeNotifierProvider<SettingsNotifier>(create: (_) => SettingsNotifier()),
        ChangeNotifierProvider<NewsletterNotifier>(create: (_) => NewsletterNotifier()),
        ChangeNotifierProvider<CloudNotifier>(create: (_) => CloudNotifier()),
        ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => TagsNotifier()),
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
      ],
      child: NoteLetterApp(router: router),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return router;
  }

  testWidgets('signs in and reaches the library', (tester) async {
    await pumpApp(tester);
    expect(FirebaseAuth.instance.currentUser, isNotNull);
    // Landing must NOT be showing — the redirect sends a signed-in user to '/'.
    expect(find.text('Your Knowledge Base, Automatically Curated'), findsNothing);
  });

  testWidgets('the reader renders and the passage mark tracks a REAL drag',
      (tester) async {
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
    final doc =
        await FirebaseFirestore.instance.collection('documents').doc(docId).get();
    expect(doc.exists, isTrue,
        reason: 'run tool/seed_long_doc.py against the emulator first');
    final chunks = await FirebaseFirestore.instance
        .collection('chunks')
        .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('document_id', isEqualTo: docId)
        .get();
    expect(chunks.docs, isNotEmpty);
    expect(chunks.docs.every((c) => (c.data()['view_count'] ?? 0) == 0), isTrue,
        reason: 'fixture chunks must be uncounted, or the fill is pinned full');

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

    expect(find.byType(PassageMark), findsWidgets,
        reason: 'the manuscript must render the extent mark at rest');

    // The mark's fill is the heightFactor of the FractionallySizedBox inside
    // it — read from the live tree rather than from any test-only hook.
    List<double> fills() => tester
        .widgetList<FractionallySizedBox>(find.descendant(
          of: find.byType(PassageMark),
          matching: find.byType(FractionallySizedBox),
        ))
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
      await tester.drag(scrollable.first, const Offset(0, 320));
      await tester.pumpAndSettle();
    }
    final backAtTop = fills();
    for (var j = 0; j < backAtTop.length && j < atBottom.length; j++) {
      expect(backAtTop[j], greaterThanOrEqualTo(atBottom[j] - 0.001),
          reason: 'passage $j retreated on scrolling back up');
    }
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
