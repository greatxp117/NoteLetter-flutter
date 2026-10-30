import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart' show KitAttentionPill;

/// §13 — the support footer. **The way out of every screen.**
///
/// INV-22: composed **once, by the shell**, and rendered as the LAST element of
/// the screen's primary scroll container ([KitShellFooter], 5.19.0, ADR-173).
/// A screen never renders it and never suppresses it. The alternative — a line copied
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
/// **Quiet, and at the end.** This is the pattern most likely to be
/// "improved" into a floating action button or a chat bubble. It is the least
/// prominent thing on the screen and on every screen, and it ends each
/// screen's scroll — "out of the way but present" (Xavier, 2026-10-17). Until
/// 5.19.0 it was pinned below the scroll and always on screen: present, and
/// never out of the way (ADR-173).
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
    // Direction D (kit §13): the footer is part of the page, not a band at
    // its end — on the page's own ground (no fill, no top rule), centred,
    // `40px 56px 32px` (18 at the sides on a phone, as web's 680 rule).
    final phone = MediaQuery.sizeOf(context).width <= 680;
    final copy = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12.5,
      height: 18 / 12.5,
      color: t.fgSubtle,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 18 : 56, 40, phone ? 18 : 56, 32),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          Text('Bugs? Feature Requests?', style: copy),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onOpen,
              child: Text(
                'Chat with support…',
                style: copy.copyWith(
                  color: _hover ? t.accentText : t.link,
                  decoration: TextDecoration.underline,
                  decorationColor: _hover ? t.accent : t.linkDecor,
                ),
              ),
            ),
          ),
          // §1.2's attention pill (D), `999+` past 999.
          if (widget.unread > 0)
            KitAttentionPill(widget.unread, label: 'unread'),
        ],
      ),
    );
  }
}
