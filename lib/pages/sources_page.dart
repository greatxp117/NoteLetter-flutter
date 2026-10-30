import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/document.dart';
import '../models/import_job.dart';
import '../services/camera_sweep_bridge.dart';
import '../shared/cloud_providers.dart';
import '../shared/cloud_return.dart';
import '../shared/cooldown.dart';
import '../shared/local_flags.dart';
import '../shared/shelf_tree.dart';
import '../state/camera_sweep_host.dart';
import '../state/cloud_notifier.dart';
import '../state/documents_notifier.dart';
import '../state/org_notifier.dart';
import '../state/tags_notifier.dart';
import '../state/upload_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/file_uploader.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import 'reader/reader_prefs.dart';
import 'settings/sources_section.dart';
import 'settings/summaries_section.dart';
import 'sources/browse_section.dart';
import 'sources/cloud_picker.dart';
import 'sources/cloud_sync_copy.dart';
import 'sources/import_review_queue.dart';
import 'sources/source_facets.dart';
import 'sources/suggestion_queue.dart';
import 'sources/organization_settings_panel.dart';
import 'sources/sweep_tray.dart';
import 'sources/sync_settings_panel.dart';
import 'reader/supersession_confirm.dart';

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
/// *Add a source* is its own page here (`/sources/add`): this client has no
/// quick-add overlay, and that page holds the uploader. The empty catalogue
/// holds the uploader too, through the same [FileUploader].
class SourcesPage extends StatefulWidget {
  /// OAuth return params (ADR-012, ADR-158), passed from the /sources route
  /// on a web build: `claim` (with [cloudConnectClaim]) or `error` (with
  /// [cloudConnectReason]). An app's return arrives through its auth session
  /// instead ([CloudReturn]). A 4.x `success` link is believed by nobody.
  final String? cloudConnectResult; // 'claim' | 'error'
  final String? cloudConnectProvider;
  final String? cloudConnectReason;
  final String? cloudConnectClaim;

  const SourcesPage({
    super.key,
    this.cloudConnectResult,
    this.cloudConnectProvider,
    this.cloudConnectReason,
    this.cloudConnectClaim,
  });

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  // ── The OAuth return, said by the notices strip (§States) ─────────────────

  /// A `cloud_connect=error` reason, in §States' copy.
  String? _errorBanner;

  /// The provider whose returned claim is being spent (5.0.0, ADR-158): the
  /// exchange with the provider happens inside that request, so it takes a
  /// moment, and the return says so rather than look like nothing happened.
  String? _claiming;

  /// A claim the server REFUSED (403 another account started it, 404 expired
  /// or already finished) — its own sentence, verbatim (§14.2).
  String? _claimRefusal;

  /// `org: "enabled"` — the write-scope upgrade, confirmed.
  String? _orgEnabled;

  /// `connection: "reconnected"` (2.21.0, ADR-026): nothing was added.
  String? _alreadyConnected;

  /// A new connection: the first-import nudge over the panels, and that
  /// provider's picker open (web `justConnected`).
  String? _justConnected;

  CloudNotifier? _cloud;
  DocumentsNotifier? _docs;

  // ── The sheet ─────────────────────────────────────────────────────────────
  String _kind = 'all';
  String? _shelf;
  String _sort = 'recent';

  /// The camera roll's tray, revealed by its row's *Review*.
  bool _trayOpen = false;

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
      CloudReturn.pending.addListener(_onReturn);
      _handleOAuthReturn();
    });
  }

  @override
  void dispose() {
    _cloud?.completionMessage.removeListener(_onSessionComplete);
    _docs?.removeListener(_onDocs);
    CloudReturn.pending.removeListener(_onReturn);
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

  // An app's auth session came back while this screen was open.
  void _onReturn() {
    if (!mounted || CloudReturn.pending.value == null) return;
    final r = CloudReturn.take();
    if (r != null) _actOnReturn(r);
  }

  // Completion notification (1.4.0): a tracked import/sync session went
  // all-terminal — summarize it as a toast, then clear the one-shot.
  void _onSessionComplete() {
    final msg = _cloud?.completionMessage.value;
    if (msg == null || !mounted) return;
    AppToast.show(context, msg, type: ToastType.success);
    _cloud!.completionMessage.value = null;
  }

  // The OAuth return (ADR-012, ADR-158, ADR-159; api/cloud-storage.md §Client
  // behavior on return). It arrives as /sources params on a web build — stripped
  // FIRST, so neither a refresh nor Back can claim twice — or through the
  // app's auth session, held by [CloudReturn] for whichever Sources takes it.
  // Either way it is acted on once. We do NOT infer a connection from the URL
  // or from an integrations diff.
  Future<void> _handleOAuthReturn() async {
    final result = widget.cloudConnectResult;
    CloudReturn? routed;
    if (result != null) {
      routed = CloudReturn.fromParams({
        'cloud_connect': result,
        if (widget.cloudConnectClaim != null) 'claim': widget.cloudConnectClaim!,
        if (widget.cloudConnectProvider != null)
          'provider': widget.cloudConnectProvider!,
        if (widget.cloudConnectReason != null)
          'reason': widget.cloudConnectReason!,
      });
      // Strip the params (equivalent of history.replaceState).
      context.go('/sources');
    }
    final r = routed ?? CloudReturn.take();
    if (r != null) await _actOnReturn(r);
  }

  Future<void> _actOnReturn(CloudReturn r) async {
    if (r.result == 'error') {
      setState(() => _errorBanner = _reasonCopy(r.provider, r.reason));
      return;
    }
    // `error` and `claim` are the only results a return carries (5.0.0);
    // anything else is believed by nobody.
    final claim = r.claim;
    if (r.result != 'claim' || claim == null || claim.isEmpty) return;
    final cloud = context.read<CloudNotifier>();
    setState(() {
      _claiming = r.provider ?? '';
      _claimRefusal = null;
      _errorBanner = null;
    });
    final (:answer, :refusal) = await cloud.claim(claim);
    if (!mounted) return;
    setState(() {
      _claiming = null;
      _claimRefusal = refusal;
    });
    final res = answer;
    if (res == null) return;
    final provider = (res['provider'] as String?) ?? r.provider;
    if (res['cloud_connect'] == 'success') {
      await _confirmConnected(provider,
          org: res['org'] == 'enabled',
          reconnected: res['connection'] == 'reconnected');
    } else {
      setState(() =>
          _errorBanner = _reasonCopy(provider, res['reason'] as String?));
    }
  }

  // Success → say it in the notices strip, and auto-open the provider's picker
  // (the first-import prompt fires on return, not on a later focus event).
  Future<void> _confirmConnected(String? provider,
      {required bool org, required bool reconnected}) async {
    final cloud = context.read<CloudNotifier>();
    // 2.21.0 — a re-authorisation is not a new connection: it says what
    // happened and stops, with no import nudge. org_upgrade confirms the
    // write-scope grant; the reader was not importing, so no first-import
    // prompt either. Open vocabulary, so anything unrecognised takes the
    // new-connect path rather than falling into silence.
    setState(() {
      if (org) {
        _orgEnabled = provider ?? '';
      } else if (reconnected) {
        _alreadyConnected = provider ?? '';
      } else {
        _justConnected = provider;
      }
    });
    if (provider != null && !reconnected && !org) {
      await cloud.openPicker(provider);
    }
  }

  // The reference's connectErrorCopy (ADR-012). Open vocabulary — unknown
  // reasons fall through to generic copy. insufficient_scope is the one
  // "error" where the base connection did succeed: only the
  // auto-organization write-scope upgrade was declined.
  String _reasonCopy(String? provider, String? reason) {
    final name = _providers[provider]?.name ?? 'the service';
    final cap = _providers[provider]?.name ?? 'The service';
    switch (reason) {
      case 'invalid_state':
        return 'That sign-in link expired before it could finish. Connect '
            '$name again.';
      case 'missing_params':
        return 'The connection didn’t complete. Connect $name again.';
      case 'insufficient_scope':
        return '$cap is connected, but didn’t grant the permissions '
            'needed for auto-organization. Reconnect and allow all requested '
            'access to enable it.';
      case 'access_denied':
        return 'Access to $name was declined. Connect again and approve to '
            'import your files.';
      default:
        return 'Couldn’t finish connecting $name. Please try again.';
    }
  }

  /// The strip's sentences, in web's order.
  List<Widget> _notices() => [
        if (_claiming != null)
          KitLibNotice(
            'Finishing the ${_providers[_claiming]?.name ?? 'cloud'} '
            'connection…',
            status: true,
          ),
        if (_claimRefusal != null) KitFailureInline(_claimRefusal!),
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
        // ADR-026: a re-authorisation, not a new source.
        if (_alreadyConnected != null)
          KitLibNotice(
            '${_providers[_alreadyConnected]?.name ?? 'That service'} was '
            'already connected — your sign-in was refreshed and nothing else '
            'changed.',
            onDismiss: () => setState(() => _alreadyConnected = null),
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

    final folio = 'The library · '
        '${measured ? kitCounted(all.length, 'volume') : '— volumes'} · '
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
            // at the subscription's cap the figures describe the window and
            // say so.
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
                        if (all.length >= 200)
                          KitLibNote('Of your most recent ${all.length}.',
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
    final meta = !measured
        ? null
        : items.length == all.length
            ? kitCounted(all.length, 'volume')
            : '${items.length} of ${kitCounted(all.length, 'volume')}';

    return KitDPage(
      folio: folio,
      title: 'The Library',
      stand: stand,
      action: KitPageAction(
        label: 'Add a source',
        short: 'Add',
        icon: Icons.add,
        onPressed: () => context.go('/sources/add'),
      ),
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
  /// ABOVE the cloud panels, so Disconnect and a second service stay
  /// reachable — then the panels, which keep every behaviour they had.
  Widget _correspondence(CloudNotifier cloud, List<String> connected) {
    final unread = cloud.integrationsError != null && !cloud.integrationsLoaded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'Correspondence',
          meta: connected.isEmpty
              ? 'Services that send you volumes'
              : 'Imports · filing · folders',
          flushTop: true,
        ),
        _CameraRollRow(
          open: _trayOpen,
          onReview: () => setState(() => _trayOpen = !_trayOpen),
        ),
        if (_trayOpen) const SweepTraySection(),
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
        // not a toast (4.89.0, ADR-123 §5).
        if (cloud.lastDisconnect != null)
          KitLibNote(disconnectOutcome(
            cloud.lastDisconnect!.$1,
            _providers[cloud.lastDisconnect!.$1]?.name ??
                cloud.lastDisconnect!.$1,
            cloud.lastDisconnect!.$2,
          )),
        // The first-import nudge (web CloudImportPanel's `.import-nudge`),
        // for the provider a claim just connected.
        if (_justConnected != null && connected.contains(_justConnected))
          KitLibNotice(
            'Connected to ${_providers[_justConnected]?.name ?? _justConnected} '
            '— import your first files below.',
            onDismiss: () => setState(() => _justConnected = null),
          ),
        // One block per connected provider, under its own header ("Import
        // from {provider}", web `CloudImportPanel`): Sync now, Sync settings,
        // Browse files… and Organization settings, the sync sentence, the
        // reconnect banner and the picker.
        for (final p in connected)
          _ImportFromProvider(
            providerId: p,
            spec: _providers[p]!,
            integration: cloud.integrationFor(p)!,
          ),
        // What the last triage batch did that the rows cannot say. HERE and
        // not inside the queue: dismissing the last held file unmounts that
        // section, and a line about what just happened would vanish with it.
        if (cloud.reviewOutcome != null)
          ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
        ImportReviewQueue(
          held: cloud.heldJobs,
          rulesFor: (p) => cloud.integrationFor(p)?.reviewRules ?? const {},
        ),
        _ImportActivity(
          jobs: cloud.progressJobs,
          all: cloud.jobs,
          error: cloud.jobsError,
          summary: _progressSummary(cloud),
          discoveringFiles: cloud.awaitingFirstJob,
        ),
        _ImportHistory(
            jobs: cloud.historyJobs, windowFull: cloud.jobs.length >= 50),
        // The reference's OrganizationPanel: the suggestions FIRST, then each
        // provider's organized folders (F-90 (6)).
        const _OrganizationSection(),
        const OrganizedFoldersSection(),
      ],
    );
  }
}

// ── Correspondence: the camera roll ─────────────────────────────────────────

/// The camera roll's row (screens/sources.md §Camera roll, *The row*, 5.43.0,
/// ADR-198): the camera glyph, *Camera roll*, a line and one action, the
/// first state that holds deciding it — for the states this client can
/// measure today. *Settings* and *Connect* open its settings; *Review*
/// reveals the tray under the row. Drawn only where there is a photo library
/// this client can sweep. (The look-back walk's position is not measured
/// yet: its *Looking back · n of N* line is F-146's, with the D flow.)
class _CameraRollRow extends StatelessWidget {
  final bool open;
  final VoidCallback onReview;

  const _CameraRollRow({required this.open, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final host = context.watch<CameraSweepHost?>();
    if (!CameraSweepBridge.isAvailable || host == null || !host.available) {
      return const SizedBox.shrink();
    }
    if (host.loadError != null) {
      return const KitServiceRow(
        glyph: Icons.photo_camera_outlined,
        name: 'Camera roll',
        failure: KitFailureInline(
            'This phone’s camera roll settings could not be read.',
            dense: true),
      );
    }
    final ledger = host.ledger, service = host.service;
    if (ledger == null || service == null) return const SizedBox.shrink();
    void settings() => context.go('/settings/camera-roll');
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, service]),
      builder: (context, _) {
        final waiting = service.candidates.length;
        final (String line, bool critical, Widget action) = service
                    .errorMessage !=
                null
            ? (
                service.errorStoppedSweep
                    ? 'The camera roll stopped'
                    : 'A photo couldn’t be added',
                true,
                KitLibAct('Settings', onTap: settings),
              )
            : ledger.enabled &&
                    host.access != null &&
                    host.access != SweepAccess.granted
                ? (
                    'NoteLetter can’t see your photos',
                    false,
                    KitLibAct('Settings', onTap: settings),
                  )
                : waiting > 0
                    ? (
                        '$waiting waiting for your review',
                        false,
                        KitLibAct('Review', strong: true, onTap: onReview),
                      )
                    : ledger.enabled
                        ? (
                            'On · ${kitThousands(ledger.ingestedCount)} taken in',
                            false,
                            KitLibAct('Settings', onTap: settings),
                          )
                        : (
                            'Pages, screenshots and notes from your photos',
                            false,
                            KitLibAct('Connect', strong: true, onTap: settings),
                          );
        return KitServiceRow(
          glyph: Icons.photo_camera_outlined,
          name: 'Camera roll',
          line: line,
          critical: critical,
          action: action,
        );
      },
    );
  }
}

// ── Correspondence: a service ───────────────────────────────────────────────

/// One service row (web `Services`): *Connect* (*Connecting…* while it runs)
/// or *Disconnect* behind the §18 confirm; a refused connect is §14.2 at
/// that row. Everything a connected provider can DO lives under its "Import
/// from" header ([_ImportFromProvider]).
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

  Future<void> _connect() async {
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

  Future<void> _disconnect() async {
    final spec = widget.spec;
    final cloud = context.read<CloudNotifier>();
    cloud.clearDisconnectNote();
    final revoke = disconnectRevokeCopy(widget.providerId, spec.name);
    // §18 Confirmation (4.56.0, ADR-092). 4.90.0 (ADR-124 §7): only imports
    // that have not reached the pipeline stop — a file already downloaded
    // finishes. 4.89.0 (ADR-123 §5): the grant is ASKED to be revoked where
    // the provider lets an app do that, and where it does not the confirm says
    // where the reader removes it. What the provider answered is said AFTER,
    // under the rows (`lastDisconnect`), never as a toast.
    await KitConfirm.show(
      context,
      title: 'Disconnect ${spec.name}?',
      body: '${disconnectConsequences(spec.name)}'
          '${revoke != null ? '\n\n$revoke' : ''}'
          '\n\nEverything already in your library stays — '
          'documents, passages and letters are unaffected, and the '
          'files in ${spec.name} itself are never touched. '
          'Reconnecting starts a fresh pick of folders.',
      confirmLabel: 'Disconnect',
      cancelLabel: 'Stay connected',
      onConfirm: () => cloud.disconnect(widget.providerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.integration != null;
    return KitServiceRow(
      provider: widget.providerId,
      name: widget.spec.name,
      line: widget.spec.sub,
      connected: connected,
      action: connected
          ? KitLibAct('Disconnect', onTap: _disconnect)
          : KitLibAct(_connecting ? 'Connecting…' : 'Connect',
              strong: true, onTap: _connecting ? null : _connect),
      failure:
          _connectFail == null ? null : KitFailureInline(_connectFail!, dense: true),
    );
  }
}

// ── Import from {provider} ───────────────────────────────────────────────────

/// A connected provider's block (web `CloudImportPanel`, per provider): a §3
/// header — the provider's glyph and "Import from {provider}", with **Sync
/// now · Sync settings · Browse files…** as its trailing links — then, in
/// order, why Sync now cannot run, what it answered, the sync settings, the
/// reconnect banner, and the import picker.
///
/// The sync-now sentence is said HERE, under the header (web `ed461b3`), not
/// in a footnote inside the connect card: the card is fixed (ruled
/// 2026-10-08).
class _ImportFromProvider extends StatefulWidget {
  final String providerId;
  final ({String name, String sub, IconData icon}) spec;
  final CloudIntegration integration;

  const _ImportFromProvider({
    required this.providerId,
    required this.spec,
    required this.integration,
  });

  @override
  State<_ImportFromProvider> createState() => _ImportFromProviderState();
}

class _ImportFromProviderState extends State<_ImportFromProvider> {
  /// Sync now in flight, and the sentence it came back with: a refusal is
  /// §14.2, a kickoff is calm copy, and a cooldown that carried its number is
  /// the PROVIDER's wait (4.107.0, ADR-140), said by the wait itself.
  bool _syncing = false;
  String? _syncNote;
  bool _syncRefused = false;

  bool _settingsOpen = false;

  bool _reconnecting = false;
  String? _reconnectFail;

  /// The server's own 400 sentence for a provider with no sync folders
  /// (`fn_request_cloud_sync`). Sync now is held on the same condition, and
  /// the reason is VISIBLE — a held control with no reason reads as broken,
  /// and a tooltip reaches neither a finger nor a screen reader.
  static const _noFolders = 'Nothing to sync — choose sync folders first.';

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncNote = null;
    });
    final (msg, result) =
        await context.read<CloudNotifier>().syncNow(widget.providerId);
    if (!mounted) return;
    final waits = result == SyncNowResult.wait &&
        Cooldowns.instance.waiting(WaitKey.cloudSync(widget.providerId));
    setState(() {
      _syncing = false;
      _syncNote = waits ? null : msg;
      _syncRefused = result == SyncNowResult.refused;
    });
  }

  Future<void> _reconnect() async {
    setState(() {
      _reconnecting = true;
      _reconnectFail = null;
    });
    final err = await context.read<CloudNotifier>().connect(widget.providerId);
    if (!mounted) return;
    setState(() {
      _reconnecting = false;
      _reconnectFail = err;
    });
  }

  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: WaitKey.cloudSync(widget.providerId),
        builder: _block,
      );

  Widget _block(BuildContext context, CooldownWait wait) {
    final t = Tokens.of(context);
    final cloud = context.watch<CloudNotifier>();
    final i = widget.integration;
    final needsReconnect = i.needsReconnect;
    final noFolders = i.folderIds.isEmpty;
    final browsing = cloud.browseProvider == widget.providerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.lib-section-h` at `margin-top: 18`: the eyebrow left, the links
        // right — and on a phone the links take the next line rather than
        // squeezing the eyebrow into a column.
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The provider's own mark at 14 (`ProviderLogo`, F-101).
                  KitGlyph(widget.spec.icon, size: 14, color: t.fgMuted),
                  const SizedBox(width: 7),
                  Eyebrow('Import from ${widget.spec.name}'),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  KitSettingLink(
                    _syncing ? 'Syncing…' : 'Sync now',
                    icon: null,
                    wait: _syncing ? 0 : wait.left,
                    onTap: needsReconnect || _syncing || noFolders
                        ? null
                        : _syncNow,
                  ),
                  KitSettingLink(
                    _settingsOpen ? 'Close settings' : 'Sync settings',
                    icon: null,
                    onTap: () =>
                        setState(() => _settingsOpen = !_settingsOpen),
                  ),
                  KitSettingLink(
                    browsing ? 'Close' : 'Browse files…',
                    icon: null,
                    onTap: needsReconnect
                        ? null
                        : () => browsing
                            ? cloud.closePicker()
                            : cloud.openPicker(widget.providerId),
                  ),
                  // The door to Settings → Sources (ruled 2026-10-09): where
                  // organizing is turned on and tuned. Drawn for every
                  // connected provider, organized or not — Settings is also
                  // where it is turned ON (web CloudImportPanel).
                  // A cloud panel's Organization settings opens the page's
                  // own Library settings in place (sources.md §Tools); with
                  // no such panel it goes to Settings → Sources.
                  KitSettingLink(
                    'Organization settings',
                    icon: null,
                    onTap: () {
                      if (!KitPageTools.instance.openSettings('sources')) {
                        context.go('/settings/sources');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (noFolders && !needsReconnect)
          const KitProcNote(_noFolders, padding: EdgeInsets.only(top: 4)),
        // A wait is calm copy; a refusal is §14.2; a kickoff says what it
        // started (§6.1, 4.108.0, ADR-145).
        if (wait.sentence != null)
          KitWaitNote(wait.sentence!,
              padding: const EdgeInsets.only(top: 4))
        else if (_syncNote != null)
          _syncRefused
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: KitFailureInline(_syncNote!, dense: true),
                )
              : KitProcNote(_syncNote!,
                  padding: const EdgeInsets.only(top: 4)),
        if (_settingsOpen)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SyncSettingsPanel(
              providerId: widget.providerId,
              integration: i,
              embedded: true,
            ),
          ),
        if (needsReconnect) ...[
          const SizedBox(height: 8),
          _Banner(
            icon: Icons.link_off,
            text: '${widget.spec.name} needs to be reconnected — its sign-in '
                'has expired.${i.statusReason != null ? '\n${i.statusReason}' : ''}',
            action: KitSettingLink(
              _reconnecting ? 'Reconnecting…' : 'Reconnect',
              icon: null,
              onTap: _reconnecting ? null : _reconnect,
            ),
          ),
          if (_reconnectFail != null)
            KitFailureInline(_reconnectFail!, dense: true),
        ],
        if (browsing && !needsReconnect) ...[
          const SizedBox(height: 10),
          const _PickerPanel(),
        ],
      ],
    );
  }
}

// ── File picker ──────────────────────────────────────────────────────────────

/// The import picker, as the reference composes it (`CloudFilePicker`,
/// mode `import`; F-61): ONE flat panel on `--bg-2` (= `--surface-raised`),
/// r-lg, padding 14. No title row and no close control — Cancel is the way
/// out. The crumbs are `.set-link`s (`Root` › …) with the counter as a
/// `.proc-note` at the right of the same row; rows are unboxed; the foot is
/// `Import N items` (the accent primary, disabled at zero — `!canConfirm`)
/// beside a quiet Cancel.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel();

  @override
  State<_PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<_PickerPanel> {
  bool _saving = false;

  /// A cap that blocks a toggle says so IN the panel, as the reference's
  /// `capNote` does — a control that silently does nothing reads as broken.
  String? _capNote;

  void _toggle(CloudNotifier cloud, CloudFile f) {
    final note = f.isFolder ? cloud.toggleFolder(f.id) : cloud.toggleFile(f.id);
    setState(() => _capNote = note);
  }

  Future<void> _confirm(CloudNotifier cloud) async {
    setState(() => _saving = true);
    final (msg, isErr) = await cloud.importSelection();
    if (!mounted) return;
    setState(() => _saving = false);
    // A refusal is drawn in the picker (importError); only the 202's count is
    // a toast, because the picker it would sit in has closed.
    if (isErr) return;
    AppToast.show(context, msg, type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final listing = cloud.listing;
    final provider = cloud.browseProvider ?? '';
    final crumbs = cloud.crumbs;
    final total = cloud.selectedFolders.length + cloud.selectedFiles.length;
    // One slot, as the reference's single `error`: the listing's failure or
    // the import's refusal, verbatim (§14.2).
    final error = cloud.importError ?? cloud.browseError;
    final items = listing?.items ?? const <CloudFile>[];

    return CloudPickerPanel(
      children: [
        // The caps are `fn_import_from_cloud`'s own (≤20 folders, ≤50 files)
        // and the picker is what enforces them.
        CloudPickerCrumbs(
          labels: [for (final c in crumbs) c.label],
          onJump: cloud.jumpToCrumb,
          counter: '${cloud.selectedFolders.length}/$kMaxImportFolders folders · '
              '${cloud.selectedFiles.length}/$kMaxImportFiles files',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error),
          ),
        if (_capNote != null)
          KitProcNote(_capNote!, padding: const EdgeInsets.only(bottom: 8)),
        // ADR-026 §3: standing guidance on every rendered Notion listing —
        // Notion never reports what it withheld, so this is never phrased as
        // a finding about THIS connection.
        if (provider == 'notion' && cloud.browseError == null && !cloud.browsing)
          const KitProcNote(
            'Notion passes along only the pages you ticked — to bring more '
            'in, grant access in Notion and return.',
            padding: EdgeInsets.only(bottom: 8),
          ),
        for (final f in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _FileRow(
                file: f, provider: provider, onToggle: () => _toggle(cloud, f)),
          ),
        // ADR-026 §2: empty is a CLAIM about a listing that answered — over a
        // failed request it is a hole drawn as a zero.
        if (!cloud.browsing && cloud.browseError == null && items.isEmpty)
          const KitProcNote('Nothing here.', padding: EdgeInsets.zero),
        if (cloud.browsing)
          const KitProcNote('Loading…', padding: EdgeInsets.zero),
        if (listing?.nextPageToken != null)
          CloudPickerLoadMore(
              loading: cloud.loadingMore, onTap: cloud.loadMore),
        CloudPickerFoot(
          confirmLabel: _saving
              ? 'Queuing…'
              : 'Import $total item${total == 1 ? '' : 's'}',
          onConfirm: total == 0 ? null : () => _confirm(cloud),
          onCancel: cloud.closePicker,
          busy: _saving,
        ),
      ],
    );
  }
}

/// A listing row, unboxed: checkbox, then a folder's `.set-link` name and
/// chevron with its contents disclosure under it, or a file's plate, name and
/// size. 4.91.0 (ADR-125 §1): a file the upload classifier refuses is offered
/// no checkbox — the import would come back `unsupported_type` — and says why
/// in the classifier's own words; the slot keeps its width so the row still
/// lines up with its neighbours.
class _FileRow extends StatelessWidget {
  final CloudFile file;
  final String provider;
  final VoidCallback onToggle;
  const _FileRow(
      {required this.file, required this.provider, required this.onToggle});

  /// Web `mimeKind`: pdf · epub · html → web · everything else → note.
  static String _plateType(String? mime) {
    final m = mime ?? '';
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('epub')) return 'epub';
    if (m.contains('html')) return 'article';
    return 'plain';
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.read<CloudNotifier>();
    final selected = file.isFolder
        ? cloud.selectedFolders.contains(file.id)
        : cloud.selectedFiles.contains(file.id);
    final refusal = cloudFileRefusal(provider, file);

    final box = CloudPickerCheck(
      value: refusal != null ? null : selected,
      label: 'Import ${file.name}',
      onToggle: onToggle,
    );

    if (file.isFolder) {
      return CloudPickerFolderRow(
        check: box,
        name: file.name,
        onOpen: () => cloud.enterFolder(file),
        provider: provider,
        folderId: file.id,
      );
    }

    final note = [
      fmtFileSize(file.size),
      // A Google-native file Drive exports says what it imports AS (4.94.0).
      cloudExportLabel(file) ?? '',
    ].where((s) => s.isNotEmpty).join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: refusal != null ? null : onToggle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box,
          const SizedBox(width: 8),
          KitFileBadge(kitDocKind(_plateType(file.mimeType)),
              size: KitBadgeSize.chip),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.ui(context)),
                if (refusal != null)
                  KitProcNote(refusal, padding: EdgeInsets.zero),
              ],
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(width: 8),
            KitProcNote(note, padding: EdgeInsets.zero),
          ],
        ],
      ),
    );
  }
}

// ── Cloud imports ────────────────────────────────────────────────────────────

class _ImportActivity extends StatelessWidget {
  /// The progress rows (`CloudNotifier.progressJobs`): every non-terminal job
  /// plus this session's terminal ones — never the whole window of 50, which
  /// is §Import history's.
  final List<ImportJob> jobs;

  /// The whole subscription, only to tell "nothing read" from "nothing here".
  final List<ImportJob> all;

  /// `CloudNotifier.jobsError` — set since the notifier was written, read by
  /// nothing until C3. Its own comment says why it matters: an unread job list
  /// renders as "no imports running", which is exactly what a reader watching
  /// an import wants to know is false.
  final String? error;

  /// "{N} of {M} imported[ so far — still discovering files]", or the
  /// settled "Everything there was already imported." Null with no kickoff
  /// and no rows.
  final String? summary;

  /// A kickoff whose jobs have not arrived yet — indeterminate, by contract.
  final bool discoveringFiles;

  const _ImportActivity({
    required this.jobs,
    required this.all,
    this.error,
    this.summary,
    this.discoveringFiles = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // Hiding the section was the failure mode, not a symptom of it: an empty
    // list and an unreadable one both collapsed to `SizedBox.shrink()`, so the
    // one reader who needed the difference — someone watching an import — got
    // the same blank space either way (INV-24, ADR-071).
    if (error != null && all.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No count: the figure is derived from a list nothing read, and
          // unread is not zero (§8, ADR-109).
          const SectionHeader('Cloud imports'),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KitFailureInline(error!),
          ),
        ],
      );
    }
    if (jobs.isEmpty && summary == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          // The reference's label (`CloudImportPanel`); this client said
          // "Import activity" until F-102.
          error != null || jobs.isEmpty
              ? 'Cloud imports'
              : 'Cloud imports · ${jobs.length}',
          note: error != null ? null : summary,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error!),
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
        if (jobs.isNotEmpty) _procList(jobs),
      ],
    );
  }
}

/// The progress summary (`screens/sources.md` §Cloud import): "{N} of {M}
/// imported" where M is the rows on screen — **never a determinate
/// fraction**, because discovery adds jobs as it goes and dedupe skips
/// silently. Null when there is nothing to summarise.
String? _progressSummary(CloudNotifier cloud) {
  final visible = cloud.progressJobs;
  if (cloud.nothingNew && visible.isEmpty) {
    return 'Everything there was already imported.';
  }
  if (visible.isEmpty && cloud.kickoff == null) return null;
  final done = visible.where((j) => j.status == 'complete').length;
  return '$done of ${visible.length} imported'
      '${cloud.discovering ? ' so far — still discovering files' : ''}';
}

/// `.proc-list` of import job cards: 12 under its header, 10 apart.
Widget _procList(List<ImportJob> jobs) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < jobs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _JobRow(key: ValueKey(jobs[i].id), job: jobs[i]),
          ],
        ],
      ),
    );

/// `.proc-note` — the italic serif 13 at `--fg-subtle` (KitProcNote's face).
TextStyle _procNote(BuildContext context) =>
    KitText.lede(context, fontSize: 13, height: 20)
        .copyWith(color: Tokens.of(context).fgSubtle);

/// **Import history** (`screens/sources.md` §Trust & feedback): collapsed,
/// terminal jobs grouped by calendar day (`created_at`, client-local), the
/// day header counting THAT day's outcomes, rows reusing the progress-row
/// treatment with its retry. Bounded by the subscription's 50 and said so.
class _ImportHistory extends StatefulWidget {
  final List<ImportJob> jobs;
  final bool windowFull;
  const _ImportHistory({required this.jobs, required this.windowFull});

  @override
  State<_ImportHistory> createState() => _ImportHistoryState();
}

class _ImportHistoryState extends State<_ImportHistory> {
  bool _open = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// One day's own counts — never the held count of the whole subscription,
  /// which the reference repeats under every day.
  static String _daySummary(List<ImportJob> rows) {
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
    final jobs = widget.jobs;
    if (jobs.isEmpty) return const SizedBox.shrink();
    final byDay = <DateTime, List<ImportJob>>{};
    for (final j in jobs) {
      final d = DateTime.fromMillisecondsSinceEpoch(j.createdAt!);
      byDay.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(j);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Import history',
          actionLabel: _open ? 'Hide' : 'Show ${jobs.length}',
          onAction: () => setState(() => _open = !_open),
        ),
        if (_open) ...[
          for (final e in byDay.entries) ...[
            // A day: its date and its own counts, both `.proc-note` (the
            // italic serif the section's other notes are), then its cards.
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                // The date at its own width and the counts in the rest, right
                // aligned: halving the row wrapped "1 skipped" onto a second
                // line where the reference's `space-between` fits one.
                children: [
                  Text(
                    '${_months[e.key.month - 1]} ${e.key.day}, ${e.key.year}',
                    style: _procNote(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_daySummary(e.value),
                        textAlign: TextAlign.right,
                        style: _procNote(context)),
                  ),
                ],
              ),
            ),
            _procList(e.value),
          ],
          if (widget.windowFull)
            const KitProcNote('Showing the most recent 50 import jobs.'),
        ],
      ],
    );
  }
}

class _JobRow extends StatefulWidget {
  final ImportJob job;
  const _JobRow({super.key, required this.job});

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  /// A retry in flight, and the sentence a refusal came back with — the
  /// 409/429 copy is user-facing and belongs ON the row it is about
  /// (§Trust & feedback: "render 409/429 `error` message inline").
  bool _busy = false;
  String? _retryError;

  /// Update from source on a kept refresh row (4.96.0, ADR-129) — the same
  /// shape as Retry, and its own state: the two never share a row. Success
  /// needs no optimistic state (the jobs subscription moves the row); a
  /// refusal is the server's sentence, under the row.
  bool _updating = false;
  String? _updateError;

  /// Each control's own cooldown (4.107.0, ADR-140): held for the wait its
  /// refusal carried, counting it down, with the server's sentence in the
  /// control's §14.2 slot for exactly as long. Retry's is the JOB's; Update
  /// from source's is keyed by the document it re-imports, and read only on a
  /// row that draws that control — another of the document's job rows has no
  /// slot for its sentence.
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
  /// or the document is in a study program (or either could not be checked).
  /// Inside the confirm a refusal renders in the panel's failure slot; with
  /// no confirm owed it is §14.2 under the row, as before.
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
    final (label, tone) = _status(job, t);
    final viewable = job.isDuplicate && job.documentId != null;
    final provider = _providers[job.provider]?.name ?? job.provider;

    // The reference's `ImportJobRow` (F-102): a `.proc-row` card — the File
    // badge · the file name over `{mark} {provider} · {path}` · the controls
    // and the §6.3 status pill — then the slots under it. It was a §4.1 source
    // row with the status folded into its subtitle.
    final card = KitProcCard(
      // The plate is the FILE's kind, from its MIME through the one kind
      // table. A hardcoded `web` plate said every imported PDF was a page.
      kind: kitDocKind(job.docType),
      title: job.providerFileName.isEmpty
          ? '(fetching name…)'
          : job.providerFileName,
      subtitleLeading: KitProviderLogo(provider: job.provider, size: 12),
      subtitle: job.providerPath.isEmpty
          ? provider
          : '$provider · ${job.providerPath}',
      // `.set-link`s, as the reference's row draws them; held is its quiet
      // tier (`.set-link:disabled`).
      actions: [
        if (viewable)
          KitSettingLink('View',
              icon: null,
              onTap: () => context.go('/reader/${job.documentId}')),
        // `canRetry` is the whole rule: error/cancelled retry, and of the
        // skips only duplicate · dismissed · plan_limit import again. A
        // size-cap skip would skip identically; a legacy skip is action-less.
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
        // A kept refresh (skipped · document_complete | document_unchanged,
        // with its document): no Retry — it would mint a second document —
        // and the sentence names this control.
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
          // A failure's sentence, verbatim, in `.proc-error`'s strip.
          if (job.status == 'error' && job.errorMessage != null)
            KitProcAttention(detail: job.errorMessage!, actions: const []),
          // A skip's reason is what makes a skip a fact rather than a shrug —
          // calm, never failure-styled. Not for a duplicate or a dismissal:
          // their `error_message` IS the pill's word.
          if (job.status == 'skipped' &&
              job.errorMessage != null &&
              !job.isDuplicate &&
              !job.isDismissed)
            KitProcNote(job.errorMessage!,
                padding: const EdgeInsets.only(bottom: 12)),
          // Each control's one slot: its cooldown as the calm caption, the
          // cap or any other refusal as §14.2 (sources.md §Trust & feedback,
          // 4.108.0 — `retry_after_s` decides).
          for (final w in [
            ?kitRefusalSlot(retryWait, _retryError, dense: true),
            ?kitRefusalSlot(updateWait, _updateError, dense: true),
          ])
            Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        ],
      ),
    );
    // **A skipped or cancelled job is muted, never failure-styled** — a
    // correct outcome, made visible rather than silent (the reference's
    // `opacity: 0.55` on the row).
    final muted = job.status == 'skipped' || job.status == 'cancelled';
    return muted ? Opacity(opacity: 0.55, child: card) : card;
  }

  /// The pill's word and tone — the reference's `PILL` map, every member
  /// named. **A skipped job is muted, never failure-styled** — it is a correct
  /// outcome, and the row exists so that outcome is visible rather than
  /// silent.
  (String, KitProcTone) _status(ImportJob j, Tokens t) {
    switch (j.status) {
      // 4.45.0 (ADR-083) — **held, waiting on the user.** Attention styling,
      // never failure styling, and **never omitted**: a status the pill map
      // does not list drops the row out of the section entirely, which is how
      // a file waiting on a judgement becomes a file that silently is not
      // there. This client rendered six of nine and had no `awaiting_review`
      // at all until 4.45.0.
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
                  // A dismissal is reversible, and **Import again** is how —
                  // `fn_retry_import_job`, which since 1.3.0 already means
                  // "import it anyway" for a skipped job. `canRetry` already
                  // covers `skipped`, so the control is there.
                  ? 'Dismissed — not imported'
                  : 'Skipped',
          KitProcTone.wait
        );
      case 'cancelled':
        return ('Cancelled', KitProcTone.wait);
      // Named, not left to the default branch (`job_status_check` reported
      // both as MIRROR-GAP): `queued` read "Waiting" here and "Queued" on the
      // reference, and a status the switch never names is one nobody decided.
      case 'pending':
        return ('Waiting', KitProcTone.wait);
      case 'queued':
        return ('Queued', KitProcTone.wait);
      case 'downloading':
        return ('Downloading', KitProcTone.work);
      case 'processing':
        return ('Processing', KitProcTone.work);
      default:
        // A status this client does not know yet: the reference draws it as
        // `pending` does, and never as its raw token.
        return ('Waiting', KitProcTone.wait);
    }
  }
}

// ── Auto-organization (1.2.0, INV-13) ───────────────────────────────────────

class _OrganizationSection extends StatelessWidget {
  const _OrganizationSection();

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgNotifier>();
    return SuggestionQueue(
      // The reference's own label (`SuggestionQueue`'s default, F-106).
      eyebrow: 'Suggestions',
      suggestions: org.suggestions,
      error: org.suggestionsError,
    );
  }
}

// ── Shared banner ────────────────────────────────────────────────────────────

/// The warning banner — a connection that needs reauthorising (an OAuth
/// return is the notices strip's since direction D). Always `--critical` at a token alpha: this is the one shape
/// on the screen that exists to interrupt, and a second, quieter tone would
/// make the reader classify it before reading it.
class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Banner({
    required this.icon,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    // The banner's own tint is the ground its sentence lands on, which is
    // the pair --critical does not clear (4.35.0, ADR-072).
    final color = Tokens.of(context).criticalText;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: KitText.meta(context))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

