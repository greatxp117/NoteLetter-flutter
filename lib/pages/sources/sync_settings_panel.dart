import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cloud_integration.dart';
import '../../shared/cloud_providers.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'folder_contents.dart' show cloudTypeLabel;
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
/// The file types a file store's sync can take — `include_types` ⊆ the
/// contract's set (`api/cloud-storage.md`), less `notion`. `epub` since
/// 4.120.0 (ADR-157): a folder sync may take books. Web: `CLOUD_TYPE_KEYS`.
const cloudFileTypes = ['pdf', 'docx', 'pptx', 'epub'];

/// The panel's last-sync line (`screens/sources.md` §Sync settings panel:
/// "Show `last_sync_at` ("Last synced …") when present"), web's `fmtLastSync`
/// to the minute in the reader's clock: `Last synced Jul 3, 1:00 AM`. Its OWN
/// line, not [CloudIntegration.lastSyncLabel]: that relative "Synced 106d ago"
/// is also the connect card's subtitle, and the card is not this panel's to
/// move (F-119).
String lastSyncedLine(int? ms) {
  if (ms == null || ms == 0) return 'Never synced automatically';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  // A no-break space holds the time to its AM/PM if the line ever wraps.
  return 'Last synced ${months[d.month - 1]} ${d.day}, $h:$m\u00a0'
      '${d.hour < 12 ? 'AM' : 'PM'}';
}

/// What the type control says (5.59.0, ADR-213; `screens/sources.md` §Sync
/// control), word for word with web `typesCopy`.
({String label, String note, String none}) syncTypesCopy(String provider) {
  if (provider == 'notion') {
    return (
      label: 'What a sync brings in',
      note: 'A sync looks through the databases you chose and brings in their '
          'pages while this is ticked. Pages you pick with Browse pages… come '
          'in either way.',
      none: 'Nothing is ticked, so a sync brings in nothing. Pages you pick '
          'with Browse pages… still come in.',
    );
  }
  final name = cloudProviders[provider]?.name ?? provider;
  return (
    label: 'File types a sync brings in',
    note: 'A sync looks through your sync folders and brings in only the '
        'ticked types. Every other file stays in $name, untouched. Files you '
        'pick with Browse files… come in either way.',
    none: 'Nothing is ticked, so a sync brings in nothing. Files you pick '
        'with Browse files… still come in.',
  );
}

class SyncSettingsPanel extends StatefulWidget {
  final String providerId;
  final CloudIntegration integration;

  /// Opened by its provider's "Sync settings" link under the §3 "Import from
  /// {provider}" header (web `CloudImportPanel`, ruled 2026-10-08 with the
  /// fixed connect card): the link is the disclosure, so the panel opens
  /// expanded and its own heading is the reference's first group label —
  /// AUTO-SYNC beside the last sync — not a second, tappable one.
  final bool embedded;

  const SyncSettingsPanel({
    super.key,
    required this.providerId,
    required this.integration,
    this.embedded = false,
  });

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
  static const _fileTypes = cloudFileTypes;
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

  /// The type control, for §Folder contents' "Change types".
  final _typesKey = GlobalKey();

  /// The type control's sentences, verbatim from §Sync control (5.59.0,
  /// ADR-213; web `typesCopy`).
  ({String label, String note, String none}) get _typesCopy =>
      syncTypesCopy(widget.providerId);

  final _patternsController = TextEditingController();
  final _patternsFocus = FocusNode();
  bool _saving = false;

  /// Which control [_saving] is, so only the one pressed draws the mark
  /// (§6.1 Busy). The whole panel is held either way.
  String? _pressed;
  bool _pressedIs(String key) => _saving && _pressed == key;
  late bool _open = widget.embedded;

  /// §14.2 — the last refusal, inline in the panel (spec: "400s show the
  /// validation message inline"). A toast is gone before the reader has found
  /// which control it was about.
  String? _error;

  @override
  void initState() {
    super.initState();
    _patternsController.text = widget.integration.excludePatterns.join(', ');
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
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Sends the WHOLE list. No `.take(50)`: a silent truncation is a writer
  /// that cannot fail — the server's 400 ("≤50") is the answer, and it is
  /// rendered.
  void _savePatterns() {
    final list = _parsedPatterns();
    if (list.join(', ') == widget.integration.excludePatterns.join(', ')) {
      return;
    }
    _save((c) => c.syncSettings(widget.providerId, excludePatterns: list),
        onRefused: () {
      // The revert goes to what the last READ stored (4.75.2): leaving the
      // refused text in the field reads as saved.
      _patternsController.text =
          widget.integration.excludePatterns.join(', ');
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
      _pressed = null;
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
  Future<String?> _saveFolders(List<String> ids, Map<String, String> names) async {
    setState(() => _saving = true);
    final err = await context.read<CloudNotifier>().syncSettings(
        widget.providerId,
        folderIds: ids,
        folderNames: names);
    if (!mounted) return err;
    setState(() {
      _saving = false;
      _pressed = null;
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

  /// A folder as a chip label: its stored name (5.9.0, `folder_names`), else
  /// the id cut at 14 — a folder chosen before names were stored has none.
  static String _chipLabel(String id, Map<String, String> names) =>
      names[id] ?? (id.length > 14 ? '${id.substring(0, 14)}…' : id);

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

    return _SyncFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.embedded)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The label keeps its width and the line takes the rest: an
                // Expanded label left the line too little room and broke
                // "1:00 AM" across two lines.
                Text('AUTO-SYNC', style: KitText.cfgLabel(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(lastSyncedLine(i.lastSyncAt),
                      textAlign: TextAlign.right,
                      style: KitText.meta(context)),
                ),
              ],
            )
          else
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
                              ? 'Auto-sync ${i.syncFrequency} · '
                                  '${lastSyncedLine(i.lastSyncAt)}'
                              : 'Auto-sync off · '
                                  '${lastSyncedLine(i.lastSyncAt)}',
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
                // Held while the save runs, at the token (web's panel is
                // 0.5; this was 0.6).
                opacity: _saving ? AppSpacing.heldOpacity : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 5),
                    // The reference's `.src-toggle` rows: a `--rule` above
                    // each (the group label is the first child, so neither row
                    // is `:first-child`), the name, then the kit's switch
                    // (§6.1) — a Material Switch drew an accent thumb on a
                    // pale track here, unlike every other switch.
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.rule))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Sync new files automatically',
                                style: KitText.body(context)),
                          ),
                          const SizedBox(width: 10),
                          KitSwitch(
                            value: i.autoSyncEnabled,
                        tooltip: 'Sync new files automatically',
                        busy: _pressedIs('auto'),
                        onChanged: (v) {
                          _pressed = 'auto';
                          _save((c) => c.syncSettings(
                              widget.providerId,
                              autoSyncEnabled: v));
                        },
                          ),
                        ],
                      ),
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
                    // sources.md §Sync settings panel (5.12.0, ADR-172).
                    // Drawn from the returned integration only.
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.rule))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Update changed files automatically',
                                style: KitText.body(context)),
                          ),
                          const SizedBox(width: 10),
                          KitSwitch(
                            value: i.autoUpdate,
                        tooltip: 'Update changed files automatically',
                        busy: _pressedIs('update'),
                        onChanged: (v) {
                          _pressed = 'update';
                          _save((c) => c.syncSettings(
                              widget.providerId,
                              autoUpdate: v));
                        },
                          ),
                        ],
                      ),
                    ),
                    KitProcNote(
                      'When a file changes in ${_providerLabel()}, its source '
                      'here is updated once it has gone 30 minutes without an '
                      'edit. Off: use Update from ${_providerLabel()} in the '
                      'reader.',
                      padding: const EdgeInsets.only(top: 6),
                    ),

                    _Label('Frequency'),
                    KitSegmented(
                      groupLabel: 'Frequency',
                      segments: [
                        for (final f in _frequencies)
                          KitSegment(_title(f), busy: _pressedIs('freq:$f')),
                      ],
                      // An unknown stored value selects NOTHING. `.clamp`
                      // turned -1 into 0 and drew "Hourly" — a claim about a
                      // schedule the server does not have.
                      selected: _frequencies.indexOf(i.syncFrequency),
                      onChanged: (n) {
                      _pressed = 'freq:${_frequencies[n]}';
                      _save((c) => c.syncSettings(
                          widget.providerId,
                          syncFrequency: _frequencies[n]));
                    },
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
                          onChanged: (v) {
                            _pressed = 'hour';
                            _save((c) => c.syncSettings(
                                widget.providerId, syncPreferredHour: v));
                          },
                        ),
                        if (_pressedIs('hour')) ...[
                          const SizedBox(width: 8),
                          KitBusyMark(size: 13, color: t.fgMuted),
                        ],
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
                              // Ruled 2026-10-14 (Xavier): the tooltip is the
                              // folder's name — the pill may cut it — and the
                              // whole id when it has none.
                              Tooltip(
                                message: i.folderNames[id] ?? id,
                                child: KitTag(
                                  _chipLabel(id, i.folderNames),
                                  // A name runs to 200 characters where the
                                  // cut id was 14: the pill stops at its row
                                  // and the name ends in an ellipsis (web
                                  // `.tag-source` max-width + `.tag-label`).
                                  clip: true,
                                  // "Remove folder {name or id}" (5.9.0).
                                  removeLabel:
                                      'Remove folder ${i.folderNames[id] ?? id}',
                                  removeBusy: _pressedIs('folder:$id'),
                                  onRemove: () {
                                    _pressed = 'folder:$id';
                                    _removeFolder(id);
                                  },
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
                        initialNames: i.folderNames,
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
                    // What the control decides, said where it is decided
                    // (5.59.0, ADR-213: "the import these types is unclear").
                    // `include_types` filters what a SYNC finds and nothing
                    // else: a file picked by hand is not filtered by it
                    // (`_classify_cloud_file`). Until 5.59.0 it said "Import
                    // these types · everything else is skipped entirely".
                    _Label(_typesCopy.label, key: _typesKey),
                    KitProcNote(_typesCopy.note,
                        padding: const EdgeInsets.only(bottom: 10)),
                    Semantics(
                      container: true,
                      label: _typesCopy.label,
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final type in _types)
                            KitTypeChoice(
                              // web `TYPE_CHOICE_LABEL[t] || cloudTypeLabel(t)`.
                              type == 'notion'
                                  ? 'Notion pages'
                                  : cloudTypeLabel(type),
                              checked: i.includeTypes.contains(type),
                              busy: _pressedIs('type:$type'),
                              onPressed: _saving
                                  ? null
                                  : () {
                                  _pressed = 'type:$type';
                                  final next = {...i.includeTypes};
                                      i.includeTypes.contains(type)
                                          ? next.remove(type)
                                          : next.add(type);
                                      _save((c) => c.syncSettings(
                                          widget.providerId,
                                          includeTypes: next.toList()));
                                    },
                            ),
                        ],
                      ),
                    ),
                    // No type ticked means a sync takes nothing (4.59.0,
                    // ADR-096). A hand-picked file is not filtered by it, so
                    // this does not say nothing can come in.
                    if (i.includeTypes.isEmpty)
                      KitProcNote(_typesCopy.none,
                          padding: const EdgeInsets.only(top: 6)),

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
                        busyChoice: !_saving || !(_pressed?.startsWith('rule:$type:') ?? false)
                            ? null
                            : int.parse(_pressed!.split(':').last),
                        onChanged: (next) {
                          _pressed = 'rule:$type:'
                              '${next == null ? 0 : (next.isAlways ? 2 : 1)}';
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

                    _Label('Exclude patterns', note: '≤50, glob'),
                    // One line, comma-separated, saved on blur or Enter (web's
                    // input). Every border named: the theme's `enabledBorder`
                    // and fill outlive `InputDecoration.collapsed`, and drew a
                    // second field inside this frame.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: AppRadius.mdR,
                        border: Border.all(color: t.border),
                      ),
                      child: TextField(
                        controller: _patternsController,
                        focusNode: _patternsFocus,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        style: KitText.small(context, color: t.fg),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: '*.tmp, draft-*',
                          hintStyle:
                              KitText.small(context, color: t.fgSubtle),
                        ),
                        onSubmitted: (_) => _patternsFocus.unfocus(),
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
  /// it is where "nothing downloaded" is said (ADR-083).
  final String? note;

  const _Label(this.text, {super.key, this.note});

  // `.cfg-group`'s rule and air, then `.cfg-label`: the name at one end and
  // the note at the other, the note dropping under it when they do not fit.
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: t.rule))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(text.toUpperCase(), style: KitText.cfgLabel(context)),
          if (note != null)
            Text(note!, style: KitText.cfgValue(context)),
        ],
      ),
    );
  }
}

/// The panel's frame: flat inside web's `.lx-cloud` (a service's page, under
/// `.dp-svc .sync-panel`), a card anywhere else.
class _SyncFrame extends StatelessWidget {
  final Widget child;
  const _SyncFrame({required this.child});

  @override
  Widget build(BuildContext context) => KitCloudScope.maybeOf(context) != null
      ? Padding(padding: const EdgeInsets.only(top: 6), child: child)
      : KitCard(padding: const EdgeInsets.all(16), child: child);
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
          style: KitText.monoFigure(context, fontSize: 12),
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

  /// §6.1 Busy: which position's own write is in flight (0 Import, 1 Ask over,
  /// 2 Always ask).
  final int? busyChoice;

  const _RuleRow({
    required this.type,
    required this.rule,
    required this.onChanged,
    this.busyChoice,
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
          ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 88),
              child: Text(cloudTypeLabel(type).toUpperCase(),
                  style: KitText.cfgLabel(context))),
          Semantics(
            container: true,
            label: cloudTypeLabel(type),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                KitDayPill('Import',
                  on: selected == 0,
                  busy: busyChoice == 0,
                  onPressed: () => onChanged(null)),
                KitDayPill('Ask over…',
                  on: selected == 1,
                  busy: busyChoice == 1,
                    onPressed: () => onChanged(ReviewRule.overMb(mb))),
                KitDayPill('Always ask',
                  on: selected == 2,
                  busy: busyChoice == 2,
                    onPressed: () => onChanged(const ReviewRule.always())),
              ],
            ),
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
