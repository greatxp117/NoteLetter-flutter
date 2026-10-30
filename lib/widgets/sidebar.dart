import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../pages/tags/shelf_sheet.dart';
import '../shared/local_flags.dart';
import '../state/tags_notifier.dart';
import '../state/activity_notifier.dart';
import '../state/review_inbox.dart';
import '../state/auth_notifier.dart';
import '../state/documents_notifier.dart';
import 'kit/kit.dart';

/// The chrome rail (`component-kit.md` §1.2), composed from the kit.
///
/// Structure mirrors the web reference (`shell/AppShell.jsx`): **Home leads the
/// rail unlabelled** — a group label above a single destination names a
/// category the user is not choosing between — and since direction D it is the
/// COMPACT rail (Xavier, 2026-10-30): Knowledge and Practice as labelled groups,
/// and the Reader's card (Settings and Activity) pinned to the bottom.
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
      // The rail's shelf tree (5.28.0) reads the one tags subscription.
      context.read<TagsNotifier>().start();
      // For your review's attention count is seen from every screen but its
      // own, so the rail opens the one inbox too (INV-30).
      context.read<ReviewInbox>().start();
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

    final aiOn = shellAiOn(context);
    return Consumer2<DocumentsNotifier, ActivityNotifier>(
      builder: (context, docs, activity, _) {
        // The corpus at a glance, derived from the documents subscription that
        // is already open (INV-02) — no extra read. All three figures are
        // measured: volumes and passages from the indexed documents, unread
        // from `view_count`, which INV-03a bumps on an open and nothing else.
        final done = docs.complete;
        final volumes = done.length;
        final passages =
            done.fold<int>(0, (n, d) => n + (d.chunkCount ?? 0));
        final unread = done.where((d) => d.viewCount == 0).length;
        final ok = docs.measured;
        final shelfCount = context.watch<TagsNotifier>().tags.length;
        final shelfRoute = route == '/shelves' || route.startsWith('/shelves/');

        // THE COMPACT RAIL (direction D, Xavier 2026-10-30; kit §1.2): Home
        // and For your review; Knowledge — the library card, Ask, Shelves with
        // its `+`; Practice — Letters, Study. No Search row (the header's pill
        // and every masthead's Search), no shelf tree (the Shelves page), no
        // Letter settings row, no Activity or Settings rows (the Reader's
        // card), no theme row (Settings), no build line.
        return KitChromeRail(
          brand: const KitBrand(),
          items: [
            KitNavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              active: route == '/',
              onTap: () => go('/'),
            ),
            // 4.100.0 (ADR-135): directly under Home, in the unlabelled lead
            // group, carrying §1.2's attention count — the same object the
            // page's folio reads, so the two cannot disagree.
            Consumer<ReviewInbox>(builder: (context, inbox, _) {
              final count = inbox.view.count;
              return KitNavItem(
                icon: Icons.inbox_outlined,
                label: 'For your review',
                active: route == '/review',
                onTap: () => go('/review'),
                badge: kitAttentionLabel(count),
                badgeUnmeasured: count == null,
              );
            }),
            const KitRailGroupLabel('Knowledge'),
            KitRailCard(
              icon: Icons.menu_book_outlined,
              label: 'Library',
              // Add a source (/sources/add) is the Library's page too.
              active: route == '/sources' || route.startsWith('/sources/'),
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
            // Absent while generative AI is off or not yet read — absent,
            // never disabled (5.29.0, ADR-186, INV-34).
            if (aiOn)
              KitNavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Ask',
                active: route.startsWith('/ask'),
                onTap: () => go('/ask'),
              ),
            // Always drawn with its `+` (4.83.0, ADR-117): the `+` is how a
            // first shelf gets made, so it cannot wait for a source to exist.
            KitRailShelvesRow(
              active: shelfRoute,
              count: shelfCount > 0 ? '$shelfCount' : null,
              onTap: () => go('/shelves'),
              onAdd: () => _newShelf(context, docs.complete.isNotEmpty),
            ),
            const KitRailGroupLabel('Practice'),
            KitNavItem(
              icon: Icons.mail_outlined,
              label: 'Letters',
              // Active on Letter settings too (kit §1.2).
              active: route == '/letters' || route.startsWith('/letters/'),
              onTap: () => go('/letters'),
            ),
            KitNavItem(
              icon: KitCardsGlyph.icon,
              label: 'Study',
              active: route.startsWith('/study'),
              onTap: () => go('/study'),
            ),
          ],
          footer: _ReaderCard(
            route: route,
            activity: activity,
            go: go,
          ),
        );
      },
    );
  }
}

/// Whether Ask is drawn — in the rail and in the tab bar's last slot.
///
/// This client reads no generative-AI setting yet: the switch (5.29.0,
/// ADR-186) is F-133's, folded into F-144. Until it lands Ask stays where it
/// has always been here, which is web's behaviour with AI on; the tab bar and
/// the rail both ask THIS function, so the day it reads the setting both move.
bool shellAiOn(BuildContext context) => true;

/// §1.2's **Reader's card** in the rail's pinned bottom region: the account
/// (opens Settings) over its perforated Activity stub — the newest event and
/// the unread count from the ONE activity subscription the rail opened.
///
/// The count is EVENTS newer than the client-local last-seen mark the feed
/// writes while it is open, zero while the feed is the route (the reader is
/// looking at it), the dash while the feed has not answered or refused —
/// never a zero it did not measure (ADR-109).
class _ReaderCard extends StatelessWidget {
  final String route;
  final ActivityNotifier activity;
  final void Function(String) go;

  const _ReaderCard(
      {required this.route, required this.activity, required this.go});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthNotifier>().user;
    final display = user?.displayName?.trim() ?? '';
    final email = user?.email ?? '';
    final name = display.isNotEmpty ? display : email;
    final onActivity = route == '/activity';
    final failed = activity.error != null;
    final latest = activity.latestEvent;
    return ValueListenableBuilder<int>(
      valueListenable: LocalFlags.activityLastSeen,
      builder: (context, lastSeen, _) => KitReaderCard(
        initials: _initialsOf(name),
        name: name,
        email: email,
        settingsLit: route.startsWith('/settings'),
        activityLit: onActivity,
        onSettings: () => go('/settings'),
        onActivity: () => go('/activity'),
        stub: KitActivityStub(
          answered: activity.answered,
          failed: failed,
          unread: failed || !activity.answered
              ? null
              : (onActivity ? 0 : activity.unreadSince(lastSeen)),
          latestTitle: latest?.title,
          latestAt: latest?.createdAt,
        ),
      ),
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
