import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../shared/local_flags.dart';
import '../../state/activity_notifier.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../library/document_detail_sheet.dart';
import '../reader/supersession_confirm.dart';
import 'shelf_books.dart';
import 'source_sheet.dart';

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
  'youtube': 'YouTube',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'note': 'Notes',
  // §6.4.1 rule 2: every live kind has a chip. Audio and Video were missing
  // here, so a recording could be sorted to but never filtered to (4.84.1).
  'podcast': 'Audio',
  'video': 'Video',
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
  'youtube': 'YouTube',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'note': 'Notes',
  'podcast': 'Audio',
  'video': 'Video',
};
const _kindOrder = [
  'pdf', 'epub', 'web', 'youtube', 'instagram', 'tiktok', 'note', //
  'podcast', 'video',
];

/// The view toggle's three positions, in the reference's order.
const _views = <({String id, String label, IconData icon})>[
  (id: 'list', label: 'List view', icon: Icons.view_agenda_outlined),
  (id: 'cards', label: 'Card view', icon: Icons.grid_view),
  (id: 'shelf', label: 'Shelf view', icon: Icons.shelves),
];

class _BrowseSectionState extends State<BrowseSection> {
  String _filter = 'all';
  String _sort = 'recent';

  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LocalFlags.sourcesView,
      builder: (context, view, _) => _build(context, view),
    );
  }

  Widget _build(BuildContext context, String view) {
    return Consumer2<DocumentsNotifier, TagsNotifier>(
      builder: (context, docs, tags, _) {
        if (docs.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final all = docs.complete;

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
            // The SECOND unread figure on this screen, and the one the
            // header fix above would have left behind (C2). `all.length` is
            // derived from the same subscription, so on a failure this said
            // "In your library · 0 volumes" beside a §14 block saying the
            // library could not be read. Unread is not zero (§8, ADR-109):
            // the label stays, the figure goes.
            SectionHeader(docs.error != null
                ? 'In your library'
                : 'In your library · ${_plural(all.length, 'volume')}'),

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
                // `.view-toggle` — list, cards or shelf, kept per viewer
                // (`nl-sources-view`); the shelf is the reference's default.
                KitSegmented(
                  segments: [
                    for (final v in _views) KitSegment.icon(v.icon, v.label),
                  ],
                  selected: _views.indexWhere((v) => v.id == view),
                  onChanged: (i) =>
                      LocalFlags.setView(LocalFlags.sourcesView, _views[i].id),
                ),
              ],
            ),

            // §7 may only speak when nothing failed (C2). `all.isEmpty` is
            // true of a failed subscription exactly as it is of a library with
            // nothing in it, so _NothingYet — an OFFER — stood in for the
            // hole, and `DocumentsNotifier` has carried the error since F-08.
            //
            // The notice itself belongs to `sources_page`, which mounts this
            // section and draws §14.1 above it: one failure gets one notice,
            // and a block here would be the second drawing of the same
            // sentence on one screen. Suppressing the offer is this section's
            // whole half of the rule.
            if (all.isEmpty && docs.error == null)
              _NothingYet(
                onAddFile: widget.onAddFile,
                onAddLink: widget.onAddLink,
              )
            else if (all.isEmpty)
              const SizedBox.shrink()
            // The shelf orders and groups its own ledges (`type` groups them
            // by kind under the shelf's own labels), as the reference's does.
            else if (view == 'shelf')
              KitShelfView(
                items: [for (final d in filtered) bookOf(d, tags.tags)],
                sort: _sort,
              )
            else if (_sort == 'type')
              ..._grouped(filtered, tags.tags, view)
            else ...[
              _set(_sorted(filtered), tags.tags, view),
              if (filtered.isEmpty)
                const _NoneOfThatKind(),
            ],
          ],
        );
      },
    );
  }

  /// One run of volumes as the chosen view draws it: §4.1 rows, or cards.
  Widget _set(List<Document> list, List<Tag> shelves, String view) {
    if (view == 'cards') {
      if (list.isEmpty) return const SizedBox.shrink();
      return KitSourceCardGrid(cards: [
        for (final d in list)
          KitSourceCard(
            book: bookOf(d, shelves),
            kindLabel: _kindName[kitDocKind(d.type)] ?? kitDocKind(d.type),
            date: _rowDate(d.createdAt),
          ),
      ]);
    }
    return KitRowList(
      rows: [for (final d in list) _VolumeRow(doc: d, shelves: shelves)],
    );
  }

  /// The `type` sort groups the list, each group under its own Section header.
  List<Widget> _grouped(List<Document> list, List<Tag> shelves, String view) {
    final byKind = <String, List<Document>>{};
    for (final d in list) {
      byKind.putIfAbsent(kitDocKind(d.type), () => []).add(d);
    }
    final keys = _kindOrder.where(byKind.containsKey).toList()
      ..addAll(byKind.keys.where((k) => !_kindOrder.contains(k)));
    return [
      for (final k in keys) ...[
        SectionHeader('${_kindName[k] ?? k} · ${byKind[k]!.length}'),
        _set(byKind[k]!, shelves, view),
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

/// §Document processing — **Being processed**, directly under the drop zone and
/// the link row (`screens/sources.md` §Composition body 1: "the processing rows
/// sit directly under it"). A source you just dropped lands where you are
/// already looking. It was the head of the *In your library* section — at the
/// foot of the screen, under the connect grid, the import panels and the
/// organization card — so on a phone the thing a drop produces was never in
/// the same view as the drop.
///
/// Everything the pipeline has not finished with, plus the terminal failures
/// still waiting to be acted on.
class ProcessingSection extends StatelessWidget {
  const ProcessingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final inFlight = docs.documents
        .where((d) => d.status != DocumentStatus.complete)
        .toList();
    if (docs.loading || inFlight.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(_processingLabel(inFlight),
            note: _processingNote(inFlight)),
        KitRowList(
          rows: [
            for (final d in inFlight) ProcessingRow(doc: d),
          ],
        ),
      ],
    );
  }
}

/// §Document processing — the header counts the section, and **splits the count
/// when anything has failed**: "{active} indexing now — {failed} needs
/// attention". One number for two states would bury the half that needs a
/// person.
String _processingLabel(List<Document> inFlight) =>
    'Being processed · ${inFlight.length}';

/// The split, beside the total. A STALLED row needs a person as much as a
/// failed one (ADR-108), so it counts on the attention side, as the
/// reference's does; with nothing needing one, the note says what to expect.
String _processingNote(List<Document> inFlight) {
  final attention = inFlight
      .where((d) =>
          d.status == DocumentStatus.error ||
          d.status == DocumentStatus.skipped ||
          d.isStalled())
      .length;
  if (attention == 0) return 'passages appear as each finishes';
  final active = inFlight.length - attention;
  final needs = attention == 1 ? 'needs' : 'need';
  return '$active indexing now — $attention $needs attention';
}

/// A volume. The §4.1 row, with its per-source affordances hanging off the end.
class _VolumeRow extends StatelessWidget {
  final Document doc;
  final List<Tag> shelves;

  const _VolumeRow({required this.doc, required this.shelves});

  @override
  Widget build(BuildContext context) {
    return KitSourceLink(
      docId: doc.id,
      builder: (context, open) => KitSourceRow(
        leading: KitFileBadge(kitDocKind(doc.type)),
        title: doc.title.isEmpty ? 'Untitled' : doc.title,
        subtitle: _shelfLabel(doc, shelves),
        count: _plural(doc.chunkCount ?? 0, 'passage'),
        date: _rowDate(doc.createdAt),
        // Unread is view_count == 0 — "you have not opened this in the reader".
        // Expanding this source out of a search result does not clear it
        // (INV-03a); that writes chunk_viewed and touches no document counter.
        unread: doc.viewCount == 0,
        onTap: open,
        trailing: _RowMenu(doc: doc),
      ),
    );
  }
}

/// A source still in the pipeline. **Not a different component** — the same
/// §4.1 row, carrying its stage in the subtitle slot (`screens/sources.md`
/// §Composition).
///
/// The trailing slot carries, in order: the **source affordance** (§6.4.2 —
/// every row offers the source itself, because `error_message` is a claim
/// *about* a source and nothing else on the screen shows it), then **the row's
/// one primary**, then the overflow.
class ProcessingRow extends StatefulWidget {
  final Document doc;

  /// Test seams for the supersession confirm's two reads; null is the live read.
  final Future<bool?> Function(String docId)? studyCheck;
  final Future<bool?> Function(String docId)? editCheck;

  const ProcessingRow(
      {super.key, required this.doc, this.studyCheck, this.editCheck});

  @override
  State<ProcessingRow> createState() => _ProcessingRowState();
}

class _ProcessingRowState extends State<ProcessingRow> {
  /// §14.2 — **one slot, shared**, since one primary means one outstanding
  /// request. A 409/429 renders here, in the row, with the server's words: the
  /// cooldown and cap copy is user-facing.
  String? _error;
  bool _busy = false;

  /// A row crosses its stall moment with NO Firestore write behind it, so
  /// nothing would rebuild it and the stage label would keep claiming progress
  /// for as long as the screen stayed open — the defect surviving the fix
  /// (4.74.0, ADR-108). The timer runs only while this document is actually
  /// mid-pipeline, and stops the moment it is not.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(covariant ProcessingRow old) {
    super.didUpdateWidget(old);
    _syncTick();
  }

  void _syncTick() {
    final watching = widget.doc.status == DocumentStatus.processing;
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
    super.dispose();
  }

  /// **The row's one primary** (4.47.0, ADR-085), chosen by `status`:
  ///
  /// * `error` → **Retry** (`fn_retry_document`, re-enters at `failed_stage`)
  /// * `skipped` + not forced → **Index it anyway** (`force: true`)
  /// * `skipped` + `skip_reason == "unresolved_article"` → **Index it anyway**
  ///   *whatever `force_process` says* — the card was read correctly and the
  ///   LOOKUP failed, and a lookup that failed may come back. Hiding it there
  ///   would make a transient failure permanent with no route back.
  /// * `skipped`, forced, any other reason → **none**. The appeal has been
  ///   heard, an unforced retry would still 409, and a control whose only job
  ///   is to explain why it does nothing is a sentence pretending to be a
  ///   button.
  ///
  /// **Retry is never rendered on a `skipped` row**: `fn_retry_document`
  /// refuses that status by name, so the control could not succeed and never
  /// could. The two branches are disjoint by construction.
  (String, bool)? _primary(Document doc) {
    if (doc.status == DocumentStatus.error) return ('Retry', false);
    // A stalled `processing` row gets the same primary (4.74.0, ADR-108).
    // `fn_retry_document` accepts it — the widened status is reachable from
    // here, which is the whole reason the backend half was not shipped alone.
    if (doc.isStalled()) return ('Retry', false);
    if (doc.status == DocumentStatus.skipped &&
        (doc.skipReason == 'unresolved_article' || !doc.forceProcess)) {
      return ('Index it anyway', true);
    }
    return null;
  }

  Future<void> _runPrimary(bool force) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final activity = context.read<ActivityNotifier>();
    final doc = widget.doc;
    final title = doc.title.isEmpty ? 'Untitled' : doc.title;
    // reader.md §Supersession confirm names "retry of an errored doc": it
    // re-derives the document, and an errored document CAN hold both facts —
    // one that failed a RE-extraction keeps its passages, and a study program
    // that took it in while complete still lists it. So both primaries run
    // through the supersession confirm (web 71987f6): it asks when a passage
    // was edited or the document is in a program, or either could not be
    // checked, and sends straight through on two definite noes. Inside the
    // confirm a refusal stays in the panel's §18 slot; with no confirm owed it
    // is §14.2 under the row, as before. The control is held until it resolves.
    final res = await SupersessionConfirm.run(
      context,
      docId: doc.id,
      title: force ? 'Index “$title” anyway?' : 'Retry “$title”?',
      lead: force ? forceLead : retryLead,
      confirmLabel: force ? 'Index it anyway' : 'Retry and replace',
      action: () => force
          ? activity.forceProcessDocument(doc.id)
          : activity.retryDocument(doc.id),
      studyCheck: widget.studyCheck,
      editCheck: widget.editCheck,
    );
    if (!mounted) return;
    // On 200 **no optimistic state is needed**: the document flips to `queued`
    // under the existing subscription and the row returns to its normal
    // progress treatment.
    setState(() {
      _busy = false;
      _error = res.outcome == SupersessionOutcome.refused ? res.message : null;
    });
  }

  /// The confirm's lead sentences, verbatim from the reference (web 71987f6).
  static const retryLead =
      'This source will be processed again from its original, and any '
      'passages it has are replaced with a fresh extraction.';
  static const forceLead =
      'This source will be read again as text, and any passages it has are '
      'replaced with a fresh extraction.';

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final failed = doc.status == DocumentStatus.error ||
        doc.status == DocumentStatus.skipped;
    // The failure message is shown VERBATIM: there is no error reason code, and
    // a client that pattern-matches the message to substitute its own copy is
    // inventing a classification the backend never made.
    // There is no `error_message` on a stalled document — nothing failed, a run
    // stopped existing — so it needs copy of its own, saying the two things the
    // reader cannot see: that waiting will not help, and that Retry costs them
    // nothing already spent. Mirrors web's STALLED_PROC_MSG verbatim.
    const stalledMsg =
        'Indexing stopped before it finished. Waiting will not help — Retry to start it again.';
    final subtitle = failed
        ? (doc.errorMessage ?? _stageLabel(doc))
        : doc.isStalled()
            ? stalledMsg
            : _stageLabel(doc);
    final primary = _primary(doc);

    final row = KitSourceRow(
      leading: KitFileBadge(kitDocKind(doc.type)),
      title: doc.title.isEmpty ? 'Untitled' : doc.title,
      subtitle: subtitle,
      date: _rowDate(doc.createdAt),
      // Three controls at once — the source affordance, the primary and the
      // overflow — do not fit beside the text on a phone.
      wideTrailing: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Offered on EVERY row — failed, queued, uploading or
          // mid-extraction — and chosen by the document's shape, which is
          // known at creation and does not depend on `status`.
          KitButton.ghost(SourceSheet.labelFor(doc),
              onPressed: () => SourceSheet.open(context, doc)),
          if (primary != null) ...[
            const SizedBox(width: 6),
            // The one accent-filled control. Same slot, same metrics, same
            // position in both branches: an `error` row and a `skipped` row
            // are the same pattern with a different decision in it, not two
            // designs.
            KitButton.primary(primary.$1,
                onPressed: _busy ? null : () => _runPrimary(primary.$2)),
          ],
          const SizedBox(width: 4),
          _RowMenu(doc: doc),
        ],
      ),
    );

    if (_error == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 8),
          child: KitFailureInline(_error!, dense: true),
        ),
      ],
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
      // Checked BEFORE the stage: a stage label on a run that ended is the
      // defect ADR-108 exists to end. "Stalled", not "Error" — nothing
      // reported a failure and saying one would be inventing it.
      if (doc.isStalled()) return 'Stalled';
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
        // Retry and Index-it-anyway are NOT here. A failure row has **one
        // primary** and it is an accent-filled control on the row itself
        // (4.47.0, ADR-085) — burying the row's single answer in an overflow
        // menu is the same defect as rendering both at once, arrived at from
        // the other side. `ProcessingRow` owns it.
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
      // §18 (4.56.0, ADR-092). The ACTION runs inside the confirmation now, so
      // its rejection renders in the panel the reader is looking at instead of
      // a toast behind it — and the panel does not close on one, which is what
      // stops a refused delete reading as a successful one.
      case 'cancel':
        final done = await KitConfirm.show(
          context,
          title: 'Stop processing “${_name()}”?',
          body: 'This deletes the document; nothing indexed so far is kept. '
              'Your original file is not affected — you can add it again any '
              'time.',
          confirmLabel: 'Stop & remove',
          cancelLabel: 'Keep processing',
          onConfirm: () => activity.cancelDocument(doc.id),
        );
        if (done != true || !context.mounted) return;
        AppToast.show(context, 'Cancelled.', type: ToastType.info);
      case 'delete':
        final done = await KitConfirm.show(
          context,
          title: 'Remove “${_name()}”?',
          body: 'This removes the document and any passages indexed from it '
              'from your library and future letters. The original file on your '
              'device or cloud service is untouched.',
          confirmLabel: 'Remove',
          cancelLabel: 'Keep it',
          onConfirm: () => activity.deleteDocument(doc.id),
        );
        if (done != true || !context.mounted) return;
        AppToast.show(context, 'Removed.', type: ToastType.info);
    }
  }

  String _name() => doc.title.isEmpty ? 'Untitled' : doc.title;
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
