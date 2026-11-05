import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/newsletter.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../services/error_text.dart';

/// Newsletter history (INV-09: query by recency, never construct IDs) +
/// "send now" via `fn_request_newsletter`. See spec/screens/letters.md.
///
/// **One query, two kinds** (2.24.0, ADR-029 §3). The collection holds both
/// letters and is read as one window, then split here — `kind != 'scripture'`
/// for the daily list, never `kind == 'daily'`, because the field is absent on
/// every pre-2.24.0 record and equality would drop a real reader's whole
/// history.
///
/// **A live subscription** (round 3; web `subscribeNewsletters`), so a Send now
/// build lands on its own, first `generating` and then `sent`, with no
/// re-read: until round 3 the archive was read once, and a letter being built
/// kept showing what it showed until the page was opened again.
class NewsletterNotifier extends ChangeNotifier {
  NewsletterNotifier({String? Function()? uid}) : _uidOf = uid;

  final String? Function()? _uidOf;

  /// The account the archive and its pending sends belong to. This notifier is
  /// process-wide and outlives a sign-out.
  String? _bound;

  List<Newsletter> _all = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  bool _loaded = false;
  StreamSubscription<List<Newsletter>>? _sub;
  int? _limit;

  /// The daily letters — everything that is not a readings letter.
  List<Newsletter> get history =>
      List.unmodifiable(_all.where((n) => !n.isScripture));

  /// The readings letters, the other side of the same filter.
  List<Newsletter> get readings =>
      List.unmodifiable(_all.where((n) => n.isScripture));

  /// The most recent daily letter that can actually be opened. `empty`/`error`
  /// rows have no body to preview; they still appear in the list below.
  Newsletter? get latest {
    for (final n in history) {
      if (n.isBuiltLetter) return n;
    }
    return null;
  }

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  /// INV-24 (ADR-071): a failed read is not an empty archive. Until [loaded] is
  /// true and this is null, a screen may not say "no letters yet".
  String? get error => _error;
  bool get loaded => _loaded;

  /// Starts the archive's subscription (the window of [limit] newest records),
  /// or — already subscribed at that window — does nothing: the records arrive
  /// on their own. Completes once the first snapshot has answered or been
  /// refused. A refused subscription is re-opened by the next call (a §14
  /// block's Try again).
  Future<void> load({int limit = 30}) {
    final of = _uidOf;
    final uid = of != null ? of() : FirestoreService.instance.signedInUid;
    final sameAccount = uid == _bound;
    if (_sub != null && _limit == limit && _error == null && sameAccount) {
      return Future.value();
    }
    _sub?.cancel();
    if (!sameAccount) {
      // Another reader's letters are not this reader's, and a pending send's
      // Try again would mail this one.
      _bound = uid;
      _all = [];
      _pending.clear();
      _loaded = false;
    }
    _limit = limit;
    _isLoading = true;
    _error = null;
    notifyListeners();
    final first = Completer<void>();
    _sub = FirestoreService.instance.subscribeNewsletters(limit: limit).listen(
      (rows) {
        _all = rows;
        _loaded = true;
        _error = null;
        _isLoading = false;
        _reconcile(rows);
        notifyListeners();
        if (!first.isCompleted) first.complete();
      },
      onError: (Object e) {
        _error = describeSdkError(e);
        _isLoading = false;
        notifyListeners();
        if (!first.isCompleted) first.complete();
      },
    );
    return first.future;
  }

  // ── The optimistic "Sending…" row (web `pending`, 4.76.0, ADR-110) ─────────

  /// How long a pending send may wait before it is read as a send that never
  /// started: well past a healthy build and past `fn_build_newsletter`'s own
  /// 300s timeout, so a row that reaches it waits on a worker that is gone.
  static const sendTimeout = Duration(minutes: 5);

  final List<PendingSend> _pending = [];

  /// Sends on their way: drawn as a *Sending…* row at the head of the archive
  /// until a record arrives that was not there when they were queued.
  List<PendingSend> get pendingSends =>
      List.unmodifiable(_pending.where((p) => !p.stale));

  /// Sends that waited [sendTimeout] for a record that never came — §14.1's
  /// *The letter did not start.*, never a row.
  List<PendingSend> get staleSends =>
      List.unmodifiable(_pending.where((p) => p.stale));

  /// The records known now. Taken BEFORE the request that may build a letter
  /// (web's closure over `archive`): the record is written before the 202, so
  /// the live archive can bring it ahead of the reply.
  Set<String> get knownLetterIds => {for (final n in _all) n.id};

  /// A build was accepted (Send now, or the send a switch-on queued): a
  /// pending row stands until the subscription brings a record outside
  /// [knownIds], which may already have happened.
  void pushPending(Set<String> knownIds, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _pending.insert(
      0,
      PendingSend(
        id: 'pending-${at.microsecondsSinceEpoch}',
        startedAt: at,
        knownIds: knownIds,
      ),
    );
    _reconcile(_all);
    notifyListeners();
  }

  /// Marks every pending send older than [sendTimeout] stale. The page that
  /// draws the sends ticks this every 15s while one waits (web's effect, which
  /// lives in the view too), so no timer outlives the screen.
  void age({DateTime? now}) {
    final at = now ?? DateTime.now();
    var moved = false;
    for (final p in _pending) {
      if (!p.stale && at.difference(p.startedAt) >= sendTimeout) {
        p.stale = true;
        moved = true;
      }
    }
    if (moved) notifyListeners();
  }

  /// Trying again is a fresh send, so the send that never started goes first.
  void dropPending(String id) {
    _pending.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// A pending send leaves the moment a record arrives that it had not seen.
  void _reconcile(List<Newsletter> rows) {
    _pending.removeWhere((p) => rows.any((r) => !p.knownIds.contains(r.id)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// "Send now" — 60s cooldown against double-taps is enforced server-side.
  ///
  /// The build is asynchronous and **always** produces a visible record
  /// (2.2.0, ADR-011): `sent`, `error`, or `empty`. The caller reloads the
  /// history to find it; nothing here polls a function (INV-02).
  Future<String?> requestNewsletter() async {
    _isSending = true;
    notifyListeners();
    try {
      await Api.instance.requestNewsletter();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to request newsletter. Please try again.';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}

/// One send on its way (web's optimistic row): queued at [startedAt], over the
/// records known then.
class PendingSend {
  final String id;
  final DateTime startedAt;
  final Set<String> knownIds;
  bool stale = false;

  PendingSend({
    required this.id,
    required this.startedAt,
    required this.knownIds,
  });
}
