import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_folder.dart';
import '../../services/firestore_service.dart';
import '../../shared/cooldown.dart';
import '../../state/cloud_notifier.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../../services/error_text.dart';
import '../../shared/cloud_providers.dart';
import 'cloud_picker.dart' show CloudPickerFoot;
import 'sync_folder_picker.dart';

/// Organized folders on Sources (`screens/sources.md` §Organized-folders
/// panel): one [OrganizedFoldersPanel] per provider whose organizing grant is
/// write-ready — the reference's `OrganizationPanel` gate
/// (`organization.enabled && write_access`, read off the integration).
///
/// The SETTINGS this panel drew until 2026-10-09 — the confidence threshold,
/// the default reorganize mode and each provider's three switches — live in
/// Settings → Sources now (`SourcesSection`, ruled that day); each provider's
/// *Import from* header links there. What stays here is what is about the
/// folders themselves: roots, charters, READMEs and rescans.
class OrganizedFoldersSection extends StatelessWidget {
  const OrganizedFoldersSection({super.key});

  static const _order = ['google_drive', 'onedrive', 'dropbox', 'notion'];

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier?>();
    if (cloud == null) return const SizedBox.shrink();
    final ready = [
      for (final p in _order)
        if (cloud.integrationFor(p)?.orgWriteReady ?? false) p,
    ];
    if (ready.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in ready) OrganizedFoldersPanel(provider: p),
      ],
    );
  }
}

/// Organized folders for one provider, from the `cloud_folders` subscription
/// (INV-02): path, charter preview/edit, README status chip, doc count, rescan.
///
/// Its §3 header carries **Rescan all** (`fn_scan_organization` with no folder),
/// as the reference's carries it beside Choose folders
/// (OrganizationPanel.jsx `RescanAll`). The header renders whatever the list
/// below it says — empty, or unread — because the provider can be rescanned
/// either way, as on the reference.
class OrganizedFoldersPanel extends StatefulWidget {
  final String provider;
  const OrganizedFoldersPanel({super.key, required this.provider});

  @override
  State<OrganizedFoldersPanel> createState() => _OrganizedFoldersPanelState();
}

class _OrganizedFoldersPanelState extends State<OrganizedFoldersPanel> {
  /// A rescan's refusal when it is NOT the cooldown — Rescan all's or one
  /// folder's — §14.2 under the header, carrying the server's sentence: the
  /// reference's one `notice` slot, which both of its rescans write. A toast
  /// would be gone before the reader looked; this stays until the next ask.
  String? _failure;

  /// *Choose folders* is open (web `pickerFor`).
  bool _choosing = false;

  /// Rescan all ([folderId] null) or one folder: one path, so both say a
  /// refusal in the same slot and a cooldown in the same calm one.
  Future<void> _rescan({String? folderId}) async {
    final org = context.read<OrgNotifier>();
    setState(() => _failure = null);
    final err = await org.scan(widget.provider, folderId: folderId);
    if (!mounted) return;
    // A cooldown is the provider's WAIT, said as calm copy above the header
    // for as long as it runs. Anything else is a failure, said under it.
    if (err != null && !org.scanIsWaiting(widget.provider)) {
      setState(() => _failure = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final provider = widget.provider;
    final name = cloudProviders[provider]?.name ?? provider;
    final scanning = context.watch<OrgNotifier?>()?.scanInFlight ?? false;
    final roots = context
            .watch<CloudNotifier?>()
            ?.integrationFor(provider)
            ?.orgRootFolderIds ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The scan cooldown is the PROVIDER's (4.107.0, ADR-140), said once,
        // ABOVE the header, as web's ScanWaitNotice sits above the providers'
        // headers (F-90 (6)) — calm copy (§6.1), never §14.2: nothing broke.
        KitWait(
          waitKey: WaitKey.orgScan(provider),
          builder: (context, wait) {
            final said = wait.sentence ??
                context.watch<OrgNotifier?>()?.scanWaitNote(provider);
            return said == null
                ? const SizedBox.shrink()
                : KitWaitNote(said,
                    padding: const EdgeInsets.symmetric(vertical: 12));
          },
        ),
        // `.lib-section-h` at 18: the provider's glyph and "Organized folders
        // · {provider}", then Choose folders · Rescan all (web
        // OrganizationPanel). On a phone the links take the next line.
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
                  KitGlyph(
                      cloudProviders[provider]?.icon ?? Icons.folder_outlined,
                      size: 14,
                      color: t.fgMuted),
                  const SizedBox(width: 7),
                  Eyebrow('Organized folders · $name'),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KitSettingLink(
                    _choosing ? 'Close' : 'Choose folders',
                    icon: null,
                    onTap: () => setState(() => _choosing = !_choosing),
                  ),
                  Text('  ·  ', style: KitText.meta(context)),
                  // The reference's `.set-link`: ` · m:ss` while the
                  // provider's cooldown runs, held while waiting or while any
                  // scan of this provider is in flight.
                  KitWait(
                    waitKey: WaitKey.orgScan(provider),
                    builder: (context, wait) => KitSettingLink(
                      scanning ? 'Scanning…' : 'Rescan all',
                      icon: null,
                      wait: scanning ? 0 : wait.left,
                      onTap: scanning ? null : () => _rescan(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: KitFailureInline(_failure!),
          ),
        // The roots, chosen with the folders-only picker (`api/organization.md`
        // §fn_set_organized_folders, ≤10). Write before move: it closes only
        // once the save has been answered, and a refusal stays inside it.
        if (_choosing)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SyncFolderPicker(
              provider: provider,
              initial: roots,
              cap: 10,
              allowEmpty: roots.isNotEmpty,
              // `fn_set_organized_folders` takes ids only.
              onConfirm: (ids, _) async {
                final err = await context
                    .read<OrgNotifier>()
                    .setOrganizedFolders(provider, ids);
                if (err == null && mounted) setState(() => _choosing = false);
                return err;
              },
              onCancel: () => setState(() => _choosing = false),
            ),
          ),
        _FolderList(
            provider: provider,
            scanning: scanning,
            onRescan: (folderId) => _rescan(folderId: folderId)),
      ],
    );
  }
}

class _FolderList extends StatelessWidget {
  final String provider;
  final bool scanning;
  final void Function(String folderId) onRescan;
  const _FolderList(
      {required this.provider, required this.scanning, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CloudFolder>>(
      stream: FirestoreService.instance.subscribeCloudFolders(provider),
      builder: (context, snap) {
        // §14.2 first (C3). "No organized folders yet." is an answer about the
        // account; on a failed subscription it is an answer about nothing, and
        // the reader is told the opposite of what happened.
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: KitFailureInline(describeSdkError(snap.error!)),
          );
        }

        final folders = (snap.data ?? const []).where((f) => f.organized).toList()
          ..sort((a, b) => a.providerPath.compareTo(b.providerPath));
        if (folders.isEmpty) {
          return const KitProcNote(
              'No organized folders yet — choose folders to begin.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < folders.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _FolderRow(
                  folder: folders[i],
                  scanning: scanning,
                  onRescan: () => onRescan(folders[i].id)),
            ],
          ],
        );
      },
    );
  }
}

class _FolderRow extends StatefulWidget {
  final CloudFolder folder;

  /// A scan of this provider is in flight (Rescan all's or a folder's): the
  /// row's rescan is held for it, as every rescan control is on the reference.
  final bool scanning;

  /// The panel's rescan of this folder — its refusal is said in the panel's
  /// §14.2 slot under the header, never on the row or in a toast.
  final VoidCallback onRescan;
  const _FolderRow(
      {required this.folder, this.scanning = false, required this.onRescan});

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _editing = false;
  bool _busy = false;
  String? _error;
  late final TextEditingController _controller =
      TextEditingController(text: widget.folder.charterText ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCharter({bool regenerate = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final org = context.read<OrgNotifier>();
    // User text sets `charter.source: "user"`; regenerate clears it back to the
    // model's own, which is why the two are one call with a flag and not two
    // half-writes.
    final err = await org.updateFolderCharter(widget.folder.id,
        charterText: regenerate ? null : _controller.text.trim(),
        regenerate: regenerate);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _editing = false;
      // §14.2 on the row, as web's FolderRow says it (it was a toast).
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.folder;
    // `missing`/`archived` folders render muted — they are history, not an
    // error, and dimming says so without a word.
    final inactive = f.status != 'active';
    final charter = f.charterText ?? '';
    final quote = KitText.monoMeta(context).copyWith(fontStyle: FontStyle.italic);

    Widget? below;
    if (_editing) {
      below = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTextField(
              controller: _controller,
              face: KitFieldFace.sans,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            // `.proc-error-actions`: Save charter · Cancel, trailing on a phone.
            CloudPickerFoot(
              confirmLabel: _busy ? 'Saving…' : 'Save charter',
              onConfirm: _controller.text.trim().isEmpty || _busy
                  ? null
                  : () => _saveCharter(),
              onCancel: () => setState(() => _editing = false),
              busy: _busy,
            ),
          ],
        ),
      );
    } else if (charter.isNotEmpty) {
      // The charter as the reference draws it: a mono italic quote, then Edit ·
      // Regenerate inline (F-90 (6); it was serif italic over two buttons).
      below = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [
            Text('“$charter”', style: quote),
            if (!inactive) ...[
              KitSettingLink('Edit', icon: null, onTap: () {
                _controller.text = charter;
                setState(() => _editing = true);
              }),
              KitSettingLink('Regenerate',
                  icon: null,
                  onTap: _busy ? null : () => _saveCharter(regenerate: true)),
            ],
          ],
        ),
      );
    }
    if (_error != null) {
      below = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?below,
          const SizedBox(height: 6),
          KitFailureInline(_error!),
        ],
      );
    }

    return Opacity(
      opacity: inactive ? 0.55 : 1,
      child: KitFolderCard(
        title: '${f.providerPath.isEmpty ? f.name : f.providerPath}'
            '${inactive ? ' · ${f.status}' : ''}',
        subtitle: '${f.docCount} ${f.docCount == 1 ? 'file' : 'files'}',
        trailing: [
          KitReadmeChip(f.readmeStatus),
          if (!inactive)
            KitWait(
              waitKey: WaitKey.orgScan(f.provider),
              // §6.1 State — Held: scanning or waiting, the control at
              // `--held-opacity` (web's `.proc-cancel:disabled`, ruled again
              // 2026-10-13, F-103). §6.5's icon button has no held look of
              // its own, so the hold is drawn here, where the wait is.
              builder: (context, wait) {
                final held = widget.scanning || wait.left > 0;
                return Opacity(
                  opacity: held ? AppSpacing.heldOpacity : 1,
                  child: KitIconButton(
                    Icons.refresh,
                    tooltip: 'Rescan this folder${waitSuffix(wait.left)}',
                    onPressed: held ? null : widget.onRescan,
                  ),
                );
              },
            ),
        ],
        below: below,
      ),
    );
  }
}
