import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthNotifier extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  AuthNotifier() {
    _user = AuthService.instance.currentUser;
    AuthService.instance.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await AuthService.instance.signIn(email, password);
    } on FirebaseAuthException catch (e) {
      _error = _friendlyMessage(e.code);
    } catch (_) {
      _error = 'Sign in failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await AuthService.instance.signUp(email, password);
    } on FirebaseAuthException catch (e) {
      _error = _friendlyMessage(e.code);
    } catch (_) {
      _error = 'Sign up failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _friendlyMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-credential':
        return 'No account found with this email or password.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
