import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/ai_settings_notifier.dart';
import '../../widgets/kit/kit.dart';

/// Ask while generative AI is off (5.29.0, ADR-186, INV-34;
/// `screens/ask.md` §While generative AI is off; web `pages/ask/AskOff.jsx`).
///
/// Nothing draws a way in, but a bookmark, an old link or a typed `/ask` still
/// arrives here — and a blank pane would read as a broken screen. So the frame
/// says why and offers the one way back. While the switch is unread it draws
/// the frame and the kit skeleton under it (web 22f9461) — never a thread, a
/// conversation list or the composer: the reader may be someone who turned
/// Ask off, and none of Ask may flash. Direction D: Ask's own masthead, one
/// column, no sheet and no action — there are no conversations to list while
/// Ask is not shown.
class AskOffPage extends StatelessWidget {
  const AskOffPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiSettingsNotifier>();
    return KitDPage(
      folio: 'Ask',
      title: 'Ask',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ai.genAI == GenAI.loading)
            const KitSkeletonLines(
              key: ValueKey('ask-off-loading'),
              lines: [
                KitSkelLine(0.6),
                KitSkelLine(),
                KitSkelLine(0.7),
                KitSkelLine(),
                KitSkelLine(0.5),
              ],
            ),
          if (ai.genAI == GenAI.off)
            KitNotice(
              text:
                  'Ask is off. Generative AI is switched off in Settings, so '
                  'NoteLetter isn’t showing Ask.',
              actionLabel: 'Open Settings',
              onAction: () => context.go('/settings'),
            ),
          if (ai.genAI == GenAI.failed)
            KitFailureBlock(
              sentence:
                  'Your generative-AI setting could not be read, so Ask is '
                  'not shown.',
              detail: ai.error ?? '',
              onRetry: ai.start,
            ),
        ],
      ),
    );
  }
}

/// The `/ask` routes' gate: Ask itself only while generative AI is READ on;
/// otherwise [AskOffPage]. A tree with no [AiSettingsNotifier] (a bare
/// harness) is Ask, as `shellAiOn` reads it.
class AskGate extends StatelessWidget {
  final Widget child;
  const AskGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiSettingsNotifier?>();
    if (ai == null || ai.aiOn) return child;
    return const AskOffPage();
  }
}
