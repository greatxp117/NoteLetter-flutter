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
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/pages/tags/shelf_sheet.dart';
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
    // A signed-out route (F-44a) is held SIGNED OUT: signed in, the router's
    // redirect would send the frame to `/` under the sign-in page's name.
    if (signedOutRoutes.contains(route)) {
      await FirebaseAuth.instance.signOut();
      return;
    }
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
    // The landing never settles — its ticker runs and its caret blinks — and a
    // settle does not fail on a live animation, it hangs until the load window
    // kills the run (2026-09-26). Signed-out routes get bounded pumps.
    if (signedOutRoutes.contains(route)) {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    } else {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
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
    // `shelf-backfill-review` made a real shelf through the sheet; every
    // later frame reads the same database, so it goes (the reference deletes
    // its own the same way).
    final made = _createdShelf;
    if (made != null) await Api.instance.deleteTag(made);
  });
}

/// The shelf `shelf-backfill-review` created, for deletion after the holds.
String? _createdShelf;

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
    // The landing below its fold (F-68) — for LOOKING only: the reference's
    // frames are the page top, so these are never checked in.
    case 'landing-curve':
    case 'landing-footer':
      final target = find.textContaining(
          holdState == 'landing-curve'
              ? 'Each mark is a letter'
              : 'Independent, and staying that way',
          findRichText: true);
      await Scrollable.ensureVisible(tester.element(target.first),
          alignment: holdState == 'landing-curve' ? 0.6 : 0.95);
      await settle();
      return;
    // Web `signin-fail` — the §14.2 line in `.si-fail`'s slot.
    // The reference's own shot presses "Forgot it?" with the email empty, a
    // refusal the page makes itself; this does the same, so the pair compares
    // the same sentence in the same place.
    case 'signin-fail':
      await settle();
      await tester.tap(find.text('Forgot it?'));
      await settle();
      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'no refusal rendered — this frame would be the page at rest');
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
      // `Your library` is the responder's LABEL, and a refused turn draws it
      // too: the 2026-09-25 re-shoot caught "Ask failed. Contact support with
      // your request ID." under this state's filename, against a shim without
      // the model. An answer is a turn that did not fail.
      expect(find.text('Try again'), findsNothing,
          reason: 'the turn failed — this frame would be a refusal under the '
              'name of an answer (the turn needs the model: run the 5599 shim '
              'with NL_DEV_FAKES=1)');
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
    // ask.md §States — a turn the endpoint REFUSED (4.61.0, ADR-097). The
    // question stays in the transcript with the server's sentence and a retry;
    // it is never returned to the composer. No route reaches this state and no
    // fake produces it, so it is driven by a REAL refusal — and which refusal
    // is not a free choice. It is held on `/ask/shelf/{id}` for a shelf that
    // does not exist, whose turn is the endpoint's own documented 404 ("Shelf
    // not found.", `api/ask.md`).
    //
    // NOT on `/ask/thread/{id}` for a missing thread, which was the first
    // attempt: the messages subscription is denied by the rules before any
    // turn is sent, so the screen correctly draws INV-24's "This conversation
    // could not be read." and the frame would have been that state under this
    // one's filename. (Which is itself worth recording: that is the thread
    // half of INV-24 rendering against a real permission-denied.) A dead
    // functions port would work too and would render OUR fallback sentence
    // instead of the server's — and the server's words, verbatim, are the half
    // of §14.2 that matters.
    case 'ask-turn-failed':
      final failField = find.byType(TextField).last;
      await tester.enterText(failField, 'Which of these recipes can use steak?');
      await settle();
      await tester.tap(find.bySemanticsLabel('Send'));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Try again').evaluate().isNotEmpty) break;
      }
      await settle();
      // Say which branch this run took, the way the device run does: a frame
      // that is not the state its filename claims is false evidence, and the
      // notifier is the only thing that can say which state it is.
      final chat = Provider.of<ChatNotifier>(
        tester.element(find.byType(KitComposerDock)),
        listen: false,
      );
      debugPrint('HOLD ask-turn-failed: sent=${chat.sentQuestion} '
          'err=${chat.sentError} msgs=${chat.messages.length} '
          'thread=${chat.activeId}');
      expect(find.text('Try again'), findsOneWidget,
          reason: 'the turn was not refused — this frame would be an answer, '
              'under a filename claiming otherwise');
      expect(find.text('Which of these recipes can use steak?'), findsOneWidget,
          reason: 'the question left the screen — the frame would show the '
              'defect ADR-097 closed rather than the state it requires');
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
      // Wait for the route to land before typing: entered too early, the text
      // went into nothing and no search was ever sent (seen 2026-09-25).
      await settle();
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
    // settings.md §Plan row (4.79.0, ADR-113) — the Account section, which is
    // the bottom of Settings and is never in the screen's own top frame. The
    // reference shoots the same state for the same reason, clipped to the
    // section (`theme-shots.mjs` `settings-plan`), so the pair compares the
    // row rather than two pictures of a header.
    //
    // The assertion is what makes this a frame OF something: `fn_plan_status`
    // has to have ANSWERED. Without it the row draws the title `Plan` and no
    // figures (ADR-109) — correct behaviour, and a photograph of the loading
    // state under the name of the row.
    case 'settings-plan':
      await settle();
      expect(find.textContaining(RegExp(r'\d+ of \d+ sources')), findsOneWidget,
          reason: 'the Plan row has no measured figures — fn_plan_status did '
              'not answer, so this frame would be the unread state under the '
              "row's name");
      await Scrollable.ensureVisible(
          tester.element(find.textContaining(RegExp(r'\d+ of \d+ sources'))),
          alignment: 0.5, duration: Duration.zero);
      await settle();
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
      // The web frame opens on the section head; so does this one, now the
      // rows are cards tall enough that the first control sits well below it.
      final procHead = find.textContaining(
          RegExp(r'^Being processed', caseSensitive: false));
      await Scrollable.ensureVisible(
          tester.element(procHead.evaluate().isEmpty
              ? find.text('View file').first
              : procHead.first),
          alignment: procHead.evaluate().isEmpty ? 0.3 : 0.0,
          duration: Duration.zero);
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
    // sources.md §Folder contents (4.59.0, ADR-096) — the import picker with
    // one folder's disclosure open. Needs the shim under NL_DEV_FAKES=1, whose
    // Drive fake carries a small tree (dev_server.py).
    case 'folder-contents':
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Browse files…').evaluate().isNotEmpty) break;
      }
      await tester.ensureVisible(find.text('Browse files…').first);
      await tester.tap(find.text('Browse files…').first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('What’s in here?').evaluate().isNotEmpty) break;
      }
      await tester.ensureVisible(find.text('What’s in here?').first);
      await tester.tap(find.text('What’s in here?').first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.textContaining(RegExp(r'^scanned \d')).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining(RegExp(r'^scanned \d')), findsOneWidget,
          reason: 'the disclosure never reported — this frame would be the list');
      // Frame the ROW with its disclosure, not the disclosure alone: which
      // folder the counts belong to is half of what the frame shows.
      await Scrollable.ensureVisible(tester.element(find.text('Docs').first),
          alignment: 0.3);
      await settle();
      return;
    // library.md §A shelf's place in the letter (4.88.0, ADR-122) — the
    // section sits below the stat cluster; scroll it into the frame.
    case 'shelf-letter':
    case 'shelf-letter-error':
      await tester.ensureVisible(find.text('Feed today’s letter'));
      await settle();
      if (holdState == 'shelf-letter') return;
      // A REAL refusal, as the web frame's: `letter_mode` is a closed set, so
      // the request is rewritten to `loud` on its way out and the sentence in
      // the frame is fn_update_tag's own, from the emulator backend.
      ApiService.instance.httpClientAdapter = _RewriteLetterMode();
      await tester.tap(find.text('Lead'));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(KitFailureInline).evaluate().isNotEmpty) break;
      }
      ApiService.instance.resetTestSeams();
      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'no refusal rendered — this frame would be the section');
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
    // component-kit §1.2 — the chrome rail. On a phone the rail IS the drawer,
    // so at rest it is off screen entirely: every frame this client captures
    // shows the app bar and nothing of the navigation. A pattern that cannot
    // be photographed is a pattern nobody looks at, which is how the drawer
    // stayed a second, divergent nav through eleven screen recompositions.
    case 'drawer':
      await tester.tap(find.byIcon(Icons.menu));
      await settle();
      expect(find.byType(KitChromeRail), findsOneWidget,
          reason: 'the drawer did not open — this frame would be the screen '
              'behind it');
      return;
    // letters.md §"See all" — the LIVE day behind a readings letter (ADR-029
    // §5, QUEUE F-33). Two states deep and reachable by no route: the letter
    // is opened from its archive row, and the day from the letter. The three
    // searches are real (fn_search_notes through the shim), which is what the
    // frame is of — a replay of the stored passages would be a picture of the
    // letter.
    case 'scripture-day':
      // By the ROW's own type: the same text is in the card above it, where
      // it is not a control, and a tap that lands on nothing is silent.
      final row = find.byWidgetPredicate((w) =>
          w is KitSourceRow && w.title.contains('Thursday of week 23'));
      expect(row, findsOneWidget,
          reason: 'run tool/seed_letters.py first — no readings letter to '
              'open');
      await tester.ensureVisible(row);
      await settle();
      await tester.tap(row);
      await settle();
      final seeAll = find.textContaining('passages for this day');
      expect(seeAll, findsOneWidget,
          reason: 'the letter did not open — this frame would be the list');
      await tester.ensureVisible(seeAll);
      await settle();
      await tester.tap(seeAll);
      // Three live searches, each a round trip through the shim.
      await settle();
      await settle();
      await settle();
      expect(find.text('Back to the letter'), findsOneWidget,
          reason: 'the day did not open — this frame would be the letter');
      return;
    // library.md §Creating a shelf / §Backfill review (4.83.0, ADR-117;
    // QUEUE F-38) — the §15 sheet over the shell, as the reference's frames
    // open it from the rail's `+`. On a phone the rail is a drawer, so the
    // sheet is opened through the one function the `+` calls.
    case 'shelf-create-sheet':
    case 'shelf-backfill-review':
      final ctx = tester.element(find.byType(Scaffold).first);
      unawaited(showShelfSheet(
        ctx,
        canBackfill: true,
        land: (_) {},
        create: (title, {description, color}) async {
          final res = await Api.instance
              .createTag(title, description: description, color: color);
          _createdShelf = res['tagId'] as String?;
          return res;
        },
      ));
      await settle();
      final fields = find.descendant(
          of: find.byType(KitOverlaySheet), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Pasta');
      if (holdState == 'shelf-create-sheet') {
        await tester.enterText(
            fields.at(1), 'Fresh and dried pasta, shapes and sauces.');
        await settle();
        return;
      }
      // The keyboard is up after typing; put it away so the button is where
      // the tap lands.
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      final create = find.widgetWithText(KitButton, 'Create shelf');
      await tester.ensureVisible(create);
      await settle();
      await tester.tap(create);
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (_createdShelf != null &&
            find.textContaining('Reading your library').evaluate().isEmpty) {
          break;
        }
      }
      await settle();
      expect(_createdShelf, isNotNull,
          reason: 'fn_create_tag never answered — this frame would be the form');
      expect(find.textContaining('Reading your library'), findsNothing,
          reason: 'the review never answered — this frame would be a wait');
      return;
    // letters.md §Composition *Archive* (4.98.0, ADR-131) — the letter rows,
    // below the fold on a phone. Look only: the web frame is the page top.
    case 'letters-archive':
      await settle();
      final sent = find.textContaining(RegExp(r'^Sent · ', caseSensitive: false));
      for (var i = 0; i < 40; i++) {
        if (sent.evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      await Scrollable.ensureVisible(tester.element(sent.first),
          alignment: 0.05);
      await settle();
      return;
    // letters.md §The letter-settings preview (F-53, ADR-131) — the stored
    // letter under the form, below the fold on a phone. Look only: the web's
    // `letter-settings` frame is the top of the page.
    case 'letter-preview':
      await settle();
      final copy = find.text('Copy');
      for (var i = 0; i < 40; i++) {
        if (copy.evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      final none = find.text('No letter has been built yet.');
      final target = none.evaluate().isNotEmpty ? none : copy;
      await Scrollable.ensureVisible(tester.element(target.first),
          alignment: 0.9);
      await settle();
      return;
    // sources.md §Composition body 3 — In your library, with the list / cards
    // / shelf toggle (F-65), below the fold at rest. Shot for looking only:
    // the web's `sources` frame is the top of the page.
    case 'sources-browse':
      await settle();
      final head = find.textContaining(
          RegExp(r'^In your library', caseSensitive: false));
      for (var i = 0; i < 40; i++) {
        if (head.evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      await Scrollable.ensureVisible(tester.element(head.first),
          alignment: 0.05);
      await settle();
      return;
    // The same, with the first spine pulled — its detail card (F-65). Look only.
    case 'sources-book':
      await settle();
      final spine = find.byType(KitBookSpine);
      for (var i = 0; i < 40; i++) {
        if (spine.evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.ensureVisible(spine.first);
      await tester.tap(spine.first);
      await settle();
      await Scrollable.ensureVisible(
          tester.element(find.byType(KitBookSpine).first),
          alignment: 0.1);
      await settle();
      return;
    // library.md — Recently read and Shelves, below the fold at rest, with
    // their list / shelf toggles (F-54). Shot for looking only.
    case 'library-shelves':
      await settle();
      final recentHead = find.textContaining(
          RegExp(r'^Recently read', caseSensitive: false));
      for (var i = 0; i < 40; i++) {
        if (recentHead.evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      await Scrollable.ensureVisible(tester.element(recentHead.first),
          alignment: 0.02);
      await settle();
      return;
    // sources.md §Sync control — the sync-folder chooser (F-67), which no
    // route reaches: the Drive sync panel opened, then its folder picker.
    // Needs the shim under NL_DEV_FAKES=1 for the Drive tree. The web
    // reference has no frame of this state, so it is shot for LOOKING and
    // never checked in (screenshot_pair_check would find no web frame).
    case 'sync-folders':
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.textContaining(RegExp(r'^sync ·', caseSensitive: false)).evaluate().isNotEmpty) break;
      }
      await tester.ensureVisible(find.textContaining(RegExp(r'^sync ·', caseSensitive: false)).first);
      await tester.tap(find.textContaining(RegExp(r'^sync ·', caseSensitive: false)).first);
      await settle();
      final choose = find.textContaining(RegExp(r'^(Choose|Change) folders…$'));
      await tester.ensureVisible(choose.first);
      await tester.tap(choose.first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('What’s in here?').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('folders selected'), findsOneWidget,
          reason: 'the sync picker did not open — this frame would be the panel');
      await Scrollable.ensureVisible(
          tester.element(find.textContaining('folders selected')),
          alignment: 0.2);
      await settle();
      return;
    default:
      fail('hold_screen_test knows no HOLD_STATE "$holdState"');
  }
}


/// Forwards every request to the real transport, with `fn_update_tag`'s
/// `letter_mode` swapped for a value outside the closed set — so the refusal
/// in the `shelf-letter-error` frame is the backend's, not one this test wrote.
class _RewriteLetterMode implements HttpClientAdapter {
  final _inner = IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (!options.path.endsWith('/fn_update_tag') || options.data is! Map) {
      return _inner.fetch(options, requestStream, cancelFuture);
    }
    final body = utf8.encode(jsonEncode(
        {...(options.data as Map), 'letter_mode': 'loud'}));
    options.headers['content-length'] = body.length.toString();
    return _inner.fetch(
        options, Stream.value(Uint8List.fromList(body)), cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
