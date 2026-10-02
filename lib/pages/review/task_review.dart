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
import '../tags/shelf_sheet.dart';
import '../tags/split_shelf_sheet.dart';

/// The kinds this client can review. A kind outside it is still a row — its
/// subject, its status, Dismiss — and still counted (§22).
bool canReviewTask(BackgroundTask t) =>
    t.result != null && _reviewable.contains(t.kind);

const _reviewable = {'shelf_delete', 'shelf_backfill', 'shelf_split'};

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
    // 4.102.0: the candidates from `result.candidates`, all kept; File is one
    // apply with the kept ids, and what went away meanwhile is said before
    // Done. Done only closes: the reader came from the inbox.
    case 'shelf_backfill':
      return showShelfSheet(
        context,
        canBackfill: true,
        land: null,
        backfillFor: BackfillFor(
          t.subjectId ?? '',
          t.subjectTitle ?? 'this shelf',
          stored: StoredBackfill(
            key: key,
            result: result,
            apply: (ids) => Api.instance
                .resolveTask(t.id, 'apply', {'documentIds': ids}),
          ),
        ),
      );
    // 4.102.0: the parts from `result.parts`, kept, skipped and renamed; the
    // apply names each kept part by its index — never document ids.
    case 'shelf_split':
      return SplitShelfSheet.showStored(
        context,
        title: t.subjectTitle ?? 'this shelf',
        proposal: result,
        apply: (parts) =>
            Api.instance.resolveTask(t.id, 'apply', {'parts': parts}),
      );
  }
  return Future.value();
}
