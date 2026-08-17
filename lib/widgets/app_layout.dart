import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/tokens.dart';
import 'kit/kit.dart';
import 'nav_drawer.dart';
import 'sidebar.dart';

/// The app shell (`component-kit.md` §1.1).
///
/// Wide: a plum **chrome rail** beside an **inset main pane** — rounded on its
/// leading top corner, carrying the checker-and-grain ground, lifted by
/// `--shadow-1`. The inset is the whole device: the pane reads as a sheet lying
/// on the plum desk.
///
/// This was previously a bare `Row(Sidebar, Expanded(child))` — no chrome
/// behind the pane, no inset, no corner, no ground and no utility bar. Every
/// colour in it was a correct token, which is exactly why nothing flagged it.
///
/// Compact: the rail becomes a drawer and the pane goes full-bleed, but **the
/// ground and the chrome surface stay**. The compact app bar previously drew
/// `surface-raised` with page-coloured text; on chrome the foreground is white
/// at token alphas, and taking it from the page tokens turns it near-black in
/// light mode.
class AppLayout extends StatelessWidget {
  final Widget child;

  /// Mono caps breadcrumb for the utility bar.
  final String? crumb;

  /// Trailing controls in the utility bar.
  final List<Widget> actions;

  const AppLayout({
    super.key,
    required this.child,
    this.crumb,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = Tokens.of(context);
        final wide = constraints.maxWidth >= AppSpacing.compactWidth;

        if (wide) {
          return Scaffold(
            backgroundColor: t.chrome,
            body: KitShell(
              rail: const Sidebar(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KitUtilityBar(crumb: crumb, actions: actions),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: t.chrome,
          appBar: AppBar(
            backgroundColor: t.chrome,
            foregroundColor: t.chromeFg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            titleSpacing: 0,
            title: KitBrand(
              mark: Icon(Icons.edit_note, size: 22, color: t.chromeFg),
            ),
            actions: actions,
          ),
          drawer: const NavDrawer(),
          body: KitShellCompact(child: child),
        );
      },
    );
  }
}
