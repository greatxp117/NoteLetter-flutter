import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/import_job.dart';
import '../models/organization_suggestion.dart';
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
import 'sources/organization_settings_panel.dart';
import 'sources/sources_info_sheet.dart';
import 'sources/sync_settings_panel.dart';
import 'reader/supersession_confirm.dart';

/// Canonical provider ids (1.2.0) with display names for not-yet-connected
/// providers (the integration list only carries connected ones). The ids are
/// exactly the backend provider strings — earlier web builds passed `gdrive`
/// and got a 400.
const _providers = <String, ({String name, String sub, IconData icon})>{
  'google_drive': (
    name: 'Google Drive',
    sub: 'Docs, PDFs, slides',
    icon: Icons.add_to_drive_outlined
  ),
  'onedrive': (
    name: 'OneDrive',
    sub: 'Files & folders',
    icon: Icons.cloud_outlined
  ),
  'notion': (
    name: 'Notion',
    sub: 'Pages & databases',
    icon: Icons.article_outlined
  ),
  'dropbox': (
    name: 'Dropbox',
    sub: 'Files & folders',
    icon: Icons.inventory_2_outlined
  ),
};

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

              if (cloud.browseProvider != null) ...[
                const SizedBox(height: 14),
                const _PickerPanel(),
              ],

              // Sync settings hang BELOW the grid, one per connected provider:
              // a form inside a card that is a quarter of the width is a form
              // nobody can use, and the grid is four across by contract.
              for (final e in _providers.entries)
                if (cloud.integrationFor(e.key) != null &&
                    !(cloud.integrationFor(e.key)!.needsReconnect))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SyncSettingsPanel(
                      providerId: e.key,
                      integration: cloud.integrationFor(e.key)!,
                    ),
                  ),

              // What the last triage batch did that the rows cannot say.
              // HERE and not inside the queue: dismissing the last held file
              // unmounts that section, and a line about what just happened
              // would vanish with the thing it is about.
              if (cloud.reviewOutcome != null)
                _ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
              _ReviewQueue(
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
  /// Sync now in flight, and the sentence it came back with — a 429 cooldown
  /// (a wait, drawn as a note) or a refusal (§14.2) — inline on the card, as
  /// §Sync control requires, never a toast that is gone before it is read.
  bool _syncing = false;
  String? _syncNote;
  bool _syncRefused = false;

  /// The server's own 400 sentence for a provider with no sync folders
  /// (`fn_request_cloud_sync`). The button is disabled on the same condition,
  /// and the reason is VISIBLE — a disabled control with no reason reads as
  /// broken, and a tooltip reaches neither a finger nor a screen reader.
  static const _noFolders = 'Nothing to sync — choose sync folders first.';

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncNote = null;
    });
    final (msg, result) =
        await context.read<CloudNotifier>().syncNow(widget.providerId);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncNote = result == SyncNowResult.queued ? null : msg;
      _syncRefused = result == SyncNowResult.refused;
    });
    if (result == SyncNowResult.queued) {
      AppToast.show(context, msg, type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerId = widget.providerId;
    final spec = widget.spec;
    final integration = widget.integration;
    final cloud = context.read<CloudNotifier>();
    final connected = integration != null;
    final needsReconnect = integration?.needsReconnect ?? false;
    final noFolders = connected && integration.folderIds.isEmpty;

    Future<void> run(Future<String?> Function() action, {String? okMsg}) async {
      final err = await action();
      if (!context.mounted) return;
      if (err != null) {
        AppToast.show(context, err, type: ToastType.error);
      } else if (okMsg != null) {
        AppToast.show(context, okMsg, type: ToastType.success);
      }
    }

    return KitConnectCard(
      icon: spec.icon,
      title: spec.name,
      subtitle: !connected
          ? spec.sub
          : (integration.providerEmail ?? integration.lastSyncLabel),
      status: needsReconnect
          ? 'Reconnect'
          : connected
              ? 'Connected'
              : 'Not connected',
      connected: connected && !needsReconnect,
      onTap: connected ? null : () => run(() => cloud.connect(providerId)),
      // Reconnect banner (1.3.0) — its own copy from `status_reason`, and
      // browsing stays unavailable while flagged.
      notice: needsReconnect
          ? _Banner(
              icon: Icons.link_off,
              text: integration!.statusReason ??
                  'This connection expired — reconnect to keep importing.',
              action: KitButton.ghost('Reconnect',
                  onPressed: () => run(() => cloud.connect(providerId))),
            )
          : null,
      actions: [
        if (!connected)
          KitButton.primary('Connect',
              onPressed: () => run(() => cloud.connect(providerId)))
        else if (!needsReconnect) ...[
          KitButton.ghost('Browse files…',
              icon: Icons.folder_open,
              onPressed: () => cloud.openPicker(providerId)),
          KitButton.ghost(_syncing ? 'Syncing…' : 'Sync now',
              icon: Icons.sync,
              onPressed: _syncing || noFolders ? null : _syncNow),
          // Auto-organization enable (1.2.0) — requests write scopes via OAuth;
          // returns to /sources with org=enabled on a full grant.
          Builder(builder: (context) {
            final org = context.watch<OrgNotifier>();
            if (org.settings.configFor(providerId).enabled) {
              return const KitStatusPill('Auto-organization on', positive: true);
            }
            return KitButton.ghost('Enable auto-organization',
                icon: Icons.auto_awesome_outlined,
                onPressed: () => run(() => org.enableOrganization(providerId)));
          }),
          // §18 Confirmation (4.56.0, ADR-092). `screens/settings.md` has
          // required this since 1.2.0 and named the copy it owes; it ran on the
          // first tap. `disconnect` already returns null-or-the-sentence, which
          // is §18's contract with the panel.
          //
          // 4.90.0 (ADR-124 §7): only imports that have not reached the
          // pipeline stop — a file already downloaded finishes. 4.89.0
          // (ADR-123 §5): the grant is ASKED to be revoked where the provider
          // lets an app do that, and where it does not the confirm says where
          // the reader removes it. What the provider answered is said AFTER,
          // under the grid (`lastDisconnect`), never as a toast: "did not
          // confirm" is a thing to act on, and a toast is gone first.
          KitButton.ghost('Disconnect', onPressed: () async {
            cloud.clearDisconnectNote();
            final revoke = disconnectRevokeCopy(providerId, spec.name);
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
              onConfirm: () => cloud.disconnect(providerId),
            );
          }),
        ],
      ],
      footnote: !connected || needsReconnect
          ? null
          : _syncNote != null
              ? (_syncRefused
                  ? KitFailureInline(_syncNote!, dense: true)
                  : Text(_syncNote!, style: KitText.meta(context)))
              : noFolders
                  ? Text(_noFolders, style: KitText.meta(context))
                  : null,
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
      _fmtSize(file.size),
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

/// A triage batch's partial outcome (4.69.0, ADR-103 §4 amended). Two lines
/// that must never merge: `skipped` is a measured count and a note — nothing
/// failed — while `failed` is §14.2 inline, naming the FILE, because the
/// retry is per-row and the reader has to find it. It sits beside the note,
/// never in place of the section: what the batch did do is real.
class _ReviewOutcomeNotes extends StatelessWidget {
  final ReviewOutcome outcome;
  const _ReviewOutcomeNotes({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    final skipped = o.skipped;
    final failed = o.failedNames;
    final rest = o.notAttempted;
    if (skipped == 0 && failed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4.90.0 (ADR-124 §7): an approve on a provider that is no longer
          // connected is `skipped` too, and the response does not say which —
          // so the note names both causes and asserts neither.
          if (skipped > 0)
            KitProcNote(reviewSkippedNote(skipped), padding: EdgeInsets.zero),
          if (failed.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: skipped > 0 ? 6 : 0),
              child: KitFailureInline(
                'Could not start ${failed.join(', ')} — the import queue did '
                'not accept ${failed.length == 1 ? 'it' : 'them'}. Retry from '
                'the list below.'
                '${rest > 0 ? ' $rest other ${rest == 1 ? 'file is' : 'files are'} '
                    'still waiting for review — nothing was started for '
                    '${rest == 1 ? 'it' : 'them'}.' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}

/// **The import review queue** (`screens/sources.md` §Import review queue,
/// 4.45.0, ADR-083) — the files a sync held because the reader asked to be
/// asked. Above the progress list, because it is the one thing here that is
/// waiting on them.
///
/// **Empty is not a state worth drawing.** With no rules configured the section
/// never renders; with rules configured and nothing held, it stays absent too.
/// "Nothing waiting" is the normal condition, not an achievement.
///
/// Every action renders **pessimistically** off the subscription — nothing
/// moves here until the write lands. A control that moves first hides the
/// failure completely, and this one acts on files that may be scrolled out of
/// sight.
class _ReviewQueue extends StatefulWidget {
  final List<ImportJob> held;

  /// The provider's `review_rules`, so a size hold can name its threshold.
  final Map<String, ReviewRule> Function(String provider) rulesFor;
  const _ReviewQueue({required this.held, required this.rulesFor});

  @override
  State<_ReviewQueue> createState() => _ReviewQueueState();
}

class _ReviewQueueState extends State<_ReviewQueue> {
  /// §14.2 — one slot for the section's own rejection. One outstanding batch at
  /// a time, so one slot.
  String? _error;
  bool _busy = false;

  Future<void> _run(List<String> ids, String action) async {
    if (ids.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<CloudNotifier>().reviewJobs(ids, action);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final held = widget.held;
    if (held.isEmpty) return const SizedBox.shrink();
    final ids = [for (final j in held) j.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '${held.length} ${held.length == 1 ? 'file' : 'files'} waiting for you',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            KitButton.primary('Import all',
                onPressed: _busy ? null : () => _run(ids, 'approve')),
            // §18 on **"Dismiss all" only**, and the asymmetry is the decision
            // rather than an omission: a reader dismissing one row has just
            // read that row, while this control acts on files that may be
            // scrolled out of sight. Both are undoable from Import history, so
            // a panel on every row would make a triage queue slower without
            // making anything safer.
            KitButton.ghost('Dismiss all', onPressed: _busy
                ? null
                : () async {
                    final done = await KitConfirm.show(
                      context,
                      title: 'Dismiss ${held.length} '
                          '${held.length == 1 ? 'file' : 'files'}?',
                      body: 'They will not be offered again, even if they '
                          'change at the provider. Nothing is deleted where it '
                          'lives. You can undo this with Import again on the '
                          'dismissed row in your import history.',
                      confirmLabel: 'Dismiss them',
                      cancelLabel: 'Keep waiting',
                      onConfirm: () => context
                          .read<CloudNotifier>()
                          .reviewJobs(ids, 'dismiss'),
                    );
                    if (done == true && mounted) setState(() => _error = null);
                  }),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          KitFailureInline(_error!),
        ],
        const SizedBox(height: 10),
        KitRowList(
          rows: [
            for (final j in held)
              _HeldRow(
                  job: j, rules: widget.rulesFor(j.provider), onRun: _run),
          ],
        ),
        // The standing sentence the per-row control keeps above the list, so a
        // single Dismiss is not silent about being permanent.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Dismissing a file means it will not be offered again, even if it '
            'changes at the provider. Import again on the dismissed row undoes '
            'it.',
            style: KitText.meta(context),
          ),
        ),
      ],
    );
  }
}

/// A held row: the progress-row anatomy, plus the **size** and the **reason**.
class _HeldRow extends StatelessWidget {
  final ImportJob job;
  final Map<String, ReviewRule> rules;
  final Future<void> Function(List<String> ids, String action) onRun;

  const _HeldRow({required this.job, required this.rules, required this.onRun});

  /// "PDF · 42 MB — over your 5 MB review size" / "PPTX — you asked about
  /// every one". **Named by size, never by length**: there is no page count to
  /// promise, because no provider reports one (ADR-083).
  ///
  /// The head is the TYPE KEY of the file's MIME, never `kitDocKind(mime)`:
  /// that table is keyed by document `type`, so a MIME fell through to `note`
  /// and every held row read "NOTE · 42 MB". The threshold is the rule's own
  /// number, read off the provider's `review_rules` — "over your review size"
  /// without it asked the reader to remember what they had set.
  String _reason() {
    final key = job.typeKey;
    final kind = key == null ? 'File' : _typeLabel(key);
    final size = _fmtSize(job.fileSize);
    final head = size.isEmpty ? kind : '$kind · $size';
    if (job.reviewReason == 'type') return '$head — you asked about every one';
    final rule = key == null ? null : rules[key];
    return rule != null && !rule.isAlways && rule.overMb != null
        ? '$head — over your ${rule.overMb} MB review size'
        : head;
  }

  @override
  Widget build(BuildContext context) {
    return KitSourceRow(
      leading: KitFileBadge(kitDocKind(job.docType)),
      title: job.providerFileName.isEmpty
          ? '(fetching name…)'
          : job.providerFileName,
      subtitle: [
        _reason(),
        if (job.providerPath.isNotEmpty) job.providerPath,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KitButton.ghost('Import',
              onPressed: () => onRun([job.id], 'approve')),
          const SizedBox(width: 4),
          KitButton.ghost('Dismiss',
              onPressed: () => onRun([job.id], 'dismiss')),
        ],
      ),
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

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _retryError = null;
    });
    final err = await context.read<CloudNotifier>().retryJob(widget.job.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _retryError = err;
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
    );
    if (!mounted) return;
    setState(() {
      _updating = false;
      _updateError =
          res.outcome == SupersessionOutcome.refused ? res.message : null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: _busy ? null : _retry),
          // A kept refresh (skipped · document_complete | document_unchanged,
          // with its document): no Retry — it would mint a second document —
          // and the sentence names this control.
          if (job.canUpdateFromSource)
            KitButton.ghost(_updating ? 'Queuing…' : 'Update from source',
                onPressed: _updating ? null : _update),
          if (tone != null) ...[
            const SizedBox(width: 4),
            Icon(tone.$1, size: 16, color: tone.$2),
          ],
        ],
      ),
    );
    final errors = [?_retryError, ?_updateError];
    if (errors.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final e in errors)
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
            child: KitFailureInline(e, dense: true),
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
    final pending = org.suggestions;
    final error = org.suggestionsError;
    final outcomes = org.outcomes;

    // Same shape as Import activity above, and the notifier's own comment says
    // it: no suggestions and unreadable suggestions are the same empty list
    // downstream, and this section's answer to empty is to vanish (C3).
    if (error != null && pending.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Organization suggestions'),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KitFailureInline(error),
          ),
        ],
      );
    }
    if (pending.isEmpty && outcomes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(error != null
            ? 'Organization suggestions'
            : 'Organization suggestions · ${pending.length}'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error),
          ),
        // What this session's approvals came to (4.92.0, ADR-126): the queue
        // reads `pending` only, so without these an approved card vanished
        // and a `failed` one — an interrupted move that may already have
        // landed — never reached the screen.
        if (outcomes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KitRowList(rows: [
              for (final o in outcomes)
                _ApprovalOutcome(
                    key: ValueKey('outcome-${o.id}'), suggestion: o),
            ]),
          ),
        for (final s in pending)
          _SuggestionCard(key: ValueKey('sugg-${s.id}'), suggestion: s),
      ],
    );
  }
}

/// One approval this session made, until it lands: `approved` works
/// (spinner), `failed` says the worker's sentence verbatim (§14.2) and offers
/// Clear. `applied` never reaches here — the notifier drops it.
class _ApprovalOutcome extends StatelessWidget {
  final OrganizationSuggestion suggestion;
  const _ApprovalOutcome({super.key, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final failed = s.status == 'failed';
    final row = KitSourceRow(
      title: s.outcomeTitle,
      trailing: failed
          ? KitButton.ghost('Clear',
              onPressed: () =>
                  context.read<OrgNotifier>().clearOutcome(s.id))
          : const KitStatusPill('Applying'),
    );
    if (!failed) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
          child: KitFailureInline(
              s.resolutionError ?? 'This change could not be made.',
              dense: true),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  final OrganizationSuggestion suggestion;
  const _SuggestionCard({super.key, required this.suggestion});

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  /// §14.2 — the resolve's refusal on the card it is about (a 400
  /// `UNKNOWN_KEYS`, a 404), not a toast that is gone before it is read.
  String? _error;

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    final org = context.read<OrgNotifier>();
    final busy = org.isResolving(suggestion.id);

    Future<void> act(String action) async {
      setState(() => _error = null);
      final err = await org.resolve([suggestion.id], action);
      if (mounted) setState(() => _error = err);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KitCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(suggestion.title, style: KitText.h4(context))),
                const SizedBox(width: 12),
                KitStatusPill('${(suggestion.confidence * 100).round()}% sure'),
              ],
            ),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(suggestion.reason,
                  style: KitText.lede(context, fontSize: 15, height: 22)),
            ],
            if (suggestion.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(suggestion.detail, style: KitText.meta(context)),
            ],
            // 4.92.0 (ADR-126 §3): approving a README adoption changes the
            // folder's charter and writes nothing at the provider — the card
            // says both, because "Approve" alone reads as a file operation.
            if (suggestion.type == 'readme') ...[
              const SizedBox(height: 4),
              Text(suggestion.adoptionNote, style: KitText.meta(context)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              KitFailureInline(_error!),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (busy) ...[
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                ],
                KitButton.ghost('Decline',
                    onPressed: busy ? null : () => act('decline')),
                const SizedBox(width: 8),
                // Pessimistic: the status transition arrives on the same
                // subscription, so nothing is rendered as done before it lands.
                KitButton.primary('Approve',
                    onPressed: busy ? null : () => act('approve')),
              ],
            ),
          ],
        ),
      ),
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

/// The spelling of a cloud type key on a held row. The spec's own examples
/// ("PDF · 42 MB", "PPTX — …") upper-case the file keys; `notion` is not an
/// acronym, and upper-cased it read "NOTION ·".
String _typeLabel(String key) => switch (key) {
      'notion' => 'Notion page',
      _ => key.toUpperCase(),
    };

/// Bytes as the reference spells them (`fmtSize`): KB under a megabyte —
/// "0.0 MB" is a measured file drawn as nothing.
String _fmtSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes <= 0) return '';
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  }
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}
