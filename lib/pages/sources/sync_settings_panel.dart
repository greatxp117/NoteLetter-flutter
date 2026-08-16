import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_integration.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';

/// Tier-C sync-settings panel (sources.md §Sync settings, 1.4.0/ADR-007).
/// Collapsible per provider: auto-sync toggle, frequency, preferred-hour (UTC),
/// include-types, exclude-patterns. Every edit sends ONLY the changed key via
/// `fn_sync_settings`; the returned `integration` is the source of truth (no
/// optimistic state — the panel renders straight off `widget.integration`).
class SyncSettingsPanel extends StatefulWidget {
  final String providerId;
  final CloudIntegration integration;
  const SyncSettingsPanel(
      {super.key, required this.providerId, required this.integration});

  @override
  State<SyncSettingsPanel> createState() => _SyncSettingsPanelState();
}

class _SyncSettingsPanelState extends State<SyncSettingsPanel> {
  static const _frequencies = ['hourly', 'daily', 'weekly'];
  static const _types = ['pdf', 'docx', 'notion'];

  final _patternsController = TextEditingController();
  final _patternsFocus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _patternsController.text = widget.integration.excludePatterns.join('\n');
  }

  @override
  void didUpdateWidget(covariant SyncSettingsPanel old) {
    super.didUpdateWidget(old);
    // Resync the pattern editor to the authoritative integration unless the
    // user is mid-edit.
    if (!_patternsFocus.hasFocus) {
      final joined = widget.integration.excludePatterns.join('\n');
      if (joined != _patternsController.text) _patternsController.text = joined;
    }
  }

  @override
  void dispose() {
    _patternsController.dispose();
    _patternsFocus.dispose();
    super.dispose();
  }

  Future<void> _save(
      Future<String?> Function(CloudNotifier c) call) async {
    setState(() => _saving = true);
    final err = await call(context.read<CloudNotifier>());
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) AppToast.show(context, err, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final fg = isDark ? AppColors.foregroundDark : AppColors.foregroundLight;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final i = widget.integration;
    final inert = i.autoSyncEnabled && i.folderIds.isEmpty;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(fontFamily: 'Geist', 
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                  color: muted)),
        );

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text('Sync settings',
            style: TextStyle(fontFamily: 'Geist', 
                fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        subtitle: Text(
            i.autoSyncEnabled
                ? 'Auto-sync ${i.syncFrequency} · ${i.lastSyncLabel}'
                : 'Auto-sync off · ${i.lastSyncLabel}',
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: muted)),
        children: [
          AbsorbPointer(
            absorbing: _saving,
            child: Opacity(
              opacity: _saving ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: primary,
                    title: Text('Automatic sync',
                        style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: fg)),
                    value: i.autoSyncEnabled,
                    onChanged: (v) =>
                        _save((c) => c.syncSettings(widget.providerId,
                            autoSyncEnabled: v)),
                  ),
                  if (inert)
                    _warn(muted,
                        'Auto-sync is on but no folders are chosen — nothing will sync until you pick sync folders.'),
                  label('Frequency'),
                  Wrap(
                    spacing: 8,
                    children: _frequencies
                        .map((f) => _chip(f, i.syncFrequency == f, primary, fg,
                            muted, isDark, () {
                          _save((c) => c.syncSettings(widget.providerId,
                              syncFrequency: f));
                        }))
                        .toList(),
                  ),
                  label('Preferred hour (UTC)'),
                  DropdownButton<int>(
                    value: i.syncPreferredHour ?? 9,
                    dropdownColor:
                        isDark ? AppColors.cardDark : Colors.white,
                    style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: fg),
                    items: List.generate(
                        24,
                        (h) => DropdownMenuItem(
                            value: h,
                            child: Text(
                                '${h.toString().padLeft(2, '0')}:00 UTC'))),
                    onChanged: (v) => v == null
                        ? null
                        : _save((c) => c.syncSettings(widget.providerId,
                            syncPreferredHour: v)),
                  ),
                  label('Include types'),
                  Wrap(
                    spacing: 8,
                    children: _types.map((t) {
                      final on = i.includeTypes.contains(t);
                      return _chip(t, on, primary, fg, muted, isDark, () {
                        final next = {...i.includeTypes};
                        on ? next.remove(t) : next.add(t);
                        _save((c) => c.syncSettings(widget.providerId,
                            includeTypes: next.toList()));
                      });
                    }).toList(),
                  ),
                  label('Exclude patterns (one glob per line, ≤50)'),
                  TextField(
                    controller: _patternsController,
                    focusNode: _patternsFocus,
                    maxLines: 3,
                    style: AppTheme.mono(fontSize: 12, color: fg),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '*.tmp\ndrafts/**',
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: () {
                      _patternsFocus.unfocus();
                      final list = _patternsController.text
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .take(50)
                          .toList();
                      _save((c) => c.syncSettings(widget.providerId,
                          excludePatterns: list));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warn(Color muted, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded,
              size: 15, color: AppColors.critical),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: muted)),
          ),
        ]),
      );

  Widget _chip(String label, bool on, Color primary, Color fg, Color muted,
      bool isDark, VoidCallback onTap) {
    final accentFg =
        isDark ? AppColors.primaryForegroundDark : AppColors.primaryForeground;
    final surface = isDark ? AppColors.secondaryDark : AppColors.secondaryLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? primary : surface,
          borderRadius: AppRadius.pillR(28),
          border: Border.all(color: on ? primary : border),
        ),
        child: Text(label,
            style: TextStyle(fontFamily: 'Geist', 
                fontSize: 12, color: on ? accentFg : fg)),
      ),
    );
  }
}
