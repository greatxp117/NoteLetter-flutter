import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_folder.dart';
import '../../services/firestore_service.dart';
import '../../shared/cooldown.dart';
import '../../state/cloud_notifier.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../../services/error_text.dart';

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
  /// (A folder's refusal was an error toast until 2026-10-07.)
  String? _failure;

  /// Rescan all ([folderId] null) or one folder: one path, so both say a
  /// refusal in the same slot and a cooldown in the same calm one.
  Future<void> _rescan({String? folderId}) async {
    final org = context.read<OrgNotifier>();
    setState(() => _failure = null);
    final err = await org.scan(widget.provider, folderId: folderId);
    if (!mounted) return;
    // A cooldown is the provider's WAIT, said as calm copy over the folders
    // for as long as it runs (below). Anything else is a failure, said here.
    // A rescan that started says nothing: progress arrives on the folders
    // themselves, as on the reference (the folder's "Rescanning folder…"
    // info toast went with its error toast).
    if (err != null && !org.scanIsWaiting(widget.provider)) {
      setState(() => _failure = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final scanning = context.watch<OrgNotifier?>()?.scanInFlight ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Organized folders',
          first: true,
          // The reference's `.set-link`: the label carries ` · m:ss` while the
          // provider's cooldown runs, and it is held (KitSettingLink's dimmed
          // look) while waiting or while any scan of this provider is in
          // flight — Rescan all's or one folder's.
          tools: KitWait(
            waitKey: WaitKey.orgScan(provider),
            builder: (context, wait) => KitSettingLink(
              scanning ? 'Scanning…' : 'Rescan all',
              icon: null,
              wait: scanning ? 0 : wait.left,
              onTap: scanning ? null : () => _rescan(),
            ),
          ),
        ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: KitFailureInline(_failure!),
          ),
        // The scan cooldown is the PROVIDER's (4.107.0, ADR-140), so its
        // sentence is said once, under the header, for exactly
        // as long as the wait every one of their rescans is held for —
        // web's ScanWaitNotice. A toast would be gone long before the
        // wait it explains.
        //
        // A cooldown is a WAIT, not a failure, so it is calm copy
        // (`.proc-note`) and never §14.2's `--critical-text` — the
        // treatment Summary's Regenerate and Study give theirs. Nothing
        // broke and there is nothing to correct (web 23d21a8; 7b0e5fd drew
        // it red). One with no number (a pre-4.107.0 backend) is still a
        // wait, and is said in the same slot.
        KitWait(
          waitKey: WaitKey.orgScan(provider),
          builder: (context, wait) {
            final said = wait.sentence ??
                context.watch<OrgNotifier?>()?.scanWaitNote(provider);
            // The kit's one calm caption (§6.1, 4.108.0, ADR-145) — it was
            // `.proc-note`'s serif italic until then.
            return said == null
                ? const SizedBox.shrink()
                : KitWaitNote(said, padding: const EdgeInsets.only(top: 6));
          },
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

        final folders =
            (snap.data ?? const []).where((f) => f.organized).toList();
        if (folders.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child:
                Text('No organized folders yet.', style: KitText.meta(context)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in folders)
              _FolderRow(
                  folder: f,
                  scanning: scanning,
                  onRescan: () => onRescan(f.id)),
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.folder.charterText ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCharter({bool regenerate = false}) async {
    setState(() => _busy = true);
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
    });
    if (err != null) AppToast.show(context, err, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final f = widget.folder;
    // `missing`/`archived` folders render muted — they are history, not an
    // error, and dimming says so without a word.
    final dim = f.status != 'active';

    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: KitCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: t.fgMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.providerPath.isEmpty ? f.name : f.providerPath,
                      overflow: TextOverflow.ellipsis,
                      style: KitText.body(context),
                    ),
                  ),
                  if (f.readmeStatus != null) ...[
                    KitStatusPill('README ${f.readmeStatus}',
                        positive: f.readmeStatus == 'written'),
                    const SizedBox(width: 8),
                  ],
                  Text('${f.docCount} docs',
                      style: KitText.monoMeta(context, letterSpacing: 0)),
                ],
              ),
              if (_editing) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    borderRadius: AppRadius.smR,
                    border: Border.all(color: t.border),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: 3,
                    enabled: !_busy,
                    style: KitText.body(context),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'What belongs in this folder…',
                      hintStyle: KitText.meta(context),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    KitButton.ghost('Regenerate',
                        onPressed:
                            _busy ? null : () => _saveCharter(regenerate: true)),
                    const Spacer(),
                    KitButton.ghost('Cancel',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _editing = false)),
                    const SizedBox(width: 8),
                    KitButton.primary('Save charter',
                        onPressed: _busy ? null : () => _saveCharter()),
                  ],
                ),
              ] else ...[
                if ((f.charterText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    f.charterText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.lede(context, fontSize: 14, height: 20),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    KitButton.ghost(
                      (f.charterText ?? '').isEmpty
                          ? 'Add charter'
                          : 'Edit charter',
                      icon: Icons.edit_outlined,
                      onPressed: () => setState(() => _editing = true),
                    ),
                    const Spacer(),
                    KitWait(
                      waitKey: WaitKey.orgScan(f.provider),
                      builder: (context, wait) => KitButton.ghost('Rescan',
                          icon: Icons.refresh,
                          wait: wait.left,
                          onPressed: widget.scanning ? null : widget.onRescan),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
