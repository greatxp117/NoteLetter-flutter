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
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/app_providers.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/pages/sources/sync_folder_picker.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/pages/chat_page.dart';
import 'package:flutter_app/pages/tags/shelf_sheet.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/pages/onboarding/wizard.dart';
import 'package:flutter_app/pages/reader/history_panel.dart';
import 'package:flutter_app/pages/reader/listen_panel.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/reader/source_priority.dart';
import 'package:flutter_app/pages/reader/speed_read_panel.dart';
import 'package:flutter_app/pages/search/result_card.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/sweep_ledger.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';
const route = String.fromEnvironment('HOLD_ROUTE', defaultValue: '/activity');

/// A STATE no route reaches — an opened letter, a typed query, a picker.
/// `tool/shots.sh <screen> <route> [HOLD_STATE]` passes it; [reachState] below
/// is the one place that knows how each is reached.
const holdState = String.fromEnvironment('HOLD_STATE');

/// A BATCH of holds in one build and one app process —
/// `screen|route|state;screen|route|state;…` (`tool/shots_batch.sh` passes
/// it). Every hold is its own testWidgets over a fresh app tree, exactly as
/// the device run's tests are, so a state reached in one cannot leak into the
/// next. Exists because each `tool/shots.sh` call rebuilds the app for its
/// compile-time route — minutes a pair, and a full re-shoot is forty pairs.
/// Markers are `HOLD:LIGHT[<screen>]` / `HOLD:DARK[<screen>]`, and a hold
/// that cannot reach its state says `HOLD:FAIL[<screen>]` before it fails.
const holdList = String.fromEnvironment('HOLD_LIST');

/// How long a BATCH hold keeps each theme after its marker, in seconds
/// (`HOLD_SECONDS=30 tool/shots_batch.sh …`). Twelve is enough on a quiet
/// machine. At load 200–340 (2026-10-17) the driver's screenshot-and-settle
/// loop outran it: 8 of 40 holds kept a LATER state under their name (the next
/// theme, the next hold, the home screen), settled, and 7 of them said OK.
const batchHoldSeconds = int.fromEnvironment('HOLD_SECONDS', defaultValue: 12);

typedef _Hold = ({String screen, String route, String state});

List<_Hold> _holds() {
  if (holdList.isEmpty) return [(screen: '', route: route, state: holdState)];
  final out = <_Hold>[];
  for (final entry in holdList.split(';')) {
    if (entry.trim().isEmpty) continue;
    final f = entry.split('|');
    out.add((
      screen: f[0].trim(),
      route: f.length > 1 ? f[1].trim() : '/',
      state: f.length > 2 ? f[2].trim() : '',
    ));
  }
  return out;
}

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
  });

  for (final h in _holds()) {
    testWidgets('holds [${h.screen}] ${h.route} ${h.state} in both themes',
        (tester) async {
      try {
        await _holdOne(tester, h);
      } catch (e) {
        debugPrint('HOLD:FAIL[${h.screen}] $e');
        rethrow;
      }
    });
  }
}

Future<void> _holdOne(WidgetTester tester, _Hold h) async {
  final route = h.route;
  final mark = h.screen.isEmpty ? '' : '[${h.screen}]';
  // Process-level state a hold can set and a fresh tree does not reset. The
  // `onboarding` hold presses Run setup, which raises a static ValueNotifier
  // (by design it outlives no LAUNCH — but a batch is one launch), and the
  // first batch drew the wizard under every later screen's name.
  LocalFlags.onboardingReplay.value = false;
  // A signed-out route (F-44a) is held SIGNED OUT: signed in, the router's
  // redirect would send the frame to `/` under the sign-in page's name.
  if (signedOutRoutes.contains(route)) {
    await FirebaseAuth.instance.signOut();
  } else {
    // Every signed-in hold signs in itself: a batch can arrive here signed out
    // (after a signed-out hold), and a session persisted on the simulator
    // from another emulator boot is not evidence of this one.
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  }
  final auth = AuthNotifier();
  final theme = ThemeNotifier();
  final router = createRouter(auth);
  await tester.pumpWidget(MultiProvider(
    // The app's own list (lib/app_providers.dart) — a copy here is how
    // F-72's ReviewInbox reached the app and not the hold.
    providers: appProviders(auth, theme: theme),
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
  // Plate I (ADR-178) is a pure function of time, so a frame taken seconds
  // after load is whatever instant its clock reached. Pause it and ask for
  // chapter 05's still — what web's theme-shots drives its landing frame to,
  // and what a reduced-motion visitor opens on.
  if (route == '/landing') await _stillThePlate(tester);
  await reachState(tester, h.state);
  // A state that focuses a field (the shelf picker's search, the create
  // sheet, a typed query) raises the SOFTWARE keyboard on a simulator with no
  // hardware keyboard attached — half the frame, and nothing the reference
  // frame has. Hidden, not unfocused: the caret stays where the reference's
  // is. (A fresh simulator has no hardware keyboard; the 2026-10-09 sitting's
  // reader-shelves frame was half keyboard.)
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

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
    debugPrint('HOLD:$label$mark');
    // A batch holds [batchHoldSeconds] (its driver shoots within seconds of
    // the marker); a single hold keeps the 30s a hand capture was given.
    for (var i = 0; i < (mark.isEmpty ? 150 : batchHoldSeconds * 5); i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  await hold('LIGHT', ThemeMode.light);
  await hold('DARK', ThemeMode.dark);
  await leaveState(tester, h.state);
}

/// Undo what [reachState] WROTE. A batch is one emulator boot, so a state that
/// changes stored data (not only the screen) would otherwise draw itself under
/// every later hold's name — the `reader` frame after `reader-priority` would
/// show High lit.
Future<void> leaveState(WidgetTester tester, String holdState) async {
  switch (holdState) {
    case 'sweep-tray':
    case 'sweep-tray-failed':
    case 'sweep-settings':
    case 'sweep-status':
      // OFF and empty: no later hold, and no device run, starts a pass.
      final host = _sweepHost(tester);
      await host.disable();
      host.service?.clearTray();
      final store = AppGroupLedgerStore();
      for (final k in SweepLedger.keys) {
        await store.write(k, null);
      }
    case 'recent-list':
      await LocalFlags.setView(LocalFlags.recentView, 'shelf');
    case 'sources-cards':
      await LocalFlags.setView(LocalFlags.sourcesView, 'shelf');
    case 'unpin-held':
      ApiService.instance.resetTestSeams();
    case 'letter-cards':
      // The card segment is the reader's stored choice; give the shelf
      // segment back, or every later Home frame draws the cards.
      await LocalFlags.setView(LocalFlags.shelvesView, 'shelf');
    case 'priority-high':
      await _pressPriority(tester, 'Default');
    case 'summary-reset-confirm':
      // The panel is cancelled — nothing it offers is sent — and the stored
      // style the hold wrote is taken away, as web's `fsRestoreSummaryPrompt`
      // puts back what it read (the seed holds none).
      final keep = find.text('Keep my style');
      if (keep.evaluate().isNotEmpty) {
        await tester.tap(keep.first);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      await Api.instance.updateSummarySettings(null);
  }
}

/// Pause the landing's film on chapter 05's still, then put the page back at
/// its top. The controls are below a phone's fold, so the page scrolls to
/// them first — on screen, a playing film's clock runs, which is how a play
/// is told from a pause.
Future<void> _stillThePlate(WidgetTester tester) async {
  final play = find.byKey(const ValueKey('reel-play'));
  if (play.evaluate().isEmpty) fail('the landing has no Plate I controls');
  final page = Scrollable.of(tester.element(play)).position;
  await tester.ensureVisible(play);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  String tc() =>
      tester.widget<Text>(find.textContaining(' / 00:36').first).data ?? '';
  Future<bool> moving() async {
    final a = tc();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return tc() != a;
  }

  if (await moving()) {
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (await moving()) fail('Plate I would not pause');
  await tester.tap(find.byKey(const ValueKey('reel-ch-4')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (tc() != '00:33 / 00:36') {
    fail('Plate I is at ${tc()}, not chapter 05\'s still');
  }
  page.jumpTo(0);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Bring a §19 rail jump on screen. Since the reader's Priority row (F-99)
/// the opening is taller than a phone's viewport, so the sticky rail starts
/// BELOW it — and a finder skips a sliver outside the viewport, so `find.text`
/// saw no jump at all ("No element", the 2026-10-13 batch). Found offstage,
/// then revealed by the WHOLE jump, not its label: the rail scrolls sideways,
/// and revealing the Text put the label at the rail's leading edge and cut
/// its glyph off (the 2026-10-07 speed-read frame). [sideways] false reveals
/// only the RAIL, vertically: a jump already in the rail's first view
/// (Manuscript) must not slide the rail, or the frame starts it where the
/// reference's never does (the 2026-10-13 manuscript frame lost "Summary").
Future<void> _revealRailJump(WidgetTester tester, String label,
    {bool sideways = true}) async {
  await tester.ensureVisible(sideways
      ? find
          .ancestor(
              of: find.text(label, skipOffstage: false).first,
              matching: find.byType(GestureDetector, skipOffstage: false))
          .first
      : find.byType(KitSectionRail, skipOffstage: false).first);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Press a segment of the reader's Priority row and wait for the server to
/// accept it — the segment moves only then (write before you move).
Future<void> _pressPriority(WidgetTester tester, String label) async {
  final track = find.descendant(
      of: find.byType(SourcePriorityRow), matching: find.byType(KitSegmented));
  String lit() {
    final seg = tester.widget<KitSegmented>(track);
    return seg.segments[seg.selected].label;
  }

  await tester.ensureVisible(track);
  await tester.pump(const Duration(milliseconds: 200));
  if (lit() == label) return;
  await tester.tap(find.descendant(of: track, matching: find.text(label)));
  for (var i = 0; i < 40 && lit() != label; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(lit(), label,
      reason: 'the Priority write was not accepted — the frame would show the '
          'row before the press');
}

/// Drive the screen into [holdState]. Bounded `pump` loops, never
/// `pumpAndSettle`: a screen with a live animation does not settle, and the
/// wait reads as green until something is actually pulsing on it.
Future<void> reachState(WidgetTester tester, String holdState) async {
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  switch (holdState) {
    case '':
      return;
    // The camera-roll sweep (F-125 S3) — `tool/sweep_tray_test.sh frames`
    // adds the three pages and sets full photo access first. Its frames pair
    // with the retired iOS app's (`NoteLetter/screenshots/sweep-tray*.ios.*`):
    // web has no sweep.
    case 'sweep-tray':
    case 'sweep-tray-failed':
    case 'sweep-settings':
    case 'sweep-status':
      await _reachSweep(tester, holdState);
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
      // The reference's own questions (theme-shots.mjs): `ask-thread` asks
      // about pasta COOKING, `ask-rail` about pasta — two pairs that compared
      // two different conversations until 2026-10-09.
      await tester.enterText(
          field,
          holdState == 'ask-thread'
              ? 'What have I been reading about pasta cooking?'
              : 'What have I been reading about pasta?');
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
        // The answer draws on `/ask` BEFORE the screen moves to the thread
        // it made (`context.go('/ask/thread/{id}')` follows the send): a
        // History tapped in between opened the rail on the page that was
        // about to be replaced, and the new page had it closed (the
        // 2026-10-12 batch). Wait for the thread's own page first.
        for (var i = 0; i < 50; i++) {
          final pages = find.byType(ChatPage).evaluate();
          if (pages.length == 1 &&
              (pages.single.widget as ChatPage).threadId != null) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 200));
        }
        await settle();
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
      // A refused turn hands the focus back to the composer, and on a device
      // that raises the KEYBOARD: half the screen, and the transcript — the
      // question, the server's sentence, Try again — squeezed out of the
      // frame. Every assertion above passed while the photograph showed an
      // empty scoped screen (F-78 (6), 2026-10-05 and 2026-10-09). The
      // reference's frame has no keyboard, so neither does this one.
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await settle();
      return;
    // reader.md §Panels — the manuscript is a BODY SWAP under the reader's one
    // header, not a route, so no URL reaches it and the frame has to select the
    // tab first. Without this the `reader-manuscript` pair would be two frames
    // of the summary panel under a filename claiming otherwise, which is worse
    // than no pair: a frame is evidence, and a mislabelled one is false
    // evidence nobody re-checks.
    case 'manuscript':
      await _revealRailJump(tester, 'Manuscript', sideways: false);
      await tester.tap(find.text('Manuscript').first);
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
    // Three sections the reference now frames (F-43): a rail jump each, as
    // `manuscript` is. `listen` draws the PLAYER only once
    // tool/seed_listen_audio.py has put a recording on the document — run it
    // before the shot and with `--remove` after, as the reference's own shot
    // does; without it this frame is the "No narration yet." empty state.
    case 'speed-read':
    case 'listen':
    case 'history':
      final label = {
        'speed-read': 'Speed read',
        'listen': 'Listen',
        'history': 'History',
      }[holdState]!;
      // The rail scrolls sideways on a phone: Listen and History start off
      // its right edge, and a tap there hits nothing. Revealed by the WHOLE
      // jump, not its label: revealing the Text put the label at the rail's
      // leading edge and cut its glyph off (the 2026-10-07 speed-read frame).
      await _revealRailJump(tester, label);
      await tester.tap(find.text(label).first);
      await settle();
      final panel = {
        'speed-read': SpeedReadPanel,
        'listen': ListenPanel,
        'history': HistoryPanel,
      }[holdState]!;
      expect(find.byType(panel), findsOneWidget,
          reason: 'the $label section did not mount');
      return;
    // §6.1 Waiting (4.107.0, ADR-140) — the reference's `summary-wait`: a
    // real 429 carrying `retry_after_s`, from Regenerate summary. The refusal
    // is the SERVER's: stamp the seed document's `last_summary_regen_at`
    // ahead of its clock first (the wait is capped at the 60s window, so it
    // holds for the whole batch), as web theme-shots stamps it; this hold only
    // presses, and waits for the countdown on the control.
    case 'summary-wait':
      // Offstage on open: on a phone the chapter opening fills the screen,
      // and a default finder skips what is not painted, so the first shot of
      // this hold found no control at all (2026-10-07). Find it mounted,
      // bring it on, then press the on-screen one. Summary is a plain sliver,
      // not the pinned rail, so this reveal lands where it says.
      final mounted =
          find.textContaining('Regenerate summary', skipOffstage: false);
      expect(mounted, findsOneWidget, reason: 'no Regenerate summary control');
      await Scrollable.ensureVisible(tester.element(mounted),
          alignment: 0.45, duration: Duration.zero);
      await settle();
      final regen = find.textContaining('Regenerate summary');
      expect(regen, findsOneWidget,
          reason: 'Regenerate summary was not brought on screen');
      await tester.tap(regen);
      final waiting = find.textContaining('Regenerate summary · ');
      for (var i = 0; i < 75 && waiting.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(waiting, findsOneWidget,
          reason: 'the control is not waiting — was last_summary_regen_at '
              'stamped ahead? This frame would be the idle panel');
      return;
    // §6.1 Waiting (4.107.0, ADR-140) — web's four held cooldowns
    // (theme-shots `letter-send-wait`, `study-wait`, `retry-wait`,
    // `sync-wait`, 7ef365c). `tool/seed_wait_states.py` stamps each endpoint's
    // own cooldown field first; the hold presses the control, and the frame is
    // of something only if the SERVER refused it — the held label counting
    // down (` · m:ss`) is that refusal's own number.
    case 'letter-send-wait':
    case 'study-wait':
    case 'retry-wait':
    case 'sync-wait':
      final label = switch (holdState) {
        'letter-send-wait' => 'Send now',
        'study-wait' => 'Study now',
        'retry-wait' => 'Retry',
        _ => 'Sync now',
      };
      final Finder control;
      if (holdState == 'retry-wait') {
        // The seed's failed DOCX (seed-doc-error, "corrupt.docx") — the
        // document the seed stamps — and its own row's Retry: another failed
        // row's Retry is ACCEPTED (2026-10-14, the first run pressed the
        // overlay's scan and retried it).
        final row = find.ancestor(
            of: find.text('corrupt.docx', skipOffstage: false),
            matching: find.byType(KitProcCard, skipOffstage: false));
        for (var i = 0; i < 60 && row.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(row, findsOneWidget, reason: 'no row for seed-doc-error');
        control = find.descendant(
            of: row, matching: find.text(label, skipOffstage: false));
      } else {
        control = find.text(label, skipOffstage: false);
        for (var i = 0; i < 60 && control.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      expect(control, findsWidgets, reason: 'no $label control');
      await Scrollable.ensureVisible(tester.element(control.first),
          alignment: 0.45, duration: Duration.zero);
      await settle();
      await tester.tap(control.first);
      final waiting = find.textContaining(RegExp('^$label · \\d+:\\d\\d\$'));
      for (var i = 0; i < 75 && waiting.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(waiting, findsOneWidget,
          reason: '$label is not waiting — run tool/seed_wait_states.py '
              'first; this frame would be the control at rest');
      await Scrollable.ensureVisible(tester.element(waiting.first),
          alignment: 0.45, duration: Duration.zero);
      await settle();
      return;
    // reader.md §Recipe body — the §5.4 body swap. Same route, same header,
    // same Manuscript panel: only the BODY differs, which is the whole claim
    // the pattern makes, so the frame has to be the manuscript of a distilled
    // document rather than a screen of its own.
    case 'recipe':
      await _revealRailJump(tester, 'Manuscript', sideways: false);
      await tester.tap(find.text('Manuscript').first);
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
    // component-kit §15.1 / §15.2 — the §15 overlay SHEET opened from a
    // processing row on Sources, as the reference frames both (theme-shots
    // `source-file`, `source-set`): a failed DOCX whose bytes are stored, and
    // a pending image set with two of three pages landed. These holds framed
    // the reader's Original section until F-82 — another surface under the
    // same name, so the pairs compared nothing. Run
    // tool/seed_overlay_sources.py first, and with `--remove` after.
    case 'source-file':
    case 'source-set':
      await settle();
      final title = holdState == 'source-file'
          ? 'minutes-2026-08.docx'
          : 'Kitchen notebook, three pages';
      final row = find.ancestor(
          of: find.text(title), matching: find.byType(KitProcCard));
      expect(row, findsOneWidget,
          reason: 'run tool/seed_overlay_sources.py first — no processing '
              'row for "$title"');
      // A set's control is "View images", a file's "View file"
      // (source_sheet.dart, the reference's `.proc-view` labels).
      final view = find.descendant(
          of: row,
          matching: find.text(
              holdState == 'source-file' ? 'View file' : 'View images'));
      await tester.ensureVisible(view);
      await settle();
      await tester.tap(view);
      final want = holdState == 'source-file'
          ? find.byType(KitSourceFileView)
          : find.byType(KitSourceSetGallery);
      for (var i = 0; i < 60 && want.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(want, findsOneWidget,
          reason: 'the §15 sheet did not open on its viewer');
      await settle();
      return;
    // component-kit §15.1 rule 4 (5.10.0, ADR-170; F-117) — theme-shots
    // `source-stitched`: a stitched scroll mid-indexing, its row's View file
    // opening the §15 sheet on a TALL picture — at the stage's width, the stage
    // scrolling, captioned "Joined from 6 screenshots of one scroll." Run
    // `tool/seed_overlay_sources.py --stitched` first, and with `--remove` after.
    case 'source-stitched':
      await settle();
      final row = find.ancestor(
          of: find.text('A long thread, six screenshots'),
          matching: find.byType(KitProcCard));
      expect(row, findsOneWidget,
          reason: 'run tool/seed_overlay_sources.py --stitched first');
      final view = find.descendant(of: row, matching: find.text('View file'));
      await tester.ensureVisible(view);
      await settle();
      await tester.tap(view);
      final caption = find.text('Joined from 6 screenshots of one scroll.');
      for (var i = 0; i < 60 && caption.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(caption, findsOneWidget,
          reason: 'the §15 sheet did not open on the stitched picture');
      // The picture's bytes: a bounded pump, never pumpAndSettle.
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
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
    // settings.md 4.108.0 — Reset to default is destructive and confirms
    // first: web's `summary-reset-confirm`, the §18 panel over a stored custom
    // style. The style is WRITTEN (through fn_summary_settings, the way the
    // reader would save it), the reset is pressed, and the panel is held; it
    // is cancelled and the style removed in [leaveState].
    case 'summary-reset-confirm':
      await Api.instance.updateSummarySettings(
          'Summarize as a field note: what the source claims, in two plain '
          'sentences.');
      final reset = find.text('Reset to default', skipOffstage: false);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (reset.evaluate().isNotEmpty) break;
      }
      expect(reset, findsWidgets,
          reason: 'no Reset to default — the stored style did not reach '
              'Settings, so this frame would be the default style');
      await tester.ensureVisible(reset.first);
      await settle();
      await tester.tap(reset.first);
      await settle();
      expect(find.byType(KitConfirm), findsOneWidget,
          reason: 'Reset to default sent nothing and opened no §18 panel');
      return;
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
        // A processing card since 4.98.0 (F-69), no longer a §4.1 row.
        matching: find.byType(KitProcCard),
      );
      expect(failed, findsOneWidget,
          reason: 'run tool/seed_recipe_and_sources.py first — without a '
              'failed document that HAS its bytes there is no stage to shoot');
      final view = find.descendant(of: failed, matching: find.text('View file'));
      // The control sits in the card's attention strip, which is under the
      // fold at rest — a tap at its unscrolled
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
    // settings disclosure, which no route reaches. The shelf the reference
    // frames is Stories (`/shelves/seed-tag-stories`), the seed's auto-created
    // shelf, whose legacy hex draws the eleventh, read-only swatch (ruled
    // 2026-10-08); a shelf holding one of the ten draws ten.
    case 'color-picker':
      await tester.tap(find.widgetWithText(KitButton, 'Settings'));
      await settle();
      expect(find.byType(KitSwatch), findsAtLeastNWidgets(10),
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
    // The reference's state (F-90 (3)): web theme-shots' readings letter —
    // Friday of week 18 — with the Psalm's search made to fail, so the frame
    // carries the partial notice, the `—` count and the §14.2 line. Run
    // tool/seed_frame_states.py first (and `--remove` after).
    case 'scripture-day':
      // By the ROW's own type: the same text is in the card above it, where
      // it is not a control, and a tap that lands on nothing is silent.
      final row = find.byWidgetPredicate((w) =>
          w is KitLetterRow && w.title.contains('Friday of week 18'));
      // The readings rows sit below the latest letters, past a phone's
      // fold, in a list that builds only what it shows: scroll for it.
      for (var i = 0; i < 20 && row.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await settle();
      }
      expect(row, findsOneWidget,
          reason: 'run tool/seed_frame_states.py first — no readings letter '
              'for Friday of week 18 to open');
      await tester.ensureVisible(row);
      await settle();
      await tester.tap(row);
      await settle();
      final seeAll = find.textContaining('passages for this day');
      expect(seeAll, findsOneWidget,
          reason: 'the letter did not open — this frame would be the list');
      await tester.ensureVisible(seeAll);
      await settle();
      // A REAL refusal, as the reference's: the Psalm's search goes out with
      // `sourceTypes` as a string, which the backend refuses with its own
      // sentence and reference id.
      ApiService.instance.httpClientAdapter = _FailOneReading();
      await tester.tap(seeAll);
      // Three live searches, each a round trip through the shim.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(KitFailureInline).evaluate().isNotEmpty ||
            find.byType(KitFailureBlock).evaluate().isNotEmpty) {
          break;
        }
      }
      await settle();
      ApiService.instance.resetTestSeams();
      expect(find.text('Back to the letter'), findsOneWidget,
          reason: 'the day did not open — this frame would be the letter');
      expect(find.textContaining('One reading could not be searched',
              findRichText: true),
          findsOneWidget,
          reason: 'no partial notice — the failure was not armed');
      return;
    // component-kit §20.1 Shelf picker (4.104.0, ADR-137; QUEUE F-39) — the
    // reader's Shelves row with its picker open, and searched for "st" (a
    // prefix match ranked, its run in 600, the create row naming the query),
    // as the reference's `reader-shelves` / `shelf-picker-search` frames are.
    // reader.md §Source priority (F-99) — web's `reader-priority`: High
    // chosen through a REAL fn_update_document (the shim), so the lit segment
    // and the 0.80 beside it are the server's answer. [leaveState] presses
    // Default after both frames: the seed carries no stamp.
    case 'priority-high':
      await _pressPriority(tester, 'High');
      // The row back at the reference frame's place: the header above it.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 2000));
      await settle();
      return;
    case 'shelf-picker':
    case 'shelf-picker-search':
      final plus = find.text('Shelf');
      await tester.ensureVisible(plus);
      await settle();
      await tester.tap(plus);
      await settle();
      final search = find.byKey(const ValueKey('shelf-pick-search'));
      expect(search, findsOneWidget,
          reason: 'the picker did not open — this frame would be the row');
      if (holdState == 'shelf-picker-search') {
        await tester.enterText(search, 'st');
        await settle();
      }
      return;
    // `shelf-backfill-review` is RETIRED. Since 4.102.0 (F-72 f) Create with
    // backfill requests a background task and the review waits in For your
    // review — the sheet closes on create. Left reachable, this state
    // photographed the shelves index under the review's name (2026-10-05):
    // false evidence, so it fails. The reference frame is as old as the state
    // (web theme-shots still waits for `.bf-list`, which nothing draws now);
    // the review's pair is web's `review-backfill`, which needs a stored
    // shelf_backfill task to shoot.
    case 'shelf-backfill-review':
      fail('shelf-backfill-review is retired (4.102.0): the backfill review '
          'is a background task now — shoot review-backfill on /review');
    // library.md §Creating a shelf (4.83.0, ADR-117; QUEUE F-38) — the §15
    // sheet over the shell, as the reference's frames open it from the rail's
    // `+`. On a phone the rail is a drawer, so the sheet is opened through the
    // one function the `+` calls. Filled, never submitted: nothing is created.
    case 'shelf-create-sheet':
      final ctx = tester.element(find.byType(Scaffold).first);
      unawaited(showShelfSheet(
        ctx,
        canBackfill: true,
        land: (_) {},
        create: (title, {description, color, parentTagId}) => Api.instance
            .createTag(title, description: description, color: color),
      ));
      await settle();
      final fields = find.descendant(
          of: find.byType(KitOverlaySheet), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Pasta');
      await tester.enterText(
          fields.at(1), 'Fresh and dried pasta, shapes and sauces.');
      await settle();
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
    // library.md §The letter chip (ruled 2026-10-14) — web 91026a9's
    // `library-letter-chips` / `library-letter-off` (the Shelves section's
    // shelf segment, Stories' head at the top) and `library-letter-cards`
    // (the card segment, its section header at the top).
    // `tool/seed_letter_chips.py [--off]` writes the data first.
    case 'letter-chips':
    case 'letter-cards':
      final cards = holdState == 'letter-cards';
      await LocalFlags.setView(LocalFlags.shelvesView, cards ? 'card' : 'shelf');
      await settle();
      final target = cards
          ? find.textContaining(RegExp(r'^shelves · \d', caseSensitive: false),
              skipOffstage: false)
          : find.ancestor(
              of: find.text('Stories', skipOffstage: false),
              matching: find.byType(KitShelfUnit, skipOffstage: false));
      for (var i = 0; i < 60 && target.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(target, findsWidgets,
          reason: cards ? 'no Shelves section' : 'no Stories shelf unit');
      await Scrollable.ensureVisible(tester.element(target.first),
          alignment: 0.0, duration: Duration.zero);
      await settle();
      return;
    // Web follow-up 3's rulings (2026-10-14; contracts b39e72a, web 7f85b50).
    // `tool/seed_followup3.py uncounted|pinned|stalled` writes the state each
    // needs first, one at a time, and `--remove` puts it back.
    //
    // 1 · library-uncounted: Home's Recently read as its LIST, the uncounted
    // source's count cell empty. sources-uncounted: Sources' card view.
    case 'recent-list':
    case 'sources-cards':
      final list = holdState == 'recent-list';
      await LocalFlags.setView(
          list ? LocalFlags.recentView : LocalFlags.sourcesView,
          list ? 'list' : 'cards');
      await settle();
      // The uncounted source's own card (web shoots the whole card grid).
      final at = list
          ? find.textContaining(RegExp(r'^recently read', caseSensitive: false),
              skipOffstage: false)
          : find.ancestor(
              of: find.text('Quarterly Tax Summary', skipOffstage: false),
              matching: find.byType(KitSourceCard, skipOffstage: false));
      for (var i = 0; i < 60 && at.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(at, findsWidgets,
          reason: list ? 'no Recently read list' : 'no source cards');
      await Scrollable.ensureVisible(tester.element(at.first),
          alignment: list ? 0.0 : 0.3, duration: Duration.zero);
      await settle();
      return;
    // 2 · reader-type: the Aa popover open over the manuscript — §6.8's
    // compact variant.
    case 'reader-type':
      await _revealRailJump(tester, 'Manuscript', sideways: false);
      await tester.tap(find.text('Manuscript').first);
      await settle();
      final aa = find.widgetWithText(KitButton, 'Aa', skipOffstage: false);
      expect(aa, findsOneWidget, reason: 'no Aa control on the manuscript');
      await Scrollable.ensureVisible(tester.element(aa),
          alignment: 0.2, duration: Duration.zero);
      await settle();
      await tester.tap(aa);
      await settle();
      expect(find.byType(OverlayPortal), findsWidgets);
      return;
    // ...and onboarding-letter: setup's fourth step, How often the standard
    // sized track.
    case 'onboarding-letter':
      await tester.tap(find.widgetWithText(KitButton, 'Run setup'));
      await settle();
      await tester.tap(find.text('Begin'));
      await settle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await settle();
      }
      // By the track's own group name: the field's label is drawn in caps.
      expect(
          find.byWidgetPredicate(
              (w) => w is KitSegmented && w.groupLabel == 'How often'),
          findsOneWidget,
          reason: 'setup did not reach its letter step');
      return;
    // 3 · letters-unpin-held: the pinned source's Unpin while its write is in
    // flight — the write held open by an adapter that never answers, as web
    // routes it; [leaveState] gives the real one back.
    case 'unpin-held':
      final unpin = find.text('Unpin', skipOffstage: false);
      for (var i = 0; i < 60 && unpin.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(unpin, findsOneWidget,
          reason: 'no pinned source — run tool/seed_followup3.py pinned first');
      await Scrollable.ensureVisible(tester.element(unpin),
          alignment: 0.4, duration: Duration.zero);
      await settle();
      ApiService.instance.httpClientAdapter = _NeverAnswers('/fn_update_document');
      await tester.tap(unpin);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Unpinning…'), findsOneWidget);
      return;
    // 4 · activity-stalled: the stalled queued document drawn Stalled.
    case 'activity-stalled':
      final chip = find.text('STALLED', skipOffstage: false);
      for (var i = 0; i < 75 && chip.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(chip, findsWidgets,
          reason: 'no Stalled row — run tool/seed_followup3.py stalled first');
      await Scrollable.ensureVisible(tester.element(chip.first),
          alignment: 0.3, duration: Duration.zero);
      await settle();
      return;
    // 5 · activity-retry-error: the newest failure row's Retry, refused with
    // a REAL 404 — the request goes out naming a document that does not
    // exist, as web rewrites it, so "Not found" is the backend's own.
    case 'activity-retry-error':
      final retry = find.widgetWithText(KitButton, 'Retry', skipOffstage: false);
      for (var i = 0; i < 75 && retry.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(retry, findsWidgets, reason: 'no Retry on a failed document row');
      await Scrollable.ensureVisible(tester.element(retry.first),
          alignment: 0.4, duration: Duration.zero);
      await settle();
      ApiService.instance.httpClientAdapter = _RewriteRetryDoc();
      await tester.tap(retry.first);
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        final confirm = find.text('Retry and replace');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.last);
        }
        if (find.byType(KitFailureInline).evaluate().isNotEmpty) break;
      }
      ApiService.instance.resetTestSeams();
      expect(find.byType(KitFailureInline), findsWidgets,
          reason: 'no refusal rendered — this frame would be the Retry');
      await settle();
      return;
    // reader.md §Source freshness (5.12.0, ADR-172; F-118) — web's
    // reader-original-update: the Original section, its "Imported from
    // {Provider}" line and Update from {Provider} beneath the intro, before
    // the file. The seed PDF came from Google Drive.
    case 'original-update':
      await _revealRailJump(tester, 'Original', sideways: true);
      await tester.tap(find.text('Original').first);
      await settle();
      final update = find.textContaining(RegExp(r'^Update from '),
          skipOffstage: false);
      for (var i = 0; i < 60 && update.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(update, findsOneWidget,
          reason: 'no Update from {Provider} in the Original section');
      // Scroll only if the button is below the fold. The rail marks the
      // section at the top of the page, so pulling the button to 0.3 moved
      // Original down and framed it under a lit *Listen* (2026-10-17).
      await Scrollable.ensureVisible(tester.element(update),
          duration: Duration.zero,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      await settle();
      return;
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
    // sources.md §Organized folders — Rescan all held on the PROVIDER's clock
    // (4.107.0 / 4.108.0, ADR-140 / ADR-145; Flutter adad438), the reference's
    // `org-scan-wait`. The refusal is the server's: stamp the Drive
    // integration's `organization.last_manual_scan_at` to now first, as web
    // theme-shots does, and remove it after. This hold only presses Rescan
    // all and waits for the 409's countdown on the link.
    // sources.md §Cloud import / §Trust & feedback (F-102) — web's
    // `import-activity` and `import-activity-failed`: an import job's card,
    // framed with its section at the top (the reference scrolls the header to
    // 32px under whatever covers the page). The seed's own jobs, nothing
    // written: `old-notes.pdf` waits in Cloud imports; Import history, opened,
    // holds taxes.pdf imported, its duplicate (View · Import again) and
    // report.docx failed ("download failed: 503 from provider").
    case 'import-activity':
    case 'import-activity-failed':
      final failed = holdState == 'import-activity-failed';
      final head = failed ? 'IMPORT HISTORY' : 'CLOUD IMPORTS';
      final header = find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? '').toUpperCase().startsWith(head));
      final row = find.text(failed ? 'report.docx' : 'old-notes.pdf');
      for (var i = 0; i < 60 && header.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(header, findsWidgets,
          reason: 'no $head section — the seed\'s import jobs did not load');
      if (failed) {
        final show = find.textContaining(RegExp(r'^Show \d+$'));
        await tester.ensureVisible(show.first);
        await settle();
        await tester.tap(show.first);
      }
      for (var i = 0; i < 60 && row.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(row, findsWidgets, reason: 'the section drew no import card');
      final el = tester.element(header.first);
      await Scrollable.ensureVisible(el);
      await settle();
      final pos = Scrollable.of(el).position;
      pos.jumpTo((pos.pixels - 32).clamp(0, pos.maxScrollExtent));
      await settle();
      return;
    case 'org-scan-wait':
      final rescan = find.textContaining(RegExp(r'^Rescan all'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (rescan.evaluate().isNotEmpty) break;
      }
      expect(rescan, findsWidgets,
          reason: 'no Organized folders header — is organization enabled on '
              'the seed Drive integration?');
      await tester.ensureVisible(rescan.first);
      await settle();
      await tester.tap(rescan.first);
      final held = find.textContaining(RegExp(r'^Rescan all · \d:\d\d$'));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (held.evaluate().isNotEmpty) break;
      }
      // On a scratch boot nothing has stamped `last_manual_scan_at`, so the
      // first Rescan all is ACCEPTED (202) and starts no clock; it stamps it,
      // and the second is refused with the cooldown — the state framed.
      if (held.evaluate().isEmpty) {
        final again = find.text('Rescan all');
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (again.evaluate().isNotEmpty) break;
        }
        await tester.tap(again.first);
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (held.evaluate().isNotEmpty) break;
        }
      }
      expect(held, findsOneWidget,
          reason: 'Rescan all is not held — stamp '
              'organization.last_manual_scan_at first, or the frame is the '
              'panel at rest under this name');
      await Scrollable.ensureVisible(tester.element(held.first),
          alignment: 0.15, duration: Duration.zero);
      await settle();
      return;
    // sources.md §Sync control — the sync-folder chooser (F-67), which no
    // route reaches: the Drive sync panel opened from its "Import from" header
    // (the connect card is fixed since 2026-10-08), then its folder picker.
    // Needs the shim under NL_DEV_FAKES=1 for the Drive tree.
    //
    // `sync-folders` is web's frame since 5.12.0 (F-118): the panel's Sync
    // folders group — its chips and Change folders… — not the picker, because
    // the panel is now taller than a screen and web crops to the group.
    // `sync-auto-update` is the auto-sync group with 5.12.0's second switch,
    // "Update changed files automatically", and its caption (ADR-172).
    case 'sync-folders':
    case 'sync-auto-update':
    case 'sync-folders-saved':
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Sync settings').evaluate().isNotEmpty) break;
      }
      await tester.ensureVisible(find.text('Sync settings').first);
      await tester.tap(find.text('Sync settings').first);
      await settle();
      if (holdState != 'sync-folders-saved') {
        final at = holdState == 'sync-auto-update'
            ? find.text('Update changed files automatically',
                skipOffstage: false)
            : find.textContaining(RegExp(r'^(Choose|Change) folders…$'),
                skipOffstage: false);
        for (var i = 0; i < 40 && at.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(at, findsWidgets,
            reason: holdState == 'sync-auto-update'
                ? 'no Update changed files automatically row'
                : 'no Sync folders group');
        await Scrollable.ensureVisible(tester.element(at.first),
            alignment: 0.5, duration: Duration.zero);
        await settle();
        return;
      }
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
      // 5.9.0 (look-only; web has no frame): tick the first folder not yet
      // chosen, save, and hold the panel's chips — the saved folder drawn by
      // the name the picker listed it under, sent as `folder_names` and read
      // back from the RETURNED integration, not by its provider id.
      final unticked = find.byWidgetPredicate(
          (w) => w is KitCheckbox && w.value == false && w.onChanged != null);
      expect(unticked, findsWidgets, reason: 'no folder left to choose');
      await tester.tap(unticked.first);
      await settle();
      final save = find.textContaining(RegExp(r'^Sync \d+ folders?$'));
      expect(save, findsOneWidget, reason: 'no Sync N folders button');
      await tester.ensureVisible(save);
      await tester.tap(save);
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(SyncFolderPicker).evaluate().isEmpty) break;
      }
      expect(find.byType(SyncFolderPicker), findsNothing,
          reason: 'the save was not answered — the picker is still open');
      final chips = find.byType(KitTag);
      expect(chips, findsWidgets, reason: 'no folder chip after the save');
      await Scrollable.ensureVisible(tester.element(chips.first),
          alignment: 0.35, duration: Duration.zero);
      await settle();
      return;
    default:
      fail('hold_screen_test knows no HOLD_STATE "$holdState"');
  }
}


/// Forwards every request to the real transport, with the Psalm's
/// `fn_search_notes` carrying `sourceTypes` as a string — not a list
/// Firestore's `in` can take — so the readings day's failed row is the
/// backend's own refusal, as web theme-shots' `scripture-day` arms it.
class _FailOneReading implements HttpClientAdapter {
  final _inner = IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final data = options.data;
    if (!options.path.endsWith('/fn_search_notes') ||
        data is! Map ||
        data['query'] != 'Psalm 42') {
      return _inner.fetch(options, requestStream, cancelFuture);
    }
    final body = utf8.encode(jsonEncode({...data, 'sourceTypes': 'pdf'}));
    options.headers['content-length'] = body.length.toString();
    return _inner.fetch(
        options, Stream.value(Uint8List.fromList(body)), cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// Forwards every request to the real transport, with `fn_update_tag`'s
/// `letter_mode` swapped for a value outside the closed set — so the refusal
/// in the `shelf-letter-error` frame is the backend's, not one this test wrote.
/// A request to [path] that never answers — the in-flight state web routes
/// with `page.route(…, () => {})`. Every other request goes through.
class _NeverAnswers implements HttpClientAdapter {
  _NeverAnswers(this.path);
  final String path;
  final _inner = IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (options.path.endsWith(path)) return Completer<ResponseBody>().future;
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// fn_retry_document sent for a document that does not exist, so the 404 and
/// its sentence are the backend's own (web's activity-retry-error).
class _RewriteRetryDoc implements HttpClientAdapter {
  final _inner = IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (!options.path.endsWith('/fn_retry_document') || options.data is! Map) {
      return _inner.fetch(options, requestStream, cancelFuture);
    }
    final body = utf8.encode(jsonEncode(
        {...(options.data as Map), 'docId': 'shot-no-such-document'}));
    options.headers['content-length'] = body.length.toString();
    return _inner.fetch(
        options, Stream.value(Uint8List.fromList(body)), cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

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


// ── The camera-roll sweep's holds (F-125 S3) ─────────────────────────────────

CameraSweepHost _sweepHost(WidgetTester tester) => Provider.of<CameraSweepHost>(
    tester.element(find.byType(NoteLetterApp)),
    listen: false);

/// The frames' pages are dated 2026-10-10..12 (tool/sweep_test_photos.py
/// --pages); the device test's photos are older, so this window holds only
/// the pages.
final _pagesSince = DateTime.utc(2026, 10, 10);

Future<void> _reachSweep(WidgetTester tester, String state) async {
  Future<void> pumpFor(int ms) async {
    for (var i = 0; i < ms ~/ 200; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  final host = _sweepHost(tester);
  await host.ready;
  final bridge = host.bridge!;
  if (await bridge.access() != SweepAccess.granted) {
    throw StateError('no full photo access — run through '
        'tool/sweep_tray_test.sh frames');
  }
  await host.setBackfillStart(_pagesSince);

  // The book page is ALREADY IN NoteLetter, its bytes landed: what a photo
  // the Swift app swept looks like. Filed through the session, completed
  // through the emulator's REST (owner bearer), as the pipeline would.
  final page = await bridge.fetchImages(since: _pagesSince);
  // A listing carries no filename (5.40.0): identify each to find the page.
  final identified = [
    for (final l in page.assets) await bridge.identify(l.localIdentifier)
  ];
  final book = identified.firstWhere((a) => a.originalFilename == 'sweep-page-book.jpg');
  final opened = await Api.instance.createCaptureSession(
    assetKey: book.assetKey,
    filename: 'sweep-page-book.jpg',
    mimeType: 'image/jpeg',
    size: 1000,
    capturedAt: DateTime.utc(2026, 10, 10, 9),
  );
  final rest = Dio(BaseOptions(
    baseUrl: 'http://${ApiService.emulatorHost}:${ApiService.firestorePort}'
        '/v1/projects/${DefaultFirebaseOptions.currentPlatform.projectId}'
        '/databases/(default)/documents',
    headers: {'Authorization': 'Bearer owner'},
  ));
  await rest.patch('/documents/${opened['docId']}',
      queryParameters: {'updateMask.fieldPaths': 'status'},
      data: {
        'fields': {'status': {'stringValue': 'complete'}},
      });

  await host.enable();
  final svc = host.service!;
  for (var i = 0; i < 300 && (svc.isSweeping || svc.candidates.isEmpty); i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (svc.candidates.isEmpty) throw StateError('the pass found no candidates');
  if (state == 'sweep-settings' || state == 'sweep-status') {
    for (var i = 0; i < 50 && host.inRange == null; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await pumpFor(1000);
    if (state == 'sweep-status') {
      // The lower half: Catch up's figure, Status and Start over.
      await Scrollable.ensureVisible(
          tester.element(find.text('Photos in range').first),
          alignment: 0.1, duration: Duration.zero);
      await pumpFor(1000);
    }
    return;
  }
  if (!svc.candidates.any((a) => svc.alreadyIn(a.localIdentifier))) {
    throw StateError('no card is already in — this frame would not show it');
  }
  if (state == 'sweep-tray-failed') {
    final fresh = svc.candidates.firstWhere((a) => !svc.alreadyIn(a.localIdentifier));
    final add = find.descendant(
        of: find.byKey(ValueKey(fresh.localIdentifier)),
        matching: find.byTooltip('Add this photo'));
    await tester.ensureVisible(add);
    await pumpFor(400);
    await tester.tap(add);
    for (var i = 0; i < 150 && svc.candidateErrors.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (svc.candidateErrors.isEmpty) throw StateError('the add was not refused');
  }
  await pumpFor(600);
  // The tray at the top of the frame, as the iOS frames have it: on Sources
  // it closes "Add to your library", below the drop zone.
  final head = find.textContaining('FROM YOUR CAMERA ROLL');
  await Scrollable.ensureVisible(tester.element(head.first),
      alignment: 0.0, duration: Duration.zero);
  await pumpFor(2000);
}
