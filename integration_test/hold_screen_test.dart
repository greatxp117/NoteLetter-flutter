// The capture harness for the fidelity ritual's screenshot pair (ADR-041 §5):
// holds one screen on the simulator in each theme, long enough for
// `xcrun simctl io booted screenshot` to catch it. **Not a gate** — it asserts
// nothing, and a run of it proves only that a screen rendered.
//
// `takeScreenshot` is not available here (iOS cannot convert the Flutter
// surface under `flutter test`), so the pair is caught from outside the
// process; the `HOLD:<theme>` markers on stdout are what a capture script
// waits for.
//
//   flutter test integration_test/hold_screen_test.dart -d <device-id> \
//     --timeout none --dart-define=HOLD_ROUTE=/activity \
//     --dart-define=USE_EMULATOR=true  (+ the EMULATOR_* ports, per /emu)
//
// then, once `HOLD:LIGHT` appears:
//   xcrun simctl io booted screenshot screenshots/<screen>.flutter.light.png
// and again on `HOLD:DARK` for the dark frame.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/scripture_letter_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/search_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/pages/onboarding/wizard.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/search/result_card.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';
const route = String.fromEnvironment('HOLD_ROUTE', defaultValue: '/activity');

/// A STATE no route reaches — an opened letter, a typed query, a picker.
/// `tool/shots.sh <screen> <route> [HOLD_STATE]` passes it; [reachState] below
/// is the one place that knows how each is reached.
const holdState = String.fromEnvironment('HOLD_STATE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    if (!ApiService.useEmulator) {
      fail('Refusing to run: pass --dart-define=USE_EMULATOR=true.');
    }
    final host = ApiService.emulatorHost;
    FirebaseFirestore.instance
        .useFirestoreEmulator(host, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(host, ApiService.authPort);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  });

  testWidgets('holds $route in both themes', (tester) async {
    final auth = AuthNotifier();
    final theme = ThemeNotifier();
    final router = createRouter(auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<UploadNotifier>(create: (_) => UploadNotifier()),
        ChangeNotifierProvider<SearchNotifier>(create: (_) => SearchNotifier()),
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
        ChangeNotifierProvider<ActivityNotifier>(
            create: (_) => ActivityNotifier()),
        ChangeNotifierProvider<DocumentsNotifier>(
            create: (_) => DocumentsNotifier()),
        ChangeNotifierProvider<SettingsNotifier>(
            create: (_) => SettingsNotifier()),
        ChangeNotifierProvider<NewsletterNotifier>(
            create: (_) => NewsletterNotifier()),
        // The readings letter's own settings document (ADR-029) —
        // separate from the daily letter's, as the endpoint is.
        ChangeNotifierProvider<ScriptureLetterNotifier>(
            create: (_) => ScriptureLetterNotifier()),
        ChangeNotifierProvider<CloudNotifier>(create: (_) => CloudNotifier()),
        ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => TagsNotifier()),
        // INV-22: every authenticated screen sits inside SupportShell, which
        // reads this. Without it the hold renders a ProviderNotFoundError
        // wall — in both themes, for every screen — instead of the screen.
        ChangeNotifierProvider<SupportNotifier>(
            create: (_) => SupportNotifier()),
        ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
      ],
      child: NoteLetterApp(router: router),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    router.go(route);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await reachState(tester);

    Future<void> hold(String label, ThemeMode mode) async {
      // `ThemeNotifier` starts an async read of the stored preference in its
      // own constructor, and that read OVERWRITES whatever was set before it
      // lands. Every hold run ends on dark, so it is the light capture that
      // loses the race — and it loses it silently: the file is written, it is
      // named `.light.png`, and it is a dark frame. Set, pump, and CONFIRM the
      // mode the app is in before the marker says it is safe to shoot.
      for (var attempt = 0; attempt < 10; attempt++) {
        if (theme.themeMode == mode && attempt > 0) break;
        await theme.setMode(mode);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      if (theme.themeMode != mode) {
        fail('theme is ${theme.themeMode}, not $mode — the capture would be '
            'the wrong theme under the right name');
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      debugPrint('HOLD:$label');
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await hold('LIGHT', ThemeMode.light);
    await hold('DARK', ThemeMode.dark);
  });
}

/// Drive the screen into [holdState]. Bounded `pump` loops, never
/// `pumpAndSettle`: a screen with a live animation does not settle, and the
/// wait reads as green until something is actually pulsing on it.
Future<void> reachState(WidgetTester tester) async {
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  switch (holdState) {
    case '':
      return;
    // letters.md — the letter itself is a state of the Letters screen, opened
    // from its archive. The letterheaded letter `tool/seed_letters.py` writes
    // is the top row.
    case 'letter':
      // Both letters offer a Preview; the daily one is first on the screen.
      expect(find.text('Preview'), findsWidgets,
          reason: 'run tool/seed_letters.py first — no readable letter to open');
      final preview = find.text('Preview').first;
      // `warnIfMissed` stays ON, deliberately: a tap that lands on nothing is
      // silent, and the capture would then be the LIST under the name of the
      // reader. The assertion below is the other half of the same point.
      await tester.tap(preview);
      await settle();
      expect(find.text('All letters'), findsOneWidget,
          reason: 'the letter did not open — this frame would be the list');
      return;
    // ask.md — the rail and a recorded turn (4.53.0, ADR-090). `/ask` alone is
    // the §7 empty state with the rail closed, which shows none of §9: no
    // grouped entries, no accent bar, no preview line. This drives a REAL turn
    // (fn_ask_turn through the shim, retrieval included) and leaves the rail
    // open, which is the phone form of the two columns the web frame shows.
    case 'ask-thread':
    case 'ask-rail':
      final field = find.byType(TextField).last;
      await tester.enterText(field, 'What have I been reading about pasta?');
      await settle();
      // The send CONTROL: §10's field takes `TextInputAction.newline`, so a
      // submit action inserts a line and sends nothing.
      await tester.tap(find.bySemanticsLabel('Send'));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Your library').evaluate().isNotEmpty) break;
      }
      await settle();
      expect(find.text('Your library'), findsWidgets,
          reason: 'no answer came back — this frame would be the empty state');
      // The rail stays CLOSED here. It is an overlay on this client, so an
      // open one covers the transcript entirely and the frame would compare
      // nothing the web `ask-thread` frame shows. §9 has its own pair below.
      if (holdState == 'ask-rail') {
        await tester.tap(find.text('History'));
        await settle();
        expect(find.byType(KitInspectorRail), findsOneWidget,
            reason: 'the rail did not open — this frame would show no §9');
        // §9.1 (4.55.0, ADR-091). The cluster is unconditional on this client
        // — there is no hover to reveal it — so a frame without it is a frame
        // of the pre-4.55.0 rail, which is exactly the picture this pair is
        // being re-taken to replace.
        expect(find.byIcon(Icons.delete_outline), findsWidgets,
            reason: 'no §9.1 entry actions — this frame would be the old rail');
      }
      return;
    // reader.md §Panels — the manuscript is a BODY SWAP under the reader's one
    // header, not a route, so no URL reaches it and the frame has to select the
    // tab first. Without this the `reader-manuscript` pair would be two frames
    // of the summary panel under a filename claiming otherwise, which is worse
    // than no pair: a frame is evidence, and a mislabelled one is false
    // evidence nobody re-checks.
    case 'manuscript':
      await tester.tap(find.text('Manuscript'));
      await settle();
      // byType, not the panel's copy. The first version asserted
      // `textContaining('Manuscript · the extracted text')` and failed on a
      // screen that was rendering perfectly: `Eyebrow` draws
      // `text.toUpperCase()`, so what is on screen is
      // `MANUSCRIPT · THE EXTRACTED TEXT`. A finder written from the source
      // string rather than from the renderer is a test that fails for its own
      // reasons — the same slip as looking for 'SpeedRead' where the label is
      // 'Speed read'. The type is what "the panel opened" actually means.
      expect(find.byType(ManuscriptPanel), findsOneWidget,
          reason: 'the manuscript panel did not open — this frame would be the '
              'summary');
      return;
    // reader.md §Recipe body — the §5.4 body swap. Same route, same header,
    // same Manuscript panel: only the BODY differs, which is the whole claim
    // the pattern makes, so the frame has to be the manuscript of a distilled
    // document rather than a screen of its own.
    case 'recipe':
      await tester.tap(find.text('Manuscript'));
      await settle();
      expect(find.byType(KitRecipeBody), findsOneWidget,
          reason: 'no recipe body — run tool/seed_recipe_and_sources.py first; '
              'this frame would be ordinary passage prose');
      // A whole recipe is several times a phone viewport, and the body begins
      // BELOW the reader's header and panel strip — so the frame at rest is a
      // picture of the header with the pattern out of shot. Aligned to the top
      // rather than merely "visible": `ensureVisible` stops as soon as an inch
      // of it has entered the screen, which is the same frame again.
      await Scrollable.ensureVisible(
          tester.element(find.byType(KitRecipeBody)),
          alignment: 0.0, duration: Duration.zero);
      await settle();
      return;
    // component-kit §15.1 / §15.2 — the Original panel is where this client
    // draws both viewers, exactly as the reference reader does. Which one
    // appears is decided by the document's SHAPE, so the two states differ
    // only in the document the route opened.
    case 'source-file':
      await tester.ensureVisible(find.text('Original'));
      await tester.pump();
      await tester.tap(find.text('Original'), warnIfMissed: false);
      await settle();
      expect(find.byType(KitSourceFileView), findsOneWidget,
          reason: 'no §15.1 view — run tool/seed_recipe_and_sources.py first '
              '(with no stored bytes the endpoint answers signed_url: null, '
              'which is a different state and a different picture)');
      return;
    case 'source-set':
      await tester.ensureVisible(find.text('Original'));
      await tester.pump();
      await tester.tap(find.text('Original'), warnIfMissed: false);
      await settle();
      expect(find.byType(KitSourceSetGallery), findsOneWidget,
          reason: 'no §15.2 gallery — run tool/seed_recipe_and_sources.py '
              'first; a set filed as a link draws a link button over a null');
      // The grid is the subject, and three pages of it do not fit under the
      // header. Aligned to the top so the frame holds the whole gallery —
      // toolbar, count, and every tile including the one that has not landed.
      await Scrollable.ensureVisible(
          tester.element(find.byType(KitSourceSetGallery)),
          alignment: 0.0, duration: Duration.zero);
      await settle();
      return;
    // search.md — a route alone renders the §7 idle offer, so the query is
    // typed. The reference's own shot types `budget` and waits: the seed's
    // chunks are the corpus and it hits the PDF. The frame has to be of
    // RESULTS, since every part this pair is compared on — the control bar,
    // the split pane, the reading pane, the score meter — exists only once
    // something has been searched for.
    case 'query':
      final field = find.byType(EditableText).first;
      await tester.enterText(field, 'budget');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(SearchResultCard).evaluate().isNotEmpty) break;
      }
      await settle();
      expect(find.byType(SearchResultCard), findsWidgets,
          reason: 'no results came back — this frame would be the idle offer, '
              'and every part the pair compares is drawn only under results');
      return;
    // sources.md §Document processing — the tray's affordances. The frame is
    // the processing section: the seed carries a failed docx (`file` — View
    // file), a queued article (`link` — Open the link) and an uploading image,
    // so every §6.4.2 branch the tray can draw is in one picture. Scrolled to
    // the section, because at rest it sits under the header and the drop zone.
    case 'proc-affordances':
      await settle();
      expect(find.text('View file'), findsWidgets,
          reason: 'no source affordance — this frame would be the tray without '
              'the thing it is a frame OF');
      await Scrollable.ensureVisible(
          tester.element(find.text('View file').first),
          alignment: 0.3, duration: Duration.zero);
      await settle();
      return;
    // sources.md §Document processing / component-kit §15 — the sheet a
    // processing row opens, holding §15.1. Opened from the FAILED row, which
    // is the case the affordance exists for: `error_message` is a claim about
    // a source, and this is the only surface that shows the source.
    case 'source-file-stage':
      await settle();
      // The FAILED row that has bytes — `tool/seed_recipe_and_sources.py`
      // writes it. Not the first View file on the screen: that one belongs to
      // the uploading docx, whose sheet is correctly the "hasn't finished
      // uploading yet" state and NOT the §15.1 stage this frame is of.
      final failed = find.ancestor(
        of: find.text('scan-2026-07-02.png'),
        matching: find.byType(KitSourceRow),
      );
      expect(failed, findsOneWidget,
          reason: 'run tool/seed_recipe_and_sources.py first — without a '
              'failed document that HAS its bytes there is no stage to shoot');
      final view = find.descendant(of: failed, matching: find.text('View file'));
      // The control sits in the row's STACKED trailing strip below the compact
      // breakpoint, which is under the fold at rest — a tap at its unscrolled
      // position lands on nothing, warns, and leaves the frame showing the
      // tray under the name of the sheet.
      await tester.ensureVisible(view);
      await settle();
      await tester.tap(view);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(KitSourceFileView).evaluate().isNotEmpty ||
            find.byType(KitFailureBlock).evaluate().isNotEmpty ||
            find.byType(KitProcNote).evaluate().isNotEmpty) {
          break;
        }
      }
      await settle();
      expect(find.byType(KitOverlaySheet), findsOneWidget,
          reason: 'the §15 sheet did not open — this frame would be the tray');
      return;
    // library.md §Shelf color — the ten swatches live inside the shelf's
    // settings disclosure, which no route reaches. The shelf the seed gives
    // this state is `seed-tag-recipes`.
    case 'color-picker':
      await tester.tap(find.widgetWithText(KitButton, 'Settings'));
      await settle();
      expect(find.byType(KitSwatch), findsNWidgets(10),
          reason: 'the picker did not open — this frame would be the shelf');
      return;
    // onboarding.md §States/Replay — the wizard is a GATE, not a route: it
    // renders only for an unset `nl-onboarded` and a first documents snapshot
    // that arrives EMPTY, and the seed user has a library. Settings' replay
    // control is the other door into the same flow, and the one the web
    // reference's own shot uses, so the pair compares the same picture.
    //
    // It writes nothing — the flow saves on its last step only — so the hold
    // leaves the emulator exactly as it found it.
    case 'onboarding':
      await tester.tap(find.widgetWithText(KitButton, 'Run setup'));
      await settle();
      expect(find.byType(OnboardingWizard), findsOneWidget,
          reason: 'the wizard did not open — this frame would be Settings');
      return;
    default:
      fail('hold_screen_test knows no HOLD_STATE "$holdState"');
  }
}
