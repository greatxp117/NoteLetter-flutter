import 'dart:async';
import 'package:flutter/foundation.dart';

import '../build_info.dart';
import '../models/support.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

/// The support conversation (4.18.0, ADR-054; `spec/screens/support.md`).
///
/// **App-scoped, not screen-scoped**, and that is the whole point: the shell's
/// footer renders an unread count on every screen (INV-22), so the thread has
/// to be subscribed above any one screen. A notifier created by the Support
/// page would leave the badge with nothing to read.
///
/// [start] is idempotent and lazy — nothing touches Firestore until something
/// asks. That keeps the widget tree constructible in a plain widget test, where
/// there is no Firebase app at all.
class SupportNotifier extends ChangeNotifier {
  SupportThread? _thread;
  List<SupportMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  StreamSubscription<SupportThread?>? _threadSub;
  StreamSubscription<List<SupportMessage>>? _messageSub;

  /// Fired at most once per app run, and only when there is something to clear.
  /// A write per render is how a counter screen becomes a billing surprise
  /// (`spec/screens/support.md` §Behaviour).
  bool _marked = false;

  SupportThread? get thread => _thread;
  List<SupportMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;

  /// The footer's badge. **Absent thread ⇒ 0**, never an error state.
  int get unreadForUser => _thread?.unreadForUser ?? 0;

  /// Derived from `last_sender`, never from a stored status field.
  bool get awaitingAnswer => _thread?.awaitingAnswer ?? false;

  void start() {
    _threadSub ??=
        FirestoreService.instance.subscribeSupportThread().listen((t) {
      _thread = t;
      _loading = false;
      notifyListeners();
    });
    _messageSub ??=
        FirestoreService.instance.subscribeSupportMessages().listen((list) {
      _messages = list;
      notifyListeners();
    });
  }

  /// Opening the screen marks it read — once, and only with something to clear.
  ///
  /// Failure is swallowed deliberately: the badge is cosmetic and must never
  /// block or redden the screen the user came here to use.
  Future<void> markRead() async {
    if (_marked || unreadForUser == 0) return;
    _marked = true;
    try {
      await Api.instance.markSupportRead();
    } catch (_) {
      // Cosmetic; the subscription still carries the truth.
    }
  }

  /// Send, **write-before-you-move** (ADR-022).
  ///
  /// Returns `true` only once the endpoint has accepted the message — the
  /// composer clears on that and on nothing else. On a `400`/`429` this returns
  /// `false` with [error] set, and the caller keeps the user's text. Clearing
  /// optimistically loses a bug report on the exact path where it matters most.
  Future<bool> send(String body, {String? route}) async {
    final text = body.trim();
    if (text.isEmpty || _sending) return false;
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      await Api.instance.sendSupportMessage(
        body: text,
        route: route,
        clientVersion: BuildInfo.clientVersion,
      );
      return true;
    } on ApiException catch (e) {
      // The endpoint's own copy, rendered as-is: a 429 cooldown is a sentence
      // the backend writes, not an error this client invents.
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Could not send that message.';
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }
}
