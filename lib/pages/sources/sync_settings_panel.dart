import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_integration.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';

/// Tier-C sync settings (`screens/sources.md` §Sync control, 1.4.0/ADR-007),
/// recomposed against the kit (ADR-041).
///
/// Collapsible per provider: auto-sync toggle, frequency, preferred hour (UTC),
/// include-types, exclude-patterns. Every edit sends **only the changed key**
/// via `fn_sync_settings`, and the returned `integration` is the source of
/// truth — the panel renders straight off `widget.integration` and holds no
/// optimistic copy. **Write before you move**: a toggle that sets local state
/// before awaiting its call hides the failure completely, and the control only
/// reverts on reload (ADR-022).
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
  bool _open = false;

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

  Future<void> _save(Future<String?> Function(CloudNotifier c) call) async {
    setState(() => _saving = true);
    final err = await call(context.read<CloudNotifier>());
    if (!mounted) return;
    setState(() => _saving = false);
    // A 400 is a validation message written for a person — show it as it came.
    if (err != null) AppToast.show(context, err, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final i = widget.integration;
    final inert = i.autoSyncEnabled && i.folderIds.isEmpty;

    return KitCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Sync · ${_providerLabel()}'),
                        const SizedBox(height: 4),
                        Text(
                          i.autoSyncEnabled
                              ? 'Auto-sync ${i.syncFrequency} · ${i.lastSyncLabel}'
                              : 'Auto-sync off · ${i.lastSyncLabel}',
                          style: KitText.meta(context),
                        ),
                      ],
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 17, color: t.fgMuted),
                ],
              ),
            ),
          ),
          if (_open)
            AbsorbPointer(
              absorbing: _saving,
              child: Opacity(
                opacity: _saving ? 0.6 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Automatic sync',
                              style: KitText.body(context)),
                        ),
                        Switch(
                          value: i.autoSyncEnabled,
                          activeThumbColor: t.accent,
                          onChanged: (v) => _save((c) => c.syncSettings(
                              widget.providerId,
                              autoSyncEnabled: v)),
                        ),
                      ],
                    ),
                    // An inert state, said out loud: auto-sync with no folder
                    // scope will never move a file, and silence there looks
                    // exactly like working.
                    if (inert) _Warning(
                      'Auto-sync is on but no folders are chosen — nothing '
                      'will sync until you pick sync folders.',
                    ),

                    _Label('Frequency'),
                    KitSegmented(
                      segments: [
                        for (final f in _frequencies) KitSegment(_title(f)),
                      ],
                      selected: _frequencies.indexOf(i.syncFrequency).clamp(0, 2),
                      onChanged: (n) => _save((c) => c.syncSettings(
                          widget.providerId,
                          syncFrequency: _frequencies[n])),
                    ),

                    _Label('Preferred hour'),
                    Row(
                      children: [
                        _HourField(
                          hour: i.syncPreferredHour ?? 9,
                          onChanged: (v) => _save((c) => c.syncSettings(
                              widget.providerId, syncPreferredHour: v)),
                        ),
                        const SizedBox(width: 10),
                        // Stored and sent as the plain UTC hour the
                        // orchestrator compares against — so the control says
                        // UTC rather than quietly implying local time.
                        Text('UTC', style: KitText.meta(context)),
                      ],
                    ),

                    _Label('Include types'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in _types)
                          KitFilterChip(
                            type.toUpperCase(),
                            selected: i.includeTypes.contains(type),
                            onPressed: () {
                              final next = {...i.includeTypes};
                              i.includeTypes.contains(type)
                                  ? next.remove(type)
                                  : next.add(type);
                              _save((c) => c.syncSettings(widget.providerId,
                                  includeTypes: next.toList()));
                            },
                          ),
                      ],
                    ),

                    _Label('Exclude patterns — one glob per line, ≤50'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.surfaceSunken,
                        borderRadius: AppRadius.smR,
                        border: Border.all(color: t.border),
                      ),
                      child: TextField(
                        controller: _patternsController,
                        focusNode: _patternsFocus,
                        maxLines: 3,
                        style: AppTheme.mono(fontSize: 12, color: t.fg),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '*.tmp\ndrafts/**',
                          hintStyle:
                              AppTheme.mono(fontSize: 12, color: t.fgSubtle),
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
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _providerLabel() => switch (widget.providerId) {
        'google_drive' => 'Google Drive',
        'onedrive' => 'OneDrive',
        'dropbox' => 'Dropbox',
        'notion' => 'Notion',
        _ => widget.providerId,
      };

  String _title(String s) => s[0].toUpperCase() + s.substring(1);
}

/// A field label inside a panel — the eyebrow role, with the panel's rhythm.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Eyebrow(text),
      );
}

/// An inert-state warning: the setting is on and will still do nothing.
class _Warning extends StatelessWidget {
  final String text;
  const _Warning(this.text);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: t.critical),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: KitText.meta(context))),
        ],
      ),
    );
  }
}

/// The preferred-hour picker. 0–23, rendered as a clock hour.
class _HourField extends StatelessWidget {
  final int hour;
  final ValueChanged<int> onChanged;

  const _HourField({required this.hour, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.controlR(36),
        border: Border.all(color: t.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: hour,
          isDense: true,
          dropdownColor: t.surface,
          borderRadius: AppRadius.smR,
          style: AppTheme.mono(fontSize: 12, color: t.fg),
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(
                value: h,
                child: Text('${h.toString().padLeft(2, '0')}:00'),
              ),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}
