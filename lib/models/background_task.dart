import 'document.dart' show tsMs;

/// `/background_tasks/{taskId}` (4.101.0, ADR-136; data-model.md) — a long
/// operation the reader asked for, as a record. Subscribed, read-only: every
/// write is a function's. `run_id` is the backend's token and is never read.
///
/// `kind` is **open for reading**: an unknown kind is still a row (its
/// subject's title, its status, Dismiss) and still counted — a kind no
/// renderer lists must not leave the inbox.
class BackgroundTask {
  final String id;
  final String kind;

  /// `queued · running · awaiting_review · applying · failed` (the open set
  /// this client subscribes to); `done`/`dismissed` are closed.
  final String status;
  final Map<String, dynamic> subject;
  final Map<String, dynamic> params;
  final Map<String, dynamic>? capture;
  final Map<String, dynamic>? progress;

  /// Exactly the synchronous proposal endpoint's body, so a review reuses its
  /// parser. Null until there is one.
  final Map<String, dynamic>? result;
  final String? errorMessage;
  final String? applyError;

  /// Epoch ms (INV-06). Null is never stalled.
  final int? stallsAt;
  final int? createdAt;
  final int? readyAt;

  const BackgroundTask({
    required this.id,
    required this.kind,
    required this.status,
    this.subject = const {},
    this.params = const {},
    this.capture,
    this.progress,
    this.result,
    this.errorMessage,
    this.applyError,
    this.stallsAt,
    this.createdAt,
    this.readyAt,
  });

  static Map<String, dynamic>? _map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  factory BackgroundTask.fromJson(String id, Map<String, dynamic> d) =>
      BackgroundTask(
        id: id,
        kind: d['kind'] as String? ?? '',
        status: d['status'] as String? ?? '',
        subject: _map(d['subject']) ?? const {},
        params: _map(d['params']) ?? const {},
        capture: _map(d['capture']),
        progress: _map(d['progress']),
        result: _map(d['result']),
        errorMessage: d['error_message'] as String?,
        applyError: d['apply_error'] as String?,
        stallsAt: tsMs(d['stalls_at']),
        createdAt: tsMs(d['created_at']),
        readyAt: tsMs(d['ready_at']),
      );

  String? get subjectTitle => subject['title'] as String?;
  String? get subjectId => subject['id'] as String?;
  String? get subjectType => subject['type'] as String?;
  String? get subjectColor => subject['color'] as String?;

  static const inFlight = {'queued', 'running', 'applying'};

  /// In flight past its own stall moment — the ADR-108 test, per task.
  bool isStalled(DateTime now) =>
      inFlight.contains(status) &&
      stallsAt != null &&
      now.millisecondsSinceEpoch > stallsAt!;

  /// Waits on the reader: a proposal, a failure, or a worker that is gone. One
  /// in flight and not stalled is RUNNING — drawn, never counted.
  bool needsReview(DateTime now) =>
      status == 'awaiting_review' || status == 'failed' || isStalled(now);
}
