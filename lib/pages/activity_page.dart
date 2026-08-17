import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/activity_item.dart';
import '../models/document.dart';
import '../state/activity_notifier.dart';
import '../state/documents_notifier.dart';
import '../widgets/kit/kit.dart';

/// **Activity** (`spec/screens/activity.md`) — the live pipeline feed, and the
/// screen that defines the canonical merge every client implements identically.
///
/// Recomposed against the kit (ADR-041, screen 4/11). What was here was a grid
/// of bespoke cards over `activity.documents` — the *documents* half of the
/// merge only, so an event with no document behind it (a letter sent, a service
/// connected, an organization move) could not appear on the activity screen at
/// all. The merge was already correct in `activity_merge.dart`; nothing on this
/// screen read it.
///
/// Composition (§Composition), every part from the kit:
///
/// * **Frame** Index (980) inside a scroll container — §1.4/§1.5.
/// * **Header** chapter opening: title `Activity` and a standfirst. **No
///   folio** — this screen counts nothing; it is a record, not an index.
/// * **Controls** a control bar (§6.6) of filter chips (§6.7) over the event
///   families, each carrying its count and **disabled, not hidden**, at zero.
/// * **Body** date-bucketed section headers (§3) over the timeline (§4.2).
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  String _filter = 'all';

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
        final docsById = {for (final d in docs.documents) d.id: d};
        final rows = [
          for (final item in activity.items) _ActivityRow.from(item, docsById),
        ];

        final counts = <String, int>{'all': rows.length};
        for (final r in rows) {
          counts[r.family] = (counts[r.family] ?? 0) + 1;
        }
        final shown = _filter == 'all'
            ? rows
            : rows.where((r) => r.family == _filter).toList();

        return KitPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ChapterOpening(
                // One word, and the reference gives it no accent clause —
                // italicising the whole title is not the same device.
                title: 'Activity',
                standfirst: 'Everything that has happened on your account — '
                    'sources added, passages processed, letters sent.',
              ),

              if (activity.isLoading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (activity.error != null && rows.isEmpty)
                KitCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(activity.error!,
                            style: KitText.meta(context)),
                      ),
                      KitButton.ghost('Try again',
                          onPressed: () =>
                              context.read<ActivityNotifier>().refresh()),
                    ],
                  ),
                )
              else if (rows.isEmpty)
                const _ActivityEmpty()
              else ...[
                KitControlBar(
                  filters: [
                    for (final f in _families.entries)
                      KitFilterChip(
                        f.value,
                        count: counts[f.key] ?? 0,
                        selected: _filter == f.key,
                        // Disabled, not hidden: the families are a vocabulary,
                        // and a bar that changes shape per account puts the
                        // same filter in a different place for every reader.
                        onPressed: f.key == 'all' || (counts[f.key] ?? 0) > 0
                            ? () => setState(() => _filter = f.key)
                            : null,
                      ),
                  ],
                ),
                if (shown.isEmpty)
                  KitCard(
                    child: Text('Nothing of that kind yet.',
                        style: KitText.meta(context)),
                  )
                else
                  for (final bucket in _buckets) ...[
                    if (shown.any((r) => r.bucket == bucket)) ...[
                      SectionHeader(bucket, first: bucket == _buckets.first),
                      KitTimeline(
                        rows: [
                          for (final r
                              in shown.where((r) => r.bucket == bucket))
                            KitTimelineRow(
                              icon: r.icon,
                              tone: r.tone,
                              chip: r.chip,
                              subject: r.subject,
                              badge: r.badgeKind == null
                                  ? null
                                  : KitFileBadge(kitDocKind(r.badgeKind!),
                                      size: KitBadgeSize.inline),
                              detail: r.detail,
                              time: r.time,
                              live: r.live,
                              onTap: r.target == null
                                  ? null
                                  : () => _open(context, r.target!),
                            ),
                        ],
                      ),
                    ],
                  ],
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
      default:
        context.go('/sources');
    }
  }
}

/// The empty feed. An offer, not an apology (§7): a reader whose account has
/// done nothing yet is shown what would put something here.
class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();

  @override
  Widget build(BuildContext context) {
    return KitEmptyState(
      icon: Icons.timeline_outlined,
      title: 'Nothing has happened *yet.*',
      standfirst: 'This is the record of your account — every source added, '
          'every passage indexed, every letter sent.',
      suggestions: [
        KitSuggestion(
            icon: Icons.upload_outlined,
            label: 'Add your first source',
            onTap: () => context.go('/sources')),
        KitSuggestion(
            icon: Icons.cloud_outlined,
            label: 'Connect a service to import from',
            onTap: () => context.go('/sources')),
        KitSuggestion(
            icon: Icons.mail_outlined,
            label: 'Set when your letter arrives',
            onTap: () => context.go('/settings')),
      ],
    );
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
  'library': 'In the library',
};

const _buckets = ['Today', 'Yesterday', 'This week', 'Earlier'];

typedef _Kind = ({
  IconData icon,
  KitNodeTone tone,
  String family,
  String chip,
});

/// Mirrors the web reference's `ACT_TYPES` — the icon, the node colour (which
/// **names the event family**, it is not decoration), the filter family and the
/// mono chip, per event type.
const _kinds = <String, _Kind>{
  'added': (
    icon: Icons.file_upload_outlined,
    tone: KitNodeTone.accent,
    family: 'sources',
    chip: 'Added'
  ),
  'connected': (
    icon: Icons.link,
    tone: KitNodeTone.sage,
    family: 'sources',
    chip: 'Connected'
  ),
  'processing': (
    icon: Icons.schedule,
    tone: KitNodeTone.plum,
    family: 'processing',
    chip: 'Processing'
  ),
  'indexed': (
    icon: Icons.check,
    tone: KitNodeTone.sage,
    family: 'processing',
    chip: 'Indexed'
  ),
  'error': (
    icon: Icons.file_upload_outlined,
    tone: KitNodeTone.accent,
    family: 'processing',
    chip: 'Error'
  ),
  'letter': (
    icon: Icons.mail_outlined,
    tone: KitNodeTone.plum,
    family: 'letters',
    chip: 'Sent'
  ),
  'opened': (
    icon: Icons.visibility_outlined,
    tone: KitNodeTone.ink,
    family: 'letters',
    chip: 'Opened'
  ),
  'search': (
    icon: Icons.search,
    tone: KitNodeTone.ink,
    family: 'library',
    chip: 'Search'
  ),
  'ask': (
    icon: Icons.chat_bubble_outline,
    tone: KitNodeTone.ink,
    family: 'library',
    chip: 'Asked'
  ),
  'shelved': (
    icon: Icons.sell_outlined,
    tone: KitNodeTone.sage,
    family: 'library',
    chip: 'Shelved'
  ),
};

class _Target {
  final String route; // 'reader' | 'sources' | 'letters'
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
  });

  /// The web reference's `mapActivity` + `targetOf`, one for one.
  ///
  /// A **document** item is read through its status: complete is an indexed
  /// row, error/skipped an error row carrying `error_message`, and anything
  /// else is live. An **event** item takes its type's entry, and an unknown
  /// type degrades to `added` rather than rendering a raw token — `type` is an
  /// open vocabulary (organization events alone add five members).
  factory _ActivityRow.from(ActivityItem item, Map<String, Document> docsById) {
    _Kind kind;
    String subject;
    String? detail;
    String? badgeKind;
    var live = false;

    if (item.kind == 'document') {
      if (item.status == 'complete') {
        kind = _kinds['indexed']!;
      } else if (item.status == 'error' || item.status == 'skipped') {
        kind = _kinds['error']!;
        detail = item.errorMessage;
      } else {
        kind = _kinds['processing']!;
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
      kind = _kinds[item.type] ?? _kinds['added']!;
      subject = item.title.isEmpty ? item.type : item.title;
    }

    return _ActivityRow(
      icon: kind.icon,
      tone: kind.tone,
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
  if (meta['newsletter_id'] != null) return const _Target('letters');
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
