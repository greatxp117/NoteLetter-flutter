import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ask_thread.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Ask — conversational retrieval over the reader's own notes, and the app
/// remembers it (contract 4.53.0/4.54.0, ADR-090; `spec/screens/ask.md`).
///
/// Everything on screen except the turn in flight comes from **Firestore**
/// (INV-02): the rail from `subscribeAskThreads`, the open conversation from
/// `subscribeAskMessages`. This notifier holds no transcript of its own. The
/// previous one did, and that was the defect: a thread in client state is a
/// thread that is gone on the next navigation.
///
/// A turn is ONE call — `fn_ask_turn`, not `fn_search_notes` — and it writes
/// both messages server-side, so the transcript this screen shows is the one
/// every other client will show.
class ChatNotifier extends ChangeNotifier {
  StreamSubscription<List<AskThread>>? _threadsSub;
  StreamSubscription<List<AskMessage>>? _messagesSub;

  List<AskThread> _threads = const [];
  List<AskMessage> _messages = const [];
  String? _activeId;

  /// The question currently in flight. Not a transcript entry: it is the one
  /// thing on this screen that has not been recorded yet.
  String? _pending;

  /// The last turn's rejection, rendered as §14.2 beside the composer.
  String? _error;

  /// A failure of the SUBSCRIPTIONS, which is a different sentence: the rail
  /// could not be read, as against a question that was refused (INV-24).
  String? _railError;
  String? _threadError;

  bool _loadingThreads = true;

  List<AskThread> get threads => _threads;
  List<AskMessage> get messages => _messages;
  String? get activeId => _activeId;
  String? get pending => _pending;
  bool get sending => _pending != null;
  String? get error => _error;
  String? get railError => _railError;
  String? get threadError => _threadError;
  bool get loadingThreads => _loadingThreads;

  ChatNotifier() {
    _listenThreads();
  }

  void _listenThreads() {
    _threadsSub?.cancel();
    _threadsSub = FirestoreService.instance.subscribeAskThreads().listen(
      (t) {
        _threads = t;
        _loadingThreads = false;
        _railError = null;
        notifyListeners();
      },
      // INV-24 (ADR-071): a subscription that fails says so. An empty rail and
      // a rail we could not read are not the same picture.
      onError: (Object e) {
        _loadingThreads = false;
        _railError = e is ApiException ? e.message : e.toString();
        notifyListeners();
      },
    );
  }

  /// Open a stored conversation.
  ///
  /// This issues **no request** and must never draw the searching state
  /// (`screens/ask.md` §States): a spinner over an answer the reader already
  /// has says the app is asking again, and it is not.
  void openThread(String id) {
    if (_activeId == id) return;
    _activeId = id;
    _error = null;
    _threadError = null;
    _messages = const [];
    _messagesSub?.cancel();
    _messagesSub =
        FirestoreService.instance.subscribeAskMessages(id).listen((m) {
      _messages = m;
      _threadError = null;
      notifyListeners();
    }, onError: (Object e) {
      _threadError = e is ApiException ? e.message : e.toString();
      notifyListeners();
    });
    notifyListeners();
  }

  /// Start a new conversation — local only. The thread is created by ASKING
  /// something (`fn_ask_turn` with no `threadId`); there is no create endpoint
  /// and no empty shell waiting for a first question.
  void newConversation() {
    _activeId = null;
    _error = null;
    _threadError = null;
    _messages = const [];
    _messagesSub?.cancel();
    _messagesSub = null;
    notifyListeners();
  }

  /// Withdraw the last rejection — the text it referred to is being changed.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// One turn. Returns true when the endpoint recorded it.
  Future<bool> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || _pending != null) return false;

    _pending = question;
    _error = null;
    notifyListeners();

    try {
      final data =
          await Api.instance.askTurn(question, threadId: _activeId, limit: 5);
      // Write BEFORE you move (ADR-022): the conversation becomes the active
      // one only once the server has recorded it. Setting it first would point
      // the rail at a thread that does not exist when the call fails.
      final id = data['threadId'] as String?;
      if (id != null && id != _activeId) openThread(id);
      return true;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _error = 'Your session expired. Sign in again.';
      return false;
    } on ApiException catch (e) {
      // The server's sentence, verbatim (§14.2). Never pattern-matched into
      // copy of ours, and never dropped for a generic one.
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Could not reach your library. Check your connection.';
      return false;
    } finally {
      _pending = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _threadsSub?.cancel();
    _messagesSub?.cancel();
    super.dispose();
  }
}
