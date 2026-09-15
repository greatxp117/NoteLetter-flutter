import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/support.dart';
import '../state/support_notifier.dart';
import '../theme/app_spacing.dart';
import '../widgets/kit/kit.dart';
import '../services/analytics.dart';

/// Support — the conversation between one user and a human (contract 4.18.0,
/// ADR-054; `spec/screens/support.md`).
///
/// Reached from the **support footer**, which the shell renders under every
/// screen (INV-22) — never from a per-screen link. This screen therefore knows
/// nothing about how it was reached except [fromRoute], which the shell passed.
///
/// The reply arrives through the notification channels the user already
/// configured (ADR-014/ADR-015). This screen does not have to be open, and
/// never claims to be the only place an answer lands.
///
/// Composition (ADR-041): Reading frame (760) inside a scroll container (§1.4)
/// · sub-screen header (§2.2) · the transcript as passage cards (§5.2) ·
/// composer dock (§10), pinned to the frame.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Opening the screen marks it read — once, and only when there is
      // something to clear. The notifier holds both guards; this is a call, not
      // a decision. The SUBSCRIPTION is the shell's (it feeds the badge on
      // every screen), so this screen never starts one.
      context.read<SupportNotifier>().markRead();
    });
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

  Future<void> _send() async {
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
    if (mounted) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final support = context.watch<SupportNotifier>();
    final messages = support.messages;

    return Stack(
      children: [
        KitPage(
          width: KitFrameWidth.reading,
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubScreenHeader(
                parentLabel: 'Settings',
                onBack: () => context.go('/settings'),
                eyebrow: 'Support',
                standfirst:
                    'Found a bug, or want something NoteLetter doesn’t do '
                    'yet? Tell us here. $_answerWindow',
              ),
              if (support.loading && messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s6),
                  child: Text('Loading…', style: KitText.meta(context)),
                )
              // INV-24 (ADR-071): the empty state below is an OFFER — it
              // invites the reader to write. A thread we failed to READ is not
              // an invitation.
              else if (support.subError != null)
                KitFailureBlock(
                  sentence: 'Your support thread could not be read.',
                  detail: support.subError!,
                )
              else if (messages.isEmpty)
                // The empty state IS the offer: the composer below is the
                // action, so this pattern carries no call-to-action button.
                const KitEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Nothing sent yet',
                  standfirst:
                      'Describe what happened, or what you wish it did. '
                      'Screens, steps and what you expected all help — there '
                      'is no wrong way to write it.',
                )
              else ...[
                // The transcript: §5.2 at reduced emphasis, one per message,
                // 18px apart, oldest first.
                for (final m in messages)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: KitMessageCard(
                      meta: [
                        m.sender == SupportSender.user ? 'You' : 'Support',
                        _stamp(m.createdAt),
                        if (m.route != null && m.route!.isNotEmpty) m.route!,
                      ],
                      body: m.body,
                      mine: m.sender == SupportSender.user,
                    ),
                  ),
                // Derived from `last_sender`, never a stored status field.
                if (support.awaitingAnswer)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: KitThreadNote(
                      'Received. $_answerWindow You’ll be told through '
                      'your notification channels when there’s a reply.',
                    ),
                  ),
              ],
              // Room for the dock, which floats over this scroller.
              const SizedBox(height: AppSpacing.s24),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: KitComposerDock(
            controller: _controller,
            placeholder: 'What happened?',
            busy: support.sending,
            error: support.error,
            maxLength: 4000,
            minLines: 2,
            onSend: _controller.text.trim().isEmpty ? null : _send,
          ),
        ),
      ],
    );
  }
}

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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day} · $time';
}
