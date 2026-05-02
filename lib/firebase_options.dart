import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'DefaultFirebaseOptions for native platforms not configured. '
      'Run flutterfire configure for iOS/Android support.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDQpRub5G2HH1Co9iW_sDHtRJzh9Nn5PZg',
    appId: '1:1018561733026:web:9873e0f42ab3db6c9312fb',
    messagingSenderId: '1018561733026',
    projectId: 'luxletter-b7a40',
    authDomain: 'luxletter-b7a40.firebaseapp.com',
    storageBucket: 'luxletter-b7a40.appspot.com',
    measurementId: 'G-BLW43SHTQW',
  );
}
