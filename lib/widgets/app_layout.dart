import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/review_inbox.dart';
import '../theme/tokens.dart';
import 'kit/kit.dart';
import 'nav_drawer.dart';
import 'sidebar.dart';

/// The app shell (`component-kit.md` §1.1, direction D §30).
///
/// Wider than 1024: a plum **chrome rail** (the compact rail, kit §1.2) beside
/// an **inset main pane** — rounded on its leading top corner, carrying the
/// checker-and-grain ground, lifted by `--shadow-1`. D removes §1.3's utility
/// bar: every D page opens on its own masthead, whose rail carries the page's
/// tools.
///
/// At 1024 and under (§30, a WINDOW breakpoint): the **app header** (menu,
/// Search pill, the page's settings) over the full-bleed pane, the **tab bar**
/// (Home, Library, the page's action, Letters, Ask) at its foot, and the rail
/// in a drawer from the header's menu. The ground and the chrome surface stay.
/// The header and the tab bar read the page's registered tools
/// ([KitPageTools]), since they live outside the page.
class AppLayout extends StatelessWidget {
  final Widget child;

  const AppLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // The shell's verbs for every D page's kit parts (web `DShellProvider`):
    // this client has no quick-search overlay, so Search goes where the
    // overlay would lead — /search; Add a source is the Library's uploader.
    final shelled = KitDShell(
      openSearch: () => context.go('/search'),
      openAdd: () => context.go('/sources'),
      child: child,
    );
    final wide = MediaQuery.sizeOf(context).width > KitD.chromeMax;
    if (wide) {
      return Scaffold(
        backgroundColor: t.chrome,
        body: KitShell(rail: const Sidebar(), child: shelled),
      );
    }
    final route = GoRouterState.of(context).uri.path;
    return Scaffold(
      backgroundColor: t.chrome,
      appBar: const _Header(),
      drawer: const NavDrawer(),
      body: KitShellCompact(child: shelled),
      bottomNavigationBar: KitTabBar(
        route: route,
        aiOn: shellAiOn(context),
        onGo: (path) => context.go(path),
        onAdd: () => context.go('/sources'),
      ),
    );
  }
}

/// §30's app header, carrying §1.2's attention DOT while For your review's
/// count is above zero (4.100.0).
///
/// It opens the inbox ITSELF. On a phone the rail — the only other thing that
/// starts it — lives inside the drawer and is not built until the drawer is
/// opened, so a dot reading an inbox nobody had started could never appear:
/// the one signal on a phone that something was waiting was unreachable until
/// the reader had already gone looking (seen on the first device frames of
/// F-72, 2026-10-05). `start()` is idempotent (INV-02: one subscription).
class _Header extends StatefulWidget implements PreferredSizeWidget {
  const _Header();

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReviewInbox>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final waiting = (context.watch<ReviewInbox>().view.count ?? 0) > 0;
    return KitAppHeader(
      attention: waiting,
      onMenu: () => Scaffold.of(context).openDrawer(),
      onSearch: () => context.go('/search'),
    );
  }
}
