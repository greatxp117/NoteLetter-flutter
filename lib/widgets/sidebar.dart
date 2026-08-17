import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/activity_notifier.dart';
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
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).uri.path;
    void go(String path) => context.go(path);

    return Consumer<ActivityNotifier>(
      builder: (context, activity, _) {
        // The web card shows three figures — Volumes · Passages · Unread.
        // Only the first has a backing signal in this client: `documents`
        // here is a list of `ActivityItem`, which carries no `chunk_count` or
        // `view_count`, and nothing in state holds a `List<Document>`.
        //
        // So it shows one figure. Rendering "0 Passages / 0 Unread" would be
        // three measurements presented alike where two are placeholders — the
        // same defect as the storage meter this replaced. Wiring
        // `subscribeDocuments()` would supply the other two; that is a
        // data-layer task, recorded in ../TODO.md, not something to fake here.
        final volumes = activity.documents.length;

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
              active: route == '/sources' || route == '/library',
              onTap: () => go('/sources'),
              figures: [
                KitRailFigure('$volumes',
                    volumes == 1 ? 'Volume' : 'Volumes'),
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
