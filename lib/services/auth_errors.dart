import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_sign_in_setup.dart';

/// One error vocabulary for every signed-out surface — the reference's
/// `shared/authErrors.js`, sentence for sentence.
///
/// The FlutterFire SDK reports the same Identity Platform codes the web SDK
/// does, without the `auth/` prefix, so the map is keyed on the bare code.
/// These are SDK codes, never our endpoint envelope (INV-01 is about `fn_*`),
/// so §14.2's inline line is the form and there is no reference id to show.
///
/// Firebase's own `message` is a library string and is never rendered — the
/// reverse of our endpoints, whose sentence is the one thing worth showing.
const _sentences = <String, String>{
  'user-not-found': 'No account found with that email.',
  'wrong-password': 'Incorrect password.',
  'email-already-in-use': 'An account with that email already exists.',
  'weak-password': 'Password must be at least 6 characters.',
  'invalid-email': 'Please enter a valid email address.',
  'too-many-requests': 'Too many attempts. Please try again later.',
  'popup-closed-by-user': 'Sign-in popup was closed.',
  'popup-blocked':
      'The browser blocked the sign-in popup. Allow popups for this site and try again.',
  'invalid-credential': 'Incorrect email or password.',
  'network-request-failed': 'The network dropped before sign-in finished.',
  'missing-email': 'Enter your email address first.',
};

const _fallback = 'Something went wrong. Please try again.';

/// The sentence for a bare SDK [code] — the reference's `humanizeError`.
String humanizeAuthCode(String? code) => _sentences[code] ?? _fallback;

/// The sentence for anything a sign-in call threw.
///
/// A dismissed native Google sheet is the web's closed popup — the reader
/// backed out of the provider's own screen — so it takes that sentence rather
/// than a new one only this client says.
String humanizeAuthError(Object error) {
  if (error is GoogleSignInNotSetUp) return GoogleSignInSetup.notSetUp;
  if (error is FirebaseAuthException) return humanizeAuthCode(error.code);
  if (error is GoogleSignInException) {
    return error.code == GoogleSignInExceptionCode.canceled
        ? humanizeAuthCode('popup-closed-by-user')
        : _fallback;
  }
  return _fallback;
}

/// Thrown instead of calling into a Google SDK this build is not configured
/// for (see [GoogleSignInSetup]).
class GoogleSignInNotSetUp implements Exception {
  const GoogleSignInNotSetUp();
  @override
  String toString() => GoogleSignInSetup.notSetUp;
}
