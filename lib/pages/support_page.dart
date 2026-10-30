import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/support.dart';
import '../shared/cooldown.dart';
import '../state/support_notifier.dart';
import '../widgets/kit/kit.dart';
import '../services/analytics.dart';

/// Support — the conversation between one user and a human (contract 4.18.0,
/// ADR-054; `spec/screens/support.md`), in direction D (§Composition; web
/// `SupportView.jsx`).
///
/// Reached from the **support footer**, which the shell composes once and every
/// screen's primary scroll ends with (INV-22, ADR-173) — never from a
/// per-screen link. This screen therefore knows nothing about how it was
/// reached except [fromRoute], which the shell passed.
///
/// The reply arrives through the notification channels the user already
/// configured (ADR-014/ADR-015). This screen does not have to be open, and
/// never claims to be the only place an answer lands.
///
/// Composition: the D frame — the crumb back to *Settings*, the folio
/// counting the messages, the sheet *The thread* (its figures, the note, Also)
/// — the correspondence as a ruled register in the column, and the §38
/// composer docked at the column's foot ([KitDPage.dock]).
class SupportPage extends StatefulWidget {
  /// The screen the user was on when they opened support.
  final String? fromRoute;

  const SupportPage({super.key, this.fromRoute});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

/// The reply window is stated **once**, here, in the standfirst. Do not repeat
/// it per message or in the composer placeholder: a promise written in three
/// places is a promise that changes in one.
const String _answerWindow =
    'A human reads every message and answers within 24–48 hours.';

class _SupportPageState extends State<SupportPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Whether this visit has asked for the thread to be marked read.
  bool _markAsked = false;

  /// The count the page last scrolled to the end for.
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Editing withdraws the last rejection, as the reference does — the
      // text it referred to is being changed.
      context.read<SupportNotifier>().clearError();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opening the screen marks it read — once a visit, and only when there is
  /// something to clear. The notifier holds the write's own guards; this is a
  /// call, not a decision. The SUBSCRIPTION is the shell's (it feeds the
  /// footer's count on every screen), so this screen never starts one — and a
  /// thread that answers after the screen opened is still marked.
  void _markRead(SupportNotifier support) {
    if (_markAsked || support.unreadForUser == 0) return;
    _markAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SupportNotifier>().markRead();
    });
  }

  Future<void> _send() async {
    // Held for a cooldown's wait (4.107.0, ADR-140); the text stays.
    if (Cooldowns.instance.waiting(WaitKey.supportSend())) return;
    final notifier = context.read<SupportNotifier>();
    final ok = await notifier.send(_controller.text, route: widget.fromRoute);
    // That a message was sent. NEVER the message — it is the reader writing to
    // a human about their own library (INV-22, INV-25b). On the accepted path
    // only: a refused send is a `request_failed`, and counting it here too would
    // report a conversation that never started.
    if (ok) Analytics.track('support_message_sent');
    // Write BEFORE you move (ADR-022): the box clears only once the endpoint
    // has accepted the message. On a 400/429 the text stays, which is the whole
    // point — this is the one screen where losing what the user typed is
    // unforgivable.
    if (ok) _controller.clear();
  }

  /// A new message brings the page's own scroller to its end — the composer
  /// is docked at the column's foot, so the last message sits just above it.
  void _scrollToEnd(int count) {
    if (count == _shown) return;
    _shown = count;
    if (count == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final support = context.watch<SupportNotifier>();
    final messages = support.messages;
    _markRead(support);
    _scrollToEnd(messages.length);

    // The thread's figures are measurements: the dash until it is read, and
    // while the read is refused (INV-24).
    final read = !support.loading && support.subError == null;
    final last = messages.isEmpty ? null : messages.last;
    final status = !read
        ? '—'
        : support.awaitingAnswer
        ? 'Awaiting a reply'
        : messages.isNotEmpty
        ? 'Answered'
        : 'Nothing sent yet';

    return KitDPage(
      folio:
          'Support · ${read ? kitCounted(messages.length, 'message') : '— messages'}',
      back: KitDBackControl('Settings', onTap: () => context.go('/settings')),
      title: 'Support',
      stand:
          'Found a bug, or want something NoteLetter doesn’t do yet? Tell us '
          'here. $_answerWindow',
      controller: _scroll,
      sheet: KitDSheet(
        label: 'The thread',
        peek: KitDIconPeek(
          icon: Icons.chat_bubble_outline,
          title: status,
          count: read ? '${messages.length}' : null,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitFigures(
              label: 'The thread',
              rows: [
                ('Messages', read ? '${messages.length}' : '—'),
                (
                  'Last',
                  last == null
                      ? '—'
                      : '${_sender(last)} · ${_stamp(last.createdAt)}',
                ),
                ('Status', status),
              ],
            ),
            const KitDNote(
              'Replies reach you through your notification '
              'channels.',
            ),
            KitSheetAlso(
              children: [
                KitAlsoButton(
                  'Notification channels',
                  icon: Icons.notifications_none,
                  onTap: () => context.go('/settings/notifications'),
                ),
              ],
            ),
          ],
        ),
      ),
      // The 10s send cooldown is the caller's (4.107.0, ADR-140): send is
      // held for the wait a refusal carried, its title says the time left, and
      // the server's sentence is the calm caption while it runs — never the
      // red §14.2 line (support.md, 4.108.0, ADR-145). The draft is kept
      // either way (write before you move).
      dock: KitWait(
        waitKey: WaitKey.supportSend(),
        builder: (context, wait) => KitDComposer(
          key: const ValueKey('support-composer'),
          fieldKey: const ValueKey('support-field'),
          sendKey: const ValueKey('support-send'),
          controller: _controller,
          placeholder: 'What happened?',
          label: 'Send to support',
          busy: support.sending,
          error: support.error,
          waitNote: wait.sentence,
          waitLeft: wait.left,
          maxLength: 4000,
          onSend: _controller.text.trim().isEmpty ? null : _send,
        ),
      ),
      child: _thread(support, messages),
    );
  }

  Widget _thread(SupportNotifier support, List<SupportMessage> messages) {
    if (support.loading && messages.isEmpty) {
      return const KitSkeletonLines(
        lines: [KitSkelLine(0.4), KitSkelLine(0.7), KitSkelLine(0.6)],
        top: 0,
      );
    }
    // INV-24 (ADR-071): the empty state below is an OFFER — it invites the
    // reader to write. A thread we failed to READ is not an invitation.
    if (support.subError != null) {
      return KitFailureBlock(
        sentence: 'Your support thread could not be read.',
        detail: support.subError!,
      );
    }
    if (messages.isEmpty) {
      // §7's quiet form: the composer below is the action, so this pattern
      // carries no call-to-action button.
      return const KitEmptyState(
        quiet: true,
        icon: Icons.chat_bubble_outline,
        title: 'Nothing sent yet',
        standfirst:
            'Describe what happened, or what you wish it did. Screens, steps '
            'and what you expected all help — there is no wrong way to write '
            'it.',
      );
    }
    // The correspondence, oldest first, as a ruled register.
    return KitDThread(
      children: [
        for (final m in messages)
          KitMessageCard(
            key: ValueKey('support-msg-${m.id}'),
            meta: [
              _sender(m),
              _stamp(m.createdAt),
              if (m.route != null && m.route!.isNotEmpty) m.route!,
            ],
            body: m.body,
            mine: m.sender == SupportSender.user,
          ),
        // Derived from `last_sender`, never a stored status field.
        if (support.awaitingAnswer)
          const KitThreadNote(
            'Received. $_answerWindow You’ll be told through your '
            'notification channels when there’s a reply.',
          ),
      ],
    );
  }
}

String _sender(SupportMessage m) =>
    m.sender == SupportSender.user ? 'You' : 'Support';

/// The reference's relative stamp: time today, `Mon D · time` otherwise.
String _stamp(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  final time = '$hh:$mm $ampm';
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return time;
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day} · $time';
}
