import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ask_thread.dart';
import 'sent_turn.dart';
import '../shared/local_flags.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/analytics.dart';

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

  /// The turn the reader has SENT (4.61.0, ADR-097).
  ///
  /// It is on screen from the moment it is sent until its own stored message
  /// arrives to replace it — never until the request settles, which is a
  /// different moment, and the gap between them is where the question used to
  /// disappear. A refusal leaves it here with the server's sentence and a
  /// retry; it is never returned to the composer as though it had not been
  /// asked. It is retired only by its own stored message arriving — a refusal
  /// included, because a refusal claims nothing was recorded and a record
  /// disproves it (ADR-102). A turn that genuinely failed wrote nothing, so no
  /// record can arrive and the screen keeps the only record of what the reader
  /// did.
  _SentTurn? _sent;

  /// A failure of the SUBSCRIPTIONS, which is a different sentence: the rail
  /// could not be read, as against a question that was refused (INV-24).
  String? _railError;
  String? _threadError;

  bool _loadingThreads = true;

  /// The shelf the ROUTE asked for (`/ask/shelf/{tagId}`, 4.62.0, ADR-098).
  /// An OPEN thread's own scope wins over it: a thread carries the shelf it was
  /// created with, and opening a library-wide conversation from a shelf-scoped
  /// screen must not label it with a shelf it never searched.
  String? _routeTagId;

  /// §9.1 entry actions (4.55.0, ADR-091). All three are about ONE entry: the
  /// rename in flight, the call in flight, and the rejection of either — which
  /// belongs in the entry that was refused, not in a rail-wide banner.
  String? _renamingId;
  String? _entryBusyId;
  String? _entryErrorId;
  String? _entryError;

  List<AskThread> get threads => _threads;
  List<AskMessage> get messages => _messages;
  String? get activeId => _activeId;

  /// The sent turn's question, or null when nothing is in flight or refused.
  String? get sentQuestion => _sent?.question;

  /// The server's sentence for the sent turn, verbatim (§14.2), or null while
  /// it is still searching.
  String? get sentError => _sent?.error;

  /// Searching: a turn is sent and has not been refused. NOT "a request is
  /// open" — a recorded turn stays in this state until its stored message
  /// arrives, which is what keeps the question on screen.
  bool get searching => _sent != null && _sent!.error == null;

  /// The composer is closed to a second question only while one is in flight.
  bool get sending => searching;

  /// The thread that is open, if the rail has it yet.
  AskThread? get activeThread {
    for (final t in _threads) {
      if (t.id == _activeId) return t;
    }
    return null;
  }

  /// The shelf this screen is asking. The open thread's own scope first, the
  /// route's only when nothing is open (ADR-098).
  String? get scopeTagId =>
      _activeId != null ? activeThread?.tagId : _routeTagId;

  /// The shelf's NAME, for the header, the empty state and the composer. A
  /// scoped thread whose shelf title is not known yet falls back to a word
  /// rather than to no scope at all: the turn IS scoped either way.
  String? scopeName(String? routeTitle) {
    final id = scopeTagId;
    if (id == null) return null;
    if (_activeId != null) {
      final title = activeThread?.tagTitle;
      if (title != null && title.isNotEmpty) return title;
    }
    if (routeTitle != null && routeTitle.isNotEmpty) return routeTitle;
    return 'this shelf';
  }
  String? get railError => _railError;
  String? get threadError => _threadError;
  bool get loadingThreads => _loadingThreads;
  String? get renamingId => _renamingId;
  bool entryBusy(String id) => _entryBusyId == id;
  String? entryError(String id) => _entryErrorId == id ? _entryError : null;

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

  /// Follow the ROUTE (4.65.0, ADR-101).
  ///
  /// The open conversation is `/ask/thread/{threadId}` and the screen's scope
  /// is `/ask/shelf/{tagId}` — neither lives here any more. Held in the screen,
  /// the open thread was dropped by a reload and by every return from the
  /// Reader a citation opened, and the screen then drew the NEW-conversation
  /// state: the app saying the reader had asked nothing, over a transcript
  /// they were reading a second earlier.
  ///
  /// Opening a stored conversation issues **no request** and must never draw
  /// the searching state (`screens/ask.md` §States): a spinner over an answer
  /// the reader already has says the app is asking again, and it is not.
  void syncRoute({String? threadId, String? tagId}) {
    if (_routeTagId != tagId) {
      _routeTagId = tagId;
      scheduleMicrotask(notifyListeners);
    }
    if (_activeId == threadId) return;
    _activeId = threadId;
    _threadError = null;
    _messages = const [];
    _messagesSub?.cancel();
    _messagesSub = null;
    // A turn belongs to the conversation it was asked in, so a navigation
    // drops it — EXCEPT the navigation the turn itself caused. The first turn
    // of a new conversation moves the screen to the thread the endpoint just
    // created (ADR-101), and clearing it there would take the question off the
    // screen for the moment between the navigation and the subscription's
    // first delivery: ADR-097's own gap, reopened by the fix for something
    // else. It is retired by its stored message, here as everywhere.
    if (_sent?.threadId != threadId) _sent = null;
    if (threadId != null) {
      _messagesSub =
          FirestoreService.instance.subscribeAskMessages(threadId).listen((m) {
        _messages = m;
        _threadError = null;
        _retireSentTurn();
        notifyListeners();
      }, onError: (Object e) {
        _threadError = e is ApiException ? e.message : e.toString();
        notifyListeners();
      });
    }
    scheduleMicrotask(notifyListeners);
  }

  /// The sent turn retires when ITS OWN stored message arrives — including a
  /// turn this screen was told had FAILED (ADR-097 §3 as amended by ADR-102).
  /// The rule, and why retiring a refusal is safe, lives beside the predicate
  /// in `sent_turn.dart`, which is also where it is asserted.
  void _retireSentTurn() {
    final sent = _sent;
    if (sent == null) return;
    if (retiresSentTurn(
        question: sent.question,
        asked: sent.asked,
        messages: _messages,
        error: sent.error)) {
      _sent = null;
    }
  }

  // ── §9.1 entry actions ─────────────────────────────────────────────────────

  /// Open the in-place rename on one entry. Local only — nothing is sent until
  /// the field is committed.
  void startRename(String id) {
    _renamingId = id;
    _entryError = null;
    _entryErrorId = null;
    notifyListeners();
  }

  void cancelRename() {
    if (_renamingId == null) return;
    _renamingId = null;
    notifyListeners();
  }

  /// Commit a rename. **Write before you move** (ADR-022): the field stays open
  /// and the title on screen stays the STORED one until the server has taken
  /// the new one — closing the field first paints a rename that may not have
  /// landed, and it would revert on the next reload with nothing to say why.
  Future<void> renameThread(String id, String title) async {
    if (_entryBusyId != null) return;
    final next = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    final current = _threads.where((t) => t.id == id).firstOrNull?.title ?? '';
    if (next.isEmpty || next == current) {
      cancelRename();
      return;
    }
    _entryBusyId = id;
    _entryError = null;
    _entryErrorId = null;
    notifyListeners();
    try {
      await Api.instance.renameAskThread(id, next);
      _renamingId = null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _fail(id, 'Your session expired. Sign in again.');
    } on ApiException catch (e) {
      // The server's sentence, verbatim (§14.2).
      _fail(id, e.message);
    } catch (_) {
      _fail(id, 'Could not reach your library. Check your connection.');
    } finally {
      _entryBusyId = null;
      notifyListeners();
    }
  }

  /// Delete a conversation and every message under it. Returns **null on
  /// success and the server's sentence on a refusal** — §18's contract with its
  /// confirmation (ADR-092), and the same shape `ActivityNotifier`'s writers
  /// already use. The rejection is NOT stored on the entry here: the reader is
  /// looking at the panel they pressed a button in, and that is where §18 puts
  /// it. A rename has no panel, so that one still answers in the entry.
  ///
  /// Deleting the OPEN conversation returns the screen to the new-conversation
  /// state (`screens/ask.md` §Composition): a transcript whose thread is gone
  /// is a view of nothing, and leaving it up offers a reply to something that
  /// no longer exists.
  Future<String?> deleteThread(String id) async {
    if (_entryBusyId != null) return null;
    _entryBusyId = id;
    _entryError = null;
    _entryErrorId = null;
    notifyListeners();
    try {
      await Api.instance.deleteAskThread(id);
      // Deleting the OPEN conversation returns the screen to the
      // new-conversation state (`screens/ask.md`). That is a NAVIGATION now
      // (ADR-101) — the screen pushes `/ask` when this reports the thread it
      // deleted was the open one — because a URL naming a deleted thread is
      // the address bar pointing at nothing.
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Your session expired. Sign in again.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach your library. Check your connection.';
    } finally {
      _entryBusyId = null;
      notifyListeners();
    }
  }

  void _fail(String id, String message) {
    _entryErrorId = id;
    _entryError = message;
  }

  /// Re-send the turn that is already on screen. It is not a draft, and
  /// putting it back in the composer would be the screen saying it was never
  /// asked (ADR-097).
  Future<String?> retry() async {
    final sent = _sent;
    if (sent == null || sent.error == null) return null;
    return ask(sent.question);
  }

  /// One turn.
  ///
  /// Returns the **threadId the endpoint recorded** when that is a thread this
  /// screen is not already on — the screen navigates to it (ADR-101) — and
  /// null otherwise, including on a refusal. Write before you move (ADR-022):
  /// a URL naming a thread the server has not recorded is the rail pointing at
  /// nothing.
  Future<String?> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || searching) return null;

    // How many copies of this question the thread ALREADY holds, counted
    // before the turn is sent — see [_retireSentTurn].
    var asked = 0;
    for (final m in _messages) {
      if (m.role == AskRole.user && m.text == question) asked++;
    }
    _sent = _SentTurn(question: question, asked: asked);
    notifyListeners();

    final Map<String, dynamic> data;
    try {
      data = await Api.instance.askTurn(
        question,
        threadId: _activeId,
        limit: 5,
        // The scope is sent only when this turn CREATES the conversation. A
        // follow-up sends the threadId alone and inherits the thread's own
        // scope; sending both is a 400 unless they agree, and the thread is
        // the authority on what it searched (ADR-098).
        tagId: _activeId == null ? _routeTagId : null,
      );
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _refuse(question, asked, 'Your session expired. Sign in again.');
      return null;
    } on ApiException catch (e) {
      // The server's sentence, verbatim (§14.2). Never pattern-matched into
      // copy of ours, and never dropped for a generic one.
      _refuse(question, asked, e.message);
      return null;
    } catch (_) {
      _refuse(question, asked,
          'Could not reach your library. Check your connection.');
      return null;
    }

    // Everything past here is about a turn that SUCCEEDED, and it is outside
    // the catch on purpose: nothing below may paint a recorded answer as a
    // refusal.
    //
    // The question is never sent, the same reason a search query is not. How
    // many passages the answer stood on is what an operator can act on.
    final message = data['message'];
    final citations =
        message is Map ? (message['citations'] as List?) ?? const [] : const [];
    Analytics.track('ask_run', {
      'results_bucket': Analytics.bucket(citations.length),
    });
    // Completes the Library checklist's "Ask your library a question" — on a
    // turn that was RECORDED, never on a refusal (web AskView `nl-onboard-asked`).
    LocalFlags.markAsked();

    final id = data['threadId'] as String?;
    // Remember which conversation this turn was recorded in, so the navigation
    // it is about to cause does not drop it (see [syncRoute]).
    if (id != null && _sent?.question == question) {
      _sent = _SentTurn(question: question, asked: _sent!.asked, threadId: id);
    }
    // No clearing of the sent turn here. It is retired by its own stored
    // message arriving, not by the request settling — the two are different
    // moments (ADR-097). On a thread already open, the subscription delivers
    // it; on a new one, [syncRoute] takes over when the screen navigates.
    if (id != null && id != _activeId) return id;
    notifyListeners();
    return null;
  }

  void _refuse(String question, int asked, String message) {
    _sent = _SentTurn(question: question, asked: asked, error: message);
    notifyListeners();
  }

  @override
  void dispose() {
    _threadsSub?.cancel();
    _messagesSub?.cancel();
    super.dispose();
  }
}

/// The turn the reader sent: the question, how many copies of it the thread
/// already held when it went (so it can be retired against its OWN stored
/// message), and the server's sentence if it was refused.
class _SentTurn {
  final String question;
  final int asked;
  final String? error;

  /// The conversation the endpoint recorded it in, once it has answered. The
  /// screen navigates to that thread, and this is what tells [syncRoute] the
  /// navigation is the turn's own rather than the reader leaving.
  final String? threadId;

  const _SentTurn({
    required this.question,
    required this.asked,
    this.error,
    this.threadId,
  });
}
