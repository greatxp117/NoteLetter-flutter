import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';
import 'auth_errors.dart';
import 'google_sign_in_setup.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> getIdToken() async {
    return currentUser?.getIdToken();
  }

  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// The reference's `signUpWithEmail`: create, then seed the letter's
  /// recipient with the address the account was made with (ADR-010).
  Future<UserCredential> signUp(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _seedRecipient(result.user);
    return result;
  }

  /// "Forgot it?" — Firebase's password-reset email. The email/password
  /// provider is already on, so this needs nothing enabled that is not.
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  bool _googleReady = false;

  /// Continue with Google — the reference's `signInWithGoogle`.
  ///
  /// Web uses Firebase's own popup with a bare `GoogleAuthProvider`, exactly as
  /// the reference does (no scopes, no custom parameters). The native clients
  /// get an id token from the Google SDK and exchange it for a Firebase
  /// credential — against the Auth emulator under `USE_EMULATOR`, which reads
  /// the token without verifying it, so nothing reaches prod Firebase.
  ///
  /// One call covers sign-in and sign-up, and only a NEW account is seeded,
  /// as the reference's `getAdditionalUserInfo(result)?.isNewUser` does.
  Future<UserCredential> signInWithGoogle() async {
    if (!GoogleSignInSetup.available) throw const GoogleSignInNotSetUp();
    final UserCredential result;
    if (kIsWeb) {
      result = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? GoogleSignInSetup.iosClientId
              : null,
          serverClientId: defaultTargetPlatform == TargetPlatform.android
              ? GoogleSignInSetup.webClientId
              : null,
        );
        _googleReady = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(code: 'invalid-credential');
      }
      result = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    if (result.additionalUserInfo?.isNewUser ?? false) {
      await _seedRecipient(result.user);
    }
    return result;
  }

  /// Visibility only — `fn_build_newsletter` falls back to the account email
  /// and persists it if this never lands, so a failure here is swallowed on
  /// purpose, as the reference's is.
  Future<void> _seedRecipient(User? user) async {
    final email = user?.email;
    if (email == null || email.isEmpty) return;
    try {
      await Api.instance.updateNewsletterSettings({'emailAddress': email});
    } catch (_) {
      // backend fallback covers it (ADR-010)
    }
  }

  Future<void> signOut() async {
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // The Firebase session is the one that matters; a stale Google
        // session only means the account picker pre-selects next time.
      }
    }
    await _auth.signOut();
  }
}
