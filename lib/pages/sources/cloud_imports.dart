import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/import_job.dart';
import '../../models/tag.dart';
import '../../shared/cloud_providers.dart';
import '../../shared/cooldown.dart';
import '../../state/cloud_notifier.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../reader/supersession_confirm.dart';

/// What arrives from a connected service, in its two places since 5.59.0
/// (ADR-213; web `CloudImportPanel`): the Library's Correspondence draws the
/// progress section across every service, and a service's own page draws it,
/// and its Import history, for that service alone ([provider]).

const _providers = cloudProviders;

/// What a job row knows about its document, from what the screen already
/// reads — the documents and shelves subscriptions; no new read (ADR-213 §4).
/// A job's `document_id` can name a document since removed (two of Xavier's
/// Notion jobs do), so a row links, and says shelves, only for a document the
/// subscription still holds. Web `useJobDocuments`.
class ImportDocLookup {
  final Map<String, Document> _byId;
  final Map<String, Tag> _shelfById;
  final Map<String, KitShelfNode> homeOf;

  ImportDocLookup._(this._byId, this._shelfById, this.homeOf);

  factory ImportDocLookup(List<Document> documents, List<Tag> shelves) {
    final model = kitShelfModel(shelves, documents);
    return ImportDocLookup._(
      {for (final d in documents) d.id: d},
      {for (final s in shelves) s.id: s},
      model.homeOf,
    );
  }

  factory ImportDocLookup.of(BuildContext context) => ImportDocLookup(
        context.watch<DocumentsNotifier>().documents,
        context.watch<TagsNotifier>().tags,
      );

  Document? docOf(ImportJob j) =>
      j.documentId == null ? null : _byId[j.documentId];

  /// Every shelf holding [doc] directly, its home shelf first — `(title,
  /// colour token)`. §32's cell shows the home shelf alone; a row here has
  /// the room, and "which shelves did this land on" is what it is read for.
  List<(String, String?)> shelvesOf(Document doc) {
    final home = homeOf[doc.id];
    final rest = [
      for (final id in doc.tagIds)
        if (id != home?.id && _shelfById[id] != null) _shelfById[id]!,
    ];
    return [
      if (home != null) (home.title.isEmpty ? 'Untitled' : home.title, home.color),
      for (final s in rest) (s.title.isEmpty ? 'Untitled' : s.title, s.color),
    ];
  }
}

/// The progress section (`screens/sources.md` §Cloud import): every
/// non-terminal job plus this session's terminal ones, on the Library across
/// every service and on a service's page for that service ([provider]).
class CloudImportActivity extends StatelessWidget {
  final String? provider;

  /// Where a row's Reader names its way back (`?from=`).
  final String from;

  const CloudImportActivity({super.key, this.provider, this.from = '/sources'});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = context.watch<CloudNotifier>();
    final lookup = ImportDocLookup.of(context);
    final jobs = [
      for (final j in cloud.progressJobs)
        if (provider == null || j.provider == provider) j,
    ];
    final all = cloud.jobs;
    final error = cloud.jobsError;
    // A kickoff's figures are its own provider's: on another service's page
    // they say nothing.
    final k = cloud.kickoff;
    final mine = k != null &&
        (provider == null || k.provider.isEmpty || k.provider == provider);
    final summary = cloudProgressSummary(cloud, jobs, kickoffHere: mine);
    final discoveringFiles = mine && cloud.awaitingFirstJob;

    // Hiding the section was the failure mode, not a symptom of it: an empty
    // list and an unreadable one both collapsed to nothing, so the one reader
    // who needed the difference — someone watching an import — got the same
    // blank space either way (INV-24, ADR-071).
    if (error != null && all.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No count: the figure is derived from a list nothing read, and
          // unread is not zero (§8, ADR-109).
          const SectionHeader('Cloud imports'),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KitFailureInline(error),
          ),
        ],
      );
    }
    if (jobs.isEmpty && summary == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          error != null || jobs.isEmpty
              ? 'Cloud imports'
              : 'Cloud imports · ${jobs.length}',
          note: error != null ? null : summary,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error),
          ),
        if (discoveringFiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: AppRadius.pillR(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: t.surfaceSunken,
                    color: t.accent,
                  ),
                ),
                const KitProcNote('Discovering files…'),
              ],
            ),
          ),
        if (jobs.isNotEmpty) importJobList(jobs, lookup, from: from),
      ],
    );
  }
}

/// The progress summary (`screens/sources.md` §Cloud import): "{N} of {M}
/// imported" where M is the rows on screen — **never a determinate
/// fraction**, because discovery adds jobs as it goes and dedupe skips
/// silently. Null when there is nothing to summarise.
String? cloudProgressSummary(CloudNotifier cloud, List<ImportJob> visible,
    {bool kickoffHere = true}) {
  if (kickoffHere && cloud.nothingNew && visible.isEmpty) {
    return 'Everything there was already imported.';
  }
  if (visible.isEmpty && (cloud.kickoff == null || !kickoffHere)) return null;
  final done = visible.where((j) => j.status == 'complete').length;
  return '$done of ${visible.length} imported'
      '${kickoffHere && cloud.discovering ? ' so far — still discovering files' : ''}';
}

/// `.proc-list` of import job cards: 12 under its header, 10 apart.
Widget importJobList(List<ImportJob> jobs, ImportDocLookup lookup,
        {required String from}) =>
    Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < jobs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            ImportJobRow(
                key: ValueKey(jobs[i].id),
                job: jobs[i],
                lookup: lookup,
                from: from),
          ],
        ],
      ),
    );

/// **Import history** (`screens/sources.md` §Trust & feedback): a section of
/// a service's own page since 5.59.0 (ADR-213), open — it is what a reader
/// came there for. That service's terminal jobs grouped by calendar day
/// (`created_at`, client-local), the day header counting THAT day's
/// outcomes, rows reusing the progress-row treatment with its retry. Bounded
/// by the subscription's window, and said so when the window is full.
class ImportHistorySection extends StatelessWidget {
  final String provider;
  final String name;
  final String from;

  const ImportHistorySection(
      {super.key,
      required this.provider,
      required this.name,
      required this.from});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// One day's own counts — never the held count of the whole subscription.
  static String daySummary(List<ImportJob> rows) {
    int n(String s) => rows.where((j) => j.status == s).length;
    return [
      if (n('complete') > 0) '${n('complete')} imported',
      if (n('error') > 0) '${n('error')} failed',
      if (n('skipped') > 0) '${n('skipped')} skipped',
      if (n('cancelled') > 0) '${n('cancelled')} cancelled',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final lookup = ImportDocLookup.of(context);
    final jobs = [
      for (final j in cloud.historyJobs)
        if (j.provider == provider) j,
    ];
    if (jobs.isEmpty) {
      return KitProcNote('Nothing has come in from $name yet.',
          padding: EdgeInsets.zero);
    }
    final byDay = <DateTime, List<ImportJob>>{};
    for (final j in jobs) {
      final d = DateTime.fromMillisecondsSinceEpoch(j.createdAt!);
      byDay.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(j);
    }
    final note = KitText.lede(context, fontSize: 13, height: 20)
        .copyWith(color: Tokens.of(context).fgSubtle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in byDay.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                    '${_months[e.key.month - 1]} ${e.key.day}, ${e.key.year}',
                    style: note),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(daySummary(e.value),
                      textAlign: TextAlign.right, style: note),
                ),
              ],
            ),
          ),
          importJobList(e.value, lookup, from: from),
        ],
        // The window's real size: 50, or what a kickoff widened it to.
        if (cloud.jobs.length >= cloud.jobsWindow)
          KitProcNote(
              'Showing the most recent ${cloud.jobsWindow} import jobs.'),
      ],
    );
  }
}

/// One import job (web `ImportJobRow`; 5.59.0, ADR-213): §33's **Cover lead**
/// (the document's `type` once one exists, else what the file will become),
/// the file name, **its shelves** — every shelf holding the document, home
/// shelf first, *Unshelved* when none — then `{mark} {provider} · {path}`, the
/// controls and the §6.3 pill, then the slots under it.
///
/// **The row is a link to its source** (§6.4.3) whenever the documents
/// subscription holds its document, whatever the status; its own controls
/// stay above the link. No link and no shelf for a document the subscription
/// does not hold, and no shelf for one still being read (§32 draws none).
class ImportJobRow extends StatefulWidget {
  final ImportJob job;
  final ImportDocLookup lookup;
  final String from;

  const ImportJobRow(
      {super.key,
      required this.job,
      required this.lookup,
      this.from = '/sources'});

  @override
  State<ImportJobRow> createState() => _ImportJobRowState();
}

class _ImportJobRowState extends State<ImportJobRow> {
  /// A retry in flight, and the sentence a refusal came back with — the
  /// 409/429 copy is user-facing and belongs ON the row it is about.
  bool _busy = false;
  String? _retryError;

  /// Update from source on a kept refresh row (4.96.0, ADR-129).
  bool _updating = false;
  String? _updateError;

  String get _retryKey => WaitKey.importJobRetry(widget.job.id);
  String? get _updateKey =>
      widget.job.canUpdateFromSource && widget.job.documentId != null
          ? WaitKey.sourceRefresh(widget.job.documentId!)
          : null;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _retryError = null;
    });
    final err = await context.read<CloudNotifier>().retryJob(widget.job.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // A cooldown with its number is the row's wait, not a copy of it.
      _retryError = Cooldowns.instance.waiting(_retryKey) ? null : err;
    });
  }

  /// reader.md §Supersession confirm: Update from source re-derives the
  /// document, so it goes through the §18 confirm when a passage was edited
  /// (or that could not be checked).
  Future<void> _update() async {
    final cloud = context.read<CloudNotifier>();
    final docId = widget.job.documentId!;
    setState(() {
      _updating = true;
      _updateError = null;
    });
    final res = await SupersessionConfirm.run(
      context,
      docId: docId,
      title: SupersessionConfirm.updateTitle,
      lead: SupersessionConfirm.updateLead(widget.job.provider),
      confirmLabel: SupersessionConfirm.updateConfirmLabel,
      study: SupersessionConfirm.updateStudy,
      editedBy: SupersessionConfirm.updateEditedBy(widget.job.provider),
      action: () => cloud.updateFromSource(docId),
      waitKey: _updateKey,
    );
    if (!mounted) return;
    setState(() {
      _updating = false;
      _updateError = res.outcome == SupersessionOutcome.refused && !res.waits
          ? res.message
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: _retryKey,
        builder: (context, retryWait) => KitWait(
          waitKey: _updateKey,
          builder: (context, updateWait) =>
              _row(context, retryWait, updateWait),
        ),
      );

  Widget _row(
      BuildContext context, CooldownWait retryWait, CooldownWait updateWait) {
    final t = Tokens.of(context);
    final job = widget.job;
    final doc = widget.lookup.docOf(job);
    // A row is read as placed only once its document is: §32 draws no shelf
    // on a source still being read, and neither does this.
    final shelves = doc != null && doc.status == DocumentStatus.complete
        ? widget.lookup.shelvesOf(doc)
        : null;
    final home = doc == null ? null : widget.lookup.homeOf[doc.id];
    final (label, tone) = importJobStatus(job);
    // *View* stays only for a duplicate whose document is past the window,
    // where the row cannot be the way in.
    final viewable = job.isDuplicate && job.documentId != null && doc == null;
    final provider = _providers[job.provider]?.name ?? job.provider;
    final title = job.providerFileName.isNotEmpty
        ? job.providerFileName
        : (doc != null && doc.title.isNotEmpty)
            ? doc.title
            : '(fetching name…)';

    final card = KitProcCard(
      kind: kitDocKind(doc?.type ?? job.sourceType),
      mark: KitCoverLead(
        id: doc?.id ?? job.id,
        type: doc?.type ?? job.sourceType,
        shelf: home == null
            ? null
            : AppColors.shelfColor(home.color, dark: t.isDark),
      ),
      title: title,
      underTitle: shelves == null
          ? null
          : KitImportShelves(shelves: [
              for (final (name, color) in shelves)
                (name, AppColors.shelfColor(color, dark: t.isDark)),
            ]),
      subtitleLeading: KitProviderLogo(provider: job.provider, size: 12),
      subtitle: job.providerPath.isEmpty
          ? provider
          : '$provider · ${job.providerPath}',
      actions: [
        if (viewable)
          KitSettingLink('View',
              icon: null,
              onTap: () => context.go(KitSourceLink.readerHref(
                  job.documentId!, 'from=${Uri.encodeComponent(widget.from)}'))),
        // `canRetry` is the whole rule: error/cancelled retry, and of the
        // skips only duplicate · dismissed · plan_limit import again.
        if (job.canRetry)
          KitSettingLink(
              _busy
                  ? 'Retrying…'
                  : job.isImportAgain
                      ? 'Import again'
                      : 'Retry',
              icon: null,
              wait: _busy ? 0 : retryWait.left,
              onTap: _busy ? null : _retry),
        // A kept refresh: no Retry — it would mint a second document — and
        // the sentence names this control.
        if (job.canUpdateFromSource)
          KitSettingLink(_updating ? 'Queuing…' : 'Update from source',
              icon: null,
              wait: _updating ? 0 : updateWait.left,
              onTap: _updating ? null : _update),
      ],
      pill: KitProcPill(label, tone: tone),
      failed: job.status == 'error',
      foot: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (job.status == 'error' && job.errorMessage != null)
            KitProcAttention(detail: job.errorMessage!, actions: const []),
          // A skip's reason is what makes a skip a fact rather than a shrug.
          // Not for a dismissal: its `error_message` IS the pill's word. A
          // duplicate draws its sentence (5.57.0, ADR-209).
          if (job.status == 'skipped' &&
              job.errorMessage != null &&
              !job.isDismissed)
            KitProcNote(job.errorMessage!,
                padding: const EdgeInsets.only(bottom: 12)),
          for (final w in [
            ?kitRefusalSlot(retryWait, _retryError, dense: true),
            ?kitRefusalSlot(updateWait, _updateError, dense: true),
          ])
            Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        ],
      ),
    );
    // A skipped or cancelled job is muted, never failure-styled.
    final muted = job.status == 'skipped' || job.status == 'cancelled';
    final drawn = muted ? Opacity(opacity: 0.55, child: card) : card;
    if (doc == null) return drawn;
    // The whole row opens the source (kit §6.4.3), from the first moment its
    // document is known; the controls inside it keep their own taps.
    return KitSourceLink(
      docId: doc.id,
      query: 'from=${Uri.encodeComponent(widget.from)}',
      builder: (context, open) => Semantics(
        link: true,
        label: 'Open $title',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('import-row-link-${job.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: drawn,
          ),
        ),
      ),
    );
  }
}

/// The pill's word and tone — the reference's `PILL` map, every member
/// named. A skipped job is muted, never failure-styled; `awaiting_review` is
/// held, never omitted (4.45.0, ADR-083).
(String, KitProcTone) importJobStatus(ImportJob j) {
  switch (j.status) {
    case 'awaiting_review':
      return ('Needs you', KitProcTone.hold);
    case 'complete':
      return ('Imported', KitProcTone.done);
    case 'error':
      return ('Error', KitProcTone.fail);
    case 'skipped':
      return (
        j.isDuplicate
            ? 'Already imported'
            : j.isDismissed
                ? 'Dismissed — not imported'
                : 'Skipped',
        KitProcTone.wait
      );
    case 'cancelled':
      return ('Cancelled', KitProcTone.wait);
    case 'pending':
      return ('Waiting', KitProcTone.wait);
    case 'queued':
      return ('Queued', KitProcTone.wait);
    case 'downloading':
      return ('Downloading', KitProcTone.work);
    case 'processing':
      return ('Processing', KitProcTone.work);
    default:
      // A status this client does not know yet: drawn as `pending` is, and
      // never as its raw token.
      return ('Waiting', KitProcTone.wait);
  }
}
