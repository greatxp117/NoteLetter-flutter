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
import 'sources/organization_settings_panel.dart';
import 'sources/sync_settings_panel.dart';

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
                title: 'Your *library*',
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
              const SectionHeader('Add to your library', first: true),
              FileUploader(
                key: _uploader,
                onUploadComplete: () => AppToast.show(
                    context, 'Queued for processing.',
                    type: ToastType.success),
                onUploadError: (msg) =>
                    AppToast.show(context, msg, type: ToastType.error),
              ),

              // ── Connect a service ──────────────────────────────────────
              const SectionHeader('Connect a service'),
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

              _ReviewQueue(held: cloud.heldJobs),
              _ImportActivity(jobs: cloud.jobs),
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

class _ProviderCard extends StatelessWidget {
  final String providerId;
  final ({String name, String sub, IconData icon}) spec;
  final CloudIntegration? integration;

  const _ProviderCard({
    required this.providerId,
    required this.spec,
    required this.integration,
  });

  @override
  Widget build(BuildContext context) {
    final cloud = context.read<CloudNotifier>();
    final connected = integration != null;
    final needsReconnect = integration?.needsReconnect ?? false;

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
          : (integration!.providerEmail ?? integration!.lastSyncLabel),
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
          KitButton.ghost('Sync now', icon: Icons.sync, onPressed: () async {
            final (msg, isErr) = await cloud.syncNow(providerId);
            if (!context.mounted) return;
            AppToast.show(context, msg,
                type: isErr ? ToastType.error : ToastType.success);
          }),
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
          KitButton.ghost('Disconnect', onPressed: () async {
            final done = await KitConfirm.show(
              context,
              title: 'Disconnect ${spec.name}?',
              body: 'Any imports still queued from ${spec.name} stop, the '
                  'folders it organized are archived, and its suggestions '
                  'expire.\n\nEverything already in your library stays — '
                  'documents, passages and letters are unaffected, and the '
                  'files in ${spec.name} itself are never touched. '
                  'Reconnecting starts a fresh pick of folders.',
              confirmLabel: 'Disconnect',
              cancelLabel: 'Stay connected',
              onConfirm: () => cloud.disconnect(providerId),
            );
            if (done == true && context.mounted) {
              AppToast.show(context, '${spec.name} disconnected.',
                  type: ToastType.info);
            }
          }),
        ],
      ],
    );
  }
}

// ── File picker ──────────────────────────────────────────────────────────────

class _PickerPanel extends StatelessWidget {
  const _PickerPanel();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = context.watch<CloudNotifier>();
    final listing = cloud.listing;
    final provider = cloud.browseProvider;

    return KitCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Import from ${_providers[provider]?.name ?? provider}',
                  style: KitText.h4(context),
                ),
              ),
              KitIconButton(Icons.close,
                  tooltip: 'Close', onPressed: cloud.closePicker),
            ],
          ),
          const SizedBox(height: 6),

          // Breadcrumb.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < cloud.crumbs.length; i++) ...[
                if (i > 0)
                  Icon(Icons.chevron_right, size: 15, color: t.fgSubtle),
                GestureDetector(
                  onTap: i == cloud.crumbs.length - 1
                      ? null
                      : () => cloud.jumpToCrumb(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Text(
                      cloud.crumbs[i].label.toUpperCase(),
                      style: KitText.capsLabel(context,
                          fontSize: 10.5,
                          letterSpacing: 0.13,
                          color: i == cloud.crumbs.length - 1
                              ? t.fg
                              : t.fgSubtle),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          if (cloud.browsing)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cloud.browseError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(cloud.browseError!,
                  style: KitText.meta(context).copyWith(color: t.criticalText)),
            )
          else if (listing == null || listing.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('This folder is empty.',
                  style: KitText.lede(context, fontSize: 15, height: 22)),
            )
          else
            KitRowList(
              rows: [
                for (final f in listing.items) _FileRow(file: f),
              ],
            ),

          if (listing?.nextPageToken != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: KitButton.ghost(
                    cloud.loadingMore ? 'Loading…' : 'Load more',
                    onPressed: cloud.loadingMore ? null : cloud.loadMore),
              ),
            ),

          const SizedBox(height: 12),
          Container(height: 1, color: t.rule),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  // The caps are `fn_import_from_cloud`'s own (≤20 folders,
                  // ≤50 files) and the picker is what enforces them.
                  '${cloud.selectedFolders.length}/$kMaxImportFolders folders · '
                  '${cloud.selectedFiles.length}/$kMaxImportFiles files',
                  style: KitText.meta(context),
                ),
              ),
              KitButton.primary('Import selected',
                  onPressed: cloud.hasSelection
                      ? () async {
                          final (msg, isErr) = await cloud.importSelection();
                          if (!context.mounted) return;
                          AppToast.show(context, msg,
                              type: isErr
                                  ? ToastType.error
                                  : ToastType.success);
                        }
                      : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final CloudFile file;
  const _FileRow({required this.file});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = context.read<CloudNotifier>();
    final selected = file.isFolder
        ? cloud.selectedFolders.contains(file.id)
        : cloud.selectedFiles.contains(file.id);

    void toggle() {
      final note = file.isFolder
          ? cloud.toggleFolder(file.id)
          : cloud.toggleFile(file.id);
      // At a cap, further toggles no-op WITH an explanation — a control that
      // silently does nothing reads as broken.
      if (note != null && context.mounted) {
        AppToast.show(context, note, type: ToastType.info);
      }
    }

    return KitSourceRow(
      leading: SizedBox(
        width: 36,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: selected,
                onChanged: (_) => toggle(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              file.isFolder
                  ? Icons.folder_outlined
                  : Icons.insert_drive_file_outlined,
              size: 16,
              color: t.fgMuted,
            ),
          ],
        ),
      ),
      title: file.name,
      // Google Docs and the like export as PDF; say so on the row that will do
      // it rather than in a legend nobody reads.
      subtitle: file.exportable ? 'Exports as PDF' : null,
      onTap: file.isFolder ? () => cloud.enterFolder(file) : toggle,
      trailing: file.isFolder
          ? Icon(Icons.chevron_right, size: 17, color: t.fgSubtle)
          : null,
    );
  }
}

// ── Import activity ──────────────────────────────────────────────────────────

class _ImportActivity extends StatelessWidget {
  final List<ImportJob> jobs;
  const _ImportActivity({required this.jobs});

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Import activity · ${jobs.length}'),
        KitRowList(
          rows: [for (final j in jobs) _JobRow(job: j)],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            // The subscription is capped at 50, so the list is a window and is
            // labelled as one rather than paginated.
            'Showing the 50 most recent import jobs.',
            style: KitText.meta(context),
          ),
        ),
      ],
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
  const _ReviewQueue({required this.held});

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
          rows: [for (final j in held) _HeldRow(job: j, onRun: _run)],
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
  final Future<void> Function(List<String> ids, String action) onRun;

  const _HeldRow({required this.job, required this.onRun});

  /// "PDF · 42 MB — over your 5 MB review size" / "PPTX — you asked about
  /// every one". **Named by size, never by length**: there is no page count to
  /// promise, because no provider reports one (ADR-083).
  String _reason() {
    final kind = job.mimeType.isEmpty
        ? ''
        : kitDocKind(job.mimeType).toUpperCase();
    final size = job.fileSize > 0
        ? '${(job.fileSize / (1024 * 1024)).toStringAsFixed(job.fileSize >= 10 * 1024 * 1024 ? 0 : 1)} MB'
        : '';
    final head = [if (kind.isNotEmpty) kind, if (size.isNotEmpty) size]
        .join(' · ');
    final why = job.reviewReason == 'type'
        ? 'you asked about every one'
        : 'over your review size';
    return head.isEmpty ? why : '$head — $why';
  }

  @override
  Widget build(BuildContext context) {
    return KitSourceRow(
      leading: const KitFileBadge('web'),
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

class _JobRow extends StatelessWidget {
  final ImportJob job;
  const _JobRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = context.read<CloudNotifier>();
    final (label, tone) = _status(job, t);

    return KitSourceRow(
      // The plate says where a source came from; an import job is a file
      // fetched from a service, so it takes the web plate.
      leading: const KitFileBadge('web'),
      title: job.providerFileName.isEmpty
          ? '(fetching name…)'
          : job.providerFileName,
      subtitle: [
        label,
        if (job.providerPath.isNotEmpty) job.providerPath,
        // The failure reason is shown verbatim; a skipped job's reason is what
        // makes "Already imported" a fact rather than a shrug.
        if (job.errorMessage != null) job.errorMessage!,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job.isDuplicate && job.documentId != null)
            KitButton.ghost('View',
                onPressed: () => context.go('/reader/${job.documentId}')),
          // A size-cap skip gets NO retry: it would skip identically.
          if (job.canRetry && !job.isSizeLimited)
            KitButton.ghost(job.isDuplicate ? 'Import again' : 'Retry',
                onPressed: () async {
              final err = await cloud.retryJob(job.id);
              if (context.mounted && err != null) {
                AppToast.show(context, err, type: ToastType.error);
              }
            }),
          if (tone != null) ...[
            const SizedBox(width: 4),
            Icon(tone.$1, size: 16, color: tone.$2),
          ],
        ],
      ),
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
      case 'downloading':
        return ('Downloading', null);
      case 'processing':
        return ('Processing', null);
      default:
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
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Organization suggestions · ${pending.length}'),
        for (final s in pending) _SuggestionCard(suggestion: s),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final OrganizationSuggestion suggestion;
  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final org = context.read<OrgNotifier>();
    final busy = org.isResolving(suggestion.id);

    Future<void> act(String action) async {
      final err = await org.resolve([suggestion.id], action);
      if (context.mounted && err != null) {
        AppToast.show(context, err, type: ToastType.error);
      }
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
