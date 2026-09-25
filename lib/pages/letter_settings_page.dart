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
import '../services/analytics.dart';
import '../services/auth_service.dart';

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
    // On the accepted path only: a rejected save changed nothing, and it is
    // already counted once as a `request_failed`.
    if (error == null) Analytics.track('letter_settings_saved');
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

    final email = _emailCtrl.text.trim();
    final accountEmail = AuthService.instance.currentUser?.email ?? '';

    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The reference's `.letter-config` (LetterSettings.jsx): a back
          // control, the title as a HEADING, and then groups — each a mono
          // caps label over its control, a hairline between them. It was a
          // stack of icon-plate setting rows here, which is Settings' form,
          // not this one's (F-51).
          KitBackControl('Letters', onTap: () => context.go('/letters')),
          const SizedBox(height: 16),
          const KitConfigHeading(
            'The daily letter',
            standfirst:
                'A letter is from someone, to someone. Tune how yours arrives.',
          ),

          // ── Scheduled delivery ────────────────────────────────────────
          KitFieldGroup(
            label: 'Scheduled delivery',
            note: _populated ? (_enabled ? 'On' : 'Off') : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitConfigToggle(
                  icon: Icons.schedule_outlined,
                  // 2.29.0 rule 3 — stated from what was READ. Before the
                  // read resolves this says nothing about arrival.
                  title: !_populated
                      ? 'Loading…'
                      : scheduleSentence(
                          enabled: _enabled,
                          deliveryTime: _deliveryTimeCtrl.text.trim(),
                          timezone: _timezone,
                          frequency: _frequency,
                        ),
                  description: _enabled
                      ? 'Turn this off to pause letters without losing any of '
                            'these settings. “Send now” keeps working either way.'
                      : 'Nothing is sent on a schedule while this is off. Your '
                            'settings below are kept, and “Send now” still works. '
                            '$activationHint',
                  value: _enabled,
                  // Write before the switch moves (ADR-022): `_enabled`
                  // changes only when the call resolves.
                  onChanged: !_populated || _scheduleBusy
                      ? null
                      : (v) => _toggleSchedule(v),
                ),
                if (_scheduleError != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  KitFailureInline(_scheduleError!),
                ],
              ],
            ),
          ),

          // ── Send to ───────────────────────────────────────────────────
          KitFieldGroup(
            label: 'Send to',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitTextField(
                  controller: _emailCtrl,
                  icon: Icons.mail_outline,
                  placeholder: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                ),
                // Unset is not an error: the backend falls back to the
                // account email and stores it (ADR-010). Only a user with no
                // account email either can't be delivered to.
                if (email.isEmpty && _populated)
                  KitConfigHint(
                    accountEmail.isNotEmpty
                        ? 'Letters will go to $accountEmail until you set a '
                              'different address.'
                        : 'Letters can’t be delivered until you add an '
                              'address.',
                    icon: Icons.error_outline,
                    warn: accountEmail.isEmpty,
                  ),
              ],
            ),
          ),

          // ── How often ─────────────────────────────────────────────────
          KitFieldGroup(
            label: 'How often',
            child: KitSegmented(
              segments: [for (final f in _frequencies) KitSegment(f.$2)],
              selected: _frequencies
                  .indexWhere((f) => f.$1 == _frequency)
                  .clamp(0, _frequencies.length - 1),
              onChanged: (i) => setState(() => _frequency = _frequencies[i].$1),
            ),
          ),

          // ── Arrives at ────────────────────────────────────────────────
          // The zone is shown as an editable value, not derived silently: a
          // time with no zone is UTC (2.29.0).
          KitFieldGroup(
            label: 'Arrives at',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

          KitFieldGroup(
            label: 'Passages per letter',
            child: KitStepper(
              value: _itemsPerLetter,
              min: 1,
              max: 5,
              unit:
                  '${_itemsPerLetter == 1 ? 'passage' : 'passages'} each morning',
              onChanged: (v) => setState(() => _itemsPerLetter = v),
            ),
          ),

          KitFieldGroup(
            label: 'Rest a passage for',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitStepper(
                  value: _excludeRecentDays,
                  min: 0,
                  max: 90,
                  // 4.39.0 (ADR-077): a FLOOR, not the whole rule.
                  unit: restDaysLabel(_excludeRecentDays),
                  onChanged: (v) => setState(() => _excludeRecentDays = v),
                ),
                // The knob a "nothing new to send" result points at (2.2.0,
                // ADR-011): a shorter rest lets "Send now" resurface content.
                const SizedBox(height: 6),
                const Lede(
                  'After a passage appears in a letter it rests this long '
                  'before it can be chosen again. Lower it if “Send now” says '
                  'there’s nothing new.',
                  fontSize: 14,
                  height: 22,
                ),
              ],
            ),
          ),

          // The mission this client edits beside the letter it weights. The
          // reference edits the same key from Settings (`Your librarian`).
          KitFieldGroup(
            label: 'Your librarian',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitTextField(
                  controller: _purposeCtrl,
                  minLines: 2,
                  maxLines: 4,
                  placeholder:
                      'e.g. Help me connect ideas across philosophy readings…',
                ),
                const SizedBox(height: 6),
                const Lede(
                  'What you want to learn or achieve. Your letter weights '
                  'passages by it.',
                  fontSize: 14,
                  height: 22,
                ),
              ],
            ),
          ),

          // ── A second letter (ADR-029) ─────────────────────────────────
          _ReadingsSettings(timeCtrl: _rlTimeCtrl, emailCtrl: _rlEmailCtrl),

          const SizedBox(height: 20),
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
                onPressed: settings.isSaving || !_populated ? null : _save,
              ),
              if (_outcome != null) KitRowNote(_outcome!),
            ],
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

    return KitFieldGroup(
      label: 'A second letter',
      note: cfg.enabled ? 'On' : 'Off',
      second: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitConfigToggle(
            icon: Icons.menu_book_outlined,
            title: 'The readings letter',
            description:
                'The day’s Mass readings, with the passages from your shelves '
                'that answer them. It arrives beside the letter above, at its '
                'own hour.',
            value: cfg.enabled,
            onChanged: n.isSaving
                ? null
                : (v) => v ? n.turnOn() : n.save(cfg.copyWith(enabled: false)),
          ),
          if (cfg.enabled) ...[
            KitConfigField(
              label: 'Arrives at',
              child: Row(
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
                  KitButton(
                    'Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: n.isSaving
                        ? null
                        : () => n.save(
                            cfg.copyWith(
                              deliveryTime: timeCtrl.text.trim(),
                              timezone: cfg.timezone.isEmpty
                                  ? deviceTimezone()
                                  : cfg.timezone,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // 4.24.0 (ADR-061) — the switch that stops the MAIL without
            // stopping the letter. It is what the footer's one-click
            // unsubscribe flips, so a reader who used that link has to be
            // able to find this and turn it back on.
            KitConfigField(
              label: 'Email it to me',
              trailing: KitSwitch(
                value: cfg.emailEnabled,
                onChanged: n.isSaving
                    ? null
                    : (v) => n.save(cfg.copyWith(emailEnabled: v)),
              ),
              note: cfg.emailEnabled
                  ? 'The day’s readings arrive in your inbox as well as here.'
                  : 'The readings are waiting here each morning; nothing is '
                        'emailed.',
            ),
            KitConfigField(
              label: 'Send to',
              note:
                  'Leave it blank to use your account address, or send the '
                  'readings somewhere of its own.',
              child: Row(
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
                  KitButton(
                    'Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: n.isSaving
                        ? null
                        : () => n.save(
                            cfg.copyWith(emailAddress: emailCtrl.text.trim()),
                          ),
                  ),
                ],
              ),
            ),
            // SHOWN, not chosen — offering three equal choices would promise
            // a letter that cannot be sent.
            KitConfigField(
              label: 'Calendar',
              note: calendarNote,
              child: KitConfigStatic(calendarLabel),
            ),
          ],
          if (n.saveError != null) ...[
            const SizedBox(height: AppSpacing.s2),
            KitFailureInline(n.saveError!),
          ],
        ],
      ),
    );
  }
}
