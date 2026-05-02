import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
      ],
      child: NoteLetterApp(router: createRouter(authNotifier)),
    ),
  );
}
