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
  /// The supported type keys. **`pptx` was missing from 1.4.0 to 4.45.0** and
  /// both clients rendered three — a synced deck could not be included or
  /// reviewed, and nothing failed, because a type absent from this list is
  /// simply a control the reader never sees. `notion` is the Notion provider's
  /// own key.
  static const _types = ['pdf', 'docx', 'pptx', 'notion'];

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
                    if (inert)
                      const KitProcNote(
                        'Auto-sync is on but no folders are chosen — nothing '
                        'will sync until you pick sync folders.',
                        padding: EdgeInsets.only(top: 6),
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

                    // **Two adjacent decisions, presented as two** (ADR-083):
                    // this one answers *never this type* — the file is dropped
                    // at discovery with no row, no count and no record it was
                    // seen. The one below answers *ask me about this one*.
                    _Label('Import these types',
                        note: 'everything else is skipped entirely'),
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

                    // **Ask first** (4.45.0, ADR-083) — the adjacent, different
                    // decision. Only the types actually being imported are
                    // listed: a type that is skipped entirely is never
                    // reviewed, so a rule on it would be a control that cannot
                    // fire.
                    _Label('Ask before importing',
                        note: 'held for review, nothing downloaded'),
                    for (final type in _types.where(i.includeTypes.contains))
                      _RuleRow(
                        type: type,
                        rule: i.reviewRules[type],
                        onChanged: (next) {
                          // `review_rules` REPLACES, it does not merge — so
                          // the whole desired map goes every time.
                          final map = {
                            for (final e in i.reviewRules.entries)
                              e.key: e.value.toJson(),
                          };
                          next == null
                              ? map.remove(type)
                              : map[type] = next.toJson();
                          _save((c) => c.syncSettings(widget.providerId,
                              reviewRules: map));
                        },
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

  /// The reference's `.v` clause — what the control means, beside its name.
  /// On the two review controls it is load-bearing rather than decorative:
  /// it is where "everything else is skipped entirely" and "nothing
  /// downloaded" are said (ADR-083).
  final String? note;

  const _Label(this.text, {this.note});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: Eyebrow(text)),
            if (note != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(note!, style: KitText.meta(context))),
            ],
          ],
        ),
      );
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

/// One type's review rule: three positions, and a size field on the middle one.
///
/// **Labelled by size, never by length.** "Ask before importing PDFs over 5 MB"
/// is a statement about bytes; there is no page count to promise, because no
/// provider reports one and reading it would cost the download the rule exists
/// to avoid (ADR-083).
class _RuleRow extends StatelessWidget {
  final String type;
  final ReviewRule? rule;

  /// Null clears the rule for this type — which is *Import*, the absence of a
  /// rule rather than a third mode.
  final ValueChanged<ReviewRule?> onChanged;

  const _RuleRow({
    required this.type,
    required this.rule,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mb = rule?.overMb ?? 5;
    final selected = rule == null ? 0 : (rule!.isAlways ? 2 : 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 52, child: Eyebrow(type.toUpperCase())),
          KitSegmented(
            segments: const [
              KitSegment('Import'),
              KitSegment('Ask over…'),
              KitSegment('Always ask'),
            ],
            selected: selected,
            onChanged: (i) => onChanged(switch (i) {
              0 => null,
              1 => ReviewRule.overMb(mb),
              _ => const ReviewRule.always(),
            }),
          ),
          if (selected == 1)
            KitStepper(
              value: mb,
              min: 1,
              max: 100,
              unit: 'MB',
              onChanged: (v) => onChanged(ReviewRule.overMb(v)),
            ),
        ],
      ),
    );
  }
}
