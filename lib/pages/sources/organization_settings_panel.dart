import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_folder.dart';
import '../../services/firestore_service.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';

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

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final org = context.watch<OrgNotifier>();
    final settings = org.settings;
    final enabledProviders = settings.providers.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList();
    if (enabledProviders.isEmpty) return const SizedBox.shrink();

    final threshold = _dragThreshold ?? settings.confidenceThreshold;

    Future<void> save(Map<String, dynamic> partial) async {
      final err = await org.updateSettings(partial);
      if (context.mounted && err != null) {
        AppToast.show(context, err, type: ToastType.error);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Organization'),
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
                      style: AppTheme.mono(fontSize: 13, color: t.fg)),
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
class OrganizedFoldersPanel extends StatelessWidget {
  final String provider;
  const OrganizedFoldersPanel({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CloudFolder>>(
      stream: FirestoreService.instance.subscribeCloudFolders(provider),
      builder: (context, snap) {
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
            for (final f in folders) _FolderRow(folder: f),
          ],
        );
      },
    );
  }
}

class _FolderRow extends StatefulWidget {
  final CloudFolder folder;
  const _FolderRow({required this.folder});

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
    // A 409 COOLDOWN comes back as user-facing copy — say it rather than
    // leaving the button looking broken.
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
                      style: AppTheme.mono(fontSize: 11, color: t.fgSubtle)),
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
                    KitButton.ghost('Rescan',
                        icon: Icons.refresh, onPressed: _rescan),
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
