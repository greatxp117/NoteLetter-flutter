import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/import_job.dart';
import '../shared/cloud_providers.dart';
import '../shared/cooldown.dart';
import '../state/cloud_notifier.dart';
import '../state/documents_notifier.dart';
import '../state/org_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_radius.dart';
import '../theme/tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/file_uploader.dart';
import '../widgets/kit/kit.dart';
import 'sources/browse_section.dart';
import 'sources/cloud_picker.dart';
import 'sources/cloud_sync_copy.dart';
import 'sources/import_review_queue.dart';
import 'sources/suggestion_queue.dart';
import 'sources/organization_settings_panel.dart';
import 'sources/sources_info_sheet.dart';
import 'sources/sync_settings_panel.dart';
import 'reader/supersession_confirm.dart';

const _providers = cloudProviders;

/// **Sources** — the rail's *Library* (`screens/sources.md`). Browse-and-manage
/// over ingestion sources, plus the add flows.
///
/// Composition (§Composition, ADR-041), every part from the kit:
///
/// * **Frame** Index (980) inside a scroll container — §1.4/§1.5.
/// * **Header** chapter opening: folio `{n} volumes`, the title with its italic
///   accent clause, a standfirst naming the passage count.
/// * **Body** three sections, each opened by a Section header (§3), in the
///   order the reference mounts them (contract 4.5.3): *Add to your library*
///   (drop zone → link row → processing rows), *Connect a service* (connect
///   cards §5.1, then the picker, the import progress and the history), and
///   *In your library* (control bar §6.6 over source rows §4.1).
///
/// The drop zone **opens** the screen. A source you just dropped lands where
/// you are already looking, and the reader with an empty library is exactly the
/// reader who must not have to scroll past it.
class SourcesPage extends StatefulWidget {
  /// OAuth return params (2.3.0, ADR-012), passed from the /sources route.
  final String? cloudConnectResult; // 'success' | 'error'
  final String? cloudConnectProvider;
  final String? cloudConnectReason;
  final String? cloudConnectOrg; // 'enabled' on org_upgrade success

  /// 2.21.0 (ADR-026) — `new` | `reconnected`, read from the integration doc
  /// immediately before it is overwritten, which is the only moment a reconnect
  /// is still distinguishable from a first connect. **Open vocabulary**: any
  /// other value takes the ordinary success path.
  final String? cloudConnectConnection;

  const SourcesPage({
    super.key,
    this.cloudConnectResult,
    this.cloudConnectProvider,
    this.cloudConnectReason,
    this.cloudConnectOrg,
    this.cloudConnectConnection,
  });

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  String? _errorBanner;
  CloudNotifier? _cloud;
  final _uploader = GlobalKey<FileUploaderState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cloud = context.read<CloudNotifier>();
      _cloud!.start();
      _cloud!.completionMessage.addListener(_onSessionComplete);
      context.read<OrgNotifier>().start();
      // The documents subscription this screen shares with Library (INV-02) —
      // it drives the folio, the processing rows and the volume list.
      context.read<DocumentsNotifier>().start();
      context.read<TagsNotifier>().start();
      _handleOAuthReturn();
    });
  }

  @override
  void dispose() {
    _cloud?.completionMessage.removeListener(_onSessionComplete);
    super.dispose();
  }

  // Completion notification (1.4.0): a tracked import/sync session went
  // all-terminal — summarize it as a toast, then clear the one-shot.
  void _onSessionComplete() {
    final msg = _cloud?.completionMessage.value;
    if (msg == null || !mounted) return;
    AppToast.show(context, msg, type: ToastType.success);
    _cloud!.completionMessage.value = null;
  }

  // 2.3.0 (ADR-012): the callback lands here with an explicit result. Success →
  // confirm + auto-open the provider's picker; error → reason banner. Then strip
  // the params so a refresh/back doesn't re-fire. We do NOT infer connection
  // from an integrations diff.
  Future<void> _handleOAuthReturn() async {
    final result = widget.cloudConnectResult;
    if (result == null) return;
    final cloud = context.read<CloudNotifier>();
    final provider = widget.cloudConnectProvider;

    if (result == 'success') {
      await cloud.loadIntegrations();
      if (!mounted) return;
      final name = provider != null
          ? (_providers[provider]?.name ?? provider)
          : 'Your account';
      final org = widget.cloudConnectOrg == 'enabled';
      // 2.21.0 — a re-authorisation is not a new connection. Saying "connected"
      // for a routine token refresh is wrong, and auto-opening the import
      // picker on every rotation nags: that prompt is for a library GAINING a
      // source. Open vocabulary, so anything unrecognised takes the new-connect
      // path rather than falling into silence.
      final reconnected = widget.cloudConnectConnection == 'reconnected';
      AppToast.show(
        context,
        reconnected
            ? '$name was already connected — sign-in refreshed, nothing else changed.'
            : org
                ? '$name connected — auto-organization enabled.'
                : '$name connected.',
        type: ToastType.success,
      );
      if (provider != null && !reconnected) {
        await cloud.openPicker(provider); // auto-open the import picker
      }
    } else {
      setState(() => _errorBanner = _reasonCopy(widget.cloudConnectReason));
    }
    if (!mounted) return;
    // Strip the params (equivalent of history.replaceState).
    context.go('/sources');
  }

  // Open vocabulary — unknown reasons fall through to generic copy.
  String _reasonCopy(String? reason) {
    switch (reason) {
      case 'invalid_state':
        return "Connection couldn't be verified. Please try connecting again.";
      case 'missing_params':
        return 'The provider returned an incomplete response. Please try again.';
      case 'insufficient_scope':
        return 'Not enough permissions were granted. Reconnect and accept the '
            'requested access.';
      case 'access_denied':
        return 'The connection was cancelled.';
      default:
        return "Couldn't finish connecting. Please try again.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CloudNotifier, DocumentsNotifier>(
      builder: (context, cloud, docs, _) {
        final volumes = docs.complete;
        final passages =
            volumes.fold<int>(0, (n, d) => n + (d.chunkCount ?? 0));

        return KitPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChapterOpening(
                // UNREAD IS NOT ZERO (§8, ADR-109). Both figures are derived
                // from a subscription that may have failed, and `0 volumes ·
                // Nothing indexed yet` is the most consequential wrong
                // sentence this screen can say to someone who has added
                // things. A figure whose signal has not been read is not
                // drawn; the §14 block below says why.
                folio: docs.error != null
                    ? null
                    : _plural(volumes.length, 'volume'),
                // `Library`, as the reference titles it (§Composition
                // Header). The rail calls this screen Library; a title that
                // says something else is a second name for one place.
                title: 'Library',
                // Both figures come from the subscription already loaded, so
                // the standfirst costs no extra read — and it states what is
                // measured, not what would be impressive.
                standfirst: docs.error != null
                    ? null
                    : volumes.isEmpty
                        ? 'Nothing indexed yet. Add a file or connect a '
                            'service, and the passages start arriving within '
                            'a minute.'
                        : '${_count(passages)} passages, indexed and '
                            'searchable — add a volume, or connect a service.',
              ),

              // §14.1 for the subscription every figure on this screen is
              // derived from (C2, INV-24).
              if (docs.error != null)
                KitFailureBlock(
                  sentence: 'Your sources could not be loaded.',
                  detail: docs.error!,
                  onRetry: () => context.read<DocumentsNotifier>().refresh(),
                ),

              if (_errorBanner != null)
                _Banner(
                  icon: Icons.error_outline,
                  text: _errorBanner!,
                  onDismiss: () => setState(() => _errorBanner = null),
                ),

              // ── Add to your library ────────────────────────────────────
              SectionHeader(
                'Add to your library',
                first: true,
                actionIcon: Icons.help_outline,
                actionLabel: 'What can I add?',
                onAction: () => SourcesInfoSheet.show(context),
              ),
              FileUploader(
                key: _uploader,
                onUploadComplete: () => AppToast.show(
                    context, 'Queued for processing.',
                    type: ToastType.success),
                onUploadError: (msg) =>
                    AppToast.show(context, msg, type: ToastType.error),
              ),
              // §Document processing, directly under the zone and the link
              // row — where a dropped source lands.
              const ProcessingSection(),

              // ── Connect a service ──────────────────────────────────────
              const SectionHeader('Connect a service'),

              // A card's whole meaning is whether that service is connected,
              // and an unread list answers "no" for all of them (C4). The
              // cards are withheld rather than drawn wrong: inviting someone
              // to connect a service they are already connected to is not a
              // missing notice, it is an instruction to re-run OAuth.
              if (cloud.integrationsError != null &&
                  !cloud.integrationsLoaded)
                KitFailureBlock(
                  sentence: 'Your connected services could not be read.',
                  detail: cloud.integrationsError!,
                  onRetry: () =>
                      context.read<CloudNotifier>().loadIntegrations(),
                )
              else ...[
                // A read that failed AFTER one succeeded keeps its cards —
                // they were true a moment ago — with the notice above them.
                if (cloud.integrationsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: KitFailureInline(cloud.integrationsError!),
                  ),
                KitCardGrid(
                  children: [
                    for (final e in _providers.entries)
                      _ProviderCard(
                        providerId: e.key,
                        spec: e.value,
                        integration: cloud.integrationFor(e.key),
                      ),
                  ],
                ),
              ],

              // What the last disconnect did at the provider — a standing
              // note, not a toast (4.89.0, ADR-123 §5).
              if (cloud.lastDisconnect != null)
                KitProcNote(disconnectOutcome(
                  cloud.lastDisconnect!.$1,
                  _providers[cloud.lastDisconnect!.$1]?.name ??
                      cloud.lastDisconnect!.$1,
                  cloud.lastDisconnect!.$2,
                )),

              // One block per connected provider, under its own §3 header
              // ("Import from {provider}", web `CloudImportPanel`): Sync now,
              // Sync settings and Browse files…, the sync sentence, the
              // reconnect banner and the picker. They hung inside the connect
              // card until the 2026-10-08 ruling made the card fixed — a form
              // inside a quarter-width card is a form nobody can use.
              for (final e in _providers.entries)
                if (cloud.integrationFor(e.key) != null)
                  _ImportFromProvider(
                    providerId: e.key,
                    spec: e.value,
                    integration: cloud.integrationFor(e.key)!,
                  ),

              // What the last triage batch did that the rows cannot say.
              // HERE and not inside the queue: dismissing the last held file
              // unmounts that section, and a line about what just happened
              // would vanish with the thing it is about.
              if (cloud.reviewOutcome != null)
                ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
              ImportReviewQueue(
                held: cloud.heldJobs,
                rulesFor: (p) =>
                    cloud.integrationFor(p)?.reviewRules ?? const {},
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
              const OrganizationSettingsPanel(),
              const _OrganizationSection(),

              // ── In your library ────────────────────────────────────────
              BrowseSection(
                onAddFile: () => _uploader.currentState?.pickFiles(),
                onAddLink: () => _uploader.currentState?.revealLinkField(),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Connect card ─────────────────────────────────────────────────────────────

/// One cell of the connect grid: the fixed §5.1 card (web `ConnectCard`) and,
/// under it, a connect that failed (§14.2, web `.connect-fail`).
///
/// The card is the affordance: connect when not connected, and the §18
/// disconnect confirm when connected. Everything a connected provider can DO
/// lives under its "Import from" header ([_ImportFromProvider]).
class _ProviderCard extends StatefulWidget {
  final String providerId;
  final ({String name, String sub, IconData icon}) spec;
  final CloudIntegration? integration;

  const _ProviderCard({
    required this.providerId,
    required this.spec,
    required this.integration,
  });

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _connecting = false;

  /// The connect's refusal, said under the card that was pressed — not a
  /// toast that is gone before it is read.
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
    // under the grid (`lastDisconnect`), never as a toast.
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
    final spec = widget.spec;
    final integration = widget.integration;
    final connected = integration != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        KitConnectCard(
          icon: spec.icon,
          title: spec.name,
          // §5.1: the account when connected, the invitation when not.
          subtitle: !connected
              ? spec.sub
              : (integration.providerEmail ?? integration.lastSyncLabel),
          // The reference's three words. A connection whose sign-in expired
          // is still connected — its reconnect banner is under its "Import
          // from" header, where Reconnect is.
          status: _connecting
              ? 'Connecting…'
              : connected
                  ? 'Connected'
                  : 'Connect',
          connected: connected,
          onTap: _connecting ? null : (connected ? _disconnect : _connect),
        ),
        if (_connectFail != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: KitFailureInline(_connectFail!, dense: true),
          ),
      ],
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
                  Icon(widget.spec.icon, size: 14, color: t.fgMuted),
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

// ── Import activity ──────────────────────────────────────────────────────────

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
          const SectionHeader('Import activity'),
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
          error != null || jobs.isEmpty
              ? 'Import activity'
              : 'Import activity · ${jobs.length}',
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
        if (jobs.isNotEmpty)
          KitRowList(rows: [for (final j in jobs) _JobRow(key: ValueKey(j.id), job: j)]),
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
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_months[e.key.month - 1]} ${e.key.day}, ${e.key.year}',
                      style: KitText.meta(context),
                    ),
                  ),
                  Flexible(
                    child: Text(_daySummary(e.value),
                        textAlign: TextAlign.right,
                        style: KitText.meta(context)),
                  ),
                ],
              ),
            ),
            KitRowList(rows: [for (final j in e.value) _JobRow(key: ValueKey(j.id), job: j)]),
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

    final row = KitSourceRow(
      // The plate is the FILE's kind, from its MIME through the one kind
      // table. A hardcoded `web` plate said every imported PDF was a page.
      leading: KitFileBadge(kitDocKind(job.docType)),
      title: job.providerFileName.isEmpty
          ? '(fetching name…)'
          : job.providerFileName,
      subtitle: [
        label,
        if (job.providerPath.isNotEmpty) job.providerPath,
        // The failure reason is shown verbatim; a skipped job's reason is what
        // makes a skip a fact rather than a shrug. Not for a duplicate or a
        // dismissal: their `error_message` IS the status word above, and the
        // row said it twice.
        if (job.errorMessage != null && !job.isDuplicate && !job.isDismissed)
          job.errorMessage!,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job.isDuplicate && job.documentId != null)
            KitButton.ghost('View',
                onPressed: () => context.go('/reader/${job.documentId}')),
          // `canRetry` is the whole rule: error/cancelled retry, and of the
          // skips only duplicate · dismissed · plan_limit import again. A
          // size-cap skip would skip identically; a legacy skip is action-less.
          if (job.canRetry)
            KitButton.ghost(
                _busy
                    ? 'Retrying…'
                    : job.isImportAgain
                        ? 'Import again'
                        : 'Retry',
                wait: _busy ? 0 : retryWait.left,
                onPressed: _busy ? null : _retry),
          // A kept refresh (skipped · document_complete | document_unchanged,
          // with its document): no Retry — it would mint a second document —
          // and the sentence names this control.
          if (job.canUpdateFromSource)
            KitButton.ghost(_updating ? 'Queuing…' : 'Update from source',
                wait: _updating ? 0 : updateWait.left,
                onPressed: _updating ? null : _update),
          if (tone != null) ...[
            const SizedBox(width: 4),
            Icon(tone.$1, size: 16, color: tone.$2),
          ],
        ],
      ),
    );
    // Each control's one slot: its cooldown as the calm caption, the cap or
    // any other refusal as §14.2 (sources.md §Trust & feedback, 4.108.0 —
    // `retry_after_s` decides).
    final slots = [
      ?kitRefusalSlot(retryWait, _retryError, dense: true),
      ?kitRefusalSlot(updateWait, _updateError, dense: true),
    ];
    if (slots.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final w in slots)
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
            child: w,
          ),
      ],
    );
  }

  /// The row's status word, and the icon that carries its tone. **A skipped job
  /// is muted, never failure-styled** — it is a correct outcome, and the row
  /// exists so that outcome is visible rather than silent.
  (String, (IconData, Color)?) _status(ImportJob j, Tokens t) {
    switch (j.status) {
      // 4.45.0 (ADR-083) — **held, waiting on the user.** Attention styling,
      // never failure styling, and **never omitted**: a status the pill map
      // does not list drops the row out of the section entirely, which is how
      // a file waiting on a judgement becomes a file that silently is not
      // there. This client rendered six of nine and had no `awaiting_review`
      // at all until now.
      case 'awaiting_review':
        return ('Waiting for you', (Icons.pause_circle_outline, t.accentText));
      case 'complete':
        return ('Imported', (Icons.check_circle_outline, t.positive));
      case 'error':
        return ('Failed', (Icons.error_outline, t.criticalText));
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
          (Icons.remove_circle_outline, t.fgSubtle)
        );
      case 'cancelled':
        return ('Cancelled', (Icons.remove_circle_outline, t.fgSubtle));
      // Named, not left to the default branch (`job_status_check` reported
      // both as MIRROR-GAP): `queued` read "Waiting" here and "Queued" on the
      // reference, and a status the switch never names is one nobody decided.
      case 'pending':
        return ('Waiting', null);
      case 'queued':
        return ('Queued', null);
      case 'downloading':
        return ('Downloading', null);
      case 'processing':
        return ('Processing', null);
      default:
        // A status this client does not know yet: the reference draws it as
        // `pending` does, and never as its raw token.
        return ('Waiting', null);
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
      eyebrow: 'Organization suggestions',
      suggestions: org.suggestions,
      error: org.suggestionsError,
    );
  }
}

// ── Shared banner ────────────────────────────────────────────────────────────

/// The warning banner — an OAuth return that failed, or a connection that needs
/// reauthorising. Always `--critical` at a token alpha: this is the one shape
/// on the screen that exists to interrupt, and a second, quieter tone would
/// make the reader classify it before reading it.
class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  final VoidCallback? onDismiss;

  const _Banner({
    required this.icon,
    required this.text,
    this.action,
    this.onDismiss,
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
          if (onDismiss != null)
            KitIconButton(Icons.close, tooltip: 'Dismiss', onPressed: onDismiss),
        ],
      ),
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────────

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Thousands separators, so a five-figure passage count is readable.
String _count(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

