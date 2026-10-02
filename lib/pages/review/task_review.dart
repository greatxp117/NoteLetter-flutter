/// For your review's **Review** (`screens/review.md` §Proposals): each kind's
/// own review, opened in a §15 sheet and fed from the stored record. The
/// review is the surface the proposal came from — the inbox is a second place
/// to answer it, never a second way. Mirrors `TaskReviewSheet` in
/// `ReviewView.jsx`.
library;

import 'package:flutter/material.dart';

import '../../models/background_task.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';
import '../reader/reorganize_sheet.dart';
import '../study/syllabus_plan_editor.dart';
import '../tags/reshelve_sheet.dart';
import '../tags/shelf_sheet.dart';
import '../tags/split_shelf_sheet.dart';

/// The kinds this client can review. A kind outside it is still a row — its
/// subject, its status, Dismiss — and still counted (§22).
bool canReviewTask(BackgroundTask t) =>
    t.result != null && _reviewable.contains(t.kind);

const _reviewable = {
  'shelf_delete', 'shelf_backfill', 'shelf_split', 'syllabus_plan', //
  'reorg_plan',
};

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
    // 4.103.0: the program screen's own editor, seeded from `result`; Apply
    // sends the reader's EDITED plan as the decision.
    case 'syllabus_plan':
      return _showSyllabusReview(context, t, result);
    // 4.103.0: the sections and destinations from `result`, no Reading state;
    // Reorganize is one apply with the operations, the same arming confirm
    // for any split, then progress off `/reorg_plans/{plan_id}`.
    case 'reorg_plan':
      return ReorganizeSheet.show(
        context,
        t.subjectId ?? '',
        () {},
        stored: StoredReorg(
          result: result,
          apply: (operations) => Api.instance
              .resolveTask(t.id, 'apply', {'operations': operations}),
          rerun: () => Api.instance.resolveTask(t.id, 'retry'),
        ),
      );
  }
  return Future.value();
}

/// §15 sheet "Syllabus for {program}" over the stored proposal. The stored
/// proposal seeds the editor and is never rewritten; a refusal (a 400 naming
/// the entry) stays in the sheet beside it (§14.2), and the sheet is held
/// while the apply is in flight.
Future<void> _showSyllabusReview(
    BuildContext context, BackgroundTask t, Map<String, dynamic> result) {
  final holding = ValueNotifier<bool>(false);
  final program = t.subjectTitle ?? 'this program';
  final document = t.params['document_title'] as String? ?? 'the syllabus';
  return KitOverlaySheet.show(
    context,
    icon: Icons.event_note_outlined,
    title: 'Syllabus for $program',
    subtitle: 'Read from $document. Nothing changes until you apply it.',
    width: 640,
    holding: holding,
    builder: (ctx) => _SyllabusReview(
      task: t,
      result: result,
      onBusy: (b) => holding.value = b,
      close: () => Navigator.of(ctx).pop(),
    ),
  ).whenComplete(holding.dispose);
}

class _SyllabusReview extends StatefulWidget {
  final BackgroundTask task;
  final Map<String, dynamic> result;
  final ValueChanged<bool> onBusy;
  final VoidCallback close;
  const _SyllabusReview(
      {required this.task,
      required this.result,
      required this.onBusy,
      required this.close});

  @override
  State<_SyllabusReview> createState() => _SyllabusReviewState();
}

class _SyllabusReviewState extends State<_SyllabusReview> {
  bool _busy = false;
  String? _error;

  Future<void> _apply(List<Map<String, dynamic>> units,
      List<Map<String, dynamic>> assessments) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusy(true);
    String? err;
    try {
      await Api.instance.resolveTask(widget.task.id, 'apply',
          {'units': units, 'assessments': assessments});
    } on ApiException catch (e) {
      err = e.message;
    } catch (_) {
      // Not swallowed: no envelope came back; rendered above the editor.
      err = 'That plan could not be applied. Nothing was changed.';
    }
    widget.onBusy(false);
    if (!mounted) return;
    if (err == null) {
      widget.close();
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              KitFailureInline(_error!),
              const SizedBox(height: 10),
            ],
            SyllabusPlanEditor(
              proposal: widget.result,
              busy: _busy,
              onApply: _apply,
              onDiscard: widget.close,
              discardLabel: 'Not now',
            ),
          ],
        ),
      );
}
