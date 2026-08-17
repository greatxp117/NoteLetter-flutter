import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/documents_notifier.dart';
import '../state/theme_notifier.dart';
import '../theme/app_colors.dart';
import 'kit/kit.dart';

/// The chrome rail (`component-kit.md` §1.2), composed from the kit.
///
/// Structure mirrors the web reference (`shell/AppShell.jsx`): **Home leads the
/// rail unlabelled** — a group label above a single destination names a
/// category the user is not choosing between — then Knowledge, Study and
/// Letters as labelled groups, with Activity and Settings pinned to the bottom
/// above the identity footer.
///
/// Two things that were here and are deliberately gone:
///
/// * The **storage meter** (`2.1 GB / 6 GB used`, `value: 0.35`) was **mock
///   data**. There is no storage-quota signal anywhere in the contract, so it
///   was a hardcoded figure presented as a measurement. A stat needs a real
///   backing signal before it gets a slot.
/// * **Welcome** and **Branding** were primary nav entries. Neither exists in
///   the web reference; Branding is a development page. The routes still work,
///   they are simply not destinations in the rail.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  @override
  void initState() {
    super.initState();
    // The rail is on every screen, so it opens the documents subscription
    // itself rather than depending on whichever screen happens to be mounted:
    // the card's figures would otherwise read zero everywhere except Library.
    // `start()` is idempotent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DocumentsNotifier>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).uri.path;
    void go(String path) => context.go(path);

    return Consumer<DocumentsNotifier>(
      builder: (context, docs, _) {
        // The corpus at a glance, derived from the documents subscription that
        // is already open (INV-02) — no extra read. All three figures are
        // measured: volumes and passages from the indexed documents, unread
        // from `view_count`, which INV-03a bumps on an open and nothing else.
        //
        // Until 4.5.1 the rail read the activity merge, whose `ActivityItem`
        // carries no `tag_ids` and no `view_count`, so two of the three cells
        // had no signal and the card showed one figure. `DocumentsNotifier`
        // supplies them.
        final done = docs.complete;
        final volumes = done.length;
        final passages =
            done.fold<int>(0, (n, d) => n + (d.chunkCount ?? 0));
        final unread = done.where((d) => d.viewCount == 0).length;

        return KitChromeRail(
          brand: const KitBrand(mark: Icon(Icons.edit_note, size: 22, color: AppColors.chromeForeground)),
          items: [
            KitNavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              active: route == '/',
              onTap: () => go('/'),
            ),
            const KitRailGroupLabel('Knowledge'),
            KitRailCard(
              icon: Icons.menu_book_outlined,
              label: 'Library',
              active: route == '/sources',
              onTap: () => go('/sources'),
              figures: [
                KitRailFigure('$volumes',
                    volumes == 1 ? 'Volume' : 'Volumes'),
                KitRailFigure('$passages', 'Passages'),
                KitRailFigure('$unread', 'Unread', highlight: unread > 0),
              ],
            ),
            KitNavItem(
              icon: Icons.search,
              label: 'Search',
              active: route == '/search',
              onTap: () => go('/search'),
            ),
            KitNavItem(
              icon: Icons.chat_bubble_outline,
              label: 'Ask',
              active: route == '/chat',
              onTap: () => go('/chat'),
            ),
            const KitRailGroupLabel('Study'),
            KitNavItem(
              icon: Icons.school_outlined,
              label: 'Study',
              active: route.startsWith('/study'),
              onTap: () => go('/study'),
            ),
            const KitRailGroupLabel('Letters'),
            KitNavItem(
              icon: Icons.mail_outlined,
              label: 'Letters',
              active: route == '/letters',
              onTap: () => go('/letters'),
            ),
            const KitRailGroupLabel('Shelves'),
            KitNavItem(
              icon: Icons.label_outline,
              label: 'All shelves',
              active: route == '/tags',
              onTap: () => go('/tags'),
            ),
          ],
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              KitNavItem(
                icon: Icons.timeline_outlined,
                label: 'Activity',
                active: route == '/activity',
                onTap: () => go('/activity'),
              ),
              const SizedBox(height: 4),
              KitNavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                active: route.startsWith('/settings'),
                onTap: () => go('/settings'),
              ),
              const SizedBox(height: 4),
              Consumer<ThemeNotifier>(
                builder: (context, notifier, _) => KitNavItem(
                  icon: notifier.modeIcon,
                  label: notifier.modeLabel,
                  onTap: notifier.toggle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
