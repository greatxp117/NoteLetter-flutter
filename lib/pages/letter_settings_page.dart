import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/newsletter_settings.dart';
import '../models/scripture_newsletter_settings.dart';
import '../state/activation_message.dart';
import '../state/newsletter_notifier.dart';
import '../state/schedule.dart';
import '../state/scripture_letter_notifier.dart';
import '../state/settings_notifier.dart';
import '../theme/app_spacing.dart';
import '../widgets/kit/kit.dart';
import 'letters/readings_letter.dart';

/// Letter settings (`spec/screens/letters.md`) — `/letters/settings`.
///
/// A screen reached FROM another one, so it takes the §2.2 sub-screen header
/// rather than opening a chapter. Both letters are edited here and each saves
/// into its own document through its own endpoint: `fn_newsletter_settings` and
/// `fn_scripture_newsletter_settings` have **separate closed key sets**, and a
/// key crossing between them is a hard 400 that writes nothing.
///
/// This form lived inside `settings_page.dart` until F-05; it moved rather than
/// being copied, so there is still one of it.
class LetterSettingsPage extends StatefulWidget {
  const LetterSettingsPage({super.key});

  @override
  State<LetterSettingsPage> createState() => _LetterSettingsPageState();
}

/// The cadences the reference offers, in its order.
const _frequencies = [
  ('daily', 'Daily'),
  ('weekdays', 'Weekdays'),
  ('weekly', 'Weekly'),
];

const _emailRe = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';

class _LetterSettingsPageState extends State<LetterSettingsPage> {
  // The stored document is the truth; these are the edit in flight.
  bool _enabled = false;
  String _timezone = deviceTimezone();
  String _frequency = 'daily';
  final _deliveryTimeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  int _itemsPerLetter = 3;
  int _excludeRecentDays = 7;
  bool _populated = false;

  String? _outcome;
  String? _saveError;
  String? _scheduleError;
  bool _scheduleBusy = false;

  // The readings letter's own fields.
  final _rlTimeCtrl = TextEditingController();
  final _rlEmailCtrl = TextEditingController();
  bool _rlPopulated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsNotifier>();
      settings.loadAll().then((_) {
        if (!mounted) return;
        final stored = settings.newsletter;
        if (stored != null) _populateForm(stored);
      });
      context.read<ScriptureLetterNotifier>().load();
    });
  }

  void _populateForm(NewsletterSettings s) {
    setState(() {
      _populated = true;
      // Absent means never scheduled — the orchestrator needs `enabled`
      // truthy, so absent and false are one thing to it and must read the
      // same here.
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

  void _populateReadings(ScriptureNewsletterSettings s) {
    _rlPopulated = true;
    _rlTimeCtrl.text = s.deliveryTime;
    _rlEmailCtrl.text = s.emailAddress;
  }

  @override
  void dispose() {
    _deliveryTimeCtrl.dispose();
    _emailCtrl.dispose();
    _purposeCtrl.dispose();
    _rlTimeCtrl.dispose();
    _rlEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !RegExp(_emailRe).hasMatch(email)) {
      setState(() => _saveError = 'That does not look like an email address.');
      return;
    }
    setState(() {
      _outcome = null;
      _saveError = null;
    });
    // `enabled` is deliberately NOT sent here — the switch above owns it.
    final error = await context.read<SettingsNotifier>().saveLetterSettings(
          emailAddress: email,
          frequency: _frequency,
          deliveryTime: _deliveryTimeCtrl.text.trim(),
          timezone: _timezone,
          purposeText: _purposeCtrl.text.trim(),
          itemsPerNewsletter: _itemsPerLetter,
          excludeRecentDays: _excludeRecentDays,
        );
    if (!mounted) return;
    setState(() {
      _saveError = error;
      _outcome = error == null ? 'Letter settings saved.' : null;
    });
  }

  Future<void> _toggleSchedule(bool next) async {
    final settings = context.read<SettingsNotifier>();
    setState(() {
      _scheduleBusy = true;
      _scheduleError = null;
      _outcome = null;
    });
    // Turning on stores the zone too: `deliveryTime` alone is read as UTC by
    // the orchestrator, so "07:00" with no zone is not the hour the reader
    // picked. Write BEFORE the switch moves (ADR-022).
    final error = await settings.setScheduledDelivery(
      enabled: next,
      deliveryTime: _deliveryTimeCtrl.text.trim(),
      timezone: _timezone,
    );
    if (!mounted) return;
    setState(() {
      _scheduleBusy = false;
      _scheduleError = error;
      if (error == null) _enabled = next;
      // 2.30.0 — what the activation send did, from the response. Absent on
      // the off-switch and on a re-save.
      _outcome = error == null && next
          ? activationMessage(settings.lastActivation)
          : null;
    });
    if (error == null && next) {
      await context.read<NewsletterNotifier>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final rl = context.watch<ScriptureLetterNotifier>();
    final stored = rl.settings;
    if (stored != null && !_rlPopulated) _populateReadings(stored);

    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubScreenHeader(
            parentLabel: 'Letters',
            onBack: () => context.go('/letters'),
            eyebrow: 'The daily letter',
            standfirst:
                'A letter is from someone, to someone. Tune how yours arrives.',
          ),

          // ── Scheduled delivery ────────────────────────────────────────
          const SectionHeader('Scheduled delivery', first: true),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.schedule_outlined,
                title: _populated ? (_enabled ? 'On' : 'Off') : 'Loading…',
                // 2.29.0 rule 3 — stated from what was READ. Before the read
                // resolves this says nothing about arrival.
                description: !_populated
                    ? null
                    : '${scheduleSentence(
                        enabled: _enabled,
                        deliveryTime: _deliveryTimeCtrl.text.trim(),
                        timezone: _timezone,
                        frequency: _frequency,
                      )}. ${_enabled ? 'Turn this off to pause letters without losing any of these settings. “Send now” keeps working either way.' : 'Nothing is sent on a schedule while this is off. Your settings below are kept, and “Send now” still works. $activationHint'}',
                trailing: [
                  KitSwitch(
                    value: _enabled,
                    onChanged: !_populated || _scheduleBusy
                        ? null
                        : (v) => _toggleSchedule(v),
                  ),
                ],
              ),
              if (_scheduleError != null)
                KitRowSlot(child: KitFailureInline(_scheduleError!)),
            ],
          ),

          // ── The daily letter's form ───────────────────────────────────
          const SectionHeader('How it is written'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.alternate_email,
                title: 'Send to',
                // Unset is not an error: the backend falls back to the account
                // email and stores it (ADR-010), so this field fills itself
                // after the first send. Clients render it; they never compute
                // it, and must not claim the account email is unused.
                description:
                    'Leave it blank to use your account address — the first '
                    'letter fills this in with it.',
                below: KitTextField(
                  controller: _emailCtrl,
                  icon: Icons.mail_outline,
                  placeholder: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              KitSettingRow(
                icon: Icons.event_repeat_outlined,
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
                // ADR-011): a shorter rest lets "Send now" resurface content.
                description:
                    'After a passage appears in a letter it rests this long '
                    'before it can be chosen again. Lower it if “Send now” '
                    'says there’s nothing new.',
                below: KitStepper(
                  value: _excludeRecentDays,
                  min: 0,
                  max: 90,
                  // 4.39.0 (ADR-077): a FLOOR, not the whole rule.
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
                      // §14.2 — the rejection beside the control that refused.
                      KitFailureInline(_saveError!),
                      const SizedBox(height: AppSpacing.s2),
                    ],
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        KitButton(
                          settings.isSaving ? 'Saving…' : 'Save settings',
                          onPressed: settings.isSaving || !_populated
                              ? null
                              : _save,
                        ),
                        if (_outcome != null) KitRowNote(_outcome!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── A second letter (ADR-029) ─────────────────────────────────
          const SectionHeader('A second letter'),
          _ReadingsSettings(
            timeCtrl: _rlTimeCtrl,
            emailCtrl: _rlEmailCtrl,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}

/// The readings letter's settings — the SAME document the Letters screen's
/// card edits, and its own closed key set.
class _ReadingsSettings extends StatelessWidget {
  final TextEditingController timeCtrl;
  final TextEditingController emailCtrl;

  const _ReadingsSettings({required this.timeCtrl, required this.emailCtrl});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<ScriptureLetterNotifier>();
    // INV-24: a failed read of this document says nothing about whether the
    // letter is on, so it must not render as "off".
    if (n.error != null) {
      return KitFailureBlock(
        sentence: 'Your readings-letter settings could not be read.',
        detail: n.error!,
        onRetry: n.load,
      );
    }
    final cfg = n.settings;
    if (cfg == null) return KitRowNote('Loading…');

    return KitRowList(
      raised: true,
      rows: [
        KitSettingRow(
          icon: Icons.menu_book_outlined,
          title: 'The readings letter',
          description:
              'The day’s Mass readings, with the passages from your shelves '
              'that answer them. It arrives beside the letter above, at its '
              'own hour.',
          trailing: [
            KitSwitch(
              value: cfg.enabled,
              onChanged: n.isSaving
                  ? null
                  : (v) => v
                      ? n.turnOn()
                      : n.save(cfg.copyWith(enabled: false)),
            ),
          ],
        ),
        if (cfg.enabled) ...[
          KitSettingRow(
            icon: Icons.schedule_outlined,
            title: 'Arrives at',
            below: Row(
              children: [
                Expanded(
                  child: KitTextField(
                    controller: timeCtrl,
                    icon: Icons.schedule_outlined,
                    placeholder: '06:30',
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                // A client that sends `deliveryTime` sends `timezone` in the
                // same call (2.29.0) — which is why one control saves both.
                KitButton('Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: n.isSaving
                        ? null
                        : () => n.save(cfg.copyWith(
                              deliveryTime: timeCtrl.text.trim(),
                              timezone: cfg.timezone.isEmpty
                                  ? deviceTimezone()
                                  : cfg.timezone,
                            ))),
              ],
            ),
          ),
          KitSettingRow(
            icon: Icons.mail_outline,
            title: 'Email it to me',
            // 4.24.0 (ADR-061) — the switch that stops the MAIL without
            // stopping the letter. It is what the footer's one-click
            // unsubscribe flips, so a reader who used that link has to be able
            // to find this and turn it back on.
            description: cfg.emailEnabled
                ? 'The day’s readings arrive in your inbox as well as here.'
                : 'The readings are waiting here each morning; nothing is '
                    'emailed.',
            trailing: [
              KitSwitch(
                value: cfg.emailEnabled,
                onChanged: n.isSaving
                    ? null
                    : (v) => n.save(cfg.copyWith(emailEnabled: v)),
              ),
            ],
          ),
          KitSettingRow(
            icon: Icons.alternate_email,
            title: 'Send to',
            description:
                'Leave it blank to use your account address, or send the '
                'readings somewhere of its own.',
            below: Row(
              children: [
                Expanded(
                  child: KitTextField(
                    controller: emailCtrl,
                    icon: Icons.mail_outline,
                    placeholder: 'your account address',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                KitButton('Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: n.isSaving
                        ? null
                        : () => n.save(
                            cfg.copyWith(emailAddress: emailCtrl.text.trim()))),
              ],
            ),
          ),
          KitSettingRow(
            icon: Icons.calendar_month_outlined,
            title: 'Calendar',
            // SHOWN, not chosen — offering three equal choices would promise a
            // letter that cannot be sent.
            titleNote: calendarLabel,
            description: calendarNote,
          ),
        ],
        if (n.saveError != null)
          KitRowSlot(child: KitFailureInline(n.saveError!)),
      ],
    );
  }
}
