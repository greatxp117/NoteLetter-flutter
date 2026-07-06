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
    apiKey: 'AIzaSyBzWYtLfv9HHLZ1QQ-jM74AqcLnrn9op5M',
    appId: '1:402841655223:web:490590af9a3c84dc6f7a32',
    messagingSenderId: '402841655223',
    projectId: 'noteletter-7a111',
    authDomain: 'noteletter-7a111.firebaseapp.com',
    storageBucket: 'noteletter-7a111.firebasestorage.app',
  );
}
