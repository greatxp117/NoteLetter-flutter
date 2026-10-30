import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/newsletter.dart';
import '../models/newsletter_settings.dart';
import '../services/analytics.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/cooldown.dart';
import '../shared/dates.dart';
import '../state/activation_message.dart';
import '../state/newsletter_notifier.dart';
import '../state/schedule.dart';
import '../state/scripture_letter_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/kit/kit.dart';
import 'letters/delivery.dart';
import 'letters/letter_reader.dart';
import 'letters/pinned_sources.dart';
import 'letters/readings_letter.dart';
import 'letters/scripture_day_page.dart';

/// The archive is a WINDOW: the newest records of both letters (INV-09's
/// recency read, `limit 30`). A count taken from a full window is a floor,
/// and says so (`30+`), never a total.
const int lettersArchiveLimit = 30;

/// What a letter being built says about itself (4.76.0, ADR-110) — the
/// `generating` record's row.
const String lettersBuildingLede =
    'Gathering the best passages from your library…';

/// The folio's and the Delivery figures' word for a schedule (direction D).
const Map<String, String> _cadence = {
  'daily': 'Daily',
  'weekdays': 'Weekdays',
  'weekly': 'Weekly',
};

/// …and the panel's (kit LetterQuick's *How often* words).
const Map<String, String> _panelCadence = {
  'daily': 'Every day',
  'weekdays': 'Weekdays',
  'weekly': 'Weekly',
};

/// `Letters · {N} letters · {when}` (screens/letters.md §Composition
/// *Letters*): the count is a measurement — the dash until the archive read
/// answers or while it is refused, a floor once the 30-record window is full —
/// and `{when}` is absent while delivery is off or unread.
@visibleForTesting
String lettersFolio({
  required bool measured,
  required int daily,
  required int window,
  String? when,
}) {
  final full = measured && window >= lettersArchiveLimit;
  final count = !measured
      ? '— letters'
      : full
      ? '$daily+ letters'
      : kitCounted(daily, 'letter');
  return ['Letters', count, ?when].join(' · ');
}

/// *Letters sent* in the Delivery figures: the folio's count by the same
/// rules — the dash, or a floor.
@visibleForTesting
String lettersSentFigure({
  required bool measured,
  required int daily,
  required int window,
}) {
  if (!measured) return '—';
  return window >= lettersArchiveLimit ? '$daily+' : '$daily';
}

/// `{Daily | Weekdays | Weekly} at {h:mm AM}` from the settings read; null
/// while delivery is off or unread.
@visibleForTesting
String? lettersWhen(NewsletterSettings? s) {
  if (s == null || !s.enabled) return null;
  final time = s.deliveryTime.isEmpty ? '07:00' : s.deliveryTime;
  return '${_cadence[s.frequency] ?? 'Daily'} at ${kitClock(time) ?? time}';
}

/// One month of the archive.
class LettersMonth {
  final String label;
  final List<(Newsletter, String)> rows;
  LettersMonth(this.label) : rows = [];
}

/// The archive by month, newest first, each row with its number: the
/// letter's own (its folio's `No.`, blank for a letter without one) — or,
/// only where NO letter in the window carries a number, its place in the
/// window. A place set under a real number reads as a second count (W4
/// FOUND 6).
@visibleForTesting
List<LettersMonth> lettersByMonth(List<Newsletter> rows, {DateTime? now}) {
  final numbered = rows.any((a) => kitLetterHead(a).no != null);
  final out = <LettersMonth>[];
  final fallback = (now ?? DateTime.now()).millisecondsSinceEpoch;
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    final k = kitMonthYear(a.generatedAt ?? fallback);
    if (out.isEmpty || out.last.label != k) out.add(LettersMonth(k));
    out.last.rows.add((
      a,
      numbered ? (kitLetterHead(a).no ?? '') : '${rows.length - i}',
    ));
  }
  return out;
}

/// **Letters** (`/letters`; screens/letters.md §Composition *Letters*,
/// direction D). Web `pages/LettersView.jsx` — the prototype's `LettersD`.
///
/// The D frame: the masthead (folio `Letters · {N} letters · {when}`, *Letters*,
/// the standfirst); the page's one action *Send now* — or *Add a delivery
/// address* with no recipient — and *Letter settings* as its settings (kit
/// LetterQuick with this page's own delivery row and the readings letter's
/// rows). What Send now answered stands under the masthead. The sheet
/// *Contents* (the latest letter, the readings letter, each month, readings
/// sent), the Delivery figures, what is pinned for the next letter, and *Read
/// the latest letter*. The column: the latest letter under its kicker, the
/// readings letter, *Sent* by month, *Readings sent*.
///
/// Opening a letter replaces the list with it ([LetterReaderView]); a readings
/// letter's *See all* replaces that with its live day ([ScriptureDayView]).
class LettersPage extends StatefulWidget {
  /// The account's own address — the backend's fallback recipient (ADR-010).
  /// A seam: the default reads the signed-in user.
  final String? Function()? accountEmail;

  const LettersPage({super.key, this.accountEmail});

  @override
  State<LettersPage> createState() => _LettersPageState();
}

String? _signedInEmail() {
  try {
    return AuthService.instance.currentUser?.email;
  } catch (_) {
    // No auth in this process (a test) — unknown, never "none".
    return null;
  }
}

class _LettersPageState extends State<LettersPage> {
  /// The letter being read, or null for the list. A state rather than a route
  /// because the archive row is what opens it — the reference does the same.
  Newsletter? _open;

  /// The readings letter whose LIVE day is being shown (ADR-029 §5). It takes
  /// precedence over [_open] — the day view is entered FROM the letter and
  /// returns to it.
  Newsletter? _dayIssue;

  final KitSections _sec = KitSections(const ['latest']);

  String? _sendMessage;
  String? _sendError;
  String? _scheduleOutcome;
  String? _scheduleError;
  bool _scheduleBusy = false;

  // The letter's parts, parsed once per record (the body is read as text).
  Newsletter? _partsOf;
  KitLetterParts? _parts;

  /// One setter rather than three call sites, so the latest letter, the
  /// archive row and the sheet's *Read the latest letter* count the same way
  /// by construction. What is emitted is that A letter was opened, never which
  /// one: the archive key is a Firestore id (INV-25b).
  void _openLetter(Newsletter? n) {
    if (n != null && n != _open) Analytics.track('letter_opened');
    setState(() => _open = n);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NewsletterNotifier>().load(limit: lettersArchiveLimit);
      // The schedule this screen describes is READ, never assumed (2.29.0
      // rule 3), and the pinned block's "how many arrive" sentence is half of
      // `itemsPerNewsletter` — so the settings have to actually be loaded for
      // either line to be allowed to appear.
      final settings = context.read<SettingsNotifier>();
      if (settings.newsletter == null) settings.loadAll();
      context.read<ScriptureLetterNotifier>().load();
    });
  }

  @override
  void dispose() {
    _sec.dispose();
    super.dispose();
  }

  Future<void> _sendNow() async {
    final notifier = context.read<NewsletterNotifier>();
    setState(() {
      _sendMessage = null;
      _sendError = null;
    });
    final error = await notifier.requestNewsletter();
    if (!mounted) return;
    if (error != null) {
      // A cooldown with its number is the action's wait and says itself
      // (4.107.0, ADR-140) — the same wait on Letter settings.
      setState(
        () => _sendError = Cooldowns.instance.waiting(WaitKey.letterSend())
            ? null
            : error,
      );
      return;
    }
    // What is known is that the build was accepted; when the EMAIL lands is
    // the receiver's decision (INV-23), and the row's badge says it.
    setState(
      () => _sendMessage =
          'On its way — it shows up here in a few minutes. The email leaves '
          'with it; the letter’s row shows what happened to it.',
    );
    // The build is asynchronous and always writes a record (2.2.0, ADR-011),
    // written BEFORE it is queued (4.76.0): re-reading finds it building.
    // Nothing here polls a function (INV-02).
    await notifier.load(limit: lettersArchiveLimit);
  }

  Future<void> _toggleSchedule(bool next) async {
    final settings = context.read<SettingsNotifier>();
    final stored = settings.newsletter;
    if (stored == null) return;
    setState(() {
      _scheduleBusy = true;
      _scheduleOutcome = null;
      _scheduleError = null;
    });
    // Write BEFORE the switch moves (ADR-022). An optimistic toggle that
    // silently reverts on reload is indistinguishable from one that worked.
    final error = await settings.setScheduledDelivery(
      enabled: next,
      deliveryTime: stored.deliveryTime.isEmpty ? '07:00' : stored.deliveryTime,
      timezone: stored.timezone.isNotEmpty ? stored.timezone : deviceTimezone(),
    );
    if (!mounted) return;
    setState(() {
      _scheduleBusy = false;
      _scheduleError = error;
      // 2.30.0 (ADR-031) — what the activation send did, read from the
      // response and never assumed. The backend owns the decision.
      _scheduleOutcome = error == null
          ? activationMessage(settings.lastActivation)
          : null;
    });
    // The activation send's letter is found the way Send now's is: its
    // record lands in the archive, building (4.76.0).
    if (error == null && next) {
      await context.read<NewsletterNotifier>().load(limit: lettersArchiveLimit);
    }
  }

  /// One LetterQuick write from the panel: the PUT, then the settings
  /// document re-read (the panel and this page draw what was read).
  Future<KitLetterWrite> _writeSettings(
    SettingsNotifier settings,
    Map<String, dynamic> patch,
  ) async {
    try {
      final res = await Api.instance.updateNewsletterSettings(patch);
      unawaited(settings.loadAll());
      return KitLetterWrite(response: res);
    } on ApiException catch (e) {
      return KitLetterWrite(error: e.message);
    } catch (_) {
      return const KitLetterWrite(error: 'The change was not saved.');
    }
  }

  void _openPanel() {
    if (!KitPageTools.instance.openSettings('letter')) {
      context.go('/letters/settings');
    }
  }

  KitLetterParts? _partsFor(Newsletter? letter) {
    if (!identical(letter, _partsOf)) {
      _partsOf = letter;
      _parts = kitLetterParts(letter);
    }
    return _parts;
  }

  @override
  Widget build(BuildContext context) {
    final day = _dayIssue;
    if (day != null) {
      return ScriptureDayView(
        letter: day,
        onBack: () => setState(() => _dayIssue = null),
        onLibrary: () => context.go('/sources'),
      );
    }

    final open = _open;
    if (open != null) {
      return LetterReaderView(
        letter: open,
        onBack: () => _openLetter(null),
        onSeeAll: open.isScripture
            ? () => setState(() => _dayIssue = open)
            : null,
      );
    }

    // The page's action carries the cooldown's seconds, so it is rebuilt with
    // the wait (one clock with Letter settings, 4.107.0).
    return KitWait(waitKey: WaitKey.letterSend(), builder: _list);
  }

  Widget _list(BuildContext context, CooldownWait wait) {
    final letters = context.watch<NewsletterNotifier>();
    final settings = context.watch<SettingsNotifier>();
    final rl = context.watch<ScriptureLetterNotifier>();
    final cfg = settings.newsletter;

    final daily = letters.history;
    final readingsRows = letters.readings;
    final latest = letters.latest;
    final measured = letters.loaded && letters.error == null;
    final window = daily.length + readingsRows.length;
    final when = lettersWhen(cfg);
    final rlShown = rl.settings != null && rl.error == null;
    final groups = measured ? lettersByMonth(daily) : const <LettersMonth>[];

    // The sheet's Contents: only the sections the page draws.
    final secs = [
      const KitContentsItem('latest', 'The latest letter'),
      if (rlShown) const KitContentsItem('readings', 'The readings letter'),
      for (var i = 0; i < groups.length; i++)
        KitContentsItem(
          'm$i',
          groups[i].label,
          count: '${groups[i].rows.length}',
        ),
      if (readingsRows.isNotEmpty)
        KitContentsItem(
          'rsent',
          'Readings sent',
          count: '${readingsRows.length}',
        ),
    ];
    final ids = [for (final s in secs) s.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

    // A recipient is a stored address or the account-email fallback the
    // backend applies (ADR-010) — Send now works with either. Assumed until
    // the settings read says otherwise: a failed read must not take Send away.
    final account = (widget.accountEmail ?? _signedInEmail)() ?? '';
    final hasRecipient =
        cfg == null || cfg.emailAddress.isNotEmpty || account.isNotEmpty;
    final sending = letters.isSending;
    final action = hasRecipient
        ? KitPageAction(
            // The tab bar's accessible name carries the wait's seconds, as
            // the rail's label does (§Endpoints: one clock).
            label: sending ? 'Sending…' : 'Send now${waitSuffix(wait.left)}',
            short: sending ? 'Sending' : 'Send now',
            // web `IcoSend` is a right arrow, never a paper plane.
            icon: Icons.arrow_forward,
            onPressed: _sendNow,
            disabled: sending || wait.left > 0,
          )
        : KitPageAction(
            label: 'Add a delivery address',
            short: 'Address',
            icon: Icons.arrow_forward,
            onPressed: () => context.go('/letters/settings'),
          );

    // What Send now answered, under the masthead: while a cooldown runs its
    // sentence is the line (calm, never §14.2 — 4.108.0); otherwise the
    // refusal (§14.2) or the queued sentence.
    final waiting = wait.sentence;
    final Widget? line = waiting != null
        ? KitSendLine(key: const ValueKey('d-letters-send-line'), note: waiting)
        : _sendError != null
        ? KitSendLine(
            key: const ValueKey('d-letters-send-line'),
            failure: _sendError,
          )
        : _sendMessage != null
        ? KitSendLine(
            key: const ValueKey('d-letters-send-line'),
            note: _sendMessage,
          )
        : null;

    // The panel's delivery row in LetterQuick's own form: the schedule as
    // read — the dash before the read answers — and the switch, which carries
    // the activation send. Write before you move: held while the write is
    // out, it moves only on the re-read.
    final scheduleRow = KitLetterSwitchRow(
      key: const ValueKey('d-letters-delivery'),
      title: 'Scheduled delivery',
      line: cfg == null
          ? '—'
          : cfg.enabled
          ? '${_panelCadence[cfg.frequency] ?? 'Every day'} at '
                '${kitClock(cfg.deliveryTime) ?? cfg.deliveryTime}'
          : 'Paused',
      value: cfg?.enabled,
      label: 'Scheduled delivery',
      onChanged: _scheduleBusy || cfg == null
          ? null
          : (v) => _toggleSchedule(v),
    );
    // The refusal (§14.2), or what the activation send did, or — while off,
    // BEFORE the switch is touched — what turning it on will do (2.30.0).
    final note =
        _scheduleOutcome ??
        (cfg != null && !cfg.enabled ? activationHint : null);
    final Widget? scheduleNotice = _scheduleError != null
        ? KitDFailureNote(_scheduleError!)
        : note != null
        ? KitDNote(note)
        : null;

    final parts = _partsFor(latest);
    final latestState = latest != null
        ? KitLatestState.built
        : letters.error != null
        ? KitLatestState.refused
        : !letters.loaded
        ? KitLatestState.loading
        : KitLatestState.none;

    return KitDPage(
      key: const ValueKey('d-letters'),
      folio: lettersFolio(
        measured: measured,
        daily: daily.length,
        window: window,
        when: when,
      ),
      title: 'Letters',
      stand:
          'Every letter your library has written you, and the one arriving '
          'next.',
      action: action,
      settings: KitPageSettings(
        label: 'Letter settings',
        has: const ['letter'],
        body: (context, close) => KitLetterQuick(
          settings: settings.newsletter,
          readError: settings.newsletter == null ? settings.error : null,
          write: (patch) => _writeSettings(settings, patch),
          onEverySetting: () {
            close();
            GoRouter.maybeOf(context)?.go('/letters/settings');
          },
          switchRow: scheduleRow,
          notice: scheduleNotice,
          extra: rlShown ? const ReadingsQuick() : null,
        ),
      ),
      under: line,
      sections: _sec,
      sheet: KitDSheet(
        label: 'Contents',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(items: secs, sections: _sec),
            KitFigures(
              label: 'Delivery',
              rows: [
                ('Schedule', when ?? (cfg != null ? 'Paused' : '—')),
                (
                  'Letters sent',
                  lettersSentFigure(
                    measured: measured,
                    daily: daily.length,
                    window: window,
                  ),
                ),
              ],
            ),
            PinnedSources(
              settings: cfg,
              onOpen: (d) => context.push('/reader/${d.id}'),
            ),
            if (latest != null)
              KitSheetAlso(
                children: [
                  KitAlsoButton(
                    'Read the latest letter',
                    key: const ValueKey('d-letters-read-latest'),
                    icon: Icons.visibility_outlined,
                    onTap: () => _openLetter(latest),
                  ),
                ],
              ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _sec.keyOf('latest'),
            child: KitLatestLetter(
              state: latestState,
              parts: parts,
              figures: latest == null ? null : letterFigures(latest),
              onRead: latest == null ? null : () => _openLetter(latest),
              onSettings: _openPanel,
            ),
          ),

          // The readings letter — a second letter beside the one above, never
          // a mode of it. Hidden until its settings document answers; a
          // refused read is §14.2 in its place (INV-24).
          if (rl.error != null)
            KitDFailureNote(
              'Your readings-letter settings could not be read — '
              '${rl.error}',
              top: 24,
            ),
          if (rlShown) ...[
            const SizedBox(height: 56),
            KeyedSubtree(
              key: _sec.keyOf('readings'),
              child: ReadingsLetterSection(
                issues: readingsRows,
                onOpen: _openLetter,
                onSettings: _openPanel,
              ),
            ),
          ],

          KitSectionHead(
            'Sent',
            meta: measured ? kitCounted(daily.length, 'letter') : null,
          ),
          ..._sent(context, letters, groups),

          if (readingsRows.isNotEmpty) ...[
            const SizedBox(height: 56),
            KeyedSubtree(
              key: _sec.keyOf('rsent'),
              child: ReadingsSentSection(
                issues: readingsRows,
                onOpen: _openLetter,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// *Sent*: the archive by month. INV-24 (ADR-071): "No letters sent yet" is
  /// a statement about the archive, and a read that failed is not evidence
  /// for it.
  List<Widget> _sent(
    BuildContext context,
    NewsletterNotifier letters,
    List<LettersMonth> groups,
  ) {
    if (letters.error != null) {
      return [
        KitFailureBlock(
          sentence: 'Your letters could not be read.',
          detail: letters.error!,
          onRetry: () => context.read<NewsletterNotifier>().load(
            limit: lettersArchiveLimit,
          ),
        ),
      ];
    }
    if (!letters.loaded) {
      return const [
        KitSkeletonLines(
          top: 0,
          lines: [KitSkelLine(0.7), KitSkelLine(0.6), KitSkelLine(0.7)],
        ),
      ];
    }
    if (groups.isEmpty) return const [KitDNone('No letters sent yet.')];
    return [
      for (var i = 0; i < groups.length; i++)
        KeyedSubtree(
          key: _sec.keyOf('m$i'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KitLetterMonthHead(
                groups[i].label,
                key: ValueKey('d-lmonth-$i'),
                count: kitCounted(groups[i].rows.length, 'letter'),
                first: i == 0,
              ),
              for (final (a, no) in groups[i].rows) _row(a, no),
            ],
          ),
        ),
    ];
  }

  /// One sent letter. Only a letter that was BUILT has a body to open; a
  /// bounced one still opens — it exists, it only never reached the mailbox
  /// (INV-23). A delivery problem outranks the lede: it is the one thing about
  /// the row a reader cannot find out any other way.
  Widget _row(Newsletter n, String no) {
    final badge = letterBadge(
      status: n.status,
      deliveryState: n.delivery?.state,
      trigger: n.trigger,
    );
    final count = n.chunkIds.length;
    final lede = n.status == 'generating'
        ? lettersBuildingLede
        : n.errorMessage ??
              deliveryNote(
                state: n.delivery?.state,
                detail: n.delivery?.detail,
                attempts: n.delivery?.attempts ?? 0,
              ) ??
              n.lede;
    return KitLetterArchiveRow(
      key: ValueKey('d-lrow-${n.id}'),
      no: no,
      title: letterTitle(n),
      lede: lede,
      figures: count > 0
          ? '$count ${count == 1 ? 'passage' : 'passages'} · ~${count + 1} min'
          : null,
      date: shortDate(n.generatedAt),
      badge: badge.text,
      settled: badge.settled,
      onTap: n.isReadable ? () => _openLetter(n) : null,
    );
  }
}
