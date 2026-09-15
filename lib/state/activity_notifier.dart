import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/activity_item.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

/// The rail's unread count (`spec/screens/activity.md` §Toasts and unread,
/// 2.5.0/ADR-014): **events** newer than the last time the feed was viewed.
///
/// A pure function, not a getter on the notifier, for the reason `tsMs` and
/// `mergeActivity` are pure: this is a rule, and a rule that can only be
/// exercised through a live subscription is a rule nothing asserts.
///
/// Two things it is deliberately NOT, both read off the reference
/// (`shell/notify.jsx`):
///
/// * It counts `kind == 'event'` only. The merge's **document** rows are the
///   fallback for documents that predate the events feature; counting them
///   would put a badge on a library that has simply never produced an event,
///   and every one of them would stay unread forever because nothing new ever
///   arrives to clear them.
/// * A null `created_at` is 0, never "now". The merge already treats null as 0
///   when sorting (INV-06), and an item that sorts oldest cannot be the news.
int activityUnread(List<ActivityItem> items, int lastSeenMs) => items
    .where((i) => i.kind == 'event' && (i.createdAt ?? 0) > lastSeenMs)
    .length;

/// Backs the Activity/Library screens with the canonical merge
/// (activity_events + documents, see spec/screens/activity.md) — realtime
/// Firestore subscriptions, never HTTP polling (INV-02).
class ActivityNotifier extends ChangeNotifier {
  List<ActivityItem> _items = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<List<ActivityItem>>? _sub;

  List<ActivityItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ActivityItem> get documents =>
      _items.where((i) => i.kind == 'document').toList();

  /// [activityUnread] over the live feed.
  int unreadSince(int lastSeenMs) => activityUnread(_items, lastSeenMs);

  /// The mark the feed writes when it is looked at: the newest event it is
  /// showing, not `DateTime.now()`.
  ///
  /// The clock would clear events this client has not received yet — the feed
  /// is a realtime subscription and a write that lands a beat before the
  /// snapshot does is newer than the moment the reader opened the screen, but
  /// it was never on it. Marking what is actually on screen cannot skip one.
  int get newestEventAt => _items
      .where((i) => i.kind == 'event')
      .fold<int>(0, (n, i) => (i.createdAt ?? 0) > n ? i.createdAt! : n);

  /// Idempotent — starts the subscription once; safe to call from initState.
  void start({int limit = 100}) {
    if (_sub != null) return;
    _isLoading = true;
    notifyListeners();
    _sub = FirestoreService.instance
        .subscribeActivity(maxItems: limit)
        .listen((items) {
      _items = items;
      _error = null;
      _isLoading = false;
      notifyListeners();
    }, onError: (_) {
      _error = 'Could not load activity. Please try again.';
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Kept for call-site compatibility — the subscription is already live.
  Future<void> load({int limit = 100}) async => start(limit: limit);
  Future<void> refresh() async => start();

  /// Permanent delete (doc + chunks + GCS) — the document list updates via
  /// the live subscription, not a local mutation.
  Future<String?> deleteDocument(String docId) async {
    try {
      await Api.instance.deleteDocument(docId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to delete document.';
    }
  }

  /// Retry from the failed stage — `status: "error"` documents only.
  Future<String?> retryDocument(String docId) async {
    try {
      await Api.instance.retryDocument(docId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to retry document.';
    }
  }

  /// Index a SKIPPED image anyway (4.47.0, ADR-085) — the owner overruling the
  /// image classifier's skip verdict. Its own method rather than a flag on
  /// [retryDocument]: the two are different requests, only one of them is
  /// offered on a skipped row, and the fallback sentence differs.
  Future<String?> forceProcessDocument(String docId) async {
    try {
      await Api.instance.retryDocument(docId, force: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to index this image.';
    }
  }

  /// Cancel mid-pipeline.
  Future<String?> cancelDocument(String docId) async {
    try {
      await Api.instance.cancelDocument(docId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to cancel document.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
