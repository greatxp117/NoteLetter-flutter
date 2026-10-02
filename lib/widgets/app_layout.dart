import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/review_inbox.dart';
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
            toolbarHeight: 54,
            shape: Border(bottom: BorderSide(color: t.chromeActive)),
            // The drawer's own button, carrying §1.2's attention DOT while For
            // your review's count is above zero: on a phone that item lives in
            // the drawer, out of sight (4.100.0).
            automaticallyImplyLeading: false,
            leading: Builder(
              builder: (ctx) {
                final waiting =
                    (ctx.watch<ReviewInbox>().view.count ?? 0) > 0;
                return Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      KitAppBarButton(
                        icon: Icons.menu,
                        label: waiting
                            ? 'Menu — something is waiting for your review'
                            : 'Menu',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                      if (waiting)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IgnorePointer(
                            child: Container(
                              key: const ValueKey('menu-attention-dot'),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: t.chromeAccentBar,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            title: const KitBrand.appBar(),
            // `.app-mobile-header`: menu · brand · spacer · search. Web's
            // search opens its QuickSearch overlay; this client has no overlay,
            // so the control goes where the overlay would lead — /search.
            actions: [
              ...actions,
              KitAppBarButton(
                icon: Icons.search,
                label: 'Search',
                onPressed: () => context.go('/search'),
              ),
              const SizedBox(width: 10),
            ],
          ),
          drawer: const NavDrawer(),
          body: KitShellCompact(child: child),
        );
      },
    );
  }
}
