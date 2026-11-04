import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_file.dart';
import '../../models/cloud_integration.dart';
import '../../models/import_job.dart';
import '../../shared/cloud_providers.dart';
import '../../shared/cooldown.dart';
import '../../state/cloud_notifier.dart';
import '../../state/documents_notifier.dart';
import '../../state/org_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import 'cloud_imports.dart';
import 'cloud_picker.dart';
import 'cloud_sync_copy.dart';
import 'import_review_queue.dart';
import 'organization_settings_panel.dart';
import 'suggestion_queue.dart';
import 'sync_settings_panel.dart';

/// **A connected service's own page** (5.59.0, ADR-213; `screens/sources.md`
/// §A service's page; web `pages/ServicePage.jsx`): `/sources/{provider}`,
/// what *Manage* opens on the Library. Everything about one service lives
/// here, so the Library says only which services are connected and what is
/// arriving: the D frame, *Contents* and the service's Figures on the sheet,
/// and five numbered sections — *Bring in* · *Sync settings* · *Filing* ·
/// *Import history* · *Connection*.
///
/// A path naming no connected service, or an unknown id, opens the Library in
/// its place. A refused integrations read is §14 on the page with a way to
/// ask again, and is never read as *not connected*. An expired sign-in keeps
/// the page: it is where the reader fixes it.
class ServicePage extends StatefulWidget {
  final String provider;

  const ServicePage({super.key, required this.provider});

  static const sectionIds = ['import', 'sync', 'filing', 'history', 'connection'];
  static const sectionLabels = [
    'Bring in',
    'Sync settings',
    'Filing',
    'Import history',
    'Connection',
  ];

  @override
  State<ServicePage> createState() => _ServicePageState();
}

const _cadence = {
  'hourly': 'Every hour',
  'daily': 'Once a day',
  'weekly': 'Once a week',
};

class _ServicePageState extends State<ServicePage> {
  final KitSections _sec = KitSections(ServicePage.sectionIds);

  /// Left for the Library once — this page stands only for a connected
  /// service. A disconnect from this page has its own way out, which sets
  /// this first.
  bool _left = false;

  String? get _name => cloudProviders[widget.provider]?.name;

  CloudNotifier? _cloud;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _name == null) return;
      // The subscriptions this page reads (INV-02), as the Library starts
      // them — a page opened cold, from a link or Settings, has no Library
      // under it to have done so. `start()` also asks for a fresh
      // integrations read, as web's page does on mount.
      _cloud = context.read<CloudNotifier>()..start();
      _cloud!.completionMessage.addListener(_onSessionComplete);
      context.read<OrgNotifier>().start();
      context.read<DocumentsNotifier>().start();
      context.read<TagsNotifier>().start();
    });
  }

  @override
  void dispose() {
    _cloud?.completionMessage.removeListener(_onSessionComplete);
    super.dispose();
  }

  /// A tracked import settled (sources.md §Completion notifications): said
  /// once, wherever the reader is watching it from.
  void _onSessionComplete() {
    final msg = _cloud?.completionMessage.value;
    if (msg == null || !mounted) return;
    AppToast.show(context, msg, type: ToastType.success);
    _cloud!.completionMessage.value = null;
  }

  void _leave() {
    if (_left) return;
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // `go` replaces the location rather than pushing one: Back does not
      // return to a page that cannot stand.
      if (mounted) context.go('/sources');
    });
  }

  String get _from => '/sources/${widget.provider}';

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final name = _name;
    final back =
        KitDBackControl('Library', onTap: () => context.go('/sources'));
    if (name == null) {
      _leave();
      return const SizedBox.shrink();
    }
    final integration = cloud.integrationFor(widget.provider);
    final readRefused =
        cloud.integrationsError != null && !cloud.integrationsLoaded;
    if (readRefused) {
      return KitDPage(
        back: back,
        folio: '',
        title: name,
        child: KitFailureBlock(
          sentence: 'Your connected accounts could not be read.',
          detail: cloud.integrationsError!,
          onRetry: () => context.read<CloudNotifier>().loadIntegrations(),
        ),
      );
    }
    if (cloud.integrationsLoaded && integration == null) {
      _leave();
      return const SizedBox.shrink();
    }
    if (integration == null) {
      return KitDPage(
        back: back,
        folio: '',
        title: name,
        child: const KitSkeletonLines(
            top: 0,
            lines: [KitSkelLine(0.6), KitSkelLine(1), KitSkelLine(0.4)]),
      );
    }
    final i = integration;
    final email = i.providerEmail;
    final expired = i.needsReconnect;
    final secs = [
      for (var n = 0; n < ServicePage.sectionIds.length; n++)
        KitContentsItem(ServicePage.sectionIds[n], ServicePage.sectionLabels[n]),
    ];
    final facts = <(String, String)>[
      ('Account', (email != null && email.isNotEmpty) ? email : 'Connected'),
      ('Access', i.orgWriteAccess ? 'Read and organize' : 'Read-only'),
      (
        'Auto-sync',
        i.autoSyncEnabled ? (_cadence[i.syncFrequency] ?? 'On') : 'Off'
      ),
      ('Last synced', _synced(i.lastSyncAt)),
    ];
    return KitDPage(
      back: back,
      crumbStacks: true,
      folio: '${expired ? 'Sign-in expired' : 'Connected'}'
          '${(email != null && email.isNotEmpty) ? ' · $email' : ''}',
      title: name,
      stand: 'What comes in from $name, how it stays current, and how to '
          'disconnect.',
      sections: _sec,
      sheet: KitDSheet(
        label: 'Contents',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(items: secs, sections: _sec),
            KitFigures(label: name, rows: facts),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BringIn(
              key: _sec.keyOf('import'),
              provider: widget.provider,
              name: name,
              integration: i,
              from: _from),
          _SyncSection(
              key: _sec.keyOf('sync'),
              provider: widget.provider,
              integration: i),
          _Filing(
              key: _sec.keyOf('filing'),
              provider: widget.provider,
              name: name,
              integration: i),
          KitSecHead(
            key: _sec.keyOf('history'),
            n: 3,
            title: 'Import history',
            actions: [
              if (_historyCount(cloud) > 0)
                KitProcNote(kitCounted(_historyCount(cloud), 'import'),
                    padding: EdgeInsets.zero),
            ],
          ),
          ImportHistorySection(
              provider: widget.provider, name: name, from: _from),
          _Connection(
            key: _sec.keyOf('connection'),
            provider: widget.provider,
            name: name,
            integration: i,
            onLeft: () => _left = true,
          ),
        ],
      ),
    );
  }

  int _historyCount(CloudNotifier cloud) => cloud.historyJobs
      .where((j) => j.provider == widget.provider)
      .length;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `last_sync_at`, or *Never* (web `fmtSynced`).
  static String _synced(int? ms) {
    if (ms == null || ms == 0) return 'Never';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, $h:$m '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ── § I · Bring in ───────────────────────────────────────────────────────────

/// *Bring in* (web `CloudImportPanel` with `provider`): *Browse files…*
/// (*Browse pages…* on Notion; *Close* while open) in the head, the reconnect
/// banner when flagged, the section's line, the picker, then this service's
/// review queue and progress.
class _BringIn extends StatefulWidget {
  final String provider;
  final String name;
  final CloudIntegration integration;
  final String from;

  const _BringIn({
    super.key,
    required this.provider,
    required this.name,
    required this.integration,
    required this.from,
  });

  @override
  State<_BringIn> createState() => _BringInState();
}

class _BringInState extends State<_BringIn> {
  bool _reconnecting = false;
  String? _reconnectFail;

  Future<void> _reconnect() async {
    setState(() {
      _reconnecting = true;
      _reconnectFail = null;
    });
    final err = await context.read<CloudNotifier>().connect(widget.provider);
    if (!mounted) return;
    setState(() {
      _reconnecting = false;
      _reconnectFail = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final i = widget.integration;
    final notion = widget.provider == 'notion';
    final needsReconnect = i.needsReconnect;
    final browsing = cloud.browseProvider == widget.provider;
    final held = [
      for (final j in cloud.heldJobs)
        if (j.provider == widget.provider) j,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSecHead(
          n: 0,
          title: 'Bring in',
          actions: [
            KitSettingLink(
              browsing
                  ? 'Close'
                  : notion
                      ? 'Browse pages…'
                      : 'Browse files…',
              icon: null,
              onTap: needsReconnect
                  ? null
                  : () => browsing
                      ? cloud.closePicker()
                      : cloud.openPicker(widget.provider),
            ),
          ],
        ),
        if (needsReconnect) ...[
          _Banner(
            icon: Icons.link_off,
            text: '${widget.name} needs to be reconnected — its sign-in '
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
        // What a Notion page brings (5.57.0, ADR-210) — the section's line on
        // Notion, word for word with the reference.
        KitProcNote(
          notion
              ? 'Notion pages keep their headings, lists, tables, pictures and links. A PDF, video or file stored in Notion becomes a link to it there.'
              : 'Choose what belongs in your library. Nothing is copied from '
                  '${widget.name} until you say so.',
          padding: const EdgeInsets.only(bottom: 10),
        ),
        if (browsing && !needsReconnect) const _PickerPanel(),
        if (cloud.reviewOutcome != null)
          ReviewOutcomeNotes(outcome: cloud.reviewOutcome!),
        ImportReviewQueue(
          held: held,
          rulesFor: (p) => cloud.integrationFor(p)?.reviewRules ?? const {},
        ),
        CloudImportActivity(provider: widget.provider, from: widget.from),
      ],
    );
  }
}

// ── § II · Sync settings ─────────────────────────────────────────────────────

/// *Sync settings* (`screens/sources.md` §Sync control): *Sync now* in the
/// head, *Nothing to sync — choose sync folders first.* with none, the wait
/// or refusal it answered, then the panel, open.
class _SyncSection extends StatefulWidget {
  final String provider;
  final CloudIntegration integration;

  const _SyncSection(
      {super.key, required this.provider, required this.integration});

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  bool _syncing = false;
  String? _syncNote;
  bool _syncRefused = false;

  /// The server's own 400 sentence for a provider with no sync folders
  /// (`fn_request_cloud_sync`). Sync now is held on the same condition, and
  /// the reason is VISIBLE — a tooltip reaches neither a finger nor a screen
  /// reader.
  static const _noFolders = 'Nothing to sync — choose sync folders first.';

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncNote = null;
    });
    final (msg, result) =
        await context.read<CloudNotifier>().syncNow(widget.provider);
    if (!mounted) return;
    final waits = result == SyncNowResult.wait &&
        Cooldowns.instance.waiting(WaitKey.cloudSync(widget.provider));
    setState(() {
      _syncing = false;
      _syncNote = waits ? null : msg;
      _syncRefused = result == SyncNowResult.refused;
    });
  }

  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: WaitKey.cloudSync(widget.provider),
        builder: _section,
      );

  Widget _section(BuildContext context, CooldownWait wait) {
    final i = widget.integration;
    final needsReconnect = i.needsReconnect;
    final noFolders = i.folderIds.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSecHead(
          n: 1,
          title: 'Sync settings',
          actions: [
            KitSettingLink(
              _syncing ? 'Syncing…' : 'Sync now',
              icon: null,
              wait: _syncing ? 0 : wait.left,
              onTap: needsReconnect || _syncing || noFolders ? null : _syncNow,
            ),
          ],
        ),
        if (noFolders && !needsReconnect)
          const KitProcNote(_noFolders, padding: EdgeInsets.only(bottom: 4)),
        // A wait is calm copy; a refusal is §14.2; a kickoff says what it
        // started (§6.1, 4.108.0, ADR-145).
        if (wait.sentence != null)
          KitWaitNote(wait.sentence!, padding: const EdgeInsets.only(bottom: 4))
        else if (_syncNote != null)
          _syncRefused
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: KitFailureInline(_syncNote!, dense: true),
                )
              : KitProcNote(_syncNote!,
                  padding: const EdgeInsets.only(bottom: 4)),
        SyncSettingsPanel(
          providerId: widget.provider,
          integration: i,
          embedded: true,
        ),
      ],
    );
  }
}

// ── § III · Filing ───────────────────────────────────────────────────────────

/// *Filing* (`screens/sources.md` §Organized-folders panel): *Organization
/// settings* in the head — drawn whether or not organizing is on, because
/// Settings is where it is turned on — then, with organizing off, the line
/// that says so, else this service's organized folders and its suggestions.
class _Filing extends StatelessWidget {
  final String provider;
  final String name;
  final CloudIntegration integration;

  const _Filing({
    super.key,
    required this.provider,
    required this.name,
    required this.integration,
  });

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgNotifier>();
    final on = integration.orgWriteReady;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSecHead(
          n: 2,
          title: 'Filing',
          actions: [
            KitSettingLink(
              'Organization settings',
              onTap: () => context.go('/settings/sources'),
            ),
          ],
        ),
        if (!on)
          KitProcNote(
            'NoteLetter files what comes in from $name on your shelves as it '
            'reads it. Organizing the folders in $name itself is off.',
            padding: EdgeInsets.zero,
          ),
        // A suggestion from another service waits on that service's page and
        // in For your review, which answers every one.
        SuggestionQueue(
          eyebrow: 'Suggestions',
          suggestions: [
            for (final x in org.suggestions)
              if (x.provider == provider) x,
          ],
          error: org.suggestionsError,
        ),
        if (on) OrganizedFoldersPanel(provider: provider),
      ],
    );
  }
}

// ── § V · Connection ─────────────────────────────────────────────────────────

/// *Connection*: the service's row — its plate, name, account or *Sign-in
/// expired* — and the quiet **Disconnect**, behind the §18 confirm. On
/// success the page leaves for the Library, whose notice says what the
/// provider answered (`disconnectOutcome`); a refusal stays in the confirm's
/// failure slot.
class _Connection extends StatelessWidget {
  final String provider;
  final String name;
  final CloudIntegration integration;
  final VoidCallback onLeft;

  const _Connection({
    super.key,
    required this.provider,
    required this.name,
    required this.integration,
    required this.onLeft,
  });

  Future<void> _disconnect(BuildContext context) async {
    final cloud = context.read<CloudNotifier>();
    final router = GoRouter.of(context);
    cloud.clearDisconnectNote();
    final revoke = disconnectRevokeCopy(provider, name);
    // §18 Confirmation (4.56.0, ADR-092). 4.90.0 (ADR-124 §7): only imports
    // that have not reached the pipeline stop — a file already downloaded
    // finishes. 4.89.0 (ADR-123 §5): what the provider answered is said AFTER,
    // on the Library (`lastDisconnect`), never as a toast.
    final done = await KitConfirm.show(
      context,
      title: 'Disconnect $name?',
      body: '${disconnectConsequences(name)}'
          '${revoke != null ? '\n\n$revoke' : ''}'
          '\n\nEverything already in your library stays — '
          'documents, passages and letters are unaffected, and the '
          'files in $name itself are never touched. '
          'Reconnecting starts a fresh pick of folders.',
      confirmLabel: 'Disconnect',
      cancelLabel: 'Stay connected',
      onConfirm: () async {
        final err = await cloud.disconnect(provider);
        if (err == null) onLeft();
        return err;
      },
    );
    if (done == true || cloud.integrationFor(provider) == null) {
      onLeft();
      router.go('/sources');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = integration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitSecHead(n: 4, title: 'Connection'),
        KitServiceRow(
          provider: provider,
          name: name,
          account: i.providerEmail,
          connected: true,
          expired: i.needsReconnect,
          action: KitLibAct('Disconnect', onTap: () => _disconnect(context)),
        ),
      ],
    );
  }
}

// ── The import picker ─────────────────────────────────────────────────────

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

  // No File under (5.52.0, ADR-203): what an import brings in is shelved by
  // indexing, as every document is (INV-12). 5.46.0 had a shelf select here.

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
        // What a Notion page brings is §Bring in's own line now, above the
        // picker (5.59.0, ADR-213), as the reference draws it.
        // The folder cap is `fn_import_from_cloud`'s own (≤20) and the picker
        // enforces it; files are uncapped — the import sends them 50 to a
        // request (5.56.0, ADR-208).
        CloudPickerCrumbs(
          labels: [for (final c in crumbs) c.label],
          onJump: cloud.jumpToCrumb,
          counter: '${cloud.selectedFolders.length}/$kMaxImportFolders folders · '
              '${kitCounted(cloud.selectedFiles.length, 'file')}',
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
          // A batched import counts what the 202s accepted (measured, never
          // a timer); one request says only that it is queuing.
          confirmLabel: _saving
              ? (cloud.importSent != null
                  ? 'Queuing… ${cloud.importSent} of '
                      '${kitCounted(cloud.selectedFiles.length, 'file')}'
                  : 'Queuing…')
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
          // §33's Cover lead (5.59.0, ADR-213): the object the file will
          // become, as `_mime_to_source_type` decides (web `mimeSourceType`).
          KitCoverLead(id: file.id, type: mimeSourceType(file.mimeType)),
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

