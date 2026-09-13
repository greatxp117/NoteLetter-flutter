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
      }
      return;
    default:
      fail('hold_screen_test knows no HOLD_STATE "$holdState"');
  }
}
