import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/newsletter.dart';
import '../models/newsletter_settings.dart';
import '../shared/dates.dart';
import '../state/activation_message.dart';
import '../state/newsletter_notifier.dart';
import '../state/schedule.dart';
import '../state/settings_notifier.dart';
import '../theme/app_spacing.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import 'letters/delivery.dart';
import 'letters/letter_reader.dart';
import 'letters/pinned_sources.dart';
import 'letters/readings_letter.dart';
import 'letters/scripture_day_page.dart';
import '../services/analytics.dart';

/// Letters (`spec/screens/letters.md` §Composition, ADR-041).
///
/// Index frame · a bespoke header (§2 names it so — the serif title, the italic
/// standfirst, and one ghost Button through to Letter settings) · §3 section
/// headers opening the pinned block, the latest letter, the readings letter and
/// the archive · §4.1 row lists for the archive · the letter itself in §11.
class LettersPage extends StatefulWidget {
  const LettersPage({super.key});

  @override
  State<LettersPage> createState() => _LettersPageState();
}

class _LettersPageState extends State<LettersPage> {
  /// The letter being read, or null for the list. A state rather than a route
  /// because the archive row is what opens it — the reference does the same.
  Newsletter? _open;

  /// The readings letter whose LIVE day is being shown (ADR-029 §5). A second
  /// state rather than a route, for the same reason [_open] is one: the letter
  /// is what opens it. It takes precedence over [_open] — the day view is
  /// entered FROM the letter and returns to it.
  Newsletter? _dayIssue;

  /// One setter rather than three call sites, so the preview, the archive row
  /// and anything that opens a letter later count the same way by construction
  /// — the reference makes the same argument with one effect. What is emitted
  /// is that A letter was opened, never which one: the archive key is a
  /// Firestore id (INV-25b).
  void _openLetter(Newsletter? n) {
    if (n != null && n != _open) Analytics.track('letter_opened');
    setState(() => _open = n);
  }

  String? _sendMessage;
  String? _sendError;
  String? _scheduleOutcome;
  String? _scheduleError;
  bool _scheduleBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NewsletterNotifier>().load();
      // The schedule this screen describes is READ, never assumed (2.29.0
      // rule 3), and the pinned block's "how many arrive" sentence is half of
      // `itemsPerNewsletter` — so the settings have to actually be loaded for
      // either line to be allowed to appear.
      final settings = context.read<SettingsNotifier>();
      if (settings.newsletter == null) settings.loadAll();
    });
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
      setState(() => _sendError = error);
      return;
    }
    setState(() => _sendMessage =
        'On its way — it shows up here in a few minutes. The email leaves '
        'with it; the letter’s row shows what happened to it.');
    // The build is asynchronous and always writes a record (2.2.0, ADR-011).
    // Re-reading is how it is found; nothing here polls a function (INV-02).
    await notifier.load();
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
      deliveryTime: stored.deliveryTime,
      timezone: stored.timezone.isNotEmpty ? stored.timezone : deviceTimezone(),
    );
    if (!mounted) return;
    setState(() {
      _scheduleBusy = false;
      _scheduleError = error;
      // 2.30.0 (ADR-031) — what the activation send did, read from the
      // response and never assumed. The backend owns the decision.
      _scheduleOutcome = error == null && next
          ? activationMessage(settings.lastActivation)
          : null;
    });
    if (error == null && next) await context.read<NewsletterNotifier>().load();
  }

  @override
  Widget build(BuildContext context) {
    final letters = context.watch<NewsletterNotifier>();
    final settings = context.watch<SettingsNotifier>();

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

    final archive = letters.history;
    final latest = letters.latest;

    return KitPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Letters',
            standfirst: 'Every letter your library has written you, and the '
                'one arriving next.',
            action: KitButton('Letter settings',
                icon: Icons.tune,
                variant: KitButtonVariant.ghost,
                onPressed: () => context.go('/letters/settings')),
          ),

          // 2.33.0 — the pin's only surface outside the extension, above the
          // letter because it describes what the NEXT one will carry.
          PinnedSources(settings: settings.newsletter),

          const SectionHeader('Latest letter', first: true),
          _LatestLetter(
            latest: latest,
            loaded: letters.loaded,
            archiveError: letters.error,
            sending: letters.isSending,
            onSend: _sendNow,
            onPreview: latest == null
                ? null
                : () => _openLetter(latest),
            onSettings: () => context.go('/letters/settings'),
            sendMessage: _sendMessage,
            sendError: _sendError,
            scheduleOutcome: _scheduleOutcome,
            scheduleError: _scheduleError,
            scheduleBusy: _scheduleBusy,
            onToggleSchedule: _toggleSchedule,
          ),

          // The SECOND letter, beside the one above and never a mode of it.
          ReadingsLetterSection(
            issues: letters.readings,
            onOpen: _openLetter,
            onSettings: () => context.go('/letters/settings'),
          ),

          SectionHeader(
              'Sent · ${archive.length} ${archive.length == 1 ? 'letter' : 'letters'}'),
          _Archive(
            rows: archive,
            loaded: letters.loaded,
            error: letters.error,
            onRetry: () => context.read<NewsletterNotifier>().load(),
            onOpen: _openLetter,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}

/// The latest letter, its schedule and the actions on it (§5.3 hero card).
class _LatestLetter extends StatelessWidget {
  final Newsletter? latest;
  final bool loaded;
  final String? archiveError;
  final bool sending;
  final Future<void> Function() onSend;
  final VoidCallback? onPreview;
  final VoidCallback onSettings;
  final String? sendMessage;
  final String? sendError;
  final String? scheduleOutcome;
  final String? scheduleError;
  final bool scheduleBusy;
  final Future<void> Function(bool) onToggleSchedule;

  const _LatestLetter({
    required this.latest,
    required this.loaded,
    required this.archiveError,
    required this.sending,
    required this.onSend,
    required this.onPreview,
    required this.onSettings,
    required this.sendMessage,
    required this.sendError,
    required this.scheduleOutcome,
    required this.scheduleError,
    required this.scheduleBusy,
    required this.onToggleSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final cfg = settings.newsletter;
    final n = latest;
    final passages = n?.chunkIds.length ?? 0;

    return KitCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScheduleRow(
            cfg: cfg,
            busy: scheduleBusy,
            onToggle: onToggleSchedule,
          ),
          if (scheduleError != null) ...[
            const SizedBox(height: AppSpacing.s2),
            KitFailureInline(scheduleError!),
          ] else if (scheduleOutcome != null) ...[
            const SizedBox(height: AppSpacing.s2),
            KitRowNote(scheduleOutcome!),
          ] else if (cfg != null && !cfg.enabled) ...[
            const SizedBox(height: AppSpacing.s2),
            // Said BEFORE the switch is touched (2.30.0 rule 5): a letter
            // arriving seconds after a settings change, unannounced, reads as
            // a bug in the direction that matters.
            KitRowNote(activationHint),
          ],
          const SizedBox(height: AppSpacing.s3),
          if (n?.generatedAt != null) ...[
            // `.nl-status`: mono 10 caps at 0.1em in `--accent-text`.
            Text('Last sent · ${longDate(n!.generatedAt)}'.toUpperCase(),
                style: KitText.capsLabel(context,
                    fontSize: 10,
                    letterSpacing: 0.1,
                    color: Tokens.of(context).accentText)),
            const SizedBox(height: AppSpacing.s2),
          ],
          // `.nl-masthead` is flex-wrap (gap 12): on a phone the subject drops
          // under the title whole rather than ellipsising beside it.
          Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s1,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              const KitVersal('A Letter', fontSize: 25),
              if (n?.subject != null && n!.subject!.isNotEmpty)
                Text(n.subject!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.capsLabel(context, letterSpacing: 0)),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Lede(
            n != null
                ? (n.lede.isNotEmpty
                    ? n.lede
                    : 'Your daily reading, drawn from your library.')
                // INV-24 (ADR-071): "no letter yet" is a claim about the
                // archive, and a read that FAILED is not evidence for it.
                : archiveError != null
                    ? 'Your letters could not be read.'
                    : !loaded
                        ? 'Loading…'
                        : "No letter yet — it draws from what's in your "
                            'library so far.',
            fontSize: 16,
            height: 24,
            maxWidth: double.infinity,
          ),
          if (passages > 0) ...[
            const SizedBox(height: AppSpacing.s3),
            // `chunk_ids` names exactly the passages the body holds (4.39.0),
            // so this is counted, not estimated.
            Text(
                '$passages ${passages == 1 ? 'passage' : 'passages'} · '
                '~${passages + 1} min read',
                style: KitText.meta(context)),
          ],
          if (sendError != null) ...[
            const SizedBox(height: AppSpacing.s2),
            KitFailureInline(sendError!),
          ] else if (sendMessage != null) ...[
            const SizedBox(height: AppSpacing.s2),
            KitRowNote(sendMessage!),
          ],
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: [
              KitButton(sending ? 'Sending…' : 'Send now',
                  icon: Icons.send_outlined,
                  onPressed: sending ? null : () => onSend()),
              if (onPreview != null)
                KitButton('Preview',
                    icon: Icons.visibility_outlined,
                    variant: KitButtonVariant.secondary,
                    onPressed: onPreview),
              KitButton('Settings',
                  icon: Icons.settings_outlined,
                  variant: KitButtonVariant.ghost,
                  onPressed: onSettings),
            ],
          ),
        ],
      ),
    );
  }
}

/// The schedule, stated from what was READ (2.29.0 rule 3), with the switch
/// that owns it.
class _ScheduleRow extends StatelessWidget {
  final NewsletterSettings? cfg;
  final bool busy;
  final Future<void> Function(bool) onToggle;

  const _ScheduleRow({
    required this.cfg,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final enabled = cfg?.enabled == true;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: AppSpacing.s2),
          decoration: BoxDecoration(
            // Off is a state, not a severity: the dot goes quiet, it does not
            // go red.
            color: cfg == null || !enabled ? t.fgSubtle : t.accent,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            // Before the read resolves, say NOTHING about arrival — this
            // screen once read "Arrives tomorrow morning" to every reader,
            // including accounts with no schedule at all.
            cfg == null
                ? 'Loading…'
                : scheduleSentence(
                    enabled: cfg!.enabled,
                    deliveryTime: cfg!.deliveryTime,
                    timezone: cfg!.timezone,
                    frequency: cfg!.frequency,
                  ).toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: KitText.capsLabel(context,
                color: t.accentText, fontSize: 10, letterSpacing: 0.1),
          ),
        ),
        if (cfg != null) ...[
          const SizedBox(width: AppSpacing.s3),
          KitSwitch(
            value: enabled,
            tooltip: enabled ? 'Pause scheduled delivery' : activationHint,
            onChanged: busy ? null : (v) => onToggle(v),
          ),
        ],
      ],
    );
  }
}

/// The archive — §4.1 source rows under a §3 header.
class _Archive extends StatelessWidget {
  final List<Newsletter> rows;
  final bool loaded;
  final String? error;
  final VoidCallback onRetry;
  final void Function(Newsletter) onOpen;

  const _Archive({
    required this.rows,
    required this.loaded,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // INV-24 (ADR-071): "No letters sent yet" is a statement about the
    // archive, and a read that failed is not evidence for it.
    if (error != null) {
      return KitFailureBlock(
        sentence: 'Your letters could not be read.',
        detail: error!,
        onRetry: onRetry,
      );
    }
    if (!loaded) return KitRowNote('Loading…');
    if (rows.isEmpty) return KitRowNote('No letters sent yet.');

    return KitRowList(
      rows: [
        for (var i = 0; i < rows.length; i++)
          _archiveRow(context, rows[i], rows.length - i),
      ],
    );
  }

  Widget _archiveRow(BuildContext context, Newsletter n, int number) {
    final badge = letterBadge(
      status: n.status,
      deliveryState: n.delivery?.state,
      trigger: n.trigger,
    );
    final count = n.chunkIds.length;
    // A delivery problem outranks the preview: it is the one thing about this
    // row a reader cannot find out any other way.
    final note = n.errorMessage ??
        deliveryNote(
          state: n.delivery?.state,
          detail: n.delivery?.detail,
          attempts: n.delivery?.attempts ?? 0,
        ) ??
        n.lede;
    return KitSourceRow(
      leading: Text('№ $number',
          style: KitText.capsLabel(context,
              color: Tokens.of(context).accentText,
              fontSize: 12,
              letterSpacing: 0.03)),
      title: n.subject?.isNotEmpty == true ? n.subject! : 'A Letter',
      subtitle: note.isEmpty ? null : note,
      count: count > 0
          ? '$count ${count == 1 ? 'passage' : 'passages'} · ~${count + 1} min'
          : null,
      date: shortDate(n.generatedAt),
      trailing: KitStatusPill(badge.text, positive: badge.settled),
      // Only a letter that was BUILT has a body to open. A bounced one still
      // opens — it exists, it just never reached the mailbox (INV-23).
      onTap: n.isReadable ? () => onOpen(n) : null,
    );
  }
}
