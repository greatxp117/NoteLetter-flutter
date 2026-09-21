import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/document.dart';
import '../services/firestore_service.dart';

/// The documents subscription itself (INV-02, `screens/library.md` §Data) —
/// `List<Document>`, not the activity merge.
///
/// [ActivityNotifier] already streams documents, but flattened into
/// `ActivityItem`s that carry no `tag_ids` and no `view_count`. Every figure the
/// library home and the chrome rail are specified to show — which shelf a volume
/// sits on, how many volumes a shelf holds, the passage total, the unread count
/// — reads one of those two fields, so the screens that need them had no signal
/// at all and the rail was left rendering a single figure.
///
/// A screen that cannot supply a figure omits it rather than rendering a zero
/// (`component-kit.md` §1.2). This exists so the figures stop being unsuppliable.
class DocumentsNotifier extends ChangeNotifier {
  List<Document> _documents = const [];
  bool _loading = true;
  StreamSubscription<List<Document>>? _sub;

  /// The subscription's failure (INV-24, ADR-071), beside the data it replaces.
  ///
  /// This notifier swallowed its `onError` into a `loading = false` until F-08:
  /// every screen counting volumes off it — the shelf figures especially — then
  /// reported a library of zero as though it had read one.
  String? _error;
  String? get error => _error;

  List<Document> get documents => List.unmodifiable(_documents);
  bool get loading => _loading;

  /// Indexed volumes — the only ones a reader can open, and the count every
  /// "{n} sources" figure means.
  List<Document> get complete =>
      _documents.where((d) => d.status == DocumentStatus.complete).toList();

  /// Idempotent — safe to call from every `initState` that needs the list.
  void start() {
    _sub ??= FirestoreService.instance.subscribeDocuments().listen((list) {
      _documents = list;
      _error = null;
      _loading = false;
      notifyListeners();
    }, onError: (e) {
      // Retry has to be able to work. `start` is idempotent on `_sub` and the
      // subscription survives its own error, so leaving it in place makes the
      // §14 block's Retry a control that does nothing and says nothing — the
      // same defect C1 had one notifier over.
      _sub?.cancel();
      _sub = null;
      _error = '$e';
      _loading = false;
      notifyListeners();
    });
  }

  /// What the §14 block's Retry calls. `start` re-subscribes because the error
  /// path dropped the subscription; without that this is a no-op.
  Future<void> refresh() async => start();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
