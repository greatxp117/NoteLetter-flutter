import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/activity_item.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

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
      await ApiService.instance.post('/fn_delete_document', data: {'docId': docId});
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
      await ApiService.instance.post('/fn_retry_document', data: {'docId': docId});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to retry document.';
    }
  }

  /// Cancel mid-pipeline.
  Future<String?> cancelDocument(String docId) async {
    try {
      await ApiService.instance.post('/fn_cancel_document', data: {'docId': docId});
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
