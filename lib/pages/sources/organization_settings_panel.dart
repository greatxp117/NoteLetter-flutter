import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_folder.dart';
import '../../services/firestore_service.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';

const _providerName = {
  'google_drive': 'Google Drive',
  'onedrive': 'OneDrive',
  'dropbox': 'Dropbox',
  'notion': 'Notion',
};

/// Auto-organization settings + organized-folders (sources.md §Organized-folders
/// / organization.md fn_organization_settings). Global confidence threshold +
/// default reorg mode, per-enabled-provider worker flags, and per-folder charter
/// editing (fn_update_folder_charter) + rescan (fn_scan_organization). Rendered
/// only when at least one provider has organization enabled.
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
    final org = context.watch<OrgNotifier>();
    final settings = org.settings;
    final enabledProviders = settings.providers.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList();
    if (enabledProviders.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.foregroundDark : AppColors.foregroundLight;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final threshold = _dragThreshold ?? settings.confidenceThreshold;

    Future<void> save(Map<String, dynamic> partial) async {
      final err = await org.updateSettings(partial);
      if (context.mounted && err != null) {
        AppToast.show(context, err, type: ToastType.error);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Organization settings',
          style: GoogleFonts.sourceSerif4(
              fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
      const SizedBox(height: 12),
      // Confidence threshold.
      Row(children: [
        Text('Auto-apply confidence',
            style: GoogleFonts.inter(fontSize: 14, color: fg)),
        const Spacer(),
        Text('${(threshold * 100).round()}%',
            style: GoogleFonts.robotoMono(fontSize: 13, color: fg)),
      ]),
      Slider(
        value: threshold.clamp(0.5, 0.95),
        min: 0.5,
        max: 0.95,
        divisions: 9,
        activeColor: primary,
        inactiveColor: isDark ? AppColors.borderDark : AppColors.borderLight,
        onChanged: (v) => setState(() => _dragThreshold = v),
        onChangeEnd: (v) {
          setState(() => _dragThreshold = null);
          save({'confidence_threshold': double.parse(v.toStringAsFixed(2))});
        },
      ),
      Text(
          'Files at or above this confidence are filed automatically; below it, they become suggestions.',
          style: GoogleFonts.inter(fontSize: 12, color: muted)),
      const SizedBox(height: 16),
      // Default reorg mode.
      Text('Default reorganize mode',
          style: GoogleFonts.inter(fontSize: 14, color: fg)),
      const SizedBox(height: 8),
      Row(children: [
        _modeChip('Split', settings.defaultReorgMode == 'split', primary, fg,
            muted, isDark, () => save({'default_reorg_mode': 'split'})),
        const SizedBox(width: 8),
        _modeChip('Copy', settings.defaultReorgMode == 'copy', primary, fg,
            muted, isDark, () => save({'default_reorg_mode': 'copy'})),
      ]),
      const SizedBox(height: 20),
      // Per-provider worker flags + organized folders.
      ...enabledProviders.map((p) {
        final cfg = settings.configFor(p);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_providerName[p] ?? p,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          _flag('Write folder READMEs', cfg.readmesEnabled, primary, fg,
              (v) => save({
                    'providers': {
                      p: {'readmes_enabled': v}
                    }
                  })),
          _flag('Flag out-of-place files', cfg.outOfPlaceEnabled, primary, fg,
              (v) => save({
                    'providers': {
                      p: {'out_of_place_enabled': v}
                    }
                  })),
          _flag('Auto-place new files', cfg.autoPlacementEnabled, primary, fg,
              (v) => save({
                    'providers': {
                      p: {'auto_placement_enabled': v}
                    }
                  })),
          const SizedBox(height: 8),
          OrganizedFoldersPanel(provider: p),
          const SizedBox(height: 16),
        ]);
      }),
    ]);
  }

  Widget _flag(String label, bool value, Color primary, Color fg,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeThumbColor: primary,
        title: Text(label, style: GoogleFonts.inter(fontSize: 13, color: fg)),
        value: value,
        onChanged: onChanged,
      );

  Widget _modeChip(String label, bool on, Color primary, Color fg, Color muted,
      bool isDark, VoidCallback onTap) {
    final accentFg =
        isDark ? AppColors.primaryForegroundDark : AppColors.primaryForeground;
    final surface = isDark ? AppColors.secondaryDark : AppColors.secondaryLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? primary : surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? primary : border),
        ),
        child: Text(label,
            style:
                GoogleFonts.inter(fontSize: 13, color: on ? accentFg : fg)),
      ),
    );
  }
}

/// Organized-folders rows for one provider from the `cloud_folders`
/// subscription (INV-02): provider_path, charter preview/edit, README status
/// chip, doc count, rescan.
class OrganizedFoldersPanel extends StatelessWidget {
  final String provider;
  const OrganizedFoldersPanel({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    return StreamBuilder<List<CloudFolder>>(
      stream: FirestoreService.instance.subscribeCloudFolders(provider),
      builder: (context, snap) {
        final folders = (snap.data ?? const [])
            .where((f) => f.organized)
            .toList();
        if (folders.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text('No organized folders yet.',
                style: GoogleFonts.inter(fontSize: 12, color: muted)),
          );
        }
        return Column(
          children: folders.map((f) => _FolderRow(folder: f)).toList(),
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

  static const _readmeColors = {
    'written': 'ok',
    'user_modified': 'warn',
    'error': 'bad',
    'pending': 'muted',
  };

  Future<void> _saveCharter({bool regenerate = false}) async {
    setState(() => _busy = true);
    final org = context.read<OrgNotifier>();
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
    final err = await org.scan(widget.folder.provider, folderId: widget.folder.id);
    if (!mounted) return;
    AppToast.show(context, err ?? 'Rescanning folder…',
        type: err != null ? ToastType.error : ToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.folder;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.foregroundDark : AppColors.foregroundLight;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final dim = f.status != 'active';

    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.folder_outlined, size: 16, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(f.providerPath.isEmpty ? f.name : f.providerPath,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w500, color: fg),
                  overflow: TextOverflow.ellipsis),
            ),
            if (f.readmeStatus != null) _readmeChip(f.readmeStatus!, isDark),
            const SizedBox(width: 8),
            Text('${f.docCount} docs',
                style: GoogleFonts.inter(fontSize: 11, color: muted)),
          ]),
          if (_editing) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 3,
              enabled: !_busy,
              style: GoogleFonts.inter(fontSize: 13, color: fg),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'What belongs in this folder…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(
                  onPressed: _busy ? null : () => _saveCharter(regenerate: true),
                  child: const Text('Regenerate')),
              const Spacer(),
              TextButton(
                  onPressed:
                      _busy ? null : () => setState(() => _editing = false),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: _busy ? null : () => _saveCharter(),
                  child: const Text('Save charter')),
            ]),
          ] else ...[
            if ((f.charterText ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(f.charterText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: muted)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text((f.charterText ?? '').isEmpty
                    ? 'Add charter'
                    : 'Edit charter'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _rescan,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Rescan'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _readmeChip(String status, bool isDark) {
    final kind = _readmeColors[status] ?? 'muted';
    final color = kind == 'ok'
        ? AppColors.positive
        : kind == 'bad'
            ? AppColors.critical
            : kind == 'warn'
                ? (isDark ? AppColors.primaryDark : AppColors.primary)
                : (isDark
                    ? AppColors.mutedForegroundDark
                    : AppColors.mutedForeground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('README $status',
          style: GoogleFonts.inter(fontSize: 10, color: color)),
    );
  }
}
