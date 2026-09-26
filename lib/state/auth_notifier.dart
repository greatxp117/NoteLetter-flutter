import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import 'pending_letter_setup.dart';

/// Who is signed in, for the router's redirect.
///
/// The sign-in and sign-up calls themselves live on the signed-out screens
/// (`lib/site/`), which own their loading and failure state the way the
/// reference's `SignIn` and `AuthModal` do: a success needs no handling there,
/// because the redirect below takes the reader into the app.
class AuthNotifier extends ChangeNotifier {
  User? _user;

  AuthNotifier() {
    _user = AuthService.instance.currentUser;
    _replayFor(_user);
    AuthService.instance.authStateChanges.listen((user) {
      final signedIn = _user == null && user != null;
      _user = user;
      if (signedIn) _replayFor(user);
      notifyListeners();
    // Deliberately quiet (INV-24 asks why): this is the AUTH stream, not a
    // Firestore query. Its error means the SDK could not determine a session,
    // and `_user` staying null is the correct reading of that — the app shows
    // the sign-in screen, which is the only useful thing it could do.
    }, onError: (_) {
      _user = null;
      notifyListeners();
    });
  }

  /// The sign-up form's letter opt-in, sent by the signed-in app — the
  /// reference runs `usePendingLetterSetup` from its authenticated shell.
  void _replayFor(User? user) {
    if (user == null) return;
    PendingLetterSetup.replay(user.email);
  }

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  Future<void> signOut() async {
    await AuthService.instance.signOut();
  }
}
