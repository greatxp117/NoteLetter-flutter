import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Whether **Continue with Google** can work on this build (F-44a).
///
/// Google sign-in needs native configuration that no Dart code can create, and
/// both halves fail badly when it is absent: iOS raises an uncatchable
/// NSException on the tap when the reversed client id is not a registered URL
/// scheme, and Android answers a DEVELOPER_ERROR from Credential Manager when
/// no Android OAuth client (the SHA-1 fingerprint) exists for the package. So
/// the button asks here first and, when the platform is not set up, says so in
/// the failure slot — "Google sign-in is not set up on this build." — rather
/// than crashing or failing with a library code.
///
/// The two flags are **not** hand-maintained claims:
/// `test/contract/google_sign_in_setup_test.dart` reads
/// `ios/Runner/Info.plist`, `ios/Runner/GoogleService-Info.plist` and
/// `android/app/google-services.json` and fails whenever a flag disagrees with
/// what the files hold — so re-downloading a config after the console step
/// turns the test red until the flag follows.
class GoogleSignInSetup {
  GoogleSignInSetup._();

  /// `GoogleService-Info.plist` carries `REVERSED_CLIENT_ID` and `Info.plist`
  /// registers it as a URL scheme.
  static const bool iosReady = true;

  /// `google-services.json` has an Android OAuth client (`client_type` 1).
  /// It does not yet: no SHA-1 fingerprint is registered for
  /// `xp.NoteLetter.Flutter` in the Firebase console.
  static const bool androidReady = false;

  /// The web OAuth client (`client_type` 3 in `google-services.json`) —
  /// Android's Credential Manager asks for an id token minted FOR this client,
  /// because that is the audience Firebase Auth verifies.
  static const String webClientId =
      '402841655223-h6f2mc0ir141s18smscd6shvqkspsr44.apps.googleusercontent.com';

  /// iOS's own client, from the same plist `firebase_options.dart` was
  /// generated from.
  static String? get iosClientId => DefaultFirebaseOptions.ios.iosClientId;

  static const String notSetUp = 'Google sign-in is not set up on this build.';

  /// Web signs in through Firebase's own popup and needs nothing native.
  static bool get available {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return iosReady && (iosClientId?.isNotEmpty ?? false);
      case TargetPlatform.android:
        return androidReady;
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }
}
