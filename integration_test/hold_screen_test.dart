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
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';
const route = String.fromEnvironment('HOLD_ROUTE', defaultValue: '/activity');

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
        ChangeNotifierProvider<CloudNotifier>(create: (_) => CloudNotifier()),
        ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => TagsNotifier()),
        ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
      ],
      child: NoteLetterApp(router: router),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    router.go(route);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> hold(String label, ThemeMode mode) async {
      await theme.setMode(mode);
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
