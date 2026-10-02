/// For your review's **Review** (`screens/review.md` §Proposals): each kind's
/// own review, opened in a §15 sheet and fed from the stored record. The
/// review is the surface the proposal came from — the inbox is a second place
/// to answer it, never a second way. Mirrors `TaskReviewSheet` in
/// `ReviewView.jsx`.
library;

import 'package:flutter/material.dart';

import '../../models/background_task.dart';
import '../../services/api.dart';
import '../tags/reshelve_sheet.dart';

/// The kinds this client can review. A kind outside it is still a row — its
/// subject, its status, Dismiss — and still counted (§22).
bool canReviewTask(BackgroundTask t) =>
    t.result != null && t.kind == 'shelf_delete';

Future<void> openTaskReview(BuildContext context, BackgroundTask t) {
  final result = t.result;
  if (result == null) return Future.value();
  // ready_at moves only when a NEW proposal lands (a Try again), never with an
  // apply's own status writes — so it keys the stored proposal.
  final key = '${t.id}:${t.readyAt ?? ''}';
  switch (t.kind) {
    case 'shelf_delete':
      final capture = t.capture ?? const {};
      return showStoredReshelveSheet(
        context,
        title: t.subjectTitle ?? 'this shelf',
        deletedId: t.subjectId ?? '',
        sources: [
          for (final s in (capture['sources'] as List?) ?? const [])
            if (s is Map)
              ReshelveItem('${s['id']}', (s['title'] as String?) ?? ''),
        ],
        stored: StoredReshelve(
          key: key,
          result: result,
          unconsidered: (capture['unconsidered'] as num?)?.toInt() ?? 0,
          apply: (assignments) => Api.instance
              .resolveTask(t.id, 'apply', {'assignments': assignments}),
        ),
      );
  }
  return Future.value();
}
