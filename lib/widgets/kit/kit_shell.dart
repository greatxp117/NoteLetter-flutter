import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_ground.dart';
import 'kit_text.dart';

/// §1.1 — the app shell: a **chrome rail** and an inset **main pane**.
///
/// The inset is the whole device: the pane reads as a sheet lying on the plum
/// desk. A main pane flush to the edges is a different app — which is what this
/// client shipped, because `AppLayout` was a bare `Row(Sidebar, Expanded)` with
/// no chrome behind it, no inset, no corner and no ground.
class KitShell extends StatelessWidget {
  final Widget rail;
  final Widget child;

  const KitShell({super.key, required this.rail, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.chrome,
      child: Row(
        children: [
          SizedBox(width: AppSpacing.railWidth, child: rail),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, AppSpacing.shellInset,
                  AppSpacing.shellInset, AppSpacing.shellInset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg)),
                  boxShadow: AppShadows.s1,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg)),
                  child: KitGround(child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact (phone) form of the shell: the rail becomes a drawer and the
/// pane goes full-bleed, but **the ground and the chrome surface stay**.
///
/// The pane paints `--surface` under the ground exactly as the wide one does.
/// [KitGround] draws only the texture — it is transparent by design, since it
/// also overlays surfaces that bring their own colour — so a compact pane that
/// omitted the fill let the Scaffold's chrome plum through the whole body:
/// every screen rendered its page text, at correct `--fg`, on the desk colour.
class KitShellCompact extends StatelessWidget {
  final Widget child;

  const KitShellCompact({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Tokens.of(context).surface,
        child: KitGround(child: child),
      );
}

/// §1.2 — the chrome rail's scaffolding: brand lockup, scrollable nav region,
/// pinned bottom.
///
/// **Foregrounds on chrome are white at token alphas, not `--fg`.** The chrome
/// surface is plum in both themes, so a foreground taken from the page tokens
/// flips to near-black in light mode and disappears.
class KitChromeRail extends StatelessWidget {
  final Widget brand;
  final List<Widget> items;
  final Widget? footer;

  const KitChromeRail(
      {super.key, required this.brand, required this.items, this.footer});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.chrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
              child: brand,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.s1),
                      items[i],
                    ],
                  ],
                ),
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: t.chromeBorder)),
                ),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The brand lockup: mark + serif wordmark, in chrome foreground.
class KitBrand extends StatelessWidget {
  final Widget mark;
  final String name;

  const KitBrand({super.key, required this.mark, this.name = 'NoteLetter'});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        SizedBox(width: 22, height: 22, child: mark),
        const SizedBox(width: 10),
        Text(
          name,
          style: AppTheme.serif(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.01 * 18,
            color: t.chromeFg,
          ),
        ),
      ],
    );
  }
}

/// A mono caps group label in the rail.
class KitRailGroupLabel extends StatelessWidget {
  final String label;

  const KitRailGroupLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, AppSpacing.s1),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.mono(
          fontSize: 10,
          letterSpacing: 0.14 * 10,
          color: t.chromeSubtle,
        ),
      ),
    );
  }
}

/// A rail nav item.
///
/// The **active item is marked by a 2px accent bar in the leading margin** plus
/// a raised fill — never by colour alone.
class KitNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? count;

  const KitNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.count,
  });

  @override
  State<KitNavItem> createState() => _KitNavItemState();
}

class _KitNavItemState extends State<KitNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = widget.active || _hover ? t.chromeFg : t.chromeMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: widget.active
                    ? t.chromeActive
                    : (_hover ? t.chromeHover : const Color(0x00000000)),
                borderRadius: AppRadius.smR,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (widget.count != null)
                    Text(
                      widget.count!,
                      style: AppTheme.mono(
                        fontSize: 11,
                        color: widget.active ? t.chromeFg : t.chromeSubtle,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                left: -8,
                top: 8,
                bottom: 8,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: t.chromeAccentBar,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The rail's **library card** (web `.sb-libcard`): the corpus at a glance, and
/// the place a newly added source visibly lands.
///
/// A card, not a row, because it carries figures. Same active treatment as
/// [KitNavItem] — 2px accent bar plus a raised fill.
///
/// NOTE: this pattern is in the web reference but was **missing from
/// `component-kit.md` §1.2** when the kit was transcribed. Recorded as owed
/// spec text (a `/contract-change` PATCH), not invented here — the figures,
/// alphas and metrics below are read off `app-kit.css`.
class KitRailCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<KitRailFigure> figures;
  final bool active;
  final VoidCallback? onTap;

  const KitRailCard({
    super.key,
    required this.icon,
    required this.label,
    required this.figures,
    this.active = false,
    this.onTap,
  });

  @override
  State<KitRailCard> createState() => _KitRailCardState();
}

class _KitRailCardState extends State<KitRailCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: widget.active
                    ? const Color(0x1AFFFFFF)
                    : (_hover
                        ? const Color(0x17FFFFFF)
                        : const Color(0x0DFFFFFF)),
                borderRadius: AppRadius.mdR,
                border: Border.all(
                    color: _hover
                        ? const Color(0x29FFFFFF)
                        : t.chromeBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.icon, size: 15, color: t.chromeFg),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: t.chromeFg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final f in widget.figures)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.value,
                                style: AppTheme.mono(
                                  fontSize: 16,
                                  height: 1,
                                  color: f.highlight
                                      ? t.chromeAccentBar
                                      : t.chromeFg,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                f.label.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.mono(
                                  fontSize: 9,
                                  letterSpacing: 0.1 * 9,
                                  color: const Color(0x61FFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                left: -9,
                top: 12,
                bottom: 16,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: t.chromeAccentBar,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One figure in a [KitRailCard]. [highlight] paints the numeral in
/// `--brick-400` — used for a non-zero unread count.
class KitRailFigure {
  final String value;
  final String label;
  final bool highlight;

  const KitRailFigure(this.value, this.label, {this.highlight = false});
}

/// The rail's footer identity block: initials avatar, name, secondary line.
class KitRailFooter extends StatelessWidget {
  final String initials;
  final String name;
  final String? secondary;

  const KitRailFooter(
      {super.key,
      required this.initials,
      required this.name,
      this.secondary});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.chromeFg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: t.chromeFg,
                  ),
                ),
                if (secondary != null && secondary!.isNotEmpty)
                  Text(
                    secondary!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      fontSize: 10,
                      letterSpacing: 0.06 * 10,
                      color: t.chromeSubtle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §1.3 — the utility rail at the top of the main pane: a mono caps breadcrumb,
/// a flexible gap, then trailing controls. 48px, closed by a `--rule`.
class KitUtilityBar extends StatelessWidget {
  final String? crumb;
  final List<Widget> actions;
  final Widget? leading;

  const KitUtilityBar(
      {super.key, this.crumb, this.actions = const [], this.leading});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s2),
          ],
          if (crumb != null)
            Flexible(
              child: Text(
                crumb!.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: KitText.capsLabel(
                  context,
                  fontSize: 10.5,
                  letterSpacing: 0.13,
                  color: t.fgSubtle,
                ),
              ),
            ),
          const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s1),
            actions[i],
          ],
        ],
      ),
    );
  }
}
