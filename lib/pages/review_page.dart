import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/background_task.dart';
import '../models/document.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../state/cloud_notifier.dart';
import '../state/review_inbox.dart';
import '../widgets/kit/kit.dart';
import 'review/task_copy.dart';
import 'review/task_review.dart';
import 'sources/browse_section.dart' show ProcessingRow;
import 'sources/import_review_queue.dart';
import 'sources/suggestion_queue.dart';

/// The endpoint's own batch cap (`fn_review_documents`).
const _dismissBatch = 50;

/// **For your review** (4.100.0–4.103.0, ADR-135/136, INV-30 —
/// `screens/review.md`). Everything the app is waiting on the reader for, in
/// one place — each thing answered with the component, handler and endpoint of
/// the surface it came from, so this is a second place to answer a question
/// and never a second way to answer it. Mirrors `ReviewView.jsx`.
///
/// Reads [ReviewInbox] — the object the rail's attention count reads — so the
/// number there and the rows here cannot disagree. Nothing moves before its
/// record does.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReviewInbox>().start();
      // The review rules only WORD a held row's reason ("over your 5 MB review
      // size"); every action works without them.
      context.read<CloudNotifier>().loadIntegrations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<ReviewInbox>();
    final cloud = context.watch<CloudNotifier>();
    final v = inbox.view;
    // The unmeasured figure is the dash (ADR-109) — never a count of the parts
    // that loaded (INV-30).
    final folio = v.count == 0 ? 'Nothing waiting' : '${v.countText ?? '—'} waiting';

    return KitPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChapterOpening(
            folio: folio,
            title: 'For your review',
            standfirst: 'Everything the app is waiting on you for. Nothing '
                'here happens until you decide.',
          ),
          if (v.empty)
            const _ReviewEmpty()
          else ...[
            if (!v.loaded && !v.anyFailed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (v.sourcesError != null)
              _groupFailure('The sources that need you could not be read.',
                  v.sourcesError!, inbox.retry)
            else if (v.sources.isNotEmpty)
              _SourcesNeedingYou(sources: v.sources),
            if (v.holdsError != null)
              _groupFailure('The files waiting to import could not be read.',
                  v.holdsError!, inbox.retry)
            else ...[
              if (cloud.reviewOutcome != null && v.holds.isNotEmpty)
                ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
              ImportReviewQueue(
                held: v.holds,
                eyebrow: 'Files waiting to import',
                rulesFor: (p) =>
                    cloud.integrationFor(p)?.reviewRules ?? const {},
              ),
            ],
            if (v.suggestionsError != null)
              _groupFailure('Your organization suggestions could not be read.',
                  v.suggestionsError!, inbox.retry)
            else
              SuggestionQueue(
                  eyebrow: 'Suggested changes', suggestions: v.suggestions),
            if (v.tasksError != null)
              _groupFailure(
                  'What is running in the background could not be read.',
                  v.tasksError!,
                  inbox.retry)
            else
              _TaskGroups(
                  proposals: v.proposals, running: v.running, now: v.now),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  /// §14.1 in the group's place; the other groups render normally.
  Widget _groupFailure(String sentence, String detail, VoidCallback retry) =>
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: KitFailureBlock(
            sentence: sentence, detail: detail, onRetry: retry),
      );
}

/// §Sources that need you: the Library's attention cards, plus Dismiss.
/// Dismiss takes a source out of HERE and changes nothing else, and the
/// standing sentence says so — a reader who thinks Dismiss deletes will not
/// press it on the one source they meant to keep.
class _SourcesNeedingYou extends StatefulWidget {
  final List<Document> sources;
  const _SourcesNeedingYou({required this.sources});

  @override
  State<_SourcesNeedingYou> createState() => _SourcesNeedingYouState();
}

class _SourcesNeedingYouState extends State<_SourcesNeedingYou> {
  /// The bulk dismiss's refusal, under the header, once its panel is closed.
  String? _allError;

  /// §18 on the BULK dismiss only: a reader dismissing one row has just read
  /// it; "Dismiss all" acts on rows that may be scrolled out of sight. Pages
  /// that landed before a refusal are real and leave by subscription; the
  /// panel stays with the sentence for the rest (§18 rule 2).
  Future<void> _dismissAll() async {
    final ids = [for (final d in widget.sources) d.id];
    final n = ids.length;
    setState(() => _allError = null);
    String? last;
    await KitConfirm.show(
      context,
      title: 'Dismiss $n ${n == 1 ? 'source' : 'sources'} from For your review?',
      body: 'They stay in your Library as they are, and come back here if a '
          'retry fails again.',
      confirmLabel: 'Dismiss all',
      cancelLabel: 'Keep them here',
      danger: false,
      onConfirm: () async {
        try {
          for (var i = 0; i < ids.length; i += _dismissBatch) {
            // Ids in `skipped` were already moved by something else (a Retry,
            // the pipeline) and leave by subscription like the rest.
            await Api.instance.reviewDocuments(ids.sublist(
                i, i + _dismissBatch > n ? n : i + _dismissBatch));
          }
          last = null;
          return null;
        } on ApiException catch (e) {
          return last = e.message;
        } catch (_) {
          // Not swallowed: no envelope came back (a socket, a parse), so this
          // sentence is the panel's §18 slot text, and it is rendered there.
          return last = 'That request could not be completed.';
        }
      },
    );
    if (mounted && last != null) setState(() => _allError = last);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.sources.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Sources that need you · $n',
            actionLabel: 'Dismiss all', onAction: _dismissAll),
        const KitProcNote(
          'Dismissing only clears it from here. It stays in your Library as '
          'it is, and comes back if a retry fails again.',
          padding: EdgeInsets.only(bottom: 10),
        ),
        if (_allError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KitFailureInline(_allError!),
          ),
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          ProcessingRow(
              key: ValueKey('review-src-${widget.sources[i].id}'),
              doc: widget.sources[i],
              dismissible: true),
        ],
      ],
    );
  }
}

/// §Proposals + §Running (4.101.0, ADR-136).
class _TaskGroups extends StatelessWidget {
  final List<BackgroundTask> proposals;
  final List<BackgroundTask> running;
  final DateTime now;

  const _TaskGroups(
      {required this.proposals, required this.running, required this.now});

  @override
  Widget build(BuildContext context) {
    List<Widget> rows(List<BackgroundTask> ts) => [
          for (var i = 0; i < ts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            TaskReviewRow(key: ValueKey('task-${ts[i].id}'), task: ts[i], now: now),
          ],
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (proposals.isNotEmpty) ...[
          SectionHeader('Proposals · ${proposals.length}'),
          ...rows(proposals),
        ],
        // Last, because nothing in it asks for anything.
        if (running.isNotEmpty) ...[
          SectionHeader('Running · ${running.length}',
              note: 'nothing here needs you yet'),
          ...rows(running),
        ],
      ],
    );
  }
}

/// One task as §22's Review row. Write before you move: every control waits
/// for its call, and the row changes only when the task's record does.
class TaskReviewRow extends StatefulWidget {
  final BackgroundTask task;
  final DateTime now;

  /// Test seams; null is the canonical builder and the kind's own review.
  final Future<void> Function(String taskId, String action)? resolve;
  final void Function(BackgroundTask task)? onReview;

  const TaskReviewRow({
    super.key,
    required this.task,
    required this.now,
    this.resolve,
    this.onReview,
  });

  @override
  State<TaskReviewRow> createState() => _TaskReviewRowState();
}

class _TaskReviewRowState extends State<TaskReviewRow> {
  String? _busy; // 'retry' | 'dismiss'
  String? _error;

  Future<void> _act(String action) async {
    setState(() {
      _busy = action;
      _error = null;
    });
    String? err;
    try {
      await (widget.resolve ??
          (id, a) => Api.instance.resolveTask(id, a))(widget.task.id, action);
    } on ApiException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'That request could not be completed.';
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final now = widget.now;
    final stalled = t.isStalled(now);
    final waiting = t.status == 'awaiting_review' || t.status == 'failed' || stalled;
    final (tone, label) = taskPill(t, now);
    final busy = _busy != null;
    final reviewable = t.status == 'awaiting_review' && !stalled;
    final failures = [
      if (t.applyError != null) KitFailureInline(t.applyError!, dense: true),
      if (_error != null) KitFailureInline(_error!, dense: true),
    ];
    return KitReviewRow(
      title: t.subjectTitle ?? 'Untitled',
      detail: taskDetail(t),
      pill: KitProcPill(label, tone: tone),
      shelfMark: t.subjectType == 'shelf',
      shelfColor: t.subjectColor,
      failed: t.status == 'failed' || stalled,
      waiting: waiting,
      sentence: taskSentence(t, now),
      failure: failures.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < failures.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  failures[i],
                ],
              ],
            ),
      actions: [
        if (reviewable) ...[
          if (canReviewTask(t))
            KitButton.primary('Review',
                onPressed: busy
                    ? null
                    : () => (widget.onReview ??
                        (task) => openTaskReview(context, task))(t)),
          // A refused apply is answered by a fresh proposal: `retry` runs it
          // again (api/tasks.md).
          if (t.applyError != null)
            KitButton.ghost(_busy == 'retry' ? 'Starting…' : 'Run again',
                onPressed: busy ? null : () => _act('retry')),
        ] else
          KitButton.primary(_busy == 'retry' ? 'Starting…' : 'Try again',
              icon: Icons.refresh,
              onPressed: busy ? null : () => _act('retry')),
        if (t.status == 'awaiting_review' || t.status == 'failed')
          KitButton.ghost(_busy == 'dismiss' ? 'Dismissing…' : 'Dismiss',
              onPressed: busy ? null : () => _act('dismiss')),
      ],
    );
  }
}

/// §7 — an offer, not an apology: nothing is waiting, and here is where things
/// come from.
class _ReviewEmpty extends StatelessWidget {
  const _ReviewEmpty();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: KitEmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nothing waiting for you',
          standfirst: 'When a source fails, a file waits for approval, or a '
              'suggestion is ready, it lands here.',
          suggestions: [
            KitSuggestion(
                icon: Icons.local_library_outlined,
                label: 'Add to your library',
                onTap: () => context.go('/sources')),
            KitSuggestion(
                icon: Icons.tune,
                label: 'Ask before importing large files',
                onTap: () => context.go('/sources')),
            KitSuggestion(
                icon: Icons.timeline_outlined,
                label: 'See what happened recently',
                onTap: () => context.go('/activity')),
          ],
        ),
      );
}
