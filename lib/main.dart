import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/api_service.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'router.dart';
import 'state/auth_notifier.dart';
import 'state/upload_notifier.dart';
import 'state/search_notifier.dart';
import 'state/chat_notifier.dart';
import 'state/activity_notifier.dart';
import 'state/settings_notifier.dart';
import 'state/newsletter_notifier.dart';
import 'state/cloud_notifier.dart';
import 'state/org_notifier.dart';
import 'state/tags_notifier.dart';
import 'state/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Umbrella law 1: Firestore/Functions development runs against the emulator
  // suite, never prod `noteletter-7a111`. This client points at REAL PROD by
  // default and writes real counters, so the switch is compile-time
  // (`--dart-define=USE_EMULATOR=true`, per /emu) and cannot be flipped at
  // runtime by accident.
  if (ApiService.useEmulator) {
    final host = ApiService.emulatorHost;
    FirebaseFirestore.instance
        .useFirestoreEmulator(host, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(host, ApiService.authPort);
    // No Storage redirect: this client has no firebase_storage dependency —
    // uploads go through signed GCS URLs minted by fn_create_upload_session
    // (INV-08), so there is no Storage SDK here to point anywhere.
    debugPrint('NoteLetter: EMULATOR mode — $host (functions '
        '${ApiService.functionsPort}, firestore ${ApiService.firestorePort}, '
        'auth ${ApiService.authPort})');
  }

  final authNotifier = AuthNotifier();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: authNotifier),
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
      child: NoteLetterApp(router: createRouter(authNotifier)),
    ),
  );
}
