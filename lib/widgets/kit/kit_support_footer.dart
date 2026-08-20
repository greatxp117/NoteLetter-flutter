import 'package:flutter/widgets.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// §13 — the support footer. **The way out of every screen.**
///
/// INV-22: composed **once, by the shell**, beneath the routed view. A screen
/// never renders it and never suppresses it. The alternative — a line copied
/// into each page — fails silently and in exactly one direction: the
/// thirteenth screen renders correctly and is simply the one with no way out.
/// Nothing throws, no test goes red, and the only person who finds out is a
/// user who had a bug to report and gave up.
///
/// **Required parts** (a pattern's required parts are not a starting point to
/// trim): the plain question `Bugs? Feature Requests?`, then
/// `Chat with support…` as an **underlined** control, in that order, on one
/// line, plus an optional trailing unread count in mono. No icon, no button
/// chrome, no dismiss.
///
/// **The underline is the specification, not a suggestion.** `--link` is
/// near-black ink in light mode, so a control distinguished only by colour is
/// invisible as a control — which is why this design system otherwise avoids
/// colour-only links.
///
/// **Quiet, and always there.** This is the pattern most likely to be
/// "improved" into a floating action button or a chat bubble. Being the least
/// prominent thing on the screen and being on every screen are the two
/// properties that let it be permanent without competing with the content.
class KitSupportFooter extends StatefulWidget {
  /// Opens the support thread. The **shell** supplies this, along with the
  /// route the user was on — the footer itself knows neither.
  final VoidCallback onOpen;

  /// `unread_for_user` from the thread. Absent thread ⇒ 0.
  final int unread;

  const KitSupportFooter({
    super.key,
    required this.onOpen,
    this.unread = 0,
  });

  @override
  State<KitSupportFooter> createState() => _KitSupportFooterState();
}

class _KitSupportFooterState extends State<KitSupportFooter> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    // The shell's own gutter — the footer spans the pane, so it follows the
    // shell rather than the page frame (§1.5), which it deliberately sits
    // outside of.
    final gutter =
        compact ? AppSpacing.frameGutterCompact : AppSpacing.frameGutter;

    return DecoratedBox(
      decoration: BoxDecoration(
        // It sits BELOW the screen's scroll container (§1.4), so it never
        // inherits the ground texture and never scrolls away.
        color: t.surface,
        border: Border(top: BorderSide(color: t.rule)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 10),
        child: Row(
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Bugs? Feature Requests? ',
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12.5,
                        height: 18 / 12.5,
                        color: t.fgSubtle,
                      ),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hover = true),
                        onExit: (_) => setState(() => _hover = false),
                        child: GestureDetector(
                          onTap: widget.onOpen,
                          child: Text(
                            'Chat with support…',
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 12.5,
                              height: 18 / 12.5,
                              color: _hover ? t.accent : t.link,
                              decoration: TextDecoration.underline,
                              decorationColor: t.linkDecor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.unread > 0) ...[
              const SizedBox(width: AppSpacing.s2),
              Text(
                '${widget.unread}',
                style: AppTheme.mono(fontSize: 11, color: t.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
