import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cloud_integration.dart';
import '../models/document.dart';
import '../shared/cloud_providers.dart';
import '../shared/cloud_return.dart';
import '../shared/document_window.dart';
import '../shared/local_flags.dart';
import '../shared/shelf_tree.dart';
import '../state/camera_sweep_host.dart';
import '../state/cloud_notifier.dart';
import '../state/documents_notifier.dart';
import '../state/org_notifier.dart';
import '../state/tags_notifier.dart';
import '../state/upload_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/file_uploader.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import 'reader/reader_prefs.dart';
import 'settings/sources_section.dart';
import 'settings/summaries_section.dart';
import 'sources/browse_section.dart';
import 'sources/cloud_imports.dart';
import 'sources/cloud_sync_copy.dart';
import 'sources/import_review_queue.dart';
import 'sources/source_facets.dart';
import 'sources/camera_roll.dart';
import '../widgets/quick_add.dart';

const _providers = cloudProviders;

/// The standfirst (web `libSentence`): what is indexed, what is unread, what
/// is still arriving — counts up to twelve in words, figures above.
String librarySentence({
  required int volumes,
  required int passages,
  required int unread,
  required int incoming,
}) {
  if (volumes == 0) {
    return incoming > 0
        ? '${kitCap(kitSay(incoming))} '
            '${incoming == 1 ? 'volume is' : 'volumes are'} being read now. '
            'Each joins the catalogue as soon as its passages are indexed.'
        : 'Nothing here yet. Add a file, paste a link, or connect a service, '
            'and each source is read and indexed as it arrives.';
  }
  final first = '${kitCounted(passages, 'passage')} from ${kitSay(volumes)} '
      '${volumes == 1 ? 'volume' : 'volumes'}, indexed and searchable.';
  final bits = [
    if (unread > 0) '${kitSay(unread)} ${unread == 1 ? 'is' : 'are'} still unread',
    if (incoming > 0)
      '${kitSay(incoming)} more ${incoming == 1 ? 'is' : 'are'} being read now',
  ];
  return bits.isEmpty ? first : '$first ${kitCap(bits.join(', and '))}.';
}

/// The Library's state, read once from the documents read (§Composition's
/// table): a refused read is never empty (INV-24).
enum LibraryState { loading, failed, empty, reading, ready }

/// **The Library** — the rail's *Library*, route `/sources`
/// (`screens/sources.md` §Composition (direction D), web `SourcesBrowse.jsx`):
/// the D frame — folio, *The Library*, the library sentence, the cloud
/// notices — then the sheet (*Filters*, or *What you can add* before anything
/// is in it) beside one column: **Correspondence** (this client's camera roll
/// first, the services, then the cloud panels), **Being catalogued**, what
/// adding answered, and **the catalogue** (List under month or initial heads,
/// or Grid's wall of covers).
///
/// *Add a source* opens quick add over the page (F-152, `widgets/quick_add.dart`),
/// whose *More options →* is the Add a source page (`/sources/add`). The empty
/// catalogue holds the uploader, through the same [FileUploader].
///
/// The OAuth return is not drawn here (5.52.0, ADR-203): it is the connect
/// page's, its own route (`pages/sources/oauth_return.dart`). What that page
/// hands over as it leaves lands in the notices ([ConnectHandoff]).
class SourcesPage extends StatefulWidget {
  /// Arrived from the retired `/settings/camera-roll` (5.43.0, ADR-198
  /// decision 6): the camera roll's panel opens — or, while it is off, its
  /// setup, which is what that screen's switch began.
  final bool openCameraRoll;

  const SourcesPage({
    super.key,
    this.openCameraRoll = false,
  });

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  // ── What the connect page handed over (§States, §The OAuth return) ───────

  /// What the connect page's *Bring in* queued — a status in the notices.
  String? _returnNote;

  /// An `insufficient_scope` reason, in §States' copy — one of the two
  /// answers about organization rather than a connection, which stay on the
  /// Library's notices.
  String? _errorBanner;

  /// `org: "enabled"` — the write-scope upgrade, confirmed (the other).
  String? _orgEnabled;

  CloudNotifier? _cloud;
  DocumentsNotifier? _docs;

  // ── The sheet ─────────────────────────────────────────────────────────────
  String _kind = 'all';
  String? _shelf;
  String _sort = 'recent';

  /// The camera roll's settings panel, opened by its row's *Settings*.
  bool _cameraPanel = false;

  // ── Just catalogued (§Document processing: held briefly as Done) ──────────
  final Map<String, Timer> _justDone = {};
  Map<String, DocumentStatus> _prev = {};

  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
    ReaderPrefs.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cloud = context.read<CloudNotifier>();
      _cloud!.start();
      _cloud!.completionMessage.addListener(_onSessionComplete);
      context.read<OrgNotifier>().start();
      // The documents subscription this screen shares with Home (INV-02) —
      // the folio, the standfirst, Being catalogued and the catalogue.
      _docs = context.read<DocumentsNotifier>()..start();
      _docs!.addListener(_onDocs);
      _onDocs();
      context.read<TagsNotifier>().start();
      // A page arriving starts with nothing answered (web: a new intake).
      context.read<UploadNotifier>().clearAnswered();
      // The Library may sit under the connect page (an app pushes it over
      // Sources), so the handoff is listened for as well as read on mount.
      ConnectHandoff.pending.addListener(_onHandoff);
      _onHandoff();
      if (widget.openCameraRoll) unawaited(_openCameraRoll());
    });
  }

  Future<void> _openCameraRoll() async {
    final host = context.read<CameraSweepHost?>();
    if (host == null || !host.available) return;
    await host.ready;
    if (!mounted) return;
    if (host.ledger?.enabled ?? false) {
      setState(() => _cameraPanel = true);
    } else if (host.ledger != null) {
      unawaited(CameraRollFlow.open(context, CameraRollStep.intro));
    }
  }

  @override
  void dispose() {
    _cloud?.completionMessage.removeListener(_onSessionComplete);
    _docs?.removeListener(_onDocs);
    ConnectHandoff.pending.removeListener(_onHandoff);
    for (final t in _justDone.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// A source that completes while the Library is open stays in Being
  /// catalogued as *Done* for five seconds, then joins the catalogue — it
  /// resolves visibly rather than vanishing (§Document processing).
  void _onDocs() {
    final docs = _docs;
    if (docs == null || !mounted) return;
    final next = <String, DocumentStatus>{};
    var changed = false;
    for (final d in docs.documents) {
      next[d.id] = d.status;
      final was = _prev[d.id];
      if (d.status == DocumentStatus.complete &&
          was != null &&
          was != DocumentStatus.complete &&
          !_justDone.containsKey(d.id)) {
        changed = true;
        _justDone[d.id] = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() => _justDone.remove(d.id));
        });
      }
    }
    _prev = next;
    if (changed) setState(() {});
  }

  // Completion notification (1.4.0): a tracked import/sync session went
  // all-terminal — summarize it as a toast, then clear the one-shot.
  void _onSessionComplete() {
    final msg = _cloud?.completionMessage.value;
    if (msg == null || !mounted) return;
    AppToast.show(context, msg, type: ToastType.success);
    _cloud!.completionMessage.value = null;
  }

  /// What the connect page handed over as it left (5.52.0, ADR-203;
  /// [ConnectHandoff]), taken once: what Bring in queued, and the two answers
  /// about organization rather than a connection — `org: "enabled"` and
  /// `insufficient_scope` — which have always been the Library's notices.
  void _onHandoff() {
    if (!mounted || ConnectHandoff.pending.value == null) return;
    final h = ConnectHandoff.take();
    if (h == null) return;
    final err = h.connectError;
    setState(() {
      if (h.note != null) _returnNote = h.note;
      if (h.orgEnabled != null) _orgEnabled = h.orgEnabled;
      if (err != null) _errorBanner = connectReasonCopy(err.provider, err.reason);
    });
  }

  /// The strip's sentences, in web's order.
  List<Widget> _notices() => [
        if (_returnNote != null)
          KitLibNotice(
            _returnNote!,
            status: true,
            onDismiss: () => setState(() => _returnNote = null),
          ),
        if (_errorBanner != null)
          KitLibNotice(_errorBanner!,
              warn: true,
              onDismiss: () => setState(() => _errorBanner = null)),
        if (_orgEnabled != null)
          KitLibNotice(
            'Auto-organization is now enabled for '
            '${_providers[_orgEnabled]?.name ?? 'your service'}.',
            onDismiss: () => setState(() => _orgEnabled = null),
          ),
      ];

  void _reset() => setState(() {
        _kind = 'all';
        _shelf = null;
      });

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final upload = context.watch<UploadNotifier>();
    final aiOn = shellAiOn(context);
    final dark = Tokens.of(context).isDark;

    final model = kitShelfModel(tags.tags, docs.documents);
    final all = model.complete.where((d) => !_justDone.containsKey(d.id)).toList();
    final processing = docs.documents
        .where((d) =>
            d.status != DocumentStatus.complete || _justDone.containsKey(d.id))
        .toList();
    final incoming = docs.documents
        .where((d) =>
            d.status == DocumentStatus.processing ||
            d.status == DocumentStatus.queued)
        .length;

    // INV-24 (ADR-071): a refused subscription hands this screen the same
    // list an empty library does, so the state is read from the READ.
    final state = docs.error != null
        ? LibraryState.failed
        : docs.loading
            ? LibraryState.loading
            : all.isNotEmpty
                ? LibraryState.ready
                : processing.isNotEmpty
                    ? LibraryState.reading
                    : LibraryState.empty;
    final none =
        state == LibraryState.empty || state == LibraryState.reading;
    final measured = state == LibraryState.ready || none;

    final counts = <String, int>{'all': all.length, 'unread': 0};
    var passages = 0;
    for (final d in all) {
      final k = sourceFacetOf(d.type);
      counts[k] = (counts[k] ?? 0) + 1;
      if (d.viewCount == 0) counts['unread'] = counts['unread']! + 1;
      passages += d.chunkCount ?? 0;
    }

    final subtree = _shelf == null ? null : ShelfTree(tags.tags).subtreeIds(_shelf!);
    final items = kitSortSources(
      all
          .where((v) =>
              (_kind == 'all' ||
                  (_kind == 'unread'
                      ? v.viewCount == 0
                      : sourceFacetOf(v.type) == _kind)) &&
              (subtree == null || inSubtree(v.tagIds, subtree)))
          .toList(),
      _sort,
    );
    final flat = model.flat;
    KitShelfNode? shelfNode;
    for (final n in flat) {
      if (n.id == _shelf) shelfNode = n;
    }

    // Library reading summary's window, and the folio's floor (ADR-211): full
    // is counted over EVERY row the subscription returned, not only the
    // complete ones — it was keyed on the complete volumes alone, and the
    // folio printed the newest 200 as the library for 551 volumes.
    final atWindowCap = windowFull(docs.documents);
    final volumesFig = !measured
        ? '— volumes'
        : atWindowCap
            ? kitCountedFloor(all.length, 'volumes')
            : kitCounted(all.length, 'volume');
    final folio = 'The library · '
        '$volumesFig · '
        '${measured ? kitCounted(model.roots.length, 'shelf', 'shelves') : '— shelves'}';
    final stand = measured
        ? librarySentence(
            volumes: all.length,
            passages: passages,
            unread: counts['unread']!,
            incoming: incoming)
        : null;

    final failedLine = 'Your sources could not be read — '
        '${docs.error ?? 'the subscription failed.'}';

    final Widget sheetBody;
    switch (state) {
      case LibraryState.failed:
        sheetBody = KitFailureInline(failedLine);
      case LibraryState.loading:
        sheetBody = const KitSkeletonLines(
          top: 0,
          lines: [
            KitSkelLine(0.6),
            KitSkelLine(),
            KitSkelLine(0.7),
            KitSkelLine(0.5),
          ],
        );
      case LibraryState.empty:
      case LibraryState.reading:
        sheetBody = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('What you can add', first: true),
            KitFigures(rows: kAddable),
          ],
        );
      case LibraryState.ready:
        sheetBody = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitFacet(
              label: 'Kind',
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
              items: [
                for (final k in kSourceFacets)
                  if (k.types == null || (counts[k.id] ?? 0) > 0)
                    KitFacetItem(
                      k.id,
                      k.label,
                      count: '${counts[k.id] ?? 0}',
                      disabled: k.id != 'all' && (counts[k.id] ?? 0) == 0,
                    ),
              ],
            ),
            KitShelfFacet(
              total: all.length,
              value: _shelf,
              onChanged: (v) => setState(() => _shelf = v),
              items: [
                for (final n in flat)
                  KitShelfFacetItem(
                    n.id,
                    n.title,
                    color: AppColors.shelfColor(n.color, dark: dark),
                    depth: n.depth,
                    count: n.vols.length,
                  ),
              ],
            ),
            KitLibOrder(
              options: kSorts,
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
            ),
            // Library reading summary (4.1.0) — opt-in, the reader's own
            // preference, computed from the subscription already loaded (no
            // extra read). Opened and Finished are two facts, never stages;
            // on a full window the figures describe the window and say so.
            ValueListenableBuilder<ReaderPrefs>(
              valueListenable: ReaderPrefs.current,
              builder: (context, p, _) => !p.stats
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KitFigures(label: 'Reading', rows: [
                          ('Sources', kitThousands(all.length)),
                          (
                            'Opened',
                            kitThousands(all.where((s) => s.viewCount > 0).length)
                          ),
                          (
                            'Finished',
                            kitThousands(
                                all.where((s) => s.finishedAt != null).length)
                          ),
                        ]),
                        if (atWindowCap)
                          KitLibNote(
                              'Of your most recent ${kitThousands(documentWindow)}.',
                              status: false),
                      ],
                    ),
            ),
          ],
        );
    }

    final kindLabel = _kind == 'all'
        ? null
        : kSourceFacets
            .firstWhere((k) => k.id == _kind,
                orElse: () => SourceFacet(_kind, _kind))
            .label;
    final sortLabel =
        kSorts.firstWhere((s) => s.$1 == _sort, orElse: () => ('', '')).$2;
    final peek = none
        ? const KitLibPeek(icon: Icons.add, title: 'What you can add')
        : KitLibPeek(
            icon: Icons.tune,
            title: kindLabel ?? shelfNode?.title ?? 'All volumes',
            meta: [
              if (kindLabel != null && shelfNode != null) shelfNode.title,
              sortLabel,
            ].join(' · '),
            count: measured ? '${items.length}' : '—',
            tail: kindLabel != null || shelfNode != null
                ? ' of ${all.length}'
                : null,
          );

    final connected = [
      for (final p in _providers.keys)
        if (cloud.integrationFor(p) != null) p,
    ];
    // The catalogue's own count is a count over the window too (ADR-211).
    final ofAll = atWindowCap
        ? kitCountedFloor(all.length, 'volumes')
        : kitCounted(all.length, 'volume');
    final meta = !measured
        ? null
        : items.length == all.length
            ? ofAll
            : '${items.length} of $ofAll';

    return KitDPage(
      folio: folio,
      title: 'The Library',
      stand: stand,
      // Quick add, the same verb as Home's and the tab bar's (sources.md
      // §Tools; F-152).
      action: KitPageAction(
        label: 'Add a source',
        short: 'Add',
        icon: Icons.add,
        onPressed: () => QuickAdd.show(context),
      ),
      panel: _cameraPanel
          ? KitPageSettings(
              label: CameraRollCopy.panelTitle,
              body: (context, close) => CameraRollSettings(
                close: close,
                onLookFurther: () => CameraRollFlow.open(
                  this.context,
                  CameraRollStep.lookingBack,
                ),
              ),
            )
          : null,
      onPanelClose: () => setState(() => _cameraPanel = false),
      settings: KitPageSettings(
        label: 'Library settings',
        // Summaries only while generative AI is on (5.29.0, ADR-186): with it
        // off no summary is written, and Settings hides the section the same
        // way.
        has: aiOn ? const ['summaries', 'sources'] : const ['sources'],
        // Settings' own sections, each under its own mono caps head (§3's
        // eyebrow: *Summaries*, *Sources*) — the label web's panel draws over
        // a section whose own head it hides; drawing both here would name
        // each section twice.
        body: (context, close) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (aiOn) const SummariesSection(),
            const SourcesSection(),
          ],
        ),
      ),
      under: KitLibNotices(children: _notices()),
      sheet: KitDSheet(
        label: none ? 'What you can add' : 'Filters',
        peek: peek,
        body: sheetBody,
      ),
      child: KitSourceView(
        builder: (context, view) {
          final grid = view == 'grid';
          final showIncoming = measured && processing.isNotEmpty;
          final Widget catalogue;
          switch (state) {
            case LibraryState.failed:
              catalogue = KitFailureInline(failedLine);
            case LibraryState.loading:
              catalogue = const KitSkeletonLines(lines: [
                KitSkelLine(),
                KitSkelLine(0.7),
                KitSkelLine(),
                KitSkelLine(0.6),
              ]);
            case LibraryState.reading:
              catalogue = const KitDNone(
                  'Nothing has finished reading yet. Each volume joins the '
                  'catalogue as soon as its passages are indexed.',
                  top: 24,
                  bottom: 24);
            case LibraryState.empty:
              // The catalogue before anything is in it: the drop zone and the
              // link field — this client's one upload path.
              catalogue = const FileUploader(look: FileUploaderLook.first);
            case LibraryState.ready:
              catalogue = items.isEmpty
                  ? KitDNone('No volumes match.',
                      top: 24,
                      bottom: 24,
                      link: KitHxLink('Show every volume', onTap: _reset))
                  : grid
                      ? KitLibWall(items: items, homeOf: model.homeOf)
                      : KitLibRegister(
                          items: items, sort: _sort, homeOf: model.homeOf);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _correspondence(cloud, connected),
              if (showIncoming) ...[
                // Correspondence 64 above Being catalogued (§Reference metrics).
                const SizedBox(height: 64),
                ProcessingList(
                  title: 'Being catalogued',
                  items: processing,
                  grid: grid,
                  justDone: _justDone.keys.toSet(),
                  uploadPcts: upload.uploadFractions,
                ),
              ],
              // What adding answered, beside the rows it made. The empty
              // catalogue carries its own, under its drop zone.
              if (state != LibraryState.empty) const AddAnswered(),
              if (showIncoming) const SizedBox(height: 64),
              KitSectionHead(
                'The catalogue',
                meta: meta,
                flushTop: showIncoming,
                actions: [
                  if (state == LibraryState.ready) const KitViewToggle(),
                ],
              ),
              catalogue,
            ],
          );
        },
      ),
    );
  }

  /// **Correspondence**: this client's camera roll first (sources.md §Camera
  /// roll — web has none), the services — with one connected, a compact grid
  /// ABOVE what is arriving now, so a second service stays reachable — then
  /// what is arriving now, across every service: the review queue and the
  /// progress section (5.59.0, ADR-213). Everything else about one service —
  /// Browse, Sync, its settings, Filing, Import history and Disconnect — is on
  /// that service's own page, which *Manage* opens. The section stands empty
  /// at rest.
  Widget _correspondence(CloudNotifier cloud, List<String> connected) {
    final unread = cloud.integrationsError != null && !cloud.integrationsLoaded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'Correspondence',
          meta: connected.isEmpty
              ? 'Services that send you volumes'
              : '${connected.length} of ${_providers.length} connected',
          flushTop: true,
        ),
        CameraRollRow(onSettings: () => setState(() => _cameraPanel = true)),
        // A row's whole meaning is whether that service is connected, and an
        // unread list answers "no" for all of them (C4). The rows are
        // withheld rather than drawn wrong: inviting someone to connect a
        // service they are already connected to is an instruction to re-run
        // OAuth.
        if (unread)
          KitFailureBlock(
            sentence: 'Your connected services could not be read.',
            detail: cloud.integrationsError!,
            onRetry: () => context.read<CloudNotifier>().loadIntegrations(),
          )
        else ...[
          // A read that failed AFTER one succeeded keeps its rows — they were
          // true a moment ago — with the notice above them.
          if (cloud.integrationsError != null)
            KitFailureInline(cloud.integrationsError!),
          KitServiceList(
            compact: connected.isNotEmpty,
            rows: [
              for (final e in _providers.entries)
                _ServiceRow(
                  providerId: e.key,
                  spec: e.value,
                  integration: cloud.integrationFor(e.key),
                ),
            ],
          ),
        ],
        // What the last disconnect did at the provider — a standing note,
        // not a toast (4.89.0, ADR-123 §5). The disconnect is on the
        // service's page; its answer is the Library's to say, because the
        // page leaves for here (ADR-213).
        if (cloud.lastDisconnect != null)
          KitLibNote(disconnectOutcome(
            cloud.lastDisconnect!.$1,
            _providers[cloud.lastDisconnect!.$1]?.name ??
                cloud.lastDisconnect!.$1,
            cloud.lastDisconnect!.$2,
          )),
        // What the last triage batch did that the rows cannot say. HERE and
        // not inside the queue: dismissing the last held file unmounts that
        // section, and a line about what just happened would vanish with it.
        if (cloud.reviewOutcome != null)
          ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
        ImportReviewQueue(
          held: cloud.heldJobs,
          rulesFor: (p) => cloud.integrationFor(p)?.reviewRules ?? const {},
        ),
        const CloudImportActivity(),
      ],
    );
  }
}

// ── Correspondence: a service ───────────────────────────────────────────────

/// One service row (web `Services`): *Connect* (*Connecting…* while it runs)
/// or, once connected, **Manage**, which opens the service's own page
/// (5.59.0, ADR-213). An expired sign-in says so here too — *Sign-in expired*
/// in `--warning` in place of the account, with **Reconnect** beside Manage —
/// because a reader who never opens the page would otherwise not learn the
/// service has gone quiet. A refused connect or reconnect is §14.2 at the row.
class _ServiceRow extends StatefulWidget {
  final String providerId;
  final ({String name, String sub, IconData icon}) spec;
  final CloudIntegration? integration;

  const _ServiceRow({
    required this.providerId,
    required this.spec,
    required this.integration,
  });

  @override
  State<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends State<_ServiceRow> {
  bool _connecting = false;

  /// The connect's refusal, said at the row that was pressed — not a toast
  /// that is gone before it is read.
  String? _connectFail;

  Future<void> _connect({bool again = false}) async {
    setState(() {
      _connecting = true;
      _connectFail = null;
    });
    final err = await context.read<CloudNotifier>().connect(widget.providerId);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connectFail = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.integration;
    final connected = i != null;
    final expired = i?.needsReconnect ?? false;
    return KitServiceRow(
      provider: widget.providerId,
      name: widget.spec.name,
      line: widget.spec.sub,
      // The account once connected, the invitation before (kit §5.1, 5.46.0,
      // ADR-201) — *Connected* while no address is stored.
      account: i?.providerEmail,
      connected: connected,
      expired: expired,
      action: connected
          ? KitLibActs(children: [
              if (expired)
                KitLibAct(_connecting ? 'Reconnecting…' : 'Reconnect',
                    strong: true,
                    onTap: _connecting ? null : () => _connect(again: true)),
              KitLibAct('Manage',
                  onTap: () => context.go('/sources/${widget.providerId}')),
            ])
          : KitLibAct(_connecting ? 'Connecting…' : 'Connect',
              strong: true, onTap: _connecting ? null : _connect),
      failure:
          _connectFail == null ? null : KitFailureInline(_connectFail!, dense: true),
    );
  }
}
