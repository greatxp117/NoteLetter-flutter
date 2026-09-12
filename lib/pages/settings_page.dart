import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../models/newsletter_settings.dart';
import '../state/activation_message.dart';
import '../state/auth_notifier.dart';
import '../state/schedule.dart';
import '../state/settings_notifier.dart';
import '../state/theme_notifier.dart';
import '../theme/app_spacing.dart';
import '../widgets/kit/kit.dart';
import 'settings/summaries_section.dart';

/// Settings (`spec/screens/settings.md` §Composition, ADR-041).
///
/// Reading frame (760) inside a scroll container · chapter opening (§2.1)
/// with the `Account · {email}` folio · sections opened by §3 headers, each a
/// raised row list of setting rows (`kit_rows.dart`) · segmented controls
/// (§6.8) in the control strips · the build stamp last.
///
/// The daily letter's form lives here until QUEUE F-05 gives it its own route
/// (`/letters/settings`, as the reference has); it is composed from the kit
/// so the move is a cut, not a rewrite. The "Run through setup again" row
/// lands with F-14.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// The cadences the reference offers, in its order.
const _frequencies = [
  ('daily', 'Daily'),
  ('weekdays', 'Weekdays'),
  ('weekly', 'Weekly'),
];

class _SettingsPageState extends State<SettingsPage> {
  // The letter form's state — the stored document is the truth; these are the
  // edit in flight, adopted from it on load.
  bool _enabled = true;
  String _timezone = deviceTimezone();
  String _frequency = 'daily';
  final _deliveryTimeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  int _itemsPerLetter = 5;
  int _excludeRecentDays = 7;

  /// What the last save said — the 2.30.0 outcome line, or "saved".
  String? _outcome;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsNotifier>().loadAll().then((_) {
        if (!mounted) return;
        final settings = context.read<SettingsNotifier>().newsletter;
        if (settings != null) _populateForm(settings);
      });
    });
  }

  void _populateForm(NewsletterSettings s) {
    setState(() {
      _enabled = s.enabled;
      // A stored zone always wins; the device guess is only a default.
      _timezone = s.timezone.isNotEmpty ? s.timezone : deviceTimezone();
      _frequency = s.frequency;
      _itemsPerLetter = s.itemsPerNewsletter;
      _excludeRecentDays = s.excludeRecentDays;
    });
    _deliveryTimeCtrl.text = s.deliveryTime;
    _emailCtrl.text = s.emailAddress;
    _purposeCtrl.text = s.purposeText;
  }

  @override
  void dispose() {
    _deliveryTimeCtrl.dispose();
    _emailCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNewsletter() async {
    final notifier = context.read<SettingsNotifier>();
    final current = notifier.newsletter ?? const NewsletterSettings();
    // 2.29.0 — a client that sends `deliveryTime` sends `timezone` in the
    // SAME call, or the orchestrator reads the stored time as UTC.
    final updated = current.copyWith(
      enabled: _enabled,
      frequency: _frequency,
      deliveryTime: _deliveryTimeCtrl.text.trim(),
      timezone: _timezone,
      emailAddress: _emailCtrl.text.trim(),
      purposeText: _purposeCtrl.text.trim(),
      itemsPerNewsletter: _itemsPerLetter,
      excludeRecentDays: _excludeRecentDays,
    );
    final wasEnabled = current.enabled;
    setState(() {
      _outcome = null;
      _saveError = null;
    });
    // Write BEFORE you move (ADR-022): nothing below moves until the PUT has
    // answered, and a rejection stays beside the control that refused it.
    final error = await notifier.saveNewsletter(updated);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saveError = error);
      return;
    }
    // 2.30.0 (ADR-031) — when this save TURNED delivery on, say what actually
    // happened rather than "saved". The backend decides whether a letter goes
    // now; this only reports it. Keyed on the transition, not the value.
    final activation = (!wasEnabled && _enabled)
        ? activationMessage(notifier.lastActivation)
        : null;
    setState(() => _outcome = activation ?? 'Letter settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final themeN = context.watch<ThemeNotifier>();
    final user = context.watch<AuthNotifier>().user;
    final who = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email ?? '');

    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChapterOpening(
            folio: 'Account · $who',
            title: 'Settings',
            standfirst:
                'How NoteLetter looks, how your letter behaves, and where '
                'your account stands.',
          ),

          // ── Appearance ────────────────────────────────────────────────
          const SectionHeader('Appearance', first: true),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Theme',
                description:
                    'Light, dark, or follow your system. The plum chrome '
                    'stays warm either way.',
                wideControl: true,
                trailing: [
                  KitSegmented(
                    segments: const [
                      KitSegment('Light', icon: Icons.wb_sunny_outlined),
                      KitSegment('System', icon: Icons.desktop_windows_outlined),
                      KitSegment('Dark', icon: Icons.dark_mode_outlined),
                    ],
                    selected: switch (themeN.themeMode) {
                      ThemeMode.light => 0,
                      ThemeMode.system => 1,
                      ThemeMode.dark => 2,
                    },
                    onChanged: (i) => themeN.setMode(const [
                      ThemeMode.light,
                      ThemeMode.system,
                      ThemeMode.dark,
                    ][i]),
                  ),
                ],
              ),
            ],
          ),

          // ── The daily letter ──────────────────────────────────────────
          const SectionHeader('The daily letter'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.mail_outline,
                title: 'Scheduled delivery',
                // 2.29.0: the schedule is STATED from what was read, never
                // assumed; 2.30.0: what turning it on does is said BEFORE the
                // switch is touched.
                description: settings.isLoading
                    ? 'Loading…'
                    : '${scheduleSentence(
                        enabled: _enabled,
                        deliveryTime: _deliveryTimeCtrl.text.trim(),
                        timezone: _timezone,
                        frequency: _frequency,
                      )}. ${_enabled ? 'Turn this off to pause letters without losing any of these settings. “Send now” keeps working either way.' : 'Nothing is sent on a schedule while this is off. Your settings below are kept, and “Send now” still works. $activationHint'}',
                trailing: [
                  KitSwitch(
                    value: _enabled,
                    onChanged: settings.isLoading
                        ? null
                        : (v) => setState(() => _enabled = v),
                  ),
                ],
              ),
              KitSettingRow(
                icon: Icons.alternate_email,
                title: 'Send to',
                description:
                    'Letters go to your account email until you set a '
                    'different address.',
                below: KitTextField(
                  controller: _emailCtrl,
                  icon: Icons.mail_outline,
                  placeholder: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              KitSettingRow(
                icon: Icons.schedule_outlined,
                title: 'How often, and when',
                description:
                    'The zone is yours to set — a time means nothing without '
                    'one.',
                below: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KitSegmented(
                      segments: [
                        for (final f in _frequencies) KitSegment(f.$2),
                      ],
                      selected: _frequencies
                          .indexWhere((f) => f.$1 == _frequency)
                          .clamp(0, _frequencies.length - 1),
                      onChanged: (i) =>
                          setState(() => _frequency = _frequencies[i].$1),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    KitTextField(
                      controller: _deliveryTimeCtrl,
                      icon: Icons.schedule_outlined,
                      placeholder: '07:00',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    KitSelect<String>(
                      icon: Icons.calendar_today_outlined,
                      value: _timezone,
                      options: timezoneOptions(_timezone),
                      label: (z) => z.replaceAll('_', ' '),
                      onChanged: (z) => setState(() => _timezone = z),
                    ),
                  ],
                ),
              ),
              KitSettingRow(
                icon: Icons.auto_stories_outlined,
                title: 'Passages per letter',
                below: KitStepper(
                  value: _itemsPerLetter,
                  min: 1,
                  max: 5,
                  unit:
                      '${_itemsPerLetter == 1 ? 'passage' : 'passages'} each morning',
                  onChanged: (v) => setState(() => _itemsPerLetter = v),
                ),
              ),
              KitSettingRow(
                icon: Icons.hourglass_empty_outlined,
                title: 'Rest a passage for',
                // The knob a "nothing new to send" result points at (2.2.0,
                // ADR-011).
                description:
                    'After a passage appears in a letter it rests this long '
                    'before it can be chosen again. Lower it if “Send now” '
                    'says there’s nothing new.',
                below: KitStepper(
                  value: _excludeRecentDays,
                  min: 0,
                  max: 90,
                  // 4.39.0 (ADR-077): a floor, not the whole rule.
                  unit: restDaysLabel(_excludeRecentDays),
                  onChanged: (v) => setState(() => _excludeRecentDays = v),
                ),
              ),
              KitSettingRow(
                icon: Icons.chat_bubble_outline,
                title: 'Your librarian',
                description:
                    'What you want to learn or achieve. Your letter weights '
                    'passages by it.',
                below: KitTextField(
                  controller: _purposeCtrl,
                  minLines: 2,
                  maxLines: 4,
                  placeholder:
                      'e.g. Help me connect ideas across philosophy readings…',
                ),
              ),
              KitRowSlot(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_saveError != null) ...[
                      // §14.2 — the rejection at the control that refused.
                      KitFailureInline(_saveError!),
                      const SizedBox(height: AppSpacing.s2),
                    ],
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        KitButton.primary(
                          settings.isSaving ? 'Saving…' : 'Save letter settings',
                          onPressed: settings.isSaving || settings.isLoading
                              ? null
                              : _saveNewsletter,
                        ),
                        if (_outcome != null) KitRowNote(_outcome!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Summaries (4.3.0 + 4.4.0, ADR-040) ────────────────────────
          const SummariesSection(),

          // ── Notifications (2.5.0, ADR-014) ────────────────────────────
          const SectionHeader('Notifications'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.notifications_none,
                title: 'Channels',
                description:
                    'How you hear about what NoteLetter does — on-screen, by '
                    'email or by push, at the severity you choose.',
                trailing: [
                  KitSettingLink('Manage channels',
                      onTap: () => context.go('/settings/notifications')),
                ],
              ),
            ],
          ),

          // ── Account ───────────────────────────────────────────────────
          const SectionHeader('Account'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.person_outline,
                leading: KitAvatarPlate(KitAvatarPlate.initialsOf(who)),
                title: (user?.displayName?.trim().isNotEmpty ?? false)
                    ? user!.displayName!
                    : 'Your account',
                description: user?.email,
                trailing: [
                  KitSettingLink('Sign out',
                      icon: Icons.logout,
                      onTap: () => context.read<AuthNotifier>().signOut()),
                ],
              ),
            ],
          ),

          const KitBuildStamp(
            contract: BuildInfo.contractPin,
            platform: BuildInfo.platform,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}
