/// The readings letter (contract 2.24.0 ADR-029; 2.26.0 ADR-030; 4.24.0
/// ADR-061).
///
/// A **second**, opt-in letter that follows the day's lectionary readings and
/// searches the reader's own library for passages against them. Turning it on
/// changes nothing about the daily letter — not its schedule, not its
/// recipient, not its selection. It is never a mode of it.
///
/// Four rules this surface exists to keep, each of which has bitten:
///
///   * **No send action.** `fn_build_scripture_newsletter` is an OIDC-only
///     worker with no `fn_request_*` counterpart, so a "send now" button here
///     would be wired to something that answers it with a 403 — the 1.5.1
///     defect exactly, and unrecoverable rather than merely slow.
///   * **`enabled` and `emailEnabled` are two controls and must not be
///     merged** (4.24.0): the first stops the letter being built, the second
///     stops only the mail, and it is the second that the footer's one-click
///     unsubscribe flips.
///   * The calendar is **shown, not chosen**: `roman` is the only one the
///     shipped table answers completely.
///   * The off state **must not name today's citations** — the lectionary
///     table lives on the backend, so a client asserting them would be
///     authoring lectionary knowledge in the one place a reader cannot check.
library;

import 'package:flutter/material.dart' show Icons, TextEditingController;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/newsletter.dart';
import '../../models/scripture_newsletter_settings.dart';
import '../../shared/dates.dart';
import '../../state/schedule.dart';
import '../../state/scripture_letter_notifier.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'delivery.dart';

/// The one calendar offered, because one calendar has readings.
///
/// 2.25.0 populated `roman` (Sundays and weekdays); `rcl` is a Sunday-and-
/// principal-feast lectionary by nature, and `anglican` was removed outright at
/// 2.25.1 when its data turned out to be generated from the date rather than
/// published. Offering three equal choices would promise a letter that cannot
/// be sent, so the active calendar is rendered as a **value** plus a note on
/// what is missing. The endpoint's accepted set is deliberately wider.
const calendarId = 'roman';
const calendarLabel = 'Roman';
const calendarNote =
    'Revised Common and Anglican aren’t in the lectionary yet.';

/// Letters' *The readings letter* section (direction D, screens/letters.md
/// §Composition *Letters*, column 2): a §31 small head with *Settings* (the
/// page's panel) while on, then the card while on or the opt-in while not.
/// **Hidden until its settings document answers**, so an opt-in never flashes
/// for someone already opted in; a refused read draws nothing here — the page
/// puts §14.2 in its place (INV-24: a failed read is not evidence it is off).
class ReadingsLetterSection extends StatelessWidget {
  final List<Newsletter> issues;
  final void Function(Newsletter) onOpen;
  final VoidCallback onSettings;

  const ReadingsLetterSection({
    super.key,
    required this.issues,
    required this.onOpen,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final n = context.watch<ScriptureLetterNotifier>();
    final cfg = n.settings;
    if (n.error != null || cfg == null) return const SizedBox.shrink();

    final latest = issues.isEmpty
        ? null
        : issues.firstWhere(
            (i) => i.status != 'empty',
            orElse: () => issues.first,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'The readings letter',
          small: true,
          actions: [if (cfg.enabled) KitHxLink('Settings', onTap: onSettings)],
        ),
        if (cfg.enabled)
          _OnCard(
            cfg: cfg,
            issue: latest,
            onPreview: latest == null ? null : () => onOpen(latest),
            onSettings: onSettings,
          )
        else
          _OptIn(busy: n.isSaving, error: n.saveError, onTurnOn: n.turnOn),
      ],
    );
  }
}

/// Letters' *Readings sent* (direction D, column 4): a §31 small head,
/// counted, over the readings letters' rows as a ruled register. Nothing
/// without any.
class ReadingsSentSection extends StatelessWidget {
  final List<Newsletter> issues;
  final void Function(Newsletter) onOpen;

  const ReadingsSentSection({
    super.key,
    required this.issues,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'Readings sent',
          small: true,
          meta: kitCounted(issues.length, 'letter'),
        ),
        // The daily archive's own row (`.letter-row.rl-row`) — not §4.1
        // source rows — in a register (`.dp-letters .archive-list`).
        KitLetterRowList(
          register: true,
          rows: [
            for (var i = 0; i < issues.length; i++)
              _archiveRow(issues[i], issues.length - i),
          ],
        ),
      ],
    );
  }

  /// A readings letter is filed by its **day**, not by a title.
  Widget _archiveRow(Newsletter n, int number) {
    final badge = n.status == 'empty'
        ? const LetterBadge('No readings')
        : letterBadge(
            status: n.status,
            deliveryState: n.delivery?.state,
            trigger: n.trigger,
          );
    final refs = n.readings.map((r) => r.ref).where((r) => r.isNotEmpty);
    final note = n.status == 'empty'
        ? (n.errorMessage ?? 'No readings for this day')
        : n.status == 'email_failed'
        ? (n.errorMessage ?? 'The email did not go out.')
        : (deliveryNote(
                state: n.delivery?.state,
                detail: n.delivery?.detail,
                attempts: n.delivery?.attempts ?? 0,
              ) ??
              refs.join('  ·  '));
    final found = n.passagesFound ?? 0;
    return KitLetterRow(
      key: ValueKey('d-rlrow-${n.id}'),
      number: number,
      title: n.liturgicalDay?.title ?? 'Readings',
      kind: 'Readings',
      refs: true,
      lede: note,
      // Stored AS SENT, so "5 of 23" stays honest as the library grows.
      figures:
          '${n.passagesSent ?? 0} of $found '
          '${found == 1 ? 'passage' : 'passages'}',
      date: shortDate(n.generatedAt),
      badge: badge.text,
      settled: badge.settled,
      onTap: n.status != 'empty' && n.readings.isNotEmpty
          ? () => onOpen(n)
          : null,
    );
  }
}

/// The readings letter's own rows in the Letters settings panel (web
/// `ReadingsQuick`; LetterQuick's `extra`), under the daily letter's: *The
/// readings letter* label, *Daily readings* with its switch — `Arrives at
/// {time}` / `Off` — and, while on, its hour with its zone. Every control
/// draws what was STORED and moves only when the write comes back (write
/// before you move): turning it on writes the whole starting document
/// ([ScriptureLetterNotifier.turnOn]); off and the hour are writes of the
/// document with that one change. The hour is a draft committed on blur or
/// Enter; a refused write puts the field back to what is stored. A refusal is
/// §14.2 under the rows.
class ReadingsQuick extends StatefulWidget {
  const ReadingsQuick({super.key});

  @override
  State<ReadingsQuick> createState() => _ReadingsQuickState();
}

class _ReadingsQuickState extends State<ReadingsQuick> {
  final TextEditingController _time = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  late final ScriptureLetterNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = context.read<ScriptureLetterNotifier>();
    _time.text = _stored;
    _focus.addListener(_onFocus);
    _n.addListener(_sync);
  }

  /// A new read (or an accepted write) is what the field shows, unless the
  /// reader is typing in it.
  void _sync() {
    if (!_editing && !_focus.hasFocus && _time.text != _stored) {
      _time.text = _stored;
    }
  }

  @override
  void dispose() {
    _n.removeListener(_sync);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _time.dispose();
    super.dispose();
  }

  String get _stored {
    final t = _n.settings?.deliveryTime ?? '';
    return t.isEmpty ? '06:30' : t;
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _editing = true;
      return;
    }
    if (_editing) _commit();
  }

  /// `6:5`-shaped input is padded to the stored `HH:MM`; anything else is sent
  /// as typed, and the endpoint's refusal is what the reader sees.
  static String _normalise(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return raw.trim();
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }

  Future<void> _commit() async {
    _editing = false;
    final cfg = _n.settings;
    final draft = _normalise(_time.text);
    if (cfg == null || draft.isEmpty || draft == _stored) {
      setState(() => _time.text = _stored);
      return;
    }
    // 2.29.0 — the hour goes with its zone, or it is read as UTC.
    await _n.save(
      cfg.copyWith(
        deliveryTime: draft,
        timezone: cfg.timezone.isEmpty ? deviceTimezone() : cfg.timezone,
      ),
    );
    if (!mounted) return;
    // What is stored now: the write, or — refused — the last read.
    if (!_focus.hasFocus) setState(() => _time.text = _stored);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<ScriptureLetterNotifier>();
    final cfg = n.settings;
    if (cfg == null) return const SizedBox.shrink();
    final on = cfg.enabled;
    final time = cfg.deliveryTime.isEmpty ? '06:30' : cfg.deliveryTime;
    final busy = n.isSaving;
    return Column(
      key: const ValueKey('d-lq-rl'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('The readings letter'),
        KitLetterSwitchRow(
          key: const ValueKey('d-lq-rl-switch'),
          title: 'Daily readings',
          line: on ? 'Arrives at ${kitClock(time) ?? time}' : 'Off',
          value: on,
          label: 'The readings letter',
          onChanged: busy
              ? null
              : (_) => on ? n.save(cfg.copyWith(enabled: false)) : n.turnOn(),
        ),
        if (on) ...[
          const SizedBox(height: 12),
          KitLetterTimeField(
            fieldKey: const ValueKey('d-lq-rl-time'),
            label: 'Readings delivery time',
            controller: _time,
            focusNode: _focus,
            readOnly: busy,
            zone: cfg.timezone.isEmpty ? null : cfg.timezone,
          ),
        ],
        if (n.saveError != null) ...[
          const SizedBox(height: 12),
          KitFailureInline(n.saveError!),
        ],
      ],
    );
  }
}

/// Off — the letter described by what it would carry, never by today's
/// citations.
class _OptIn extends StatelessWidget {
  final bool busy;
  final String? error;
  final Future<void> Function() onTurnOn;

  const _OptIn({
    required this.busy,
    required this.error,
    required this.onTurnOn,
  });

  @override
  Widget build(BuildContext context) {
    return KitCard(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('A second letter'),
          const SizedBox(height: AppSpacing.s2),
          Text('The readings letter', style: KitText.h4(context)),
          const SizedBox(height: AppSpacing.s2),
          const Lede(
            'Each morning the day’s Mass readings arrive with the passages '
            'from your own shelves that answer them. It comes beside your '
            'daily letter, at its own hour — your daily letter is not changed.',
            fontSize: 16,
            height: 24,
            maxWidth: double.infinity,
          ),
          const SizedBox(height: AppSpacing.s4),
          // What it carries — the three labels, with no citation against them.
          KitRowList(
            rows: const [
              KitRowSlot(child: Eyebrow('First reading')),
              KitRowSlot(child: Eyebrow('Responsorial')),
              KitRowSlot(child: Eyebrow('Gospel')),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          KitRowNote('$calendarLabel calendar. $calendarNote'),
          const SizedBox(height: AppSpacing.s4),
          KitButton(
            busy ? 'Turning on…' : 'Turn on the readings letter',
            onPressed: busy ? null : () => onTurnOn(),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.s3),
            KitFailureInline(error!),
          ],
        ],
      ),
    );
  }
}

/// On — the schedule, and the most recent readings letter.
class _OnCard extends StatelessWidget {
  final ScriptureNewsletterSettings cfg;
  final Newsletter? issue;
  final VoidCallback? onPreview;
  final VoidCallback onSettings;

  const _OnCard({
    required this.cfg,
    required this.issue,
    required this.onPreview,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final n = issue;
    return KitCard(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  // `emailEnabled` false is NOT "off": the letter still
                  // arrives here every morning, and saying otherwise is the
                  // merge 4.24.0 forbids.
                  // The zone as stored, as the reference prints it
                  // (`ReadingsLetterCard`: `${cfg.timezone || browserTimezone()}`)
                  // — the daily card's city spelling is scheduleSentence's,
                  // not this line's.
                  (cfg.emailEnabled
                          ? 'On · arrives ${cfg.deliveryTime} '
                                '${cfg.timezone.isEmpty ? deviceTimezone() : cfg.timezone}'
                          : 'On · in the app only')
                      .toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.capsLabel(
                    context,
                    color: t.accentText,
                    fontSize: 10,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          // `.nl-masthead` is flex-wrap and `.nl-title` nowrap: on a phone the
          // date drops under the title whole — the title is never cut
          // ("THE READIN…" beside a cut date was the 2026-09-25 frame).
          Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s1,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              const KitVersal('The Readings', fontSize: 25),
              if (n?.generatedAt != null)
                Text(
                  longDate(n!.generatedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.capsLabel(context, letterSpacing: 0.04),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Lede(
            n?.liturgicalDay?.title ??
                'No readings letter has arrived yet — the next one sends on '
                    'schedule.',
            fontSize: 16,
            height: 24,
            maxWidth: double.infinity,
          ),
          if (n != null && n.readings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s3),
            KitRowList(
              rows: [
                for (final r in n.readings)
                  KitRowSlot(
                    child: Row(
                      children: [
                        Expanded(child: Eyebrow(r.label)),
                        Text(r.ref, style: KitText.meta(context)),
                        const SizedBox(width: AppSpacing.s3),
                        Text(
                          r.passages.isEmpty ? '—' : '${r.passages.length}',
                          style: KitText.capsLabel(context),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (n != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              [
                '${n.passagesSent ?? 0} of ${n.passagesFound ?? 0} passages',
                // 2.26.0 — where the verse text came from. `bible_on_shelf`
                // keeps its 2.24.0 meaning and is NOT this question.
                if (n.verseSource == 'system')
                  'matched against ${n.verseEdition ?? 'a public-domain edition'}',
                '$calendarLabel calendar',
              ].join(' · '),
              style: KitText.meta(context),
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: [
              // Deliberately NO send action.
              if (onPreview != null)
                KitButton(
                  'Preview',
                  icon: Icons.visibility_outlined,
                  onPressed: onPreview,
                ),
              KitButton(
                'Settings',
                icon: Icons.settings_outlined,
                variant: KitButtonVariant.ghost,
                onPressed: onSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The readings letter itself, in the §11 sheet — it carries no letterhead of
/// its own and never has (`kind: "scripture"` records are unaffected by
/// ADR-087), so this client draws the frame.
class ReadingsLetterDocument extends StatelessWidget {
  final Newsletter letter;

  /// Opens the live day view (ADR-029 §5). Null where there is nothing to
  /// open into — the control is not drawn rather than drawn inert.
  final VoidCallback? onSeeAll;

  /// A key for each reading's rule (its label) — what a reader's *Passages*
  /// Contents follows (direction D). Readings with no label are not counted.
  final Key Function(int i)? headKey;

  /// False in a D column: the sheet takes the column's width.
  final bool inset;

  const ReadingsLetterDocument({
    super.key,
    required this.letter,
    this.onSeeAll,
    this.headKey,
    this.inset = true,
  });

  @override
  Widget build(BuildContext context) {
    final n = letter;
    final body = <Widget>[];

    if (n.liturgicalDay != null) {
      body.add(KitLetterProse(child: Text(n.liturgicalDay!.title)));
      if (n.liturgicalDay!.cycleLine.isNotEmpty) {
        body.add(KitLetterAttribution(n.liturgicalDay!.cycleLine));
      }
    }

    // 4.24.0 — the letter is complete and this IS it; only the mail did not
    // go. Rendered above the readings rather than instead of them.
    if (n.status == 'email_failed') {
      body.add(
        KitLetterProse(
          child: Text(
            'This letter did not reach your inbox. '
                    '${n.errorMessage ?? ''}'
                .trim(),
          ),
        ),
      );
    }

    if (n.status == 'empty') {
      body.add(
        KitLetterProse(
          child: Text(
            n.errorMessage ?? 'No readings are available for this day yet.',
          ),
        ),
      );
    } else {
      var head = 0;
      for (final r in n.readings) {
        final label = RuledSectionLabel('${r.label}  ·  ${r.ref}');
        body.add(
          headKey != null && r.label.trim().isNotEmpty
              ? KeyedSubtree(key: headKey!(head++), child: label)
              : label,
        );
        if (r.passages.isEmpty) {
          body.add(
            KitLetterProse(
              child: Text(
                r.parsed
                    ? 'Nothing on your shelves answers this reading yet.'
                    // A citation that did not parse says so, rather than showing
                    // an empty result — which would read as an empty library.
                    : 'This citation could not be read, so nothing was matched '
                          'against it.',
              ),
            ),
          );
        } else {
          for (final p in r.passages) {
            body.add(
              KitLetterProse(
                child: KitMarkedText(
                  p.text,
                  style: DefaultTextStyle.of(context).style,
                ),
              ),
            );
          }
          if (r.matchTotal > r.passages.length) {
            body.add(
              KitLetterAttribution(
                '${r.passages.length} of ${r.matchTotal} matches',
              ),
            );
          }
        }
      }
    }

    // The live day (ADR-029 §5). It counts the passages the letter FOUND, not
    // the ones it sent — that is the number the day view re-measures, and
    // saying "see all 5" under a letter that carried 3 is the whole point.
    if (n.readings.isNotEmpty && onSeeAll != null) {
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: KitButton(
              'See all ${n.passagesFound ?? 0} passages for this day',
              variant: KitButtonVariant.ghost,
              onPressed: onSeeAll,
            ),
          ),
        ),
      );
    }

    return KitLetterSheet(
      title: 'The Readings',
      inset: inset,
      marker: longDate(n.generatedAt),
      sealText: [
        '${n.status == 'email_failed' ? 'Prepared' : 'Sent'} '
            '${longDate(n.generatedAt)}',
        '${n.passagesSent ?? 0} of ${n.passagesFound ?? 0} passages.',
        if (n.verseSource == 'system')
          'Matched against ${n.verseEdition ?? 'a public-domain edition'} — '
              'add your own bible and it uses that instead.',
        if (n.verseSource == 'none')
          'Matched on the citations alone — no verse text was available for '
              'this day.',
      ].join(' · '),
      children: body,
    );
  }
}
