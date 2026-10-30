import 'package:flutter/foundation.dart' show listEquals;
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
/// Direction D (§Composition): the masthead's folio is the inbox's count (the
/// dash unmeasured, *Nothing waiting* at zero); the sheet *Waiting on you*
/// counts what waits as the page's Contents — from the rows the column draws —
/// then Also; the groups keep their own components, under D's group heads.
///
/// Reads [ReviewInbox] — the object the rail's attention count reads — so the
/// number there and the rows here cannot disagree. Nothing moves before its
/// record does.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

/// The groups in the column's order, and their names on the sheet.
const _groups = ['sources', 'holds', 'suggestions', 'tasks'];
const _groupLabel = {
  'sources': 'Couldn’t be read',
  'holds': 'Imports held',
  'suggestions': 'Suggested changes',
  'tasks': 'Proposals and tasks',
};

class _ReviewPageState extends State<ReviewPage> {
  final KitSections _sec = KitSections(const []);

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
  void dispose() {
    _sec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<ReviewInbox>();
    final cloud = context.watch<CloudNotifier>();
    final v = inbox.view;
    // The unmeasured figure is the dash (ADR-109) — never a count of the parts
    // that loaded (INV-30).
    final folio = v.count == 0
        ? 'Nothing waiting'
        : '${v.countText ?? '—'} waiting';

    // The sheet's Contents: one row per group that has something in it,
    // counted from the same lists the column draws (INV-30). Proposals and
    // tasks counts what waits and what runs.
    final counts = {
      'sources': v.sources.length,
      'holds': v.holds.length,
      'suggestions': v.suggestions.length,
      'tasks': v.proposals.length + v.running.length,
    };
    final items = [
      for (final id in _groups)
        if (counts[id]! > 0)
          KitContentsItem(id, _groupLabel[id]!, count: '${counts[id]}'),
    ];
    // `current` follows only the groups the Contents list, so the running
    // head never names an empty one.
    final ids = [for (final i in items) i.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

    final errors = {
      'sources': v.sourcesError,
      'holds': v.holdsError,
      'suggestions': v.suggestionsError,
      'tasks': v.tasksError,
    };
    // The first group that draws anything opens at the column's top.
    final firstDrawn = _groups
        .where((id) => errors[id] != null || counts[id]! > 0)
        .firstOrNull;

    Widget group(String id, Widget child) => KeyedSubtree(
      key: _sec.keyOf(id),
      child: KitDGroupHeads(first: id == firstDrawn, child: child),
    );

    Widget failure(String id, String sentence) => Padding(
      padding: EdgeInsets.only(top: id == firstDrawn ? 0 : 56),
      child: KitFailureBlock(
        sentence: sentence,
        detail: errors[id]!,
        onRetry: inbox.retry,
      ),
    );

    return KitDPage(
      folio: 'For your review\u00a0· $folio',
      title: 'For Your Review',
      stand:
          'Everything the app is waiting on you for. Nothing here happens '
          'until you decide.',
      sections: _sec,
      sheet: KitDSheet(
        label: 'Waiting on you',
        foldOnPick: true,
        peek: items.isNotEmpty
            ? KitSecPeek(items: items, sections: _sec)
            : KitLibPeek(
                title: 'For your review',
                meta: v.loaded ? 'Nothing waiting' : null,
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            if (items.isNotEmpty)
              KitContents(items: items, sections: _sec)
            else if (!v.loaded)
              const KitSkeletonLines(
                lines: [KitSkelLine(0.7), KitSkelLine(0.6)],
                top: 0,
              )
            // Nothing at all when a read failed: its §14.1 block is in the
            // column, and a sentence here would be about what it did not say.
            else if (!v.anyFailed)
              const KitLedgerNone('Nothing is waiting on you.'),
            Builder(
              builder: (context) => KitSheetAlso(
                children: [
                  KitAlsoButton(
                    'See what happened recently',
                    icon: Icons.timeline_outlined,
                    onTap: () {
                      KitSheetScope.pick(context);
                      context.go('/activity');
                    },
                  ),
                  KitAlsoButton(
                    'Go to the library',
                    icon: Icons.menu_book_outlined,
                    onTap: () {
                      KitSheetScope.pick(context);
                      context.go('/sources');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      child: v.empty
          ? const _ReviewEmpty()
          : !v.loaded && !v.anyFailed && items.isEmpty
          ? const KitSkeletonLines(
              lines: [
                KitSkelLine(0.5, true),
                KitSkelLine(),
                KitSkelLine(0.7),
                KitSkelLine(),
                KitSkelLine(0.6),
              ],
              top: 0,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v.sourcesError != null)
                  group(
                    'sources',
                    failure(
                      'sources',
                      'The sources that need you could not be read.',
                    ),
                  )
                else if (v.sources.isNotEmpty)
                  group('sources', _SourcesNeedingYou(sources: v.sources)),
                if (v.holdsError != null)
                  group(
                    'holds',
                    failure(
                      'holds',
                      'The files waiting to import could not be read.',
                    ),
                  )
                else
                  group(
                    'holds',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (cloud.reviewOutcome != null && v.holds.isNotEmpty)
                          ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
                        ImportReviewQueue(
                          held: v.holds,
                          eyebrow: 'Files waiting to import',
                          rulesFor: (p) =>
                              cloud.integrationFor(p)?.reviewRules ?? const {},
                        ),
                      ],
                    ),
                  ),
                if (v.suggestionsError != null)
                  group(
                    'suggestions',
                    failure(
                      'suggestions',
                      'Your organization suggestions could not be read.',
                    ),
                  )
                else
                  group(
                    'suggestions',
                    SuggestionQueue(
                      eyebrow: 'Suggested changes',
                      suggestions: v.suggestions,
                    ),
                  ),
                if (v.tasksError != null)
                  group(
                    'tasks',
                    failure(
                      'tasks',
                      'What is running in the background could not be read.',
                    ),
                  )
                else
                  group(
                    'tasks',
                    _TaskGroups(
                      proposals: v.proposals,
                      running: v.running,
                      now: v.now,
                    ),
                  ),
              ],
            ),
    );
  }
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
        const KitDStanding(
          'Dismissing only clears it from here. It stays in your Library as '
          'it is, and comes back if a retry fails again.',
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
        // Last, because nothing in it asks for anything. Never the first
        // head when Proposals stands above it.
        if (running.isNotEmpty) ...[
          KitDGroupHeads(
            first: proposals.isEmpty &&
                (KitDGroupHeads.maybeOf(context)?.first ?? false),
            child: SectionHeader('Running · ${running.length}',
                note: 'nothing here needs you yet'),
          ),
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

  /// In the D frame [KitEmptyState] takes §37's form: set on the column's
  /// leading edge, a seal for its mark, its offers a ruled list.
  @override
  Widget build(BuildContext context) => KitEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing waiting for you',
        standfirst: 'When a source fails, a file waits for approval, or a '
            'suggestion is ready, it lands here.',
        suggestions: [
          KitSuggestion(
              icon: Icons.menu_book_outlined,
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
      );
}
