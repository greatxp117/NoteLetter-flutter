import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/activity_item.dart';
import '../models/document.dart';
import '../shared/cooldown.dart';
import '../shared/local_flags.dart';
import '../shared/stalled.dart';
import '../state/activity_notifier.dart';
import '../state/documents_notifier.dart';
import '../widgets/kit/kit.dart';
import 'reader/supersession_confirm.dart';
import 'sources/browse_section.dart' show runSourcePrimary;

/// **Activity** (`spec/screens/activity.md`) — the live pipeline feed, and the
/// screen that defines the canonical merge every client implements identically.
///
/// Direction D (§Composition; web `pages/ActivityView.jsx`), every part from
/// the kit:
///
/// * **Frame** the D frame (kit §26–§29) inside the primary scroll container,
///   which ends with the support footer.
/// * **Masthead** folio `Activity · {N} events` (the ellipsis while the feed
///   is out, the dash when it was refused — never a zero for a read that has
///   not said so), title *Activity* and its standfirst. Search alone.
/// * **Sheet** *Filters*: the Kind facet over the event families, each with
///   its count, **held, not hidden**, at zero; then *When* — Contents over the
///   day buckets that hold rows under the chosen kind. On a phone it is the
///   running head: the sliders, the chosen kind and `{shown} of {all}`.
/// * **Column** one section per day under a small SectionHead (§31), over the
///   timeline (§4.2) — its row hover kit §36's reference. Skeleton lines while
///   the feed is out, never *Nothing of that kind yet.*
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  String _filter = 'all';

  /// The day buckets as the page's sections: *When* jumps to one.
  final KitSections _sec = KitSections(const []);

  /// A stalled row crosses its threshold with NO Firestore write behind it, so
  /// nothing would redraw it (sources.md §Stalled rows: a client must run a
  /// clock). One clock for the screen, running only while a document is
  /// `queued` or `processing` (web ActivityView, 15 s).
  Timer? _tick;

  void _syncTick(bool watching) {
    if (watching && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) setState(() {});
      });
    } else if (!watching) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sec.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActivityNotifier>().start();
      // The documents subscription this screen shares with Library and Sources
      // (INV-02). It is not a second read of the feed: it is what resolves a
      // row's target — an event's `doc_id` only earns a Reader link when the
      // document it names can be SEEN to be complete.
      context.read<DocumentsNotifier>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ActivityNotifier, DocumentsNotifier>(
      builder: (context, activity, docs, _) {
        // Looking at the feed is what marks it seen (§Toasts and unread) — on
        // every snapshot, not only on arrival, because the reader sits here
        // while events land and the badge must not light for what is already
        // on their screen. `markActivitySeen` never moves backwards, so this
        // is idempotent and a rebuild costs nothing.
        final newest = activity.newestEventAt;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) LocalFlags.markActivitySeen(newest);
        });

        final docsById = {for (final d in docs.documents) d.id: d};
        final now = DateTime.now();
        final watching = docs.documents.any((d) =>
            d.status == DocumentStatus.queued ||
            d.status == DocumentStatus.processing);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncTick(watching);
        });
        // Retry on a failed document's NEWEST failure row only (the feed is
        // newest first), so a document that failed twice offers one.
        final offered = <String>{};
        final rows = [
          for (final item in activity.items)
            () {
              final row = _ActivityRow.from(item, docsById, now);
              final failedId = _failedDocIdOf(item, docsById, now);
              if (failedId == null || !offered.add(failedId)) return row;
              return row.acting(failedId, docsById[failedId], now);
            }(),
        ];

        final counts = <String, int>{'all': rows.length};
        for (final r in rows) {
          counts[r.family] = (counts[r.family] ?? 0) + 1;
        }
        final shown = _filter == 'all'
            ? rows
            : rows.where((r) => r.family == _filter).toList();
        final buckets = [
          for (final b in _buckets)
            if (shown.any((r) => r.bucket == b))
              (b, shown.where((r) => r.bucket == b).toList()),
        ];
        final ids = [for (final g in buckets) g.$1];
        if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

        // INV-24 (ADR-071): the feed is unread until its first answer, and a
        // refusal leaves it unmeasured (ADR-109).
        final failed = activity.error != null;
        final loading = activity.isLoading && rows.isEmpty && !failed;
        final folioN = failed
            ? '— events'
            : loading
            ? '…'
            : kitCounted(rows.length, 'event');
        final kind = _families[_filter] ?? 'All';
        final when = [
          for (final g in buckets)
            KitContentsItem(g.$1, g.$1, count: '${g.$2.length}'),
        ];

        return KitDPage(
          folio: 'Activity\u00a0· $folioN',
          title: 'Activity',
          stand:
              'Everything that has happened on your account — sources added, '
              'passages processed, letters sent, and more.',
          sections: _sec,
          sheet: KitDSheet(
            label: 'Filters',
            // A day row folds the running head; a kind does not — the days
            // under it change with it (web `foldOn: '.rx-nav-b'`).
            foldOnPick: true,
            peek: KitLibPeek(
              icon: Icons.tune,
              title: _filter == 'all' ? 'All activity' : kind,
              count: loading || failed ? null : '${shown.length}',
              tail: loading || failed || _filter == 'all'
                  ? null
                  : ' of ${rows.length}',
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(
                  builder: (context) {
                    final scope = KitSheetScope.maybeOf(context);
                    return KitSheetScope(
                      lines: scope?.lines ?? false,
                      dock: scope?.dock ?? false,
                      child: KitFacet(
                        label: 'Kind',
                        value: _filter,
                        // Held, not hidden: the families are a vocabulary.
                        // `other` is the one exception — a bucket rather than
                        // a family, and its choice appearing at all is the
                        // visible form of this build being older than the
                        // backend.
                        items: [
                          for (final f in _families.entries)
                            if (f.key != 'other' || (counts['other'] ?? 0) > 0)
                              KitFacetItem(
                                f.key,
                                f.value,
                                count: '${counts[f.key] ?? 0}',
                                disabled:
                                    f.key != 'all' && (counts[f.key] ?? 0) == 0,
                              ),
                        ],
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    );
                  },
                ),
                if (when.isNotEmpty) ...[
                  const KitDLabel('When'),
                  KitContents(items: when, sections: _sec, label: 'When'),
                ],
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // §14.1 (ADR-070) whenever there IS an error, and above the rows
              // (C1): a feed that loaded once and then failed keeps what did
              // load — it is still true — under the notice that it is stale.
              if (failed)
                KitFailureBlock(
                  sentence: 'Your activity could not be loaded.',
                  detail: activity.error!,
                  onRetry: () => context.read<ActivityNotifier>().refresh(),
                ),
              if (loading)
                const KitSkeletonLines(
                  lines: [
                    KitSkelLine(0.3, true),
                    KitSkelLine(),
                    KitSkelLine(0.7),
                    KitSkelLine(),
                    KitSkelLine(0.6),
                    KitSkelLine(),
                    KitSkelLine(0.7),
                  ],
                )
              else if (buckets.isEmpty && !failed)
                const KitDNone('Nothing of that kind yet.')
              else
                for (var i = 0; i < buckets.length; i++) ...[
                  // `.dp-act-g + .dp-act-g { margin-top: 48px }` — outside
                  // the section, so When's jump lands its head 24 under the
                  // top.
                  if (i > 0 || failed) const SizedBox(height: 48),
                  KeyedSubtree(
                    key: _sec.keyOf(buckets[i].$1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KitSectionHead(
                          buckets[i].$1,
                          small: true,
                          meta: kitCounted(buckets[i].$2.length, 'event'),
                        ),
                        KitTimeline(
                          rows: [
                            for (final r in buckets[i].$2)
                              KitTimelineRow(
                                icon: r.icon,
                                tone: r.tone,
                                chip: r.chip,
                                subject: r.subject,
                                badge: r.badgeKind == null
                                    ? null
                                    : KitFileBadge(
                                        kitDocKind(r.badgeKind!),
                                        size: KitBadgeSize.inline,
                                      ),
                                detail: r.detail,
                                time: r.time,
                                live: r.live,
                                action: r.actsDocId == null
                                    ? null
                                    : _RowRetry(
                                        key: ValueKey('retry-${r.actsDocId}'),
                                        docId: r.actsDocId!,
                                        doc: r.retryDoc,
                                      ),
                                onTap: r.target == null
                                    ? null
                                    : () => _open(context, r.target!),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, _Target target) {
    switch (target.route) {
      case 'reader':
        context.push('/reader/${target.docId}');
      case 'letters':
        context.go('/letters');
      case 'support':
        context.go('/support');
      case 'study':
        context.go('/study');
      default:
        context.go('/sources');
    }
  }
}

// ── The event vocabulary ─────────────────────────────────────────────────────

/// The filter families, in the reference's order. `all` leads and is never
/// disabled.
const _families = <String, String>{
  'all': 'All',
  'sources': 'Sources',
  'processing': 'Processing',
  'letters': 'Letters',
  'study': 'Study',
  'library': 'In the library',
  // `other` is a bucket, not a family: its chip appears only when a row lands
  // in it, and a count above zero there means this build is older than the
  // backend. That is the visible form of client/contract skew.
  'other': 'Other',
};

const _buckets = ['Today', 'Yesterday', 'This week', 'Earlier'];

typedef _Kind = ({
  String family,
  String chip,
  IconData icon,
});

/// The activity-event vocabulary (contract 4.21.0, ADR-057).
///
/// The client half of a contract whose other half is `_write_activity_event`;
/// `spec/data-model.md` §The `type` vocabulary is normative and
/// `harness/activity_vocab_check.py` compares the two in **both** directions.
///
/// It replaced a ten-token map copied from the web reference, which had itself
/// taken it from the design prototype — `added`, `connected`, `indexed`,
/// `letter`, `opened`, `search`, `ask`, `shelved` — none of which the backend
/// has ever written. Every event fell through `_kinds[item.type] ??
/// _kinds['added']!` and rendered as "Added", so a failed ingest and a
/// successful one were the same row.
///
/// The node tone is NOT in this table any more: it is the family's colour,
/// overridden by `level` (see [_toneFor]). Shape is load-bearing for the gate's
/// parser — one entry per line, `family:` then `chip:`, single-quoted.
///
/// The glyph follows web `activityKinds.jsx`: its `IcoAlert` is the TRIANGLE
/// (`warning_amber_rounded`, the kit's own alert), never the circled `!` this
/// table drew for all thirteen until 2026-10-05; its `IcoSend` is a right
/// arrow, never a paper plane.
const _kinds = <String, _Kind>{
  // ── processing — the document pipeline ─────────────────────────────────────
  'doc_indexed': (family: 'processing', chip: 'Indexed', icon: Icons.check),
  'doc_processing_note': (family: 'processing', chip: 'Note', icon: Icons.notes_outlined),
  'doc_processing_failed': (family: 'processing', chip: 'Failed', icon: Icons.warning_amber_rounded),
  'doc_indexing_failed': (family: 'processing', chip: 'Failed', icon: Icons.warning_amber_rounded),
  'doc_skipped': (family: 'processing', chip: 'Skipped', icon: Icons.close),
  'doc_cancelled': (family: 'processing', chip: 'Cancelled', icon: Icons.close),
  'article_resolved': (family: 'processing', chip: 'Article found', icon: Icons.article_outlined),

  // ── sources — services, imports, cloud organization ────────────────────────
  'service_connected': (family: 'sources', chip: 'Connected', icon: Icons.link),
  'service_disconnected': (family: 'sources', chip: 'Disconnected', icon: Icons.link_off),
  'sync_session': (family: 'sources', chip: 'Synced', icon: Icons.sync),
  'cloud_sync_failed': (family: 'sources', chip: 'Sync failed', icon: Icons.warning_amber_rounded),
  'plan_limit_reached': (family: 'sources', chip: 'Plan limit', icon: Icons.warning_amber_rounded),
  'integration_reconnect_required': (family: 'sources', chip: 'Reconnect', icon: Icons.warning_amber_rounded),
  'organization_move': (family: 'sources', chip: 'Moved', icon: Icons.drive_file_move_outlined),
  'organization_placement': (family: 'sources', chip: 'Filed', icon: Icons.drive_file_move_outlined),
  'organization_error': (family: 'sources', chip: 'Organizing', icon: Icons.warning_amber_rounded),
  'organization_scope_denied': (family: 'sources', chip: 'Permission', icon: Icons.warning_amber_rounded),
  'readme_written': (family: 'sources', chip: 'README', icon: Icons.description_outlined),
  'reorg_executed': (family: 'sources', chip: 'Reorganized', icon: Icons.folder_open_outlined),

  // ── letters — everything outbound ──────────────────────────────────────────
  'newsletter_sent': (family: 'letters', chip: 'Letter', icon: Icons.mail_outlined),
  'newsletter_delivery_failed': (family: 'letters', chip: 'Not delivered', icon: Icons.warning_amber_rounded),
  'newsletter_delivery_delayed': (family: 'letters', chip: 'Still sending', icon: Icons.arrow_forward),
  'newsletter_unsubscribed': (family: 'letters', chip: 'Unsubscribed', icon: Icons.unsubscribe_outlined),
  'scripture_emails_off': (family: 'letters', chip: 'Readings email off', icon: Icons.unsubscribe_outlined),
  'scripture_newsletter_sent': (family: 'letters', chip: 'Readings', icon: Icons.menu_book_outlined),
  'scripture_newsletter_empty': (family: 'letters', chip: 'Readings', icon: Icons.menu_book_outlined),
  'scripture_newsletter_email_failed': (family: 'letters', chip: 'Readings email', icon: Icons.warning_amber_rounded),
  'scripture_delivery_failed': (family: 'letters', chip: 'Not delivered', icon: Icons.warning_amber_rounded),
  'scripture_delivery_delayed': (family: 'letters', chip: 'Still sending', icon: Icons.arrow_forward),

  // ── study ──────────────────────────────────────────────────────────────────
  'study_session_sent': (family: 'study', chip: 'Study', icon: Icons.style_outlined),
  'study_session_empty': (family: 'study', chip: 'Study empty', icon: Icons.style_outlined),
  'study_session_failed': (family: 'study', chip: 'Study failed', icon: Icons.warning_amber_rounded),
  'study_session_email_failed': (family: 'study', chip: 'Study email', icon: Icons.arrow_forward),
  'study_material_low': (family: 'study', chip: 'Material low', icon: Icons.speed_outlined),
  'study_emails_off': (family: 'study', chip: 'Study email off', icon: Icons.unsubscribe_outlined),
  'study_items_retired': (family: 'study', chip: 'Retired', icon: Icons.history),
  'study_delivery_failed': (family: 'study', chip: 'Not delivered', icon: Icons.warning_amber_rounded),
  'study_delivery_delayed': (family: 'study', chip: 'Still sending', icon: Icons.arrow_forward),

  // ── library ────────────────────────────────────────────────────────────────
  'shelf_split': (family: 'library', chip: 'Split', icon: Icons.call_split),
  // Background tasks (4.101.0, ADR-136) — the vocab gate's CLIENT-SHORT
  // direction; the task surfaces themselves are QUEUE F-72.
  'shelf_deleted': (family: 'library', chip: 'Deleted', icon: Icons.delete_outline),
  'review_ready': (family: 'library', chip: 'Ready for review', icon: Icons.inbox_outlined),
  'task_finished': (family: 'library', chip: 'Finished', icon: Icons.check_circle_outline),
  'task_failed': (family: 'library', chip: 'Failed', icon: Icons.warning_amber_rounded),
  'support_reply': (family: 'library', chip: 'Support', icon: Icons.support_agent_outlined),
  'search_synthesized': (family: 'library', chip: 'Arranged', icon: Icons.auto_awesome_outlined),
};

/// Node tone per family, **overridden by severity** (component-kit §4.2).
/// `level` is the axis (2.5.0, ADR-014), not `status`; an absent or unknown
/// level reads as `info`, never as an error.
KitNodeTone _toneFor(String family, String? level) {
  if (level == 'error') return KitNodeTone.critical;
  if (level == 'warning') return KitNodeTone.warning;
  return switch (family) {
    'sources' => KitNodeTone.sage,
    'processing' => KitNodeTone.plum,
    'letters' => KitNodeTone.plum,
    'study' => KitNodeTone.sage,
    _ => KitNodeTone.ink,
  };
}

/// `doc_processing_note` → `Processing note`. Only ever reached for a type this
/// build has not heard of, which means it is older than the backend.
String _humanizeType(String type) {
  final words = type.replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Event';
  return words[0].toUpperCase() + words.substring(1);
}

/// An unlisted type renders NEUTRALLY — it never borrows a listed type's chip,
/// icon or family. Resolving to a specific wrong meaning is worse than
/// resolving to none: nothing about the row then says the client did not
/// understand it.
_Kind _kindFor(String type) =>
    _kinds[type] ??
    (family: 'other', chip: _humanizeType(type), icon: Icons.help_outline);

/// The rows that report a document's failure (activity.md §Where a row
/// leads): its failure events, keyed on `metadata.doc_id`, and a document row
/// in `error` — or, since Xavier's ruling of 2026-10-17, a document row drawn
/// STALLED (the same stall test, on the screen's clock).
const _docFailureEvents = {'doc_processing_failed', 'doc_indexing_failed'};

String? _failedDocIdOf(
    ActivityItem item, Map<String, Document> docsById, DateTime now) {
  if (item.kind == 'document') {
    if (item.status == 'error') return item.id;
    final doc = docsById[item.id];
    return doc != null && doc.isStalled(now) ? item.id : null;
  }
  if (!_docFailureEvents.contains(item.type)) return null;
  final id = item.metadata?['doc_id'];
  return id is String && id.isNotEmpty ? id : null;
}

/// The row's Retry — **the Sources row's own action** ([runSourcePrimary]):
/// the same `fn_retry_document`, the same supersession confirm, the same
/// cooldown and held control, the same accent primary. Its refusal is §14.2
/// with the endpoint's sentence verbatim, and it stays said after the Retry
/// goes (the document moved on, 409, or was deleted, 404). On success nothing
/// is optimistic: the document leaves `error` under the subscription and the
/// Retry goes with it.
class _RowRetry extends StatefulWidget {
  final String docId;

  /// The document while it is `error` or stalled; null draws no Retry (the
  /// refusal, if one was said, stays).
  final Document? doc;

  const _RowRetry({super.key, required this.docId, required this.doc});

  @override
  State<_RowRetry> createState() => _RowRetryState();
}

class _RowRetryState extends State<_RowRetry> {
  bool _busy = false;
  String? _error;

  Future<void> _retry(Document doc) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await runSourcePrimary(context, doc, force: false);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.outcome == SupersessionOutcome.refused && !res.waits
          ? res.message
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: WaitKey.documentRetry(widget.docId),
        builder: (context, wait) {
          final doc = widget.doc;
          final slot = kitRefusalSlot(wait, _error, dense: true);
          if (doc == null && slot == null) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (doc != null)
                KitButton.primary('Retry',
                    icon: Icons.refresh,
                    wait: _busy ? 0 : wait.left,
                    onPressed: _busy ? null : () => _retry(doc)),
              if (slot != null) ...[
                if (doc != null) const SizedBox(height: 6),
                slot,
              ],
            ],
          );
        },
      );
}

class _Target {
  final String route; // 'reader' | 'sources' | 'letters' | 'support' | 'study'
  final String? docId;

  const _Target(this.route, [this.docId]);
}

/// One row of the feed, resolved from a merged [ActivityItem].
class _ActivityRow {
  final IconData icon;
  final KitNodeTone tone;
  final String family;
  final String chip;
  final String subject;
  final String? detail;
  final String? badgeKind;
  final String time;
  final String bucket;
  final bool live;
  final _Target? target;

  /// The document this row offers Retry for — set on the NEWEST failure row
  /// of a document only (activity.md §Where a row leads, ruled 2026-10-14),
  /// whatever its status now, so a refusal already said stays said once the
  /// Retry goes (a 409 because it moved on, a 404 because it was deleted).
  /// The page fills it after mapping (it needs the whole feed).
  final String? actsDocId;

  /// That document while it is retryable in the documents subscription —
  /// `error`, or stalled (ruled 2026-10-17: what `fn_retry_document` accepts
  /// without `force`) — and only then is there a Retry.
  final Document? retryDoc;

  const _ActivityRow({
    required this.icon,
    required this.tone,
    required this.family,
    required this.chip,
    required this.subject,
    this.detail,
    this.badgeKind,
    required this.time,
    required this.bucket,
    required this.live,
    required this.target,
    this.actsDocId,
    this.retryDoc,
  });

  _ActivityRow acting(String docId, Document? doc, DateTime now) =>
      _ActivityRow(
        icon: icon,
        tone: tone,
        family: family,
        chip: chip,
        subject: subject,
        detail: detail,
        badgeKind: badgeKind,
        time: time,
        bucket: bucket,
        live: live,
        target: target,
        actsDocId: docId,
        retryDoc: doc != null &&
                (doc.status == DocumentStatus.error || doc.isStalled(now))
            ? doc
            : null,
      );

  /// The web reference's `mapActivity` + `targetOf`, one for one.
  ///
  /// A **document** item is read through its status: complete is an indexed
  /// row, error/skipped an error row carrying `error_message`, and anything
  /// else is live. An **event** item takes its type's entry, and an unknown
  /// type degrades to `added` rather than rendering a raw token — `type` is an
  /// open vocabulary (organization events alone add five members).
  factory _ActivityRow.from(
      ActivityItem item, Map<String, Document> docsById, DateTime now) {
    _Kind kind;
    String subject;
    String? detail;
    String? badgeKind;
    var live = false;
    // A stalled run is drawn Stalled, as the Sources row and For your review
    // draw it (activity.md §The row, ruled by Xavier 2026-10-14) — it was
    // "Processing" with the pulsing node: progress drawn on a run that has
    // ended or will never start. The stall moment is read from the documents
    // subscription this screen already holds (the merged document item does
    // not carry `processing_stalls_at`), and [now] is the page's one clock.
    final stalledDoc =
        item.kind == 'document' ? docsById[item.id] : null;
    final stalled = stalledDoc != null && stalledDoc.isStalled(now);

    if (item.kind == 'document') {
      if (stalled) {
        kind = (
          family: 'processing',
          chip: 'Stalled',
          icon: Icons.warning_amber_rounded
        );
        detail = stalledMessage(stalledDoc);
      } else if (item.status == 'complete') {
        kind = (family: 'processing', chip: 'Indexed', icon: Icons.check);
      } else if (item.status == 'error' || item.status == 'skipped') {
        kind = (
          family: 'processing',
          chip: item.status == 'skipped' ? 'Skipped' : 'Failed',
          // web `mapActivity`: IcoAlert, the triangle — as the table's.
          icon: Icons.warning_amber_rounded
        );
        detail = item.errorMessage;
      } else {
        kind = (
          family: 'processing',
          chip: 'Processing',
          icon: Icons.schedule
        );
        // 2.19.0 (ADR-024): name WHICH half of the pipeline is running. Both
        // take minutes, and while they shared one label a reader could not
        // tell an advancing document from a stuck one. Only when there IS a
        // stage — for a queued document the detail line would just say
        // "Queued" under a chip that already says PROCESSING.
        detail = item.processingStage == null ? null : item.statusLabel;
        live = true;
      }
      subject = item.title.isEmpty ? 'Untitled' : item.title;
      badgeKind = item.type;
    } else {
      kind = _kindFor(item.type);
      subject = item.title.isEmpty ? item.type : item.title;
      // The sentence that says what happened. `metadata.note` carries the
      // pipeline note, the skip reason and the support answer (INV-22);
      // `metadata.error` the failure text. Hardcoding this `null` for events is
      // what dropped every message the backend has ever written.
      final meta = item.metadata ?? const <String, dynamic>{};
      detail = (meta['note'] ?? meta['error']) as String?;
    }

    return _ActivityRow(
      icon: kind.icon,
      tone: _toneFor(
        kind.family,
        // A document row has no `level` of its own — its severity is its
        // status, the way the merge already derives it; a stalled run's node
        // is `critical`.
        item.kind == 'document'
            ? (stalled || item.status == 'error'
                ? 'error'
                : item.status == 'skipped'
                    ? 'warning'
                    : null)
            : item.level,
      ),
      family: kind.family,
      chip: kind.chip,
      subject: subject,
      detail: detail,
      badgeKind: badgeKind,
      time: _clock(item.createdAt),
      bucket: _bucketOf(item.createdAt),
      live: live,
      target: _targetOf(item, docsById),
    );
  }
}

/// Where did this activity happen? Every target is derived from data the feed
/// already carries — `metadata.doc_id`, `metadata.newsletter_id`, and the
/// provider on cloud events.
///
/// A row whose target cannot be resolved stays **inert** rather than looking
/// tappable and going nowhere: a dead link is worse than a plain row. And a
/// `doc_id` earns a Reader link only when the document can be seen to be
/// complete — one missing from the documents subscription was deleted or has
/// aged out of the window, and the Reader would open on nothing, so those fall
/// back to Sources, which lists every source in every status.
_Target? _targetOf(ActivityItem item, Map<String, Document> docsById) {
  if (item.kind == 'document') {
    return item.status == 'complete'
        ? _Target('reader', item.id)
        : const _Target('sources');
  }
  final meta = item.metadata ?? const <String, dynamic>{};
  final docId = meta['doc_id'] as String?;
  if (docId != null) {
    final d = docsById[docId];
    if (d == null) return null;
    return d.status == DocumentStatus.complete
        ? _Target('reader', docId)
        : const _Target('sources');
  }
  if (meta['thread_id'] != null) return const _Target('support');
  if (meta['newsletter_id'] != null) return const _Target('letters');
  if (meta['program_id'] != null) return const _Target('study');
  // Cloud and organization events (connect/disconnect, moves, README writes,
  // scope denials) all resolve to the provider's card on Sources.
  if (item.provider != null || meta['provider'] != null) {
    return const _Target('sources');
  }
  return null;
}

/// `Today` · `Yesterday` · `This week` · `Earlier`, by calendar day rather
/// than by elapsed hours — 11pm and 1am are different days, not two hours.
String _bucketOf(int? ms) {
  if (ms == null) return 'Earlier';
  final now = DateTime.now();
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff <= 7) return 'This week';
  return 'Earlier';
}

/// The trailing timestamp: a clock time, because the bucket already carries the
/// day. `h:mm AM` — the reference's `toLocaleTimeString('en-US')`.
String _clock(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
