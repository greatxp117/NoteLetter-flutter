import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../state/activity_notifier.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../library/document_detail_sheet.dart';

/// **Browse** — the volume list on Sources (`screens/sources.md` §Composition
/// body 2), rebuilt against the kit (ADR-041, contract 4.5.2).
///
/// What this replaces is worth naming, because it was the largest inline block
/// left in this client: a **column-headed table** — Name / Added / Words /
/// Status — with its own hover fill, its own status pills in raw Material
/// colours, and `theme.textTheme` for every line. It arrived here by a move
/// (the old library body), and a table is not a pattern this app has: there is
/// no table in `component-kit.md`, and the §4.1 row already carries badge,
/// title, subtitle, count and date. 4.5.2 states that outright so the next
/// reader does not re-derive it.
///
/// Composition: Control bar (§6.6) of Filter chips (§6.7) with a trailing sort
/// Segmented control (§6.8), then Source row lists (§4.1) under Section
/// headers (§3) per group.
///
/// **Reads the documents subscription** (INV-02, `screens/sources.md` §Data —
/// the one Library shares), not the merged activity feed the table read. That
/// is what puts `view_count` and `processing_stage` in reach, and both are
/// required parts here: the unread dot is `view_count == 0` and nothing else,
/// and a processing row carries its stage in the subtitle slot.
class BrowseSection extends StatefulWidget {
  /// The empty state's offers act on the add panel at the foot of the screen,
  /// which owns the file picker and the link field. It is the screen's job to
  /// wire them: an empty state whose suggestion rows do nothing is the apology
  /// again, wearing the pattern.
  final VoidCallback? onAddFile;
  final VoidCallback? onAddLink;

  const BrowseSection({super.key, this.onAddFile, this.onAddLink});

  @override
  State<BrowseSection> createState() => _BrowseSectionState();
}

/// The filter vocabulary, matching the web reference's `SRC_KINDS`. It is a
/// **closed set rendered whole**: a kind with no volumes renders disabled, not
/// hidden (§6.7), so the bar keeps its shape from one library to the next.
const _kinds = <String, String>{
  'all': 'All',
  'pdf': 'PDFs',
  'epub': 'Books',
  'web': 'Web',
  'note': 'Notes',
  'unread': 'Unread',
};

const _sorts = <String, String>{
  'recent': 'Recent',
  'type': 'Type',
  'title': 'Title',
  'passages': 'Passages',
};

/// Group headings and their order, for the `type` sort.
const _kindName = <String, String>{
  'pdf': 'PDFs',
  'epub': 'Books',
  'web': 'Web clips',
  'note': 'Notes',
};
const _kindOrder = ['pdf', 'epub', 'web', 'note'];

class _BrowseSectionState extends State<BrowseSection> {
  String _filter = 'all';
  String _sort = 'recent';

  @override
  Widget build(BuildContext context) {
    return Consumer2<DocumentsNotifier, TagsNotifier>(
      builder: (context, docs, tags, _) {
        if (docs.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final all = docs.complete;
        // Everything the pipeline has not finished with, plus the terminal
        // failures that are still waiting to be acted on (§Document
        // processing). They lead the section: a source in flight is the thing
        // the reader just did.
        final inFlight = docs.documents
            .where((d) => d.status != DocumentStatus.complete)
            .toList();

        final counts = <String, int>{'all': all.length, 'unread': 0};
        for (final d in all) {
          final k = kitDocKind(d.type);
          counts[k] = (counts[k] ?? 0) + 1;
          if (d.viewCount == 0) counts['unread'] = counts['unread']! + 1;
        }

        final filtered = switch (_filter) {
          'all' => all,
          'unread' => all.where((d) => d.viewCount == 0).toList(),
          _ => all.where((d) => kitDocKind(d.type) == _filter).toList(),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (inFlight.isNotEmpty) ...[
              SectionHeader(_processingLabel(inFlight)),
              KitRowList(
                rows: [
                  for (final d in inFlight)
                    _ProcessingRow(doc: d),
                ],
              ),
            ],

            SectionHeader('In your library · ${_plural(all.length, 'volume')}'),

            KitControlBar(
              filters: [
                for (final e in _kinds.entries)
                  KitFilterChip(
                    e.value,
                    count: counts[e.key] ?? 0,
                    selected: _filter == e.key,
                    // Disabled, not hidden: an empty kind keeps its slot.
                    onPressed: e.key == 'all' || (counts[e.key] ?? 0) > 0
                        ? () => setState(() => _filter = e.key)
                        : null,
                  ),
              ],
              trailing: [
                const KitControlLabel('Order by'),
                KitSegmented(
                  segments: [
                    for (final label in _sorts.values) KitSegment(label),
                  ],
                  selected: _sorts.keys.toList().indexOf(_sort),
                  onChanged: (i) =>
                      setState(() => _sort = _sorts.keys.elementAt(i)),
                ),
              ],
            ),

            if (all.isEmpty)
              _NothingYet(
                onAddFile: widget.onAddFile,
                onAddLink: widget.onAddLink,
              )
            else if (_sort == 'type')
              ..._grouped(filtered, tags.tags)
            else ...[
              KitRowList(
                rows: [
                  for (final d in _sorted(filtered))
                    _VolumeRow(doc: d, shelves: tags.tags),
                ],
              ),
              if (filtered.isEmpty)
                const _NoneOfThatKind(),
            ],
          ],
        );
      },
    );
  }

  /// The `type` sort groups the list, each group under its own Section header.
  List<Widget> _grouped(List<Document> list, List<Tag> shelves) {
    final byKind = <String, List<Document>>{};
    for (final d in list) {
      byKind.putIfAbsent(kitDocKind(d.type), () => []).add(d);
    }
    final keys = _kindOrder.where(byKind.containsKey).toList()
      ..addAll(byKind.keys.where((k) => !_kindOrder.contains(k)));
    return [
      for (final k in keys) ...[
        SectionHeader('${_kindName[k] ?? k} · ${byKind[k]!.length}'),
        KitRowList(
          rows: [
            for (final d in byKind[k]!) _VolumeRow(doc: d, shelves: shelves),
          ],
        ),
      ],
    ];
  }

  List<Document> _sorted(List<Document> list) {
    final arr = [...list];
    switch (_sort) {
      case 'title':
        arr.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'passages':
        arr.sort((a, b) => (b.chunkCount ?? 0).compareTo(a.chunkCount ?? 0));
      // `recent` is the subscription's own order (created_at desc) — re-sorting
      // it would only be a chance to disagree with it.
    }
    return arr;
  }
}

/// §Document processing — the header counts the section, and **splits the count
/// when anything has failed**: "{active} indexing now — {failed} needs
/// attention". One number for two states would bury the half that needs a
/// person.
String _processingLabel(List<Document> inFlight) {
  final failed = inFlight
      .where((d) =>
          d.status == DocumentStatus.error || d.status == DocumentStatus.skipped)
      .length;
  final active = inFlight.length - failed;
  if (failed == 0) return 'Being processed · $active';
  if (active == 0) return '$failed needs attention';
  return '$active indexing now — $failed needs attention';
}

/// A volume. The §4.1 row, with its per-source affordances hanging off the end.
class _VolumeRow extends StatelessWidget {
  final Document doc;
  final List<Tag> shelves;

  const _VolumeRow({required this.doc, required this.shelves});

  @override
  Widget build(BuildContext context) {
    return KitSourceRow(
      leading: KitFileBadge(kitDocKind(doc.type)),
      title: doc.title.isEmpty ? 'Untitled' : doc.title,
      subtitle: _shelfLabel(doc, shelves),
      count: _plural(doc.chunkCount ?? 0, 'passage'),
      date: _rowDate(doc.createdAt),
      // Unread is view_count == 0 — "you have not opened this in the reader".
      // Expanding this source out of a search result does not clear it
      // (INV-03a); that writes chunk_viewed and touches no document counter.
      unread: doc.viewCount == 0,
      onTap: () => context.push('/reader/${doc.id}'),
      trailing: _RowMenu(doc: doc),
    );
  }
}

/// A source still in the pipeline. **Not a different component** — the same
/// §4.1 row, carrying its stage in the subtitle slot (`screens/sources.md`
/// §Composition), with retry/remove or cancel in the trailing slot.
class _ProcessingRow extends StatelessWidget {
  final Document doc;

  const _ProcessingRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final failed = doc.status == DocumentStatus.error ||
        doc.status == DocumentStatus.skipped;
    // The failure message is shown VERBATIM: there is no error reason code, and
    // a client that pattern-matches the message to substitute its own copy is
    // inventing a classification the backend never made.
    final subtitle = failed
        ? (doc.errorMessage ?? _stageLabel(doc))
        : _stageLabel(doc);

    return KitSourceRow(
      leading: KitFileBadge(kitDocKind(doc.type)),
      title: doc.title.isEmpty ? 'Untitled' : doc.title,
      subtitle: subtitle,
      date: _rowDate(doc.createdAt),
      trailing: _RowMenu(doc: doc),
    );
  }
}

/// The pill label, derived from `status` and refined by `processing_stage` —
/// **never the raw status string**. `processing_stage` is an open vocabulary
/// (ADR-024): an unrecognised value falls back to the generic "Processing",
/// never to an error.
String _stageLabel(Document doc) {
  switch (doc.status) {
    case DocumentStatus.pendingUpload:
      return 'Uploading';
    case DocumentStatus.queued:
      return 'Queued';
    case DocumentStatus.processing:
      switch (doc.processingStage) {
        case 'extraction':
          return 'Extracting text';
        case 'embedding':
          return 'Embedding passages';
        default:
          return 'Processing';
      }
    case DocumentStatus.error:
      return 'Error';
    case DocumentStatus.skipped:
      return 'Skipped';
    case DocumentStatus.complete:
      return 'Done';
  }
}

/// The per-source overflow: open, priority & tags, retry, cancel, delete.
class _RowMenu extends StatelessWidget {
  final Document doc;

  const _RowMenu({required this.doc});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final complete = doc.status == DocumentStatus.complete;
    final failed = doc.status == DocumentStatus.error ||
        doc.status == DocumentStatus.skipped;
    final active = !complete && !failed;

    return PopupMenuButton<String>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(Icons.more_horiz, size: 17, color: t.fgMuted),
      itemBuilder: (_) => [
        if (complete)
          const PopupMenuItem(value: 'open', child: Text('Open')),
        const PopupMenuItem(value: 'details', child: Text('Priority & tags…')),
        if (failed)
          const PopupMenuItem(value: 'retry', child: Text('Retry')),
        if (active)
          const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
        const PopupMenuItem(value: 'delete', child: Text('Remove')),
      ],
      onSelected: (action) => _run(context, action),
    );
  }

  Future<void> _run(BuildContext context, String action) async {
    final activity = context.read<ActivityNotifier>();

    switch (action) {
      case 'open':
        context.push('/reader/${doc.id}');
      case 'details':
        final saved = await DocumentDetailSheet.show(context, doc.id);
        if (saved == true && context.mounted) {
          AppToast.show(context, 'Saved.', type: ToastType.info);
        }
      case 'retry':
        final err = await activity.retryDocument(doc.id);
        if (!context.mounted) return;
        AppToast.show(context, err ?? 'Retrying this source.',
            type: err != null ? ToastType.error : ToastType.info);
      case 'cancel':
        final confirmed = await _confirm(
          context,
          title: 'Stop processing “${_name()}”?',
          body: 'This deletes the document; nothing indexed so far is kept. '
              'Your original file is not affected — you can add it again any '
              'time.',
          confirmLabel: 'Stop & remove',
          cancelLabel: 'Keep processing',
        );
        if (confirmed != true || !context.mounted) return;
        final err = await activity.cancelDocument(doc.id);
        if (!context.mounted) return;
        AppToast.show(context, err ?? 'Cancelled.',
            type: err != null ? ToastType.error : ToastType.info);
      case 'delete':
        final confirmed = await _confirm(
          context,
          title: 'Remove “${_name()}”?',
          body: 'This removes the document and any passages indexed from it '
              'from your library and future letters. The original file on your '
              'device or cloud service is untouched.',
          confirmLabel: 'Remove',
          cancelLabel: 'Keep it',
        );
        if (confirmed != true || !context.mounted) return;
        final err = await activity.deleteDocument(doc.id);
        if (!context.mounted) return;
        AppToast.show(context, err ?? 'Removed.',
            type: err != null ? ToastType.error : ToastType.info);
    }
  }

  String _name() => doc.title.isEmpty ? 'Untitled' : doc.title;
}

/// A destructive confirm, in the kit's own buttons — the copy names the
/// consequence and the cancel label names the alternative ("Keep it"), rather
/// than the two-word Cancel/OK pair that makes a reader guess which way is
/// safe.
Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = Tokens.of(ctx);
      return AlertDialog(
        backgroundColor: t.surface,
        title: Text(title, style: KitText.h4(ctx)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(body, style: KitText.meta(ctx)),
        ),
        actions: [
          KitButton.ghost(cancelLabel,
              onPressed: () => Navigator.pop(ctx, false)),
          KitButton.danger(confirmLabel,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      );
    },
  );
}

/// The library with nothing in it. **An offer, not an apology** (§7) — the
/// suggestion rows are the required part, and the drop zone that closes the
/// screen is directly below.
class _NothingYet extends StatelessWidget {
  final VoidCallback? onAddFile;
  final VoidCallback? onAddLink;

  const _NothingYet({this.onAddFile, this.onAddLink});

  @override
  Widget build(BuildContext context) {
    return KitEmptyState(
      icon: Icons.auto_stories_outlined,
      title: 'Nothing here yet.',
      standfirst: 'Add a file or connect a service, and the passages start '
          'arriving within a minute.',
      suggestions: [
        KitSuggestion(
          icon: Icons.upload_outlined,
          label: 'Add your first file',
          onTap: onAddFile,
        ),
        KitSuggestion(
          icon: Icons.link,
          label: 'Paste a link — article, video, or podcast',
          onTap: onAddLink,
        ),
      ],
    );
  }
}

/// A filter that matched nothing. Serif italic, centred — the reference's
/// `.browse-none`, which is a note inside a list, not an empty state.
class _NoneOfThatKind extends StatelessWidget {
  const _NoneOfThatKind();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Center(
        child: Text('No sources of that kind yet.',
            style: KitText.lede(context, fontSize: 15, height: 22)),
      ),
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────────

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The row date — the web's `formatDate`: minutes-ago, then a clock time within
/// the day, then a calendar date.
String _rowDate(int? ms) {
  if (ms == null) return '';
  final then = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 24) {
    final h = then.hour % 12 == 0 ? 12 : then.hour % 12;
    final m = then.minute.toString().padLeft(2, '0');
    return '$h:$m ${then.hour < 12 ? 'AM' : 'PM'}';
  }
  return '${_months[then.month - 1]} ${then.day}';
}

String _shelfLabel(Document doc, List<Tag> shelves) {
  for (final s in shelves) {
    if (doc.tagIds.contains(s.id)) return s.title;
  }
  return 'Unshelved';
}
