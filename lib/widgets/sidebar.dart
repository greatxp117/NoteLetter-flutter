import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../pages/tags/shelf_sheet.dart';
import '../shared/local_flags.dart';
import '../state/activity_notifier.dart';
import '../state/auth_notifier.dart';
import '../state/documents_notifier.dart';
import '../state/theme_notifier.dart';
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
  Widget build(BuildContext context) => const RailContent();
}

/// The rail's contents, shared by the wide rail and the compact **drawer**.
///
/// One definition, because the reference has one: its `Drawer` renders the same
/// `SidebarContent` the sidebar does. This client had two — a `NavDrawer` with
/// its own nav vocabulary (*Daily Digest*, *Knowledge Base*, a `/library`
/// route this app does not serve, plus Welcome and Branding), its own plain
/// `ListTile` rows, no library card, no groups, no identity footer and no
/// unread badge. Nothing was red: a second nav is not a wrong nav to any gate,
/// and a phone is where most of this client is actually used, so the divergent
/// one was the one being looked at.
///
/// [onNavigate] is how the drawer closes itself. The wide rail passes nothing:
/// there is no drawer to dismiss, and a `Navigator.pop` there would pop the
/// route the reader is on.
class RailContent extends StatefulWidget {
  final VoidCallback? onNavigate;

  const RailContent({super.key, this.onNavigate});

  @override
  State<RailContent> createState() => _RailContentState();
}

class _RailContentState extends State<RailContent> {
  @override
  void initState() {
    super.initState();
    // The rail is on every screen, so it opens the subscriptions itself rather
    // than depending on whichever screen happens to be mounted: the card's
    // figures would otherwise read zero everywhere except Library, and the
    // unread badge — whose whole job is to be seen from the screens that are
    // NOT Activity — would never count anything at all. Both `start()`s are
    // idempotent (INV-02: one subscription, shared).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DocumentsNotifier>().start();
      context.read<ActivityNotifier>().start();
    });
    LocalFlags.ensureLoaded();
  }

  /// Opens §Creating a shelf in a §15 sheet over whatever the reader is on.
  /// The navigator and router are taken BEFORE the drawer closes itself: on a
  /// phone the rail is the drawer, and closing it unmounts this context.
  void _newShelf(BuildContext context, bool canBackfill) {
    final nav = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);
    widget.onNavigate?.call();
    showShelfSheet(
      nav.context,
      canBackfill: canBackfill,
      land: (id) => router.go('/shelves/$id'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).uri.path;
    void go(String path) {
      widget.onNavigate?.call();
      context.go(path);
    }

    return Consumer2<DocumentsNotifier, ActivityNotifier>(
      builder: (context, docs, activity, _) {
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
        final ok = docs.measured;

        return KitChromeRail(
          brand: const KitBrand(),
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
                // A refused or unarrived read is the dash, not three zeros
                // beside a §14 block saying the read failed (ADR-109).
                KitRailFigure(ok ? '$volumes' : null,
                    ok && volumes == 1 ? 'Volume' : 'Volumes'),
                KitRailFigure(ok ? '$passages' : null, 'Passages'),
                KitRailFigure(ok ? '$unread' : null, 'Unread',
                    highlight: unread > 0),
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
              active: route == '/ask',
              onTap: () => go('/ask'),
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
            // Always drawn (4.83.0, ADR-117): the `+` is how a first shelf
            // gets made, so it cannot wait for a source to exist. The rail
            // does NOT list every shelf here — that is a separate parity
            // question, not this control's.
            KitRailGroupLabel(
              'Shelves',
              addLabel: 'New shelf',
              onAdd: () => _newShelf(context, docs.complete.isNotEmpty),
            ),
            KitNavItem(
              icon: Icons.label_outline,
              label: 'All shelves',
              active: route.startsWith('/shelves'),
              onTap: () => go('/shelves'),
            ),
          ],
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActivityNavItem(
                activity: activity,
                onActivity: route == '/activity',
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
              // §1.2's pinned bottom region — the part the rail had never
              // rendered. `KitRailFooter` has been in the kit since 4.5.0 with
              // no call site: a kit widget nothing mounts reads as a built
              // pattern to everyone after, which is the dead-class trap with
              // the repo's own component layer standing in for the stylesheet.
              const SizedBox(height: 6),
              const _RailIdentity(),
            ],
          ),
        );
      },
    );
  }
}

/// The Activity entry point and its **unread badge**
/// (`screens/activity.md` §Toasts and unread).
///
/// The badge is a count of EVENTS newer than the client-local last-seen mark;
/// the feed writes that mark while it is open. Three consequences of the
/// reference's rule, all deliberate:
///
/// * **Zero while the feed is the route.** Not merely "marked on arrival": the
///   reader is looking at the thing, and an item arriving under their eyes
///   would otherwise put a `1` on the entry point for the screen they are on.
/// * The mark is written from the newest event the feed is SHOWING, not from
///   the clock — see [ActivityNotifier.newestEventAt].
/// * A never-visited feed shows every event as unread, capped at `9+`. That is
///   the right answer, not a bug to soften: nothing has been seen.
class _ActivityNavItem extends StatelessWidget {
  final ActivityNotifier activity;
  final bool onActivity;
  final VoidCallback onTap;

  const _ActivityNavItem({
    required this.activity,
    required this.onActivity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LocalFlags.activityLastSeen,
      builder: (context, lastSeen, _) {
        final unread = onActivity ? 0 : activity.unreadSince(lastSeen);
        return KitNavItem(
          icon: Icons.timeline_outlined,
          label: 'Activity',
          active: onActivity,
          onTap: onTap,
          badge: unread > 0 ? kitBadgeLabel(unread) : null,
        );
      },
    );
  }
}

/// §1.2's footer identity: initials, name, and the account line beneath it.
class _RailIdentity extends StatelessWidget {
  const _RailIdentity();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthNotifier>(
      builder: (context, auth, _) {
        final user = auth.user;
        if (user == null) return const SizedBox.shrink();
        final name = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email ?? '');
        if (name.isEmpty) return const SizedBox.shrink();
        return KitRailFooter(
          initials: _initialsOf(name),
          name: name,
          // The email only where it is not already the name — the reference
          // draws a blank second line rather than the address twice.
          secondary: user.displayName?.trim().isNotEmpty == true
              ? (user.email ?? '')
              : '',
        );
      },
    );
  }
}

/// `initialsOf` from the reference: one name gives two letters, two or more
/// give the first and the last.
String _initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length < 2 ? parts.first.length : 2)
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
