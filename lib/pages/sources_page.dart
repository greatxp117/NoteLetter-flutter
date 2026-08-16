import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/import_job.dart';
import '../models/organization_suggestion.dart';
import '../state/cloud_notifier.dart';
import '../state/org_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import 'sources/organization_settings_panel.dart';
import 'sources/sync_settings_panel.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

/// Canonical provider ids (1.2.0) with display names for not-yet-connected
/// providers (the integration list only carries connected ones).
const _providers = <String, String>{
  'google_drive': 'Google Drive',
  'onedrive': 'OneDrive',
  'dropbox': 'Dropbox',
  'notion': 'Notion',
};

/// Sources — cloud connect/import/sync + import activity. See
/// spec/screens/sources.md. (Document upload + organized-folders/suggestions
/// panels are separate follow-ups.)
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cloud = context.read<CloudNotifier>();
      _cloud!.start();
      _cloud!.completionMessage.addListener(_onSessionComplete);
      context.read<OrgNotifier>().start();
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
          ? (_providers[provider] ?? provider)
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return Consumer<CloudNotifier>(
      builder: (context, cloud, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sources',
                  style: AppTheme.serif(
                      fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Connect cloud storage and import documents.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              const SizedBox(height: 20),

              if (_errorBanner != null)
                _Banner(
                  icon: Icons.error_outline,
                  color: AppColors.critical,
                  text: _errorBanner!,
                  onDismiss: () => setState(() => _errorBanner = null),
                ),

              // Provider connection cards.
              ..._providers.entries.map((e) {
                final integration = cloud.integrationFor(e.key);
                return _ProviderCard(
                  providerId: e.key,
                  displayName: e.value,
                  integration: integration,
                  muted: muted,
                );
              }),

              const SizedBox(height: 24),

              // Live picker (single provider open at a time).
              if (cloud.browseProvider != null) _PickerPanel(muted: muted),

              const SizedBox(height: 24),
              _ImportActivity(jobs: cloud.jobs, muted: muted),

              const SizedBox(height: 24),
              const OrganizationSettingsPanel(),

              const SizedBox(height: 24),
              _OrganizationSection(muted: muted),
            ],
          ),
        );
      },
    );
  }
}

// ── Provider card ─────────────────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final String providerId;
  final String displayName;
  final CloudIntegration? integration;
  final Color muted;

  const _ProviderCard({
    required this.providerId,
    required this.displayName,
    required this.integration,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final cloud = context.read<CloudNotifier>();
    final connected = integration != null;
    final needsReconnect = integration?.needsReconnect ?? false;

    Future<void> run(Future<String?> Function() action,
        {String? okMsg}) async {
      final err = await action();
      if (!context.mounted) return;
      if (err != null) {
        AppToast.show(context, err, type: ToastType.error);
      } else if (okMsg != null) {
        AppToast.show(context, okMsg, type: ToastType.success);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 20, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      !connected
                          ? 'Not connected'
                          : (integration!.providerEmail ??
                              integration!.lastSyncLabel),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (!connected)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: primary),
                  onPressed: () => run(() => cloud.connect(providerId)),
                  child: const Text('Connect'),
                )
              else
                TextButton(
                  onPressed: () => run(() => cloud.disconnect(providerId),
                      okMsg: '$displayName disconnected.'),
                  child: Text('Disconnect',
                      style: TextStyle(color: AppColors.critical)),
                ),
            ],
          ),

          // Reconnect banner (1.3.0) — browsing disabled while flagged.
          if (needsReconnect) ...[
            const SizedBox(height: 12),
            _Banner(
              icon: Icons.link_off,
              color: AppColors.critical,
              text: integration!.statusReason ??
                  'This connection expired — reconnect to keep importing.',
              action: TextButton(
                onPressed: () => run(() => cloud.connect(providerId)),
                child: const Text('Reconnect'),
              ),
            ),
          ],

          // Import + sync actions (hidden while reconnect is required).
          if (connected && !needsReconnect) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Browse files…'),
                  onPressed: () => cloud.openPicker(providerId),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync now'),
                  onPressed: () async {
                    final (msg, isErr) = await cloud.syncNow(providerId);
                    if (!context.mounted) return;
                    AppToast.show(context, msg,
                        type: isErr ? ToastType.error : ToastType.success);
                  },
                ),
                // Auto-organization enable (1.2.0) — requests write scopes via
                // OAuth; returns to /sources with org=enabled on a full grant.
                Builder(builder: (context) {
                  final org = context.watch<OrgNotifier>();
                  final enabled = org.settings.configFor(providerId).enabled;
                  if (enabled) {
                    return Chip(
                      avatar: Icon(Icons.auto_awesome,
                          size: 14, color: AppColors.positive),
                      label: const Text('Auto-organization on'),
                      visualDensity: VisualDensity.compact,
                    );
                  }
                  return OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('Enable auto-organization'),
                    onPressed: () =>
                        run(() => org.enableOrganization(providerId)),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            SyncSettingsPanel(
                providerId: providerId, integration: integration!),
          ],
        ],
      ),
    );
  }
}

// ── File picker ───────────────────────────────────────────────────────────────

class _PickerPanel extends StatelessWidget {
  final Color muted;
  const _PickerPanel({required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final cloud = context.watch<CloudNotifier>();
    final listing = cloud.listing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Import from ${_providers[cloud.browseProvider] ?? cloud.browseProvider}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Close',
                onPressed: cloud.closePicker,
              ),
            ],
          ),

          // Breadcrumb.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < cloud.crumbs.length; i++) ...[
                if (i > 0)
                  Icon(Icons.chevron_right, size: 16, color: muted),
                InkWell(
                  onTap: i == cloud.crumbs.length - 1
                      ? null
                      : () => cloud.jumpToCrumb(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Text(cloud.crumbs[i].label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: i == cloud.crumbs.length - 1 ? null : primary,
                        )),
                  ),
                ),
              ],
            ],
          ),
          const Divider(),

          if (cloud.browsing)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cloud.browseError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(cloud.browseError!,
                  style: TextStyle(color: AppColors.critical)),
            )
          else if (listing == null || listing.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('This folder is empty.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            )
          else
            ...listing.items.map((f) => _FileRow(file: f, muted: muted)),

          if (listing?.nextPageToken != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: cloud.loadingMore ? null : cloud.loadMore,
                child: Text(cloud.loadingMore ? 'Loading…' : 'Load more'),
              ),
            ),

          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${cloud.selectedFolders.length}/$kMaxImportFolders folders · '
                  '${cloud.selectedFiles.length}/$kMaxImportFiles files',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: primary),
                onPressed: cloud.hasSelection
                    ? () async {
                        final (msg, isErr) = await cloud.importSelection();
                        if (!context.mounted) return;
                        AppToast.show(context, msg,
                            type: isErr
                                ? ToastType.error
                                : ToastType.success);
                      }
                    : null,
                child: const Text('Import selected'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final CloudFile file;
  final Color muted;
  const _FileRow({required this.file, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = context.read<CloudNotifier>();
    final selected = file.isFolder
        ? cloud.selectedFolders.contains(file.id)
        : cloud.selectedFiles.contains(file.id);

    void toggle() {
      final note =
          file.isFolder ? cloud.toggleFolder(file.id) : cloud.toggleFile(file.id);
      if (note != null && context.mounted) {
        AppToast.show(context, note, type: ToastType.info);
      }
    }

    return Row(
      children: [
        Checkbox(value: selected, onChanged: (_) => toggle()),
        Icon(
          file.isFolder
              ? Icons.folder_outlined
              : Icons.insert_drive_file_outlined,
          size: 18,
          color: muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: file.isFolder ? () => cloud.enterFolder(file) : toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(file.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                  ),
                  if (file.exportable)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('→ PDF',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted)),
                    ),
                  if (file.isFolder)
                    Icon(Icons.chevron_right, size: 18, color: muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Import activity ───────────────────────────────────────────────────────────

class _ImportActivity extends StatelessWidget {
  final List<ImportJob> jobs;
  final Color muted;
  const _ImportActivity({required this.jobs, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (jobs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Import activity',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...jobs.map((j) => _JobRow(job: j, muted: muted)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Showing the 50 most recent import jobs.',
              style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        ),
      ],
    );
  }
}

class _JobRow extends StatelessWidget {
  final ImportJob job;
  final Color muted;
  const _JobRow({required this.job, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = context.read<CloudNotifier>();
    final pill = _pill(job);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, height: 20, child: _leading(job)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.providerFileName.isEmpty
                      ? '(fetching name…)'
                      : job.providerFileName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  [
                    pill.$1,
                    if (job.providerPath.isNotEmpty) job.providerPath,
                    if (job.errorMessage != null) job.errorMessage!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: pill.$2),
                ),
              ],
            ),
          ),
          if (job.isDuplicate && job.documentId != null)
            TextButton(
              onPressed: () => context.go('/reader/${job.documentId}'),
              child: const Text('View'),
            ),
          if (job.canRetry && !job.isSizeLimited)
            TextButton(
              onPressed: () async {
                final err = await cloud.retryJob(job.id);
                if (context.mounted && err != null) {
                  AppToast.show(context, err, type: ToastType.error);
                }
              },
              child: Text(job.isDuplicate ? 'Import again' : 'Retry'),
            ),
        ],
      ),
    );
  }

  Widget _leading(ImportJob j) {
    if (j.isWorking || j.status == 'pending' || j.status == 'queued') {
      return const CircularProgressIndicator(strokeWidth: 2);
    }
    if (j.status == 'complete') {
      return Icon(Icons.check_circle, size: 18, color: AppColors.positive);
    }
    if (j.status == 'error') {
      return Icon(Icons.error_outline, size: 18, color: AppColors.critical);
    }
    return Icon(Icons.remove_circle_outline, size: 18, color: muted); // skipped/cancelled
  }

  /// (label, color) for the status sub-line.
  (String, Color) _pill(ImportJob j) {
    switch (j.status) {
      case 'complete':
        return ('Imported', AppColors.positive);
      case 'error':
        return ('Failed', AppColors.critical);
      case 'skipped':
        return (j.isDuplicate ? 'Already imported' : 'Skipped', muted);
      case 'cancelled':
        return ('Cancelled', muted);
      case 'downloading':
        return ('Downloading', muted);
      case 'processing':
        return ('Processing', muted);
      default:
        return ('Waiting', muted);
    }
  }
}

// ── Auto-organization (1.2.0, INV-13) ────────────────────────────────────────

class _OrganizationSection extends StatelessWidget {
  final Color muted;
  const _OrganizationSection({required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.watch<OrgNotifier>();
    final pending = org.suggestions;
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Organization suggestions',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: AppRadius.controlR(20),
              ),
              child: Text('${pending.length}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...pending.map((s) => _SuggestionCard(suggestion: s, muted: muted)),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final OrganizationSuggestion suggestion;
  final Color muted;
  const _SuggestionCard({required this.suggestion, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final org = context.read<OrgNotifier>();
    final busy = org.isResolving(suggestion.id);

    Future<void> act(String action) async {
      final err = await org.resolve([suggestion.id], action);
      if (context.mounted && err != null) {
        AppToast.show(context, err, type: ToastType.error);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(suggestion.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text('${(suggestion.confidence * 100).round()}% confident',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ),
          const SizedBox(height: 4),
          if (suggestion.reason.isNotEmpty)
            Text(suggestion.reason, style: theme.textTheme.bodyMedium),
          if (suggestion.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(suggestion.detail,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              TextButton(
                onPressed: busy ? null : () => act('decline'),
                child: Text('Decline', style: TextStyle(color: muted)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? AppColors.primaryDark
                        : AppColors.primary),
                onPressed: busy ? null : () => act('approve'),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared banner ─────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  final VoidCallback? onDismiss;

  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdR,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
          if (action != null) action!,
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
