import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_folder.dart';
import '../../services/firestore_service.dart';
import '../../shared/cooldown.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../../services/error_text.dart';

const _providerName = {
  'google_drive': 'Google Drive',
  'onedrive': 'OneDrive',
  'dropbox': 'Dropbox',
  'notion': 'Notion',
};

/// Auto-organization settings + organized folders (`screens/sources.md`
/// §Organized-folders panel, `api/organization.md`), recomposed against the kit
/// (ADR-041).
///
/// Global confidence threshold + default reorganize mode, per-provider worker
/// flags, and per-folder charter editing (`fn_update_folder_charter`) + rescan
/// (`fn_scan_organization`). Rendered only when a provider has organization
/// enabled — a settings block for a feature nobody turned on is furniture.
class OrganizationSettingsPanel extends StatefulWidget {
  const OrganizationSettingsPanel({super.key});

  @override
  State<OrganizationSettingsPanel> createState() =>
      _OrganizationSettingsPanelState();
}

class _OrganizationSettingsPanelState extends State<OrganizationSettingsPanel> {
  double? _dragThreshold; // live slider value while dragging

  /// §14.2 — a save's refusal, verbatim, in the panel it came from (a 400
  /// validation or, since 4.93.0 / ADR-127, `UNKNOWN_KEYS`). It was a toast.
  String? _saveError;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final org = context.watch<OrgNotifier>();
    final settings = org.settings;
    // §14 BEFORE the vanish (C4, ORDER). `settings.providers` is empty on the
    // defaults, so a failed read took this panel off the screen entirely —
    // the reader lost the controls and the reason in one step, and nothing
    // said either had happened.
    if (org.settingsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Organization'),
          KitFailureBlock(
            sentence: 'Your organization settings could not be read.',
            detail: org.settingsError!,
            onRetry: () => context.read<OrgNotifier>().loadSettings(),
          ),
        ],
      );
    }

    // Not yet read is not "on the defaults". Drawing the controls here would
    // show a threshold and a mode this reader has never chosen, and the first
    // nudge would save them.
    if (!org.settingsLoaded) return const SizedBox.shrink();

    final enabledProviders = settings.providers.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList();
    if (enabledProviders.isEmpty) return const SizedBox.shrink();

    final threshold = _dragThreshold ?? settings.confidenceThreshold;

    Future<void> save(Map<String, dynamic> partial) async {
      setState(() => _saveError = null);
      final err = await org.updateSettings(partial);
      if (mounted) setState(() => _saveError = err);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Organization'),
        if (_saveError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(_saveError!),
          ),
        KitCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Auto-apply confidence',
                        style: KitText.body(context)),
                  ),
                  Text('${(threshold * 100).round()}%',
                      style: KitText.monoFigure(context)),
                ],
              ),
              Slider(
                value: threshold.clamp(0.5, 0.95),
                min: 0.5,
                max: 0.95,
                divisions: 9,
                activeColor: t.accent,
                inactiveColor: t.border,
                // The slider writes only when the drag ENDS — a call per frame
                // would be one write per pixel.
                onChanged: (v) => setState(() => _dragThreshold = v),
                onChangeEnd: (v) {
                  setState(() => _dragThreshold = null);
                  save({
                    'confidence_threshold': double.parse(v.toStringAsFixed(2))
                  });
                },
              ),
              Text(
                'Files at or above this confidence are filed automatically; '
                'below it, they become suggestions you approve.',
                style: KitText.meta(context),
              ),

              const SizedBox(height: 18),
              const Eyebrow('Default reorganize mode'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: KitSegmented(
                  segments: const [KitSegment('Split'), KitSegment('Copy')],
                  selected: settings.defaultReorgMode == 'copy' ? 1 : 0,
                  onChanged: (i) => save(
                      {'default_reorg_mode': i == 1 ? 'copy' : 'split'}),
                ),
              ),
            ],
          ),
        ),

        for (final p in enabledProviders) ...[
          const SizedBox(height: 12),
          KitCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Eyebrow(_providerName[p] ?? p),
                const SizedBox(height: 6),
                _Flag(
                  label: 'Write folder READMEs',
                  value: settings.configFor(p).readmesEnabled,
                  onChanged: (v) => save({
                    'providers': {
                      p: {'readmes_enabled': v}
                    }
                  }),
                ),
                _Flag(
                  label: 'Flag out-of-place files',
                  value: settings.configFor(p).outOfPlaceEnabled,
                  onChanged: (v) => save({
                    'providers': {
                      p: {'out_of_place_enabled': v}
                    }
                  }),
                ),
                _Flag(
                  label: 'Auto-place new files',
                  value: settings.configFor(p).autoPlacementEnabled,
                  onChanged: (v) => save({
                    'providers': {
                      p: {'auto_placement_enabled': v}
                    }
                  }),
                ),
                const SizedBox(height: 6),
                OrganizedFoldersPanel(provider: p),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One worker flag. **Write before you move**: the switch renders the stored
/// value and the call is awaited, so a rejected write shows as a toast and the
/// control never lies about state it does not have (ADR-022).
class _Flag extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Flag({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: KitText.body(context))),
        Switch(
          value: value,
          activeThumbColor: t.accent,
          onChanged: onChanged,
        ),
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
  /// Rescan all's refusal when it is NOT the cooldown — §14.2 under the header,
  /// carrying the server's sentence, the reference's `notice` slot. A toast
  /// would be gone before the reader looked; this stays until the next ask.
  String? _failure;

  Future<void> _rescanAll() async {
    final org = context.read<OrgNotifier>();
    setState(() => _failure = null);
    final err = await org.scan(widget.provider);
    if (!mounted) return;
    // A cooldown is the provider's WAIT, said as calm copy over the folders
    // for as long as it runs (below). Anything else is a failure, said here.
    // A rescan that started says nothing: progress arrives on the folders
    // themselves, as on the reference.
    if (err != null && !org.scanIsWaiting(widget.provider)) {
      setState(() => _failure = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final scanning = context.watch<OrgNotifier?>()?.isScanning(provider) ?? false;
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
              onTap: scanning ? null : _rescanAll,
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
        _FolderList(provider: provider, scanning: scanning),
      ],
    );
  }
}

class _FolderList extends StatelessWidget {
  final String provider;
  final bool scanning;
  const _FolderList({required this.provider, required this.scanning});

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
            for (final f in folders) _FolderRow(folder: f, scanning: scanning),
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
  const _FolderRow({required this.folder, this.scanning = false});

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

  Future<void> _rescan() async {
    final org = context.read<OrgNotifier>();
    final err =
        await org.scan(widget.folder.provider, folderId: widget.folder.id);
    if (!mounted) return;
    // A cooldown is the provider's WAIT: with its number every rescan of it
    // is held and the sentence is said over the folders until it ends
    // (ADR-140); without one the sentence stands in the same calm slot. Either
    // way it is not also a toast, and never an error one.
    if (err != null && org.scanIsWaiting(widget.folder.provider)) return;
    AppToast.show(context, err ?? 'Rescanning folder…',
        type: err != null ? ToastType.error : ToastType.info);
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
                          onPressed: widget.scanning ? null : _rescan),
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
