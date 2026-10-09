import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_integration.dart';
import '../../models/organization_settings.dart';
import '../../shared/cloud_providers.dart';
import '../../state/cloud_notifier.dart';
import '../../state/org_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// Settings → Sources (`screens/settings.md` §Sources section; web
/// `SettingsView` `SourcesSection`): the ONE home of the auto-organization
/// settings, ruled 2026-10-09. In order: the confidence threshold, the default
/// reorganize mode, and per CONNECTED provider either **Enable organizing**
/// (which explains the write-scope grant and hands off to the provider) or,
/// once the grant is write-ready, its three capability switches and the way
/// back to its organized folders on Sources.
///
/// Until the ruling this section was headed Organization and held only the
/// per-provider door; the threshold, the mode and the switches were drawn on
/// Sources (`OrganizationSettingsPanel`), while the reference drew them here.
/// The Sources page now links here (`/settings/sources`), and [focus] is how
/// that route opens Settings at this section.
///
/// Nothing is drawn while no provider is connected, as on the reference.
class SourcesSection extends StatefulWidget {
  /// Scroll this section into view once it is drawn — the `/settings/sources`
  /// route. It is drawn only after the integrations read lands, so a scroll on
  /// the page's first frame would find nothing to scroll to.
  final bool focus;

  const SourcesSection({super.key, this.focus = false});

  @override
  State<SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<SourcesSection> {
  /// The reference's order for this section (web `ORG_PROVIDERS`), which is
  /// not the connect grid's.
  static const _order = ['google_drive', 'onedrive', 'dropbox', 'notion'];

  /// The reference's three capabilities (web `ORG_CAPABILITIES`): the flag
  /// each writes, its label, its description.
  static const _capabilities = [
    (
      'readmes_enabled',
      'Folder READMEs',
      'A README.noteletter.md in each organized folder saying what belongs '
          'there. Your edits always win.'
    ),
    (
      'out_of_place_enabled',
      'Out-of-place detection',
      'Files that don’t match their folder get moved when NoteLetter is '
          'confident, suggested when not.'
    ),
    (
      'auto_placement_enabled',
      'Place new uploads',
      'New documents you add to NoteLetter are filed into the right cloud '
          'folder too.'
    ),
  ];

  String? _busy;
  String? _error;
  double? _dragThreshold; // the drag in flight; the stored value otherwise
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    // Without these reads every provider renders as NOT connected, which is
    // an invitation to connect an account that is already connected, and the
    // settings render as never chosen (§14).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CloudNotifier?>()?.loadIntegrations();
      final org = context.read<OrgNotifier?>();
      if (org != null && !org.settingsLoaded) org.loadSettings();
    });
  }

  Future<void> _enable(String provider) async {
    final org = context.read<OrgNotifier?>();
    if (org == null) return;
    setState(() {
      _busy = provider;
      _error = null;
    });
    final err = await org.enableOrganization(provider);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  /// One write; the controls draw what the notifier STORED, so a refusal
  /// leaves them where they were and says why under the section (write
  /// before you move).
  Future<void> _save(Map<String, dynamic> partial) async {
    final org = context.read<OrgNotifier?>();
    if (org == null) return;
    setState(() {
      _busy = 'settings';
      _error = null;
    });
    final err = await org.updateSettings(partial);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  void _focusOnce() {
    if (!widget.focus || _scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier?>();
    if (cloud == null) return const SizedBox.shrink();
    final connected = <(String, CloudIntegration)>[
      for (final p in _order)
        if (cloud.integrationFor(p) case final i?) (p, i),
    ];
    if (connected.isEmpty) return const SizedBox.shrink();
    _focusOnce();

    final org = context.watch<OrgNotifier?>();
    final settings = org?.settings;
    final loaded = org?.settingsLoaded ?? false;
    final threshold = _dragThreshold ?? settings?.confidenceThreshold ?? 0.75;
    final mode = settings?.defaultReorgMode == 'copy' ? 'copy' : 'split';
    final t = Tokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Sources'),
        // §14 before the controls: a failed read drawn as the defaults is a
        // threshold and a mode this reader never chose, and the first nudge
        // would save them.
        if (org?.settingsError != null)
          KitFailureBlock(
            sentence: 'Your organization settings could not be read.',
            detail: org!.settingsError!,
            onRetry: () => org.loadSettings(),
          ),
        KitRowList(
          raised: true,
          rows: [
            if (loaded) ...[
              KitSettingRow(
                icon: Icons.tune,
                title: 'Confidence threshold',
                description: 'At or above ${(threshold * 100).round()}% '
                    'NoteLetter acts automatically; below it, it asks first. '
                    'Every automatic action stays reviewable in Sources.',
                below: Slider(
                  value: threshold.clamp(0.5, 0.95),
                  min: 0.5,
                  max: 0.95,
                  divisions: 9,
                  activeColor: t.accent,
                  inactiveColor: t.border,
                  semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  // One write per drag, sent when the drag ends — a call per
                  // frame would be one write per pixel.
                  onChanged: _busy != null
                      ? null
                      : (v) => setState(() => _dragThreshold = v),
                  onChangeEnd: (v) {
                    setState(() => _dragThreshold = null);
                    _save({
                      'confidence_threshold':
                          double.parse(v.toStringAsFixed(2))
                    });
                  },
                ),
              ),
              KitSettingRow(
                icon: Icons.call_split,
                title: 'Default reorganize mode',
                description: 'Where a reorganization plan starts for each '
                    'section. Split moves the section out of its document '
                    'once it is copied (you confirm first); Copy leaves the '
                    'document whole. You can change either one in the plan.',
                wideControl: true,
                trailing: [
                  KitSegmented(
                    segments: const [KitSegment('Split'), KitSegment('Copy')],
                    selected: mode == 'copy' ? 1 : 0,
                    onChanged: (i) {
                      final next = i == 1 ? 'copy' : 'split';
                      if (_busy == null && next != mode) {
                        _save({'default_reorg_mode': next});
                      }
                    },
                  ),
                ],
              ),
            ],
            for (final (p, i) in connected)
              KitSettingRow(
                icon: cloudProviders[p]!.icon,
                title: cloudProviders[p]!.name,
                // The link drops under the copy on a phone: "Choose organized
                // folders in Sources" beside the icon is wider than a phone
                // row (it overflowed by 7.5 at 390 in the 2026-10-09 frames).
                wideControl: true,
                description: i.orgWriteReady
                    ? null
                    : (!i.orgEnabled && i.orgScopeLevel == 'read'
                        ? 'Write access wasn’t granted — reconnect and approve '
                            'all permissions to turn organization on.'
                        : 'Organizing needs permission to move files and '
                            'write READMEs in your storage. You’ll approve '
                            'this with the provider.'),
                below: i.orgWriteReady && loaded
                    ? _Capabilities(
                        provider: p,
                        name: cloudProviders[p]!.name,
                        flags: settings!.configFor(p),
                        capabilities: _capabilities,
                        enabled: _busy == null,
                        onChanged: (flag, v) => _save({
                          'providers': {
                            p: {'enabled': true, flag: v}
                          }
                        }),
                      )
                    : null,
                trailing: [
                  if (i.orgWriteReady)
                    KitSettingLink('Choose organized folders in Sources',
                        onTap: () => context.go('/sources'))
                  else
                    KitSettingLink('Enable organizing',
                        onTap: _busy != null ? null : () => _enable(p)),
                ],
              ),
          ],
        ),
        if (_error != null) KitFailureInline(_error!),
      ],
    );
  }
}

/// A write-ready provider's three switches (web `ORG_CAPABILITIES`). A switch
/// is ON only when the flag AND the provider's `enabled` are — the
/// reference's `!!flags[cap] && !!flags.enabled` — and it draws the STORED
/// value: the switch moves when the notifier does, never on the tap.
class _Capabilities extends StatelessWidget {
  final String provider;
  final String name;
  final OrgProviderConfig flags;
  final List<(String, String, String)> capabilities;
  final bool enabled;
  final void Function(String flag, bool value) onChanged;

  const _Capabilities({
    required this.provider,
    required this.name,
    required this.flags,
    required this.capabilities,
    required this.enabled,
    required this.onChanged,
  });

  bool _value(String flag) {
    if (!flags.enabled) return false;
    return switch (flag) {
      'readmes_enabled' => flags.readmesEnabled,
      'out_of_place_enabled' => flags.outOfPlaceEnabled,
      _ => flags.autoPlacementEnabled,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (flag, label, desc) in capabilities)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: KitText.body(context)),
                      Text(
                        provider == 'notion' && flag == 'out_of_place_enabled'
                            ? '$desc Notion pages can’t be moved by its API — '
                                'NoteLetter copies and links back instead.'
                            : desc,
                        style: KitText.meta(context),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: '$name: $label',
                  child: Switch(
                    value: _value(flag),
                    activeThumbColor: t.accent,
                    onChanged: enabled ? (v) => onChanged(flag, v) : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
