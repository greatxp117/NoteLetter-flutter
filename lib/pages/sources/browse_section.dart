import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../shared/cooldown.dart';
import '../../state/activity_notifier.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../reader/supersession_confirm.dart';
import 'source_sheet.dart';
import '../../shared/stalled.dart';

/// **The processing rules** a source in the pipeline carries — its stage, its
/// one primary, Remove, Cancel and the source itself (`screens/sources.md`
/// §Document processing) — in ONE place, drawn three ways: For your review's
/// card ([ProcessingLook.card], `review.md` §Composition), and in direction D
/// the Library's *Being catalogued* row and its Grid arrival
/// ([ProcessingLook.row], [ProcessingLook.arrival]; web `proc.jsx`'s
/// `ProcRow`, `DProcRow`, `ArrivalCover`). The two cannot disagree about what
/// a document in the pipeline is, or what can be done to it.
///
/// The pre-D browse that lived here — the filter chips (`_kinds`), the sort
/// bar, the list · cards · shelf toggle and the §7 empty state — is retired
/// with direction D (sources.md §Composition, *Rewritten for direction D*):
/// the Library's kinds are `source_facets.dart`'s facet table, its catalogue
/// the kit's `KitLibRegister` / `KitLibWall`.

/// How a [ProcessingRow] is drawn; its rules are the same in every one.
enum ProcessingLook { card, row, arrival }

/// The stage clock (4.74.0, ADR-108; `queued` 5.3.0, ADR-161): a run crosses
/// its stall moment with NO write behind it, so something must tick. One
/// clock per list, every 15 seconds and only while something is `queued` or
/// `processing`, so every row flips on the same tick.
bool _watching(Iterable<Document> items) => items.any((d) =>
    d.status == DocumentStatus.processing || d.status == DocumentStatus.queued);

bool _needsYou(Document d, DateTime now) =>
    d.status == DocumentStatus.error ||
    d.status == DocumentStatus.skipped ||
    d.isStalled(now);

/// "4 indexing · 1 needs you" — *Being catalogued*'s meta (web `procSummary`).
/// A stalled row needs a person as much as a failed one (ADR-108).
String procSummary(List<Document> items, DateTime now) {
  if (items.isEmpty) return 'Nothing arriving';
  final att = items.where((d) => _needsYou(d, now)).length;
  return att > 0
      ? '${items.length - att} indexing · $att ${att == 1 ? 'needs' : 'need'} you'
      : '${items.length} indexing';
}

/// **Being catalogued** in direction D (web `Incoming` / `ProcList`): every
/// source still in the pipeline (or just finished, [justDone]), the ones that
/// need the reader first and the rest in the order they arrived — as D rows,
/// or in Grid ([grid]) face-out arrivals. With [title], its small SectionHead
/// and `{n} indexing · {k} need(s) you`. One clock for the whole list.
class ProcessingList extends StatefulWidget {
  final List<Document> items;
  final bool grid;
  final Set<String> justDone;

  /// docId → the upload's committed fraction (UploadNotifier).
  final Map<String, double> uploadPcts;
  final String? title;

  const ProcessingList({
    super.key,
    required this.items,
    this.grid = false,
    this.justDone = const {},
    this.uploadPcts = const {},
    this.title,
  });

  @override
  State<ProcessingList> createState() => _ProcessingListState();
}

class _ProcessingListState extends State<ProcessingList> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProcessingList old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final watching = _watching(widget.items);
    if (watching && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) setState(() => _now = DateTime.now());
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

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final now = _now.isBefore(DateTime.now().subtract(const Duration(seconds: 16)))
        ? DateTime.now()
        : _now;
    // The rows that need the reader lead; the rest keep their order.
    final indexed = [
      for (var i = 0; i < widget.items.length; i++) (i, widget.items[i]),
    ]..sort((x, y) {
        final a = _needsYou(x.$2, now) ? 0 : 1;
        final b = _needsYou(y.$2, now) ? 0 : 1;
        return a != b ? a - b : x.$1 - y.$1;
      });
    final rows = [
      for (final e in indexed)
        ProcessingRow(
          key: ValueKey('proc-${e.$2.id}'),
          doc: e.$2,
          look: widget.grid ? ProcessingLook.arrival : ProcessingLook.row,
          justDone: widget.justDone.contains(e.$2.id),
          uploadPct: widget.uploadPcts[e.$2.id],
          now: now,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null)
          KitSectionHead(
            widget.title!,
            small: true,
            meta: procSummary(widget.items, now),
          ),
        if (widget.grid)
          KitLibGrid(top: 10, children: rows)
        else
          ...rows,
      ],
    );
  }
}

/// A source still in the pipeline — **a card per document with the stage in a
/// status pill, never in the subtitle** (`screens/sources.md` §Composition at
/// 4.98.0, ADR-131; web ProcRow). It was a §4.1 row carrying its stage in the
/// subtitle, which is what the composition line said until then.
///
/// Every row offers the **source affordance** (§6.4.2 — `error_message` is a
/// claim *about* a source and nothing else on the screen shows it). While
/// working: the bar, the affordance and Cancel. When it needs a person: the
/// detail sentence, **the row's one primary**, Remove and the affordance.
class ProcessingRow extends StatefulWidget {
  final Document doc;

  /// The card (For your review), or a D row or arrival (the Library, Add a
  /// source). The rules do not change with it.
  final ProcessingLook look;

  /// Completed during this session: held briefly as *Done* so the row
  /// resolves visibly rather than vanishing (§Document processing).
  final bool justDone;

  /// The upload's committed fraction while its bytes leave this device — the
  /// one determinate phase (ADR-024). Null otherwise.
  final double? uploadPct;

  /// The list's clock, so every row flips together; null runs the row's own.
  final DateTime? now;

  /// Test seams for the supersession confirm's two reads; null is the live read.
  final Future<bool?> Function(String docId)? studyCheck;
  final Future<bool?> Function(String docId)? editCheck;

  /// For your review's one addition (4.100.0, `screens/review.md` §Sources
  /// that need you): **Dismiss** beside Remove on a row that needs a person.
  /// It takes the source out of that screen and its count and changes nothing
  /// else — the Library shows every source it holds, so the control is that
  /// screen's alone.
  final bool dismissible;

  /// Test seam for Dismiss; null is `Api.reviewDocuments`.
  final Future<void> Function(String docId)? dismiss;

  const ProcessingRow(
      {super.key,
      required this.doc,
      this.look = ProcessingLook.card,
      this.justDone = false,
      this.uploadPct,
      this.now,
      this.studyCheck,
      this.editCheck,
      this.dismissible = false,
      this.dismiss});

  @override
  State<ProcessingRow> createState() => _ProcessingRowState();
}

class _ProcessingRowState extends State<ProcessingRow> {
  /// §14.2 — **one slot, shared**, since one primary means one outstanding
  /// request. A 409/429 renders here, in the row, with the server's words: the
  /// cooldown and cap copy is user-facing.
  String? _error;
  bool _busy = false;
  bool _dismissing = false;

  /// No confirmation on one row — the reader has just read it, and nothing is
  /// lost. The row leaves when the subscription says `review_dismissed_at` is
  /// set, never on the press; an id the server reports in `skipped` was
  /// already moved by something else and leaves the same way.
  Future<void> _dismiss() async {
    if (_dismissing) return;
    setState(() {
      _dismissing = true;
      _error = null;
    });
    String? err;
    try {
      await (widget.dismiss ??
          (id) => Api.instance.reviewDocuments([id]))(widget.doc.id);
    } on ApiException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'That request could not be completed.';
    }
    if (!mounted) return;
    setState(() {
      _dismissing = false;
      _error = err;
    });
  }

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
    // `queued` too since 5.3.0 (ADR-161): a run that never started crosses
    // its 24 h deadline with no write behind it either.
    final watching = widget.now == null &&
        (widget.doc.status == DocumentStatus.processing ||
            widget.doc.status == DocumentStatus.queued);
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
  (String, bool)? _primary(Document doc, DateTime now) {
    if (doc.status == DocumentStatus.error) return ('Retry', false);
    // A stalled `processing` row gets the same primary (4.74.0, ADR-108), and
    // a stalled `queued` one (5.3.0, ADR-161). `fn_retry_document` accepts
    // both — the widened status is reachable from here, which is the whole
    // reason the backend half was not shipped alone.
    if (doc.isStalled(now)) return ('Retry', false);
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
    final doc = widget.doc;
    // reader.md §Supersession confirm names "retry of an errored doc": it
    // re-derives the document, and an errored document CAN hold both facts —
    // one whose edit failed to re-embed keeps its passages (a `docHtml`
    // reindex retires the old set only once the new one is embedded; any
    // other re-entry retires them and nulls the counts as it claims, 5.4.0,
    // ADR-162), and a study program that took it in while complete still
    // lists it. So both primaries run
    // through the supersession confirm (web 71987f6): it asks when a passage
    // was edited or the document is in a program, or either could not be
    // checked, and sends straight through on two definite noes. Inside the
    // confirm a refusal stays in the panel's §18 slot; with no confirm owed it
    // is §14.2 under the row, as before. The control is held until it resolves.
    final res = await runSourcePrimary(context, doc,
        force: force,
        studyCheck: widget.studyCheck,
        editCheck: widget.editCheck);
    if (!mounted) return;
    // On 200 **no optimistic state is needed**: the document flips to `queued`
    // under the existing subscription and the row returns to its normal
    // progress treatment. A cooldown with its number is the row's WAIT, not a
    // held copy of it: the row says the sentence for as long as it runs.
    setState(() {
      _busy = false;
      _error = res.outcome == SupersessionOutcome.refused && !res.waits
          ? res.message
          : null;
    });
  }


  /// The document's retry cooldown (4.107.0, ADR-140) holds BOTH primaries —
  /// a forced retry is a retry — on this row wherever it is drawn (the
  /// Sources tray and For your review wait on one clock), and is the row's
  /// sentence while it runs: the calm caption, where the hard retry cap and
  /// every other refusal stay §14.2 (sources.md, 4.108.0, ADR-145).
  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: WaitKey.documentRetry(widget.doc.id),
        builder: _row,
      );

  Widget _row(BuildContext context, CooldownWait wait) {
    final doc = widget.doc;
    final now = widget.now ?? DateTime.now();
    final failed = doc.status == DocumentStatus.error ||
        doc.status == DocumentStatus.skipped;
    final stalled = doc.isStalled(now);
    final refusal = kitRefusalSlot(wait, _error, dense: true);
    // A stalled run takes the attention branch — Retry, Remove and the source
    // live there — but not the failed EDGE: it is not an error.
    final attention = failed || stalled;
    // The failure message is shown VERBATIM: there is no error reason code, and
    // a client that pattern-matches the message to substitute its own copy is
    // inventing a classification the backend never made.
    // There is no `error_message` on a stalled document — nothing failed, a run
    // stopped existing — so it needs copy of its own, saying the two things the
    // reader cannot see: that waiting will not help, and that Retry costs them
    // nothing already spent. Mirrors web's STALLED_PROC_MSG verbatim. The copy
    // follows the status (5.3.0, ADR-161; ruled 2026-10-13): a `queued` run
    // never started, so it has nothing to finish.
    final stalledMsg = stalledMessage(doc);
    // web DEFAULT_PROC_ERROR, for a failed row the backend left unexplained.
    const defaultMsg =
        'No readable text was found. Retry, or remove this source.';
    final primary = _primary(doc, now);
    final title = doc.title.isEmpty ? 'Untitled' : doc.title;
    if (widget.look != ProcessingLook.card) {
      return _dRow(context, wait,
          now: now,
          failed: failed,
          attention: attention,
          message: stalled ? stalledMsg : (doc.errorMessage ?? defaultMsg),
          primary: primary,
          title: title,
          refusal: refusal);
    }
    // "the passages when there are any" — none drawn for 0 or never counted.
    final passages = doc.chunkCount ?? 0;
    // Offered on EVERY row — failed, queued, uploading or mid-extraction — and
    // chosen by the document's shape, which is known at creation and does not
    // depend on `status`.
    final source = KitButton.ghost(SourceSheet.labelFor(doc),
        icon: SourceSheet.iconFor(doc),
        onPressed: () => SourceSheet.open(context, doc));

    return KitProcCard(
      kind: kitDocKind(doc.type),
      title: title,
      // `.proc-sub`: the type, and the passages when there are any. The stage
      // is the pill's, never this line's.
      subtitle: passages > 0
          ? '${doc.type} · ${_plural(passages, 'passage')}'
          : doc.type,
      failed: failed,
      pill: KitProcPill(_stageLabel(doc, now), tone: _stageTone(doc, now)),
      foot: attention
          ? KitProcAttention(
              detail: stalled ? stalledMsg : (doc.errorMessage ?? defaultMsg),
              failure: refusal,
              actions: [
                // One primary, never two: an `error` row and a `skipped` row
                // are the same pattern with a different decision in it.
                if (primary != null)
                  KitButton.primary(primary.$1,
                      icon: primary.$2 ? Icons.notes : Icons.refresh,
                      wait: _busy ? 0 : wait.left,
                      onPressed:
                          _busy ? null : () => _runPrimary(primary.$2)),
                KitButton.ghost('Remove',
                    onPressed: _busy || _dismissing
                        ? null
                        : () => confirmRemove(context, doc)),
                if (widget.dismissible)
                  KitButton.ghost(_dismissing ? 'Dismissing…' : 'Dismiss',
                      onPressed: _busy || _dismissing ? null : _dismiss),
                source,
              ],
            )
          : KitProcActive(
              queued: doc.status == DocumentStatus.queued,
              actions: [
                source,
                KitButton.ghost('Cancel',
                    onPressed: () => confirmCancel(context, doc)),
              ],
            ),
    );
  }
}

extension on _ProcessingRowState {
  /// Direction D's row and arrival (web `DProcRow`, `ArrivalCover`): the
  /// cover's word for the type, the title, the stage in mono caps, a short
  /// bar — or, when the row needs the reader, the detail sentence, the slot
  /// and the SAME actions as the card as quiet text. Done rows carry none.
  Widget _dRow(
    BuildContext context,
    CooldownWait wait, {
    required DateTime now,
    required bool failed,
    required bool attention,
    required String message,
    required (String, bool)? primary,
    required String title,
    required Widget? refusal,
  }) {
    final doc = widget.doc;
    final done = widget.justDone;
    final label = done ? 'Done' : _stageLabel(doc, now);
    final tone = done ? KitProcTone.done : _stageTone(doc, now);
    final pct = doc.status == DocumentStatus.pendingUpload && !done
        ? widget.uploadPct
        : null;
    final stage = KitLibStage(
        pct == null ? label : '$label · ${(pct * 100).round()}%',
        tone: tone);
    final bar = attention
        ? null
        : KitLibBar(
            live: !done && pct == null && doc.status != DocumentStatus.queued,
            value: pct,
            done: done);
    final source = KitLibAct(SourceSheet.labelFor(doc),
        icon: SourceSheet.iconFor(doc),
        onTap: () => SourceSheet.open(context, doc));
    final arrival = widget.look == ProcessingLook.arrival;
    Widget? actions;
    if (done) {
      actions = null;
    } else if (!attention) {
      actions = KitLibActs(tight: arrival, children: [
        source,
        KitLibAct('Cancel', onTap: () => confirmCancel(context, doc)),
      ]);
    } else {
      actions = KitLibActs(tight: arrival, children: [
        // One primary, never two (ADR-085): the row's strong slot holds the
        // one control that can change this document's outcome.
        if (primary != null)
          KitLibAct(primary.$1,
              strong: true,
              icon: primary.$2 ? Icons.notes : Icons.refresh,
              wait: _busy ? 0 : wait.left,
              onTap: _busy ? null : () => _runPrimary(primary.$2)),
        KitLibAct('Remove',
            onTap: _busy || _dismissing ? null : () => confirmRemove(context, doc)),
        if (widget.dismissible)
          KitLibAct(_dismissing ? 'Dismissing…' : 'Dismiss',
              onTap: _busy || _dismissing ? null : _dismiss),
        source,
      ]);
    }
    final word = kitTypeLabel(doc.type);
    if (arrival) {
      return Semantics(
        container: true,
        label: title,
        child: KitArrivalSlip(
          word: word,
          title: title,
          author: doc.author,
          stage: stage,
          bar: bar,
          // A stalled run is not a failure — nothing reported one (ADR-108) —
          // so its stamp says Stalled, the stage's own word.
          stamp: attention ? (failed ? 'Couldn’t be read' : label) : null,
          message: attention ? message : null,
          refusal: refusal,
          actions: actions,
          attention: attention,
        ),
      );
    }
    return KitLibProcRow(
      word: word,
      title: title,
      stage: stage,
      bar: bar,
      message: attention ? message : null,
      refusal: refusal,
      actions: actions,
      attention: attention,
    );
  }
}

/// The pill's tone (web `procPill`): a failure or a stall is `fail` (no
/// spinner on a run that ended, ADR-108), queued waits, the rest work.
KitProcTone _stageTone(Document doc, DateTime now) {
  switch (doc.status) {
    case DocumentStatus.error:
    case DocumentStatus.skipped:
      return KitProcTone.fail;
    case DocumentStatus.complete:
      return KitProcTone.done;
    case DocumentStatus.queued:
      // A run that never started is a stall, not a wait (5.3.0, ADR-161).
      return doc.isStalled(now) ? KitProcTone.fail : KitProcTone.wait;
    case DocumentStatus.pendingUpload:
      return KitProcTone.work;
    case DocumentStatus.processing:
      return doc.isStalled(now) ? KitProcTone.fail : KitProcTone.work;
  }
}

/// The pill label, derived from `status` and refined by `processing_stage` —
/// **never the raw status string**. `processing_stage` is an open vocabulary
/// (ADR-024): an unrecognised value falls back to the generic "Processing",
/// never to an error.
String _stageLabel(Document doc, DateTime now) {
  switch (doc.status) {
    case DocumentStatus.pendingUpload:
      return 'Uploading';
    case DocumentStatus.queued:
      // Checked BEFORE the Queued label: "Queued" on a run that will never
      // start is the defect ADR-161 exists to end.
      if (doc.isStalled(now)) return 'Stalled';
      return 'Queued';
    case DocumentStatus.processing:
      // Checked BEFORE the stage: a stage label on a run that ended is the
      // defect ADR-108 exists to end. "Stalled", not "Error" — nothing
      // reported a failure and saying one would be inventing it.
      if (doc.isStalled(now)) return 'Stalled';
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
    // web `procPill`: a skipped row reads Error too — its sentence below says
    // why, and its primary is Index it anyway rather than Retry.
    case DocumentStatus.skipped:
      return 'Error';
    case DocumentStatus.complete:
      return 'Done';
  }
}

String _nameOf(Document doc) => doc.title.isEmpty ? 'Untitled' : doc.title;

/// Cancel a document mid-pipeline, through §18 (4.56.0, ADR-092): the ACTION
/// runs inside the confirmation, so its rejection renders in the panel the
/// reader is looking at, and the panel does not close on one.
Future<void> confirmCancel(BuildContext context, Document doc) async {
  final activity = context.read<ActivityNotifier>();
  final done = await KitConfirm.show(
    context,
    title: 'Stop processing “${_nameOf(doc)}”?',
    body: 'This deletes the document; nothing indexed so far is kept. '
        'Your original file is not affected — you can add it again any '
        'time.',
    confirmLabel: 'Stop & remove',
    cancelLabel: 'Keep processing',
    onConfirm: () => activity.cancelDocument(doc.id),
  );
  if (done != true || !context.mounted) return;
  AppToast.show(context, 'Cancelled.', type: ToastType.info);
}

/// Remove a document, through §18 — same shape as [confirmCancel].
Future<void> confirmRemove(BuildContext context, Document doc) async {
  final activity = context.read<ActivityNotifier>();
  final done = await KitConfirm.show(
    context,
    title: 'Remove “${_nameOf(doc)}”?',
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

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// The confirm's lead sentences, verbatim from the reference (web 71987f6).
const sourceRetryLead =
    'This source will be processed again from its original, and any '
    'passages it has are replaced with a fresh extraction.';
const sourceForceLead =
    'This source will be read again as text, and any passages it has are '
    'replaced with a fresh extraction.';

/// **The Sources row's primary**, in one place, so every surface that offers
/// it offers THE same action (activity.md §Where a row leads, ruled
/// 2026-10-14: Activity's Retry "is the Sources row's own action, not a second
/// spelling of it"): `fn_retry_document` — or `force: true` — through the
/// supersession confirm (reader.md), on the document's one retry cooldown
/// (ADR-085: a forced retry is a retry; 4.107.0, ADR-140). Inside the confirm
/// a refusal stays in the panel's §18 slot; with no confirm owed the caller
/// renders [SupersessionResult.message] in its own §14.2 slot, verbatim.
Future<SupersessionResult> runSourcePrimary(
  BuildContext context,
  Document doc, {
  required bool force,
  Future<bool?> Function(String docId)? studyCheck,
  Future<bool?> Function(String docId)? editCheck,
}) {
  final activity = context.read<ActivityNotifier>();
  final title = doc.title.isEmpty ? 'Untitled' : doc.title;
  return SupersessionConfirm.run(
    context,
    docId: doc.id,
    title: force ? 'Index “$title” anyway?' : 'Retry “$title”?',
    lead: force ? sourceForceLead : sourceRetryLead,
    confirmLabel: force ? 'Index it anyway' : 'Retry and replace',
    action: () => force
        ? activity.forceProcessDocument(doc.id)
        : activity.retryDocument(doc.id),
    studyCheck: studyCheck,
    editCheck: editCheck,
    waitKey: WaitKey.documentRetry(doc.id),
  );
}
