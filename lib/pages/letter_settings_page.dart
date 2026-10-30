import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/newsletter.dart';
import '../models/newsletter_settings.dart';
import '../models/scripture_newsletter_settings.dart';
import '../models/tag.dart';
import '../shared/cooldown.dart';
import '../state/activation_message.dart';
import '../state/newsletter_notifier.dart';
import '../state/schedule.dart';
import '../state/scripture_letter_notifier.dart';
import '../state/settings_notifier.dart';
import '../state/tags_notifier.dart';
import '../widgets/kit/kit.dart';
import 'letters/letter_preview.dart';
import 'letters/readings_letter.dart' show calendarLabel, calendarNote;
import '../services/error_text.dart';
import '../services/firestore_service.dart';
import '../services/analytics.dart';
import '../services/auth_service.dart';

/// The signed-in account's address: where an unset *Send to* delivers
/// (ADR-010), and whether Send now has anywhere to send at all.
String _signedInEmail() => AuthService.instance.currentUser?.email ?? '';

/// Letter settings (`spec/screens/letters.md` §Composition, *Letter
/// settings*; web `LetterSettings.jsx`) — `/letters/settings`, in direction
/// D: the crumb back to *Letters*, the folio stating the schedule, the sheet's
/// Contents and the latest letter's figures, and the settings as four
/// numbered sections — *Delivery*, *Composition*, *The readings letter*, *The
/// latest letter*.
///
/// Both letters are edited here and each saves into its own document through
/// its own endpoint: `fn_newsletter_settings` and
/// `fn_scripture_newsletter_settings` have **separate closed key sets**, and a
/// key crossing between them is a hard 400 that writes nothing — which is why
/// the readings letter saves on its own, after the daily letter's Save.
class LetterSettingsPage extends StatefulWidget {
  /// The signed-in account's address — a seam for the tests, which have no
  /// signed-in account.
  final String Function() accountEmail;

  const LetterSettingsPage({super.key, this.accountEmail = _signedInEmail});

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

/// The readings letter's fields that draw their own refusal (`.rl-ferr`).
const _rlFields = {'deliveryTime', 'timezone', 'emailEnabled', 'emailAddress'};

/// The passages stepper's top: the settings panel's largest choice
/// (LetterQuick: 3 · 5 · 7), so a count set there is one this page shows and
/// keeps. The endpoint takes up to 20; a stored count above this is shown,
/// and `+` never lowers it (web `MAX_PASSAGES`).
const _maxPassages = 7;

/// What a field shows before the read answers, and for a key the stored
/// document does not carry: what the BUILD uses (area_letter.py — `daily`,
/// `07:00`, 5, 7). One source: the model's own defaults. It read *weekdays*
/// and *3* until direction D on web, and 3 passages here.
const _blank = NewsletterSettings();

class _LetterSettingsPageState extends State<LetterSettingsPage> {
  // The stored document is the truth; these are the edit in flight.
  bool _enabled = false;
  String _timezone = deviceTimezone();
  String _frequency = _blank.frequency;
  final _deliveryTimeCtrl = TextEditingController(text: _blank.deliveryTime);
  final _emailCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  int _itemsPerLetter = _blank.itemsPerNewsletter;
  int _excludeRecentDays = _blank.excludeRecentDays;

  /// The settings read answered — until then the folio says nothing about
  /// the schedule and Save cannot fire.
  bool _populated = false;

  /// The settings read was refused (§14.1, INV-24): *Delivery* is the failure
  /// alone, and *Composition* is not drawn — a form rendered against the
  /// defaults would be a confident claim about a schedule nobody read, and
  /// Save would then make it true.
  String? _cfgError;

  final _scroll = ScrollController();
  final KitSections _sec = KitSections(const [
    'delivery',
    'composition',
    'latest',
  ]);

  /// Draw from — held as shelf TITLES, which is what `topicFilters` stores
  /// (web LetterSettings). A title no current shelf carries is dropped on the
  /// next save, as the reference's id-mapped selection drops it.
  final Set<String> _drawFrom = {};

  bool _saving = false;

  /// The last Save landed and nothing has been touched since (web's *Saved*).
  bool _saved = false;
  String? _saveError;

  /// What the activation send did (2.30.0, ADR-031), under the switch.
  String? _schedMsg;
  String? _scheduleError;
  bool _scheduleBusy = false;

  /// The last letter the backend BUILT (4.98.0, ADR-131) — the preview's one
  /// source. `_letterLoaded` false until the read answers; `_letterError` is a
  /// failed read, never "none built" (INV-24).
  Newsletter? _letter;
  bool _letterLoaded = false;
  String? _letterError;
  String? _sendMessage;
  String? _sendError;

  // The readings letter's own fields.
  final _rlTimeCtrl = TextEditingController();
  final _rlEmailCtrl = TextEditingController();
  bool _rlPopulated = false;

  /// Which readings-letter control wrote last, so its refusal stands beside
  /// it (`.rl-ferr`), not at the foot of the form.
  String? _rlField;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSettings();
      context.read<ScriptureLetterNotifier>().load();
      _loadLetter();
    });
  }

  /// Named so the §14.1 block's retry re-issues exactly this read.
  Future<void> _loadSettings() async {
    final settings = context.read<SettingsNotifier>();
    setState(() {
      _cfgError = null;
      _populated = false;
    });
    await settings.loadAll();
    if (!mounted) return;
    final stored = settings.newsletter;
    final error = settings.error;
    if (error != null || stored == null) {
      setState(
        () => _cfgError = error ?? 'Could not load newsletter settings.',
      );
      return;
    }
    _populateForm(stored);
  }

  Future<void> _loadLetter() async {
    try {
      final n = await FirestoreService.instance.getLatestLetter();
      if (!mounted) return;
      setState(() {
        _letter = n;
        _letterLoaded = true;
        _letterError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _letter = null;
        _letterError = describeSdkError(e);
      });
    }
  }

  /// Send now keeps its §Endpoints behaviour beside the preview. It says
  /// where the truth will be, never when the mail arrives (INV-23).
  Future<void> _sendNow() async {
    setState(() {
      _sendMessage = null;
      _sendError = null;
    });
    final error = await context.read<NewsletterNotifier>().requestNewsletter();
    if (!mounted) return;
    setState(() {
      // A cooldown with its number is Send now's wait and says itself, on
      // this screen and on Letters alike (4.107.0, ADR-140).
      _sendError = Cooldowns.instance.waiting(WaitKey.letterSend())
          ? null
          : error;
      _sendMessage = error == null
          ? 'On its way — it appears on the Letters screen in a few minutes, '
                'and its row shows what happened to the email.'
          : null;
    });
  }

  void _populateForm(NewsletterSettings s) {
    setState(() {
      _populated = true;
      _saved = false;
      // Absent means never scheduled — the orchestrator needs `enabled`
      // truthy, so absent and false are one thing to it and must read the
      // same here.
      _enabled = s.enabled;
      // A stored zone always wins; never stored, the device's zone is the
      // value the reader is about to save — not one that is stored.
      _timezone = s.timezone.isNotEmpty ? s.timezone : deviceTimezone();
      _frequency = s.frequency;
      _itemsPerLetter = s.itemsPerNewsletter;
      _excludeRecentDays = s.excludeRecentDays;
      _drawFrom
        ..clear()
        ..addAll(s.topicFilters);
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

  /// A draft moved: the form no longer says *Saved*.
  void _edit(VoidCallback change) => setState(() {
    change();
    _saved = false;
  });

  @override
  void dispose() {
    _deliveryTimeCtrl.dispose();
    _emailCtrl.dispose();
    _purposeCtrl.dispose();
    _rlTimeCtrl.dispose();
    _rlEmailCtrl.dispose();
    _scroll.dispose();
    _sec.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !RegExp(_emailRe).hasMatch(email)) {
      setState(() => _saveError = 'That does not look like an email address.');
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _saveError = null;
    });
    // `enabled` is deliberately NOT sent here — the switch above owns it.
    final shelves = context.read<TagsNotifier>().tags;
    final error = await context.read<SettingsNotifier>().saveLetterSettings(
      // Titles, not ids: they bias scoring by topic rather than scoping.
      topicFilters: topicFiltersFor(shelves, _drawFrom),
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
      _saving = false;
      _saveError = error;
      _saved = error == null;
    });
  }

  Future<void> _toggleSchedule(bool next) async {
    final settings = context.read<SettingsNotifier>();
    setState(() {
      _scheduleBusy = true;
      _scheduleError = null;
      _schedMsg = null;
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
      _schedMsg = error == null && next
          ? activationMessage(settings.lastActivation)
          : null;
    });
    if (error == null && next) {
      await context.read<NewsletterNotifier>().load();
    }
  }

  /// A readings-letter write, remembered by the control that made it.
  void _rlWrite(String field, Future<void> Function() write) {
    setState(() => _rlField = field);
    write();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final rl = context.watch<ScriptureLetterNotifier>();
    final shelves = context.watch<TagsNotifier>().tags;
    final stored = rl.settings;
    if (stored != null && !_rlPopulated) _populateReadings(stored);

    final email = _emailCtrl.text.trim();
    final accountEmail = widget.accountEmail();
    final sending = context.watch<NewsletterNotifier>().isSending;

    // Contents lists only the sections the page draws: no Composition over a
    // refused read, no readings letter until its document answers or refuses.
    final rlShown = rl.settings != null || rl.error != null;
    final secs = [
      const KitContentsItem('delivery', 'Delivery'),
      if (_cfgError == null)
        const KitContentsItem('composition', 'Composition'),
      if (rlShown) const KitContentsItem('readings', 'The readings letter'),
      const KitContentsItem('latest', 'The latest letter'),
    ];
    final ids = [for (final s in secs) s.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;
    int n(String id) => ids.indexOf(id);

    // The folio states the schedule the form holds — nothing until the read
    // answers, and nothing over a refused one.
    final freq = _frequencies
        .firstWhere((f) => f.$1 == _frequency, orElse: () => _frequencies.first)
        .$2;
    final time = _deliveryTimeCtrl.text.trim();
    final schedule = !_populated || _cfgError != null
        ? null
        : (_enabled ? '$freq at ${kitClock(time) ?? time}' : 'Delivery off');

    final letter = _letter;
    final built = letter != null
        ? (letter.generatedAt == null ? '—' : kitLongDay(letter.generatedAt!))
        : (_letterLoaded && _letterError == null ? 'None yet' : '—');
    // ADR-109: a record with no chunk_ids is unmeasured — the dash, never 0.
    final passages = letter != null && letter.chunkIdsKnown
        ? '${letter.chunkIds.length}'
        : '—';

    final save = KitDSaveRow(
      button: KitButton(
        _saving ? 'Saving…' : (_saved ? 'Saved' : 'Save settings'),
        key: const ValueKey('lset-save'),
        icon: _saved && !_saving ? Icons.check : null,
        onPressed: _saving || settings.isSaving || !_populated ? null : _save,
      ),
      error: _saveError,
    );

    return KitDPage(
      folio: ['Letters', 'Settings', ?schedule].join(' · '),
      back: KitDBackControl('Letters', onTap: () => context.go('/letters')),
      // On a phone the folio cannot fit beside the crumb, so it stands under
      // it, as web's `flex-wrap` puts it (Support's fits, and stays inline).
      crumbStacks: true,
      title: 'Letter Settings',
      stand: 'A letter is from someone, to someone. Tune how yours arrives.',
      controller: _scroll,
      sections: _sec,
      sheet: KitDSheet(
        label: 'Letter settings',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(
              key: const ValueKey('lset-contents'),
              items: secs,
              sections: _sec,
            ),
            KitFigures(
              label: 'The latest letter',
              rows: [('Built', built), ('Passages', passages)],
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitDNumbered(
            sectionKey: _sec.keyOf('delivery'),
            n: n('delivery'),
            title: 'Delivery',
            children: _cfgError != null
                ? [
                    // §14.1 — the form IS the region that failed.
                    KitFailureBlock(
                      sentence:
                          'Your letter settings could not be read, so there '
                          'is nothing here to change yet.',
                      detail: _cfgError!,
                      onRetry: _loadSettings,
                    ),
                  ]
                : !_populated
                // Until the read answers, every control here would show the
                // BUILD's defaults (Daily, 07:00, 5 passages, the switch
                // off) — figures nobody measured, drawn as if they were this
                // reader's letter (INV-24, ADR-109; web 22f9461). So the
                // sections stand over the kit skeleton and the controls
                // arrive with what is stored; Save stays held below.
                ? const [
                    KitSkeletonLines(
                      key: ValueKey('lset-loading'),
                      lines: [
                        KitSkelLine(0.4),
                        KitSkelLine(),
                        KitSkelLine(0.7),
                        KitSkelLine(),
                        KitSkelLine(0.6),
                        KitSkelLine(),
                        KitSkelLine(0.5),
                      ],
                    ),
                  ]
                : _delivery(email, accountEmail),
          ),
          if (_cfgError == null)
            KitDNumbered(
              sectionKey: _sec.keyOf('composition'),
              n: n('composition'),
              title: 'Composition',
              children: _populated
                  ? [..._composition(shelves), save]
                  : [
                      const KitSkeletonLines(
                        lines: [
                          KitSkelLine(0.5),
                          KitSkelLine(),
                          KitSkelLine(0.6),
                          KitSkelLine(),
                          KitSkelLine(0.7),
                        ],
                      ),
                      save,
                    ],
            ),
          // A second letter, not a selection mode on this one (ADR-029). It
          // has its own settings document and saves on its own, which is why
          // it sits after the daily letter's Save.
          if (rlShown)
            KitDNumbered(
              sectionKey: _sec.keyOf('readings'),
              n: n('readings'),
              title: 'The readings letter',
              children: _readings(rl),
            ),
          KitDNumbered(
            sectionKey: _sec.keyOf('latest'),
            n: n('latest'),
            title: 'The latest letter',
            children: [
              LetterPreviewPane(
                letter: _letter,
                loaded: _letterLoaded,
                error: _letterError,
                sending: sending,
                // Disabled with no address to send to (the reference's rule).
                onSend: sending || (email.isEmpty && accountEmail.isEmpty)
                    ? null
                    : _sendNow,
                sendMessage: _sendMessage,
                sendError: _sendError,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 1 Delivery ─────────────────────────────────────────────────────────

  List<Widget> _delivery(String email, String accountEmail) => [
    KitFieldGroup(
      label: 'Scheduled delivery',
      note: _populated ? (_enabled ? 'On' : 'Off') : null,
      first: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitConfigToggle(
            key: const ValueKey('lset-schedule'),
            icon: Icons.schedule_outlined,
            // 2.29.0 rule 3 — stated from what was READ. Before the read
            // resolves this says nothing about arrival.
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
            // Write before the switch moves (ADR-022): `_enabled` changes
            // only when the call resolves.
            onChanged: !_populated || _scheduleBusy ? null : _toggleSchedule,
          ),
          if (_schedMsg != null) KitDConfigSub(_schedMsg!),
          KitDSlot(
            _scheduleError == null ? null : KitFailureInline(_scheduleError!),
          ),
        ],
      ),
    ),
    KitFieldGroup(
      label: 'Send to',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTextField(
            key: const ValueKey('lset-email'),
            controller: _emailCtrl,
            icon: Icons.mail_outline,
            placeholder: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _edit(() {}),
          ),
          // Unset is not an error: the backend falls back to the account
          // email and stores it (ADR-010). Only a user with no account email
          // either can't be delivered to.
          if (email.isEmpty && _populated)
            KitConfigHint(
              accountEmail.isNotEmpty
                  ? 'Letters will go to $accountEmail until you set a '
                        'different address.'
                  : 'Letters can’t be delivered until you add an address.',
              icon: Icons.error_outline,
              warn: accountEmail.isEmpty,
            ),
        ],
      ),
    ),
    KitFieldGroup(
      label: 'How often',
      // §34 — a DRAFT until Save, so the switch moves with the choice; Save
      // is the write.
      child: KitSlideSwitch<String>(
        key: const ValueKey('lset-frequency'),
        label: 'How often',
        expand: true,
        value: _frequency,
        onChanged: (v) => _edit(() => _frequency = v),
        options: [for (final f in _frequencies) KitSlideOption(f.$1, f.$2)],
      ),
    ),
    // The zone is shown as an editable value, not derived silently: a time
    // with no zone is UTC (2.29.0).
    KitFieldGroup(
      label: 'Arrives at',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTextField(
            key: const ValueKey('lset-time'),
            controller: _deliveryTimeCtrl,
            icon: Icons.schedule_outlined,
            placeholder: _blank.deliveryTime,
            onChanged: (_) => _edit(() {}),
          ),
          KitDSlot(
            KitSelect<String>(
              icon: Icons.calendar_today_outlined,
              value: _timezone,
              options: timezoneOptions(_timezone),
              label: (z) => z.replaceAll('_', ' '),
              onChanged: (z) => _edit(() => _timezone = z),
            ),
          ),
        ],
      ),
    ),
  ];

  // ── 2 Composition ──────────────────────────────────────────────────────

  List<Widget> _composition(List<Tag> shelves) => [
    KitFieldGroup(
      label: 'Passages per letter',
      first: true,
      // 1 to 7; a stored count above 7 is shown, and `+` (held at the top)
      // never lowers it.
      child: KitStepper(
        key: const ValueKey('lset-passages'),
        value: _itemsPerLetter,
        min: 1,
        max: _maxPassages,
        unit: '${_itemsPerLetter == 1 ? 'passage' : 'passages'} each morning',
        onChanged: (v) => _edit(() => _itemsPerLetter = v),
      ),
    ),
    KitFieldGroup(
      label: 'Rest a passage for',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitStepper(
            key: const ValueKey('lset-rest'),
            value: _excludeRecentDays,
            min: 0,
            max: 90,
            // 4.39.0 (ADR-077): a FLOOR, not the whole rule.
            unit: restDaysLabel(_excludeRecentDays),
            onChanged: (v) => _edit(() => _excludeRecentDays = v),
          ),
          // The knob a "nothing new to send" result points at (2.2.0,
          // ADR-011): a shorter rest lets "Send now" resurface content.
          const KitDConfigSub(
            'After a passage appears in a letter it rests this long before '
            'it can be chosen again. Lower it if “Send now” says there’s '
            'nothing new.',
            top: 6,
          ),
        ],
      ),
    ),
    // ── Draw from — the shelves the letter leans on ───────────────────────
    if (shelves.isNotEmpty)
      LetterDrawFrom(
        shelves: shelves,
        selected: _drawFrom,
        onChanged: (title, v) =>
            _edit(() => v ? _drawFrom.add(title) : _drawFrom.remove(title)),
      ),
    // The mission the letter weights passages by. Web edits the same key from
    // Settings (`Your librarian`); this client's Settings does not, so it
    // stays here, inside the daily letter's Save.
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
            onChanged: (_) => _edit(() {}),
          ),
          const KitDConfigSub(
            'What you want to learn or achieve. Your letter weights passages '
            'by it.',
            top: 6,
          ),
        ],
      ),
    ),
  ];

  // ── 3 The readings letter ──────────────────────────────────────────────

  List<Widget> _readings(ScriptureLetterNotifier rl) {
    final read = rl.error == null
        ? null
        : KitFailureInline(
            'Your readings-letter settings could not be read — ${rl.error}',
          );
    final cfg = rl.settings;
    // INV-24 (ADR-071): a first read that never answered is not "off".
    if (cfg == null) return [?read];
    String? refused(String field) =>
        rl.saveError != null && _rlField == field ? rl.saveError : null;
    // A refusal stands beside the field that wrote; one whose field is not
    // drawn (the switch's own, a write made while the letter is off, or one
    // from the Letters page) stands under the switch.
    final placed = cfg.enabled && _rlFields.contains(_rlField);
    final held = rl.isSaving;
    return [
      KitFieldGroup(
        label: 'A second letter',
        note: cfg.enabled ? 'On' : 'Off',
        first: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitConfigToggle(
              key: const ValueKey('lset-readings'),
              icon: Icons.menu_book_outlined,
              title: 'The readings letter',
              description:
                  'The day’s Mass readings, with the passages from your '
                  'shelves that answer them. It arrives beside the letter '
                  'above, at its own hour.',
              value: cfg.enabled,
              // Writes before it moves (ADR-022): the notifier adopts the
              // value only once the PUT has answered.
              onChanged: held
                  ? null
                  : (v) => _rlWrite(
                      'enabled',
                      () => v
                          ? rl.turnOn()
                          : rl.save(cfg.copyWith(enabled: false)),
                    ),
            ),
            KitDSlot(
              rl.saveError == null || placed
                  ? null
                  : KitFailureInline(rl.saveError!),
            ),
            if (cfg.enabled) ...[
              KitConfigField(
                label: 'Arrives at',
                error: refused('deliveryTime'),
                child: KitConfigInline(
                  field: KitTextField(
                    controller: _rlTimeCtrl,
                    icon: Icons.schedule_outlined,
                    placeholder: '06:30',
                  ),
                  // A client that sends `deliveryTime` sends `timezone` in the
                  // same call (2.29.0) — which is why one control saves both.
                  action: KitButton(
                    'Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: held
                        ? null
                        : () => _rlWrite(
                            'deliveryTime',
                            () => rl.save(
                              cfg.copyWith(
                                deliveryTime: _rlTimeCtrl.text.trim(),
                                timezone: cfg.timezone.isEmpty
                                    ? deviceTimezone()
                                    : cfg.timezone,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              KitConfigField(
                label: 'Time zone',
                error: refused('timezone'),
                // Moves when the stored document does (write before you move).
                child: KitSelect<String>(
                  value: cfg.timezone.isEmpty ? deviceTimezone() : cfg.timezone,
                  options: timezoneOptions(cfg.timezone),
                  label: (z) => z.replaceAll('_', ' '),
                  onChanged: held
                      ? null
                      : (z) => _rlWrite(
                          'timezone',
                          () => rl.save(cfg.copyWith(timezone: z)),
                        ),
                ),
              ),
              // 4.24.0 (ADR-061) — the switch that stops the MAIL without
              // stopping the letter. It is what the footer's one-click
              // unsubscribe flips, so a reader who used that link has to be
              // able to find this and turn it back on.
              KitConfigField(
                label: 'Email it to me',
                error: refused('emailEnabled'),
                trailing: KitSwitch(
                  value: cfg.emailEnabled,
                  tooltip: 'Email the readings letter',
                  onChanged: held
                      ? null
                      : (v) => _rlWrite(
                          'emailEnabled',
                          () => rl.save(cfg.copyWith(emailEnabled: v)),
                        ),
                ),
                note: cfg.emailEnabled
                    ? 'The day’s readings arrive in your inbox as well as '
                          'here.'
                    : 'The readings are waiting here each morning; nothing '
                          'is emailed.',
              ),
              KitConfigField(
                label: 'Send to',
                error: refused('emailAddress'),
                note:
                    'Leave it blank to use your account address, or send the '
                    'readings somewhere of its own.',
                child: KitConfigInline(
                  field: KitTextField(
                    controller: _rlEmailCtrl,
                    icon: Icons.mail_outline,
                    placeholder: 'your account address',
                    keyboardType: TextInputType.emailAddress,
                    enabled: cfg.emailEnabled,
                  ),
                  action: KitButton(
                    'Save',
                    variant: KitButtonVariant.secondary,
                    onPressed: held || !cfg.emailEnabled
                        ? null
                        : () => _rlWrite(
                            'emailAddress',
                            () => rl.save(
                              cfg.copyWith(
                                emailAddress: _rlEmailCtrl.text.trim(),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // SHOWN, not chosen — offering three equal choices would
              // promise a letter that cannot be sent.
              KitConfigField(
                label: 'Calendar',
                note: calendarNote,
                child: const KitConfigStatic(calendarLabel),
              ),
              KitConfigFoot(
                held
                    ? 'Saving…'
                    : 'Your daily letter keeps arriving either way.',
              ),
            ],
            // INV-24 (ADR-071): a later read that failed says so here too.
            KitDSlot(read),
          ],
        ),
      ),
    ];
  }
}

/// What **Draw from** saves: the selected shelves' TITLES, in shelf order —
/// `topicFilters` biases scoring by topic rather than scoping to a shelf. A
/// stored title no current shelf carries is dropped, as web's id-mapped
/// selection drops it.
List<String> topicFiltersFor(List<Tag> shelves, Set<String> selected) => [
  for (final t in shelves)
    if (selected.contains(t.title)) t.title,
];

/// **Draw from** (web LetterSettings `.cfg-group`): a [KitFieldGroup] whose
/// note counts the shelves in play (`all shelves` when none are), over one
/// [KitSourceToggle] per shelf — each under a `--rule`, the first too (the
/// group's label is the reference's first child, so no row is).
class LetterDrawFrom extends StatelessWidget {
  final List<Tag> shelves;
  final Set<String> selected;
  final void Function(String title, bool on) onChanged;

  const LetterDrawFrom({
    super.key,
    required this.shelves,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final on = topicFiltersFor(shelves, selected).length;
    return KitFieldGroup(
      label: 'Draw from',
      note: on == 0 ? 'all shelves' : kitCounted(on, 'shelf', 'shelves'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in shelves)
            KitSourceToggle(
              label: s.title,
              colorToken: s.color,
              value: selected.contains(s.title),
              onChanged: (v) => onChanged(s.title, v),
            ),
        ],
      ),
    );
  }
}
