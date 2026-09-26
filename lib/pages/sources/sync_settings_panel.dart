import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_integration.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'sync_folder_picker.dart';

/// Tier-C sync settings (`screens/sources.md` §Sync control, 1.4.0/ADR-007),
/// recomposed against the kit (ADR-041).
///
/// Collapsible per provider: auto-sync toggle, frequency, preferred hour
/// (shown in the reader's time, stored and said as UTC), sync folders (the
/// folders-only picker, F-47), include-types, exclude-patterns. Every edit sends **only the changed key**
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

  /// The supported type keys, **per provider** (`screens/sources.md` §Sync
  /// control): `pdf`, `docx`, `pptx` for a file store, and `notion` only for
  /// Notion. One list for all four offered a NOTION pill on Google Drive and
  /// three file types on Notion — controls that could never match a file.
  /// **`pptx` was missing from 1.4.0 to 4.45.0**: a type absent from this list
  /// is simply a control the reader never sees, and nothing fails.
  static const _fileTypes = ['pdf', 'docx', 'pptx'];
  List<String> get _types =>
      widget.providerId == 'notion' ? const ['notion'] : _fileTypes;

  /// The backend's own default when the field was never written
  /// (`main.py` stamps 3 on connect, and the orchestrator reads `?? 3`).
  static const _defaultHour = 3;

  /// `fn_sync_settings` validates `folder_ids` at ≤20 — web's
  /// `SYNC_FOLDER_CAP`.
  static const _folderCap = 20;

  /// The sync-folder chooser is open.
  bool _picking = false;

  /// *Import these types*, for §Folder contents' "Change types".
  final _typesKey = GlobalKey();

  final _patternsController = TextEditingController();
  final _patternsFocus = FocusNode();
  bool _saving = false;
  bool _open = false;

  /// §14.2 — the last refusal, inline in the panel (spec: "400s show the
  /// validation message inline"). A toast is gone before the reader has found
  /// which control it was about.
  String? _error;

  @override
  void initState() {
    super.initState();
    _patternsController.text = widget.integration.excludePatterns.join('\n');
    // Saved when the field lets go of focus — tapping away, tabbing out,
    // collapsing the panel. `onEditingComplete` never fires here: on a
    // multi-line field Enter inserts a newline, and Chrome has no done key,
    // so the only save path this field had was one no reader could reach.
    _patternsFocus.addListener(_onPatternsFocus);
  }

  void _onPatternsFocus() {
    if (!_patternsFocus.hasFocus && mounted) _savePatterns();
  }

  List<String> _parsedPatterns() => _patternsController.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Sends the WHOLE list. No `.take(50)`: a silent truncation is a writer
  /// that cannot fail — the server's 400 ("≤50") is the answer, and it is
  /// rendered.
  void _savePatterns() {
    final list = _parsedPatterns();
    if (list.join('\n') == widget.integration.excludePatterns.join('\n')) {
      return;
    }
    _save((c) => c.syncSettings(widget.providerId, excludePatterns: list),
        onRefused: () {
      // The revert goes to what the last READ stored (4.75.2): leaving the
      // refused text in the field reads as saved.
      _patternsController.text =
          widget.integration.excludePatterns.join('\n');
    });
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
    _patternsFocus.removeListener(_onPatternsFocus);
    _patternsController.dispose();
    _patternsFocus.dispose();
    super.dispose();
  }

  Future<void> _save(Future<String?> Function(CloudNotifier c) call,
      {VoidCallback? onRefused}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await call(context.read<CloudNotifier>());
    if (!mounted) return;
    setState(() {
      _saving = false;
      // A 400 is a validation message written for a person — shown as it
      // came, inline, beside the controls it is about.
      _error = err;
    });
    if (err != null) onRefused?.call();
  }

  /// The whole folder list, saved; the panel moves only on the answer. Unlike
  /// [_save], a refusal is returned to the picker that asked rather than
  /// drawn at the foot of the panel — the picker is where the reader is
  /// looking, and it holds the draft they would correct.
  Future<String?> _saveFolders(List<String> ids) async {
    setState(() => _saving = true);
    final err = await context
        .read<CloudNotifier>()
        .syncSettings(widget.providerId, folderIds: ids);
    if (!mounted) return err;
    setState(() {
      _saving = false;
      if (err == null) _picking = false;
    });
    return err;
  }

  /// A chip's `×`: the list without that folder, and the chip goes only when
  /// the returned `integration` no longer holds it.
  void _removeFolder(String id) => _save((c) => c.syncSettings(
      widget.providerId,
      folderIds: [
        for (final f in widget.integration.folderIds)
          if (f != id) f
      ]));

  /// A folder id as a chip label. The integration stores ids, not names —
  /// the reference draws the id, cut at 14.
  static String _chipLabel(String id) =>
      id.length > 14 ? '${id.substring(0, 14)}…' : id;

  /// The UTC hour [utcHour] as a wall-clock time here. The server compares
  /// the plain UTC hour; the reader thinks in their own.
  static String _localClock(int utcHour) {
    final now = DateTime.now().toUtc();
    final local =
        DateTime.utc(now.year, now.month, now.day, utcHour).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
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
                        'will sync until you pick sync folders below.',
                        padding: EdgeInsets.only(top: 6),
                      ),

                    _Label('Frequency'),
                    KitSegmented(
                      segments: [
                        for (final f in _frequencies) KitSegment(_title(f)),
                      ],
                      // An unknown stored value selects NOTHING. `.clamp`
                      // turned -1 into 0 and drew "Hourly" — a claim about a
                      // schedule the server does not have.
                      selected: _frequencies.indexOf(i.syncFrequency),
                      onChanged: (n) => _save((c) => c.syncSettings(
                          widget.providerId,
                          syncFrequency: _frequencies[n])),
                    ),

                    // Daily and weekly only: the orchestrator ignores the
                    // hour on Hourly (`_scheduled_sync_due`), so a control
                    // there would set a value nothing reads. The reference
                    // hides it the same way (NoteLetter-web@f050fe2).
                    if (i.syncFrequency != 'hourly') ...[
                      _Label('Preferred hour'),
                      Row(
                      children: [
                        _HourField(
                          hour: i.syncPreferredHour ?? _defaultHour,
                          label: _localClock,
                          onChanged: (v) => _save((c) => c.syncSettings(
                              widget.providerId, syncPreferredHour: v)),
                        ),
                        const SizedBox(width: 10),
                        // Rendered in the reader's time, stored and sent as
                        // the plain UTC hour the orchestrator compares
                        // against — and the control SAYS the UTC hour, so
                        // neither is implied (sources.md §Sync control).
                        Flexible(
                          child: Text(
                            'your time · ${(i.syncPreferredHour ?? _defaultHour).toString().padLeft(2, '0')}:00 UTC',
                            style: KitText.meta(context),
                          ),
                        ),
                      ],
                      ),
                    ],

                    // Sync folders — the scope (§Sync control: "reuse the
                    // file picker in folders-only mode, ≤20; chips with
                    // remove affordances"). The chips are the RETURNED
                    // integration's list and nothing else.
                    _Label('Sync folders',
                        note: '${i.folderIds.length}/$_folderCap'),
                    if (i.folderIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final id in i.folderIds)
                              Tooltip(
                                message: id,
                                child: KitTag(
                                  _chipLabel(id),
                                  removeLabel: 'Remove folder $id',
                                  onRemove: () => _removeFolder(id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: KitSettingLink(
                        _picking
                            ? 'Close'
                            : i.folderIds.isEmpty
                                ? 'Choose folders…'
                                : 'Change folders…',
                        icon: null,
                        onTap: () => setState(() => _picking = !_picking),
                      ),
                    ),
                    if (_picking)
                      SyncFolderPicker(
                        provider: widget.providerId,
                        initial: i.folderIds,
                        cap: _folderCap,
                        allowEmpty: true,
                        onConfirm: _saveFolders,
                        onCancel: () => setState(() => _picking = false),
                        onFixTypes: () {
                          final ctx = _typesKey.currentContext;
                          if (ctx != null) Scrollable.ensureVisible(ctx);
                        },
                      ),

                    // **Two adjacent decisions, presented as two** (ADR-083):
                    // this one answers *never this type* — the file is dropped
                    // at discovery with no row, no count and no record it was
                    // seen. The one below answers *ask me about this one*.
                    _Label('Import these types',
                        key: _typesKey,
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
                    // No type ticked means nothing imports (4.59.0, ADR-096).
                    // Until then it meant the opposite and silently imported
                    // everything, under this control's own "everything else
                    // is skipped" label.
                    if (i.includeTypes.isEmpty)
                      const KitProcNote(
                          'No types are ticked — nothing will be imported from '
                          'this account until you choose at least one.',
                          padding: EdgeInsets.only(top: 6)),

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

                    _Label('Exclude patterns — one glob per line, ≤50',
                        note: 'saved when you leave the field'),
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
                        onTapOutside: (_) => _patternsFocus.unfocus(),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: KitFailureInline(_error!),
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

  const _Label(this.text, {super.key, this.note});

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
  /// The stored UTC hour.
  final int hour;

  /// How an hour is drawn — the reader's wall clock.
  final String Function(int utcHour) label;
  final ValueChanged<int> onChanged;

  const _HourField(
      {required this.hour, required this.label, required this.onChanged});

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
                child: Text(label(h)),
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
