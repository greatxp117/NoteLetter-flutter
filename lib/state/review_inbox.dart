import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/background_task.dart';
import '../models/document.dart';
import '../models/import_job.dart';
import '../models/organization_suggestion.dart';
import '../services/error_text.dart';
import '../services/firestore_service.dart';

/// The subscriptions' own limit. At it, a figure is `500+` — the query returned
/// all it was allowed to, not all there is (`screens/review.md` §Data).
const reviewReadLimit = 500;

/// `screens/review.md` §The needs-decision set — normative (INV-30). A source
/// is asked about when it failed, was skipped, or stalled, and the reader has
/// not dismissed it. A FRESH `processing` document is read (so a stalled one
/// can be seen crossing its threshold) but is not in the set: it is work in
/// progress, and asking about it would be inventing a failure.
bool sourceNeedsReview(Document d, DateTime now) {
  if (d.reviewDismissedAt != null) return false;
  return d.status == DocumentStatus.error ||
      d.status == DocumentStatus.skipped ||
      d.isStalled(now);
}

/// One subscription's state: what it last delivered, whether it has answered
/// at all, and its failure.
class InboxPart<T> {
  final List<T> data;
  final bool loaded;
  final String? error;
  const InboxPart({this.data = const [], this.loaded = false, this.error});
}

/// What For your review shows and counts, computed from the four parts at one
/// moment — a pure function, so the drawer's count and the page's rows are the
/// same arithmetic over the same lists (INV-30), and a test can drive it.
class InboxView {
  final List<Document> sources;
  final List<ImportJob> holds;
  final List<OrganizationSuggestion> suggestions;
  final List<BackgroundTask> proposals;
  final List<BackgroundTask> running;
  final String? sourcesError;
  final String? holdsError;
  final String? suggestionsError;
  final String? tasksError;
  final bool loaded;
  final bool atLimit;
  final DateTime now;

  /// The size of exactly the needs-decision set, or **null — unmeasured** —
  /// until every subscription has answered, and again whenever any of them
  /// has failed. Never the size of the parts that loaded, and never 0 for a
  /// read that did not happen (ADR-109).
  final int? count;

  const InboxView._({
    required this.sources,
    required this.holds,
    required this.suggestions,
    required this.proposals,
    required this.running,
    required this.sourcesError,
    required this.holdsError,
    required this.suggestionsError,
    required this.tasksError,
    required this.loaded,
    required this.atLimit,
    required this.now,
    required this.count,
  });

  factory InboxView.compute({
    required InboxPart<Document> docs,
    required InboxPart<ImportJob> holds,
    required InboxPart<OrganizationSuggestion> suggestions,
    required InboxPart<BackgroundTask> tasks,
    required DateTime now,
  }) {
    final sources = docs.data.where((d) => sourceNeedsReview(d, now)).toList();
    final proposals = tasks.data.where((t) => t.needsReview(now)).toList();
    final running = tasks.data.where((t) => !t.needsReview(now)).toList();
    final loaded =
        docs.loaded && holds.loaded && suggestions.loaded && tasks.loaded;
    final measured = loaded &&
        docs.error == null &&
        holds.error == null &&
        suggestions.error == null &&
        tasks.error == null;
    return InboxView._(
      sources: sources,
      holds: holds.data,
      suggestions: suggestions.data,
      proposals: proposals,
      running: running,
      sourcesError: docs.error,
      holdsError: holds.error,
      suggestionsError: suggestions.error,
      tasksError: tasks.error,
      loaded: loaded,
      atLimit: docs.data.length >= reviewReadLimit ||
          holds.data.length >= reviewReadLimit,
      now: now,
      count: measured
          ? sources.length +
              holds.data.length +
              suggestions.data.length +
              proposals.length
          : null,
    );
  }

  bool get anyFailed =>
      sourcesError != null ||
      holdsError != null ||
      suggestionsError != null ||
      tasksError != null;

  /// The count as text — `500+` at the read limit, never 500. Null stays
  /// null: the caller draws the unmeasured figure.
  String? get countText =>
      count == null ? null : (atLimit ? '$count+' : '$count');

  /// Nothing waiting, nothing running, and nothing failed (§States Empty).
  bool get empty => loaded && !anyFailed && count == 0 && running.isEmpty;
}

typedef InboxOpen<T> = Stream<List<T>> Function();

/// For your review's **one** source of truth (4.100.0, ADR-135, INV-30): the
/// rail's attention count and the page both read this notifier, held once
/// above the app, so the number in the rail and the rows on the page cannot
/// disagree. Mirrors the reference's `useReviewInbox`.
class ReviewInbox extends ChangeNotifier {
  final InboxOpen<Document> _openDocs;
  final InboxOpen<ImportJob> _openHolds;
  final InboxOpen<OrganizationSuggestion> _openSuggestions;
  final InboxOpen<BackgroundTask> _openTasks;
  final DateTime Function() _clock;

  ReviewInbox({
    InboxOpen<Document>? docs,
    InboxOpen<ImportJob>? holds,
    InboxOpen<OrganizationSuggestion>? suggestions,
    InboxOpen<BackgroundTask>? tasks,
    DateTime Function()? clock,
  })  : _openDocs = docs ??
            (() => FirestoreService.instance.subscribeAttentionDocuments()),
        _openHolds = holds ??
            (() => FirestoreService.instance.subscribeHeldImportJobs()),
        _openSuggestions = suggestions ??
            (() =>
                FirestoreService.instance.subscribeOrganizationSuggestions()),
        _openTasks = tasks ??
            (() => FirestoreService.instance.subscribeBackgroundTasks()),
        _clock = clock ?? DateTime.now;

  InboxPart<Document> _docs = const InboxPart();
  InboxPart<ImportJob> _holds = const InboxPart();
  InboxPart<OrganizationSuggestion> _suggestions = const InboxPart();
  InboxPart<BackgroundTask> _tasks = const InboxPart();
  final List<StreamSubscription> _subs = [];
  Timer? _tick;
  InboxView? _view;

  InboxView get view => _view ??= InboxView.compute(
      docs: _docs,
      holds: _holds,
      suggestions: _suggestions,
      tasks: _tasks,
      now: _clock());

  void _changed() {
    _view = null;
    _syncTick();
    notifyListeners();
  }

  StreamSubscription _listen<T>(
          InboxOpen<T> open, void Function(InboxPart<T>) set) =>
      open().listen(
        (list) {
          set(InboxPart(data: list, loaded: true));
          _changed();
        },
        // A refused listener is not retried by Firestore: the part keeps no
        // rows and says why, and [retry] opens all four again.
        onError: (Object e) {
          set(InboxPart(loaded: true, error: describeSdkError(e)));
          _changed();
        },
      );

  /// Idempotent — the rail calls it on every screen.
  void start() {
    if (_subs.isNotEmpty) return;
    _subs
      ..add(_listen<Document>(_openDocs, (p) => _docs = p))
      ..add(_listen<ImportJob>(_openHolds, (p) => _holds = p))
      ..add(_listen<OrganizationSuggestion>(
          _openSuggestions, (p) => _suggestions = p))
      ..add(_listen<BackgroundTask>(_openTasks, (p) => _tasks = p));
  }

  /// The §14.1 block's Try again: tears the four down and opens them again.
  void retry() {
    _cancel();
    _docs = const InboxPart();
    _holds = const InboxPart();
    _suggestions = const InboxPart();
    _tasks = const InboxPart();
    _changed();
    start();
  }

  /// A stalled row crosses its threshold with NO Firestore write, so nothing
  /// would move it into the set. One clock, running only while a `processing`
  /// document or an in-flight task is held, so every row and the count flip
  /// on the same tick.
  void _syncTick() {
    final watching = _docs.data.any((d) => d.status == DocumentStatus.processing) ||
        _tasks.data.any((t) => BackgroundTask.inFlight.contains(t.status));
    if (watching && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 15), (_) {
        _view = null;
        notifyListeners();
      });
    } else if (!watching) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _cancel();
    _tick?.cancel();
    super.dispose();
  }
}
