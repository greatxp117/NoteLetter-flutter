import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_frame.dart';
import 'kit_text.dart';

/// §19 — Section rail (4.64.0, ADR-100).
///
/// The strip that names the stacked sections of a **long single-scroll screen**
/// and moves the reader between them. Its only consumer is the reader, which is
/// the only screen in this app long enough to need one.
///
/// **This is not a tab strip and not §6.8's segmented control.** A segmented
/// control SETS the state it displays; this REPORTS one it cannot set — every
/// section it names is already mounted and already reachable by scrolling past
/// it, and the marked jump is whichever section currently crosses the rail's
/// own bottom edge. Built as a segmented control it acquires a selected state
/// that scrolling contradicts, and the first thing a reader does here is
/// scroll.
///
/// The row **scrolls horizontally rather than compressing**: a label is a name,
/// and "Speed read" broken over two lines makes the rail two rows tall and
/// reads as two rails.
class KitSectionRailItem {
  final String id;
  final String label;
  final IconData icon;

  /// The mono chip trailing the label — the reader's Original section carries
  /// the document's own `type`. Null everywhere else.
  final String? count;

  const KitSectionRailItem(this.id, this.label, this.icon, {this.count});
}

class KitSectionRail extends StatelessWidget {
  final List<KitSectionRailItem> items;

  /// The section that currently crosses the rail's bottom edge. Reported by
  /// the host from scroll position — never set by a tap alone (a tap marks a
  /// jump only because the scroll it causes arrives there).
  final String current;

  final ValueChanged<String> onJump;

  final KitFrameWidth width;

  /// The ground this rail is pinned OVER, as the host's own token.
  ///
  /// It has to hide the content scrolling beneath it, so it paints — and a
  /// rail painting a different token from the surface behind it reads as a
  /// **bar across the page** instead of as part of it. Measured, not guessed:
  /// the first pair of this screen drew `--bg` over the reader's `--surface`
  /// ground and the band was obvious in dark mode.
  final Color background;

  /// Reference metrics: 13px above the label, 14px below, plus the 1px rule.
  static const double height = 48;

  const KitSectionRail({
    super.key,
    required this.items,
    required this.current,
    required this.onJump,
    required this.background,
    this.width = KitFrameWidth.reading,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      color: background,
      alignment: Alignment.topCenter,
      child: KitFrameBand(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in items)
                  _Jump(
                    item: item,
                    on: item.id == current,
                    onTap: () => onJump(item.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail as a **pinned** sliver — the sticky row §19 requires. A rail that
/// scrolls away with the content is a heading, not a rail: it can name where
/// the reader is only while it is on screen.
class KitSectionRailHeader extends SliverPersistentHeaderDelegate {
  final List<KitSectionRailItem> items;
  final String current;
  final ValueChanged<String> onJump;
  final KitFrameWidth width;
  final Color background;

  const KitSectionRailHeader({
    required this.items,
    required this.current,
    required this.onJump,
    required this.background,
    this.width = KitFrameWidth.reading,
  });

  @override
  double get minExtent => KitSectionRail.height;

  @override
  double get maxExtent => KitSectionRail.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(
        height: KitSectionRail.height,
        child: KitSectionRail(
          items: items,
          current: current,
          onJump: onJump,
          background: background,
          width: width,
        ),
      );

  @override
  bool shouldRebuild(KitSectionRailHeader old) =>
      old.current != current ||
      old.items != items ||
      old.background != background;
}

class _Jump extends StatelessWidget {
  final KitSectionRailItem item;
  final bool on;
  final VoidCallback onTap;

  const _Jump({required this.item, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // Position AND weight, never hue alone: the underline is the mark, and the
    // label moving `--fg-muted` → `--fg` is the second channel.
    final fg = on ? t.fg : t.fgMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
        // The current mark is a BOTTOM BORDER, not a sized bar: the row scrolls
        // horizontally, so its children are laid out with an unbounded width
        // and a `Container(height: 2)` with no child collapses to nothing
        // there — the underline was drawn and invisible in the first pair.
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? t.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(
              item.label,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
            if (item.count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: on ? t.accentChipBg : t.surfaceSunken,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.count!,
                  style: KitText.capsLabel(
                    context,
                    fontSize: 10,
                    letterSpacing: 0.04,
                    color: on ? t.accentChipFg : t.fgMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
