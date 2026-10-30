import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_frame.dart';
import 'kit_d_parts.dart';
import 'kit_shell.dart';

// ── Direction D's app chrome (component-kit §1.2 compact rail, §30) ─────────
//
// At 1024 and under the page's tools move to an app header and a tab bar,
// which read the page's registration ([KitPageTools]); the rail opens as a
// drawer from the header's menu. The compact rail and the Reader's card are
// the rail at every width (Xavier, 2026-10-30). Web: `kit/d/PhoneChrome.jsx`,
// `shell/AppShell.jsx` (`SidebarContent`, `ReaderCard`).

/// §30 — the app header (54, plum chrome): the **menu** (opens the drawer,
/// carrying §1.2's attention dot while For your review's count is above zero,
/// and saying so in its name), the **Search pill** (opens quick search), then
/// the **page's settings** when the page registered any — raised while its
/// panel is open. No wordmark. It draws the status bar's inset itself.
class KitAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onMenu;
  final VoidCallback onSearch;
  final bool attention;

  const KitAppHeader({
    super.key,
    required this.onMenu,
    required this.onSearch,
    this.attention = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      color: t.chrome,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.chromeActive)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                KitAppBarButton(
                  icon: Icons.menu,
                  label: attention
                      ? 'Menu — something is waiting for your review'
                      : 'Menu',
                  onPressed: onMenu,
                ),
                if (attention)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('menu-attention-dot'),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Expanded(child: _SearchPill(onTap: onSearch)),
            ListenableBuilder(
              listenable: KitPageTools.instance,
              builder: (context, _) {
                final s = KitPageTools.instance.settings;
                if (s == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: KitSettingsButton(settings: s, chrome: true),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      key: const ValueKey('d-header-search'),
      onTap: onTap,
      label: 'Search your library…',
      builder: (context, hover, focus) {
        final fg = hover ? t.chromeFg : t.chromeSearch;
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hover ? t.chromeRaised : t.chromeBorder,
            borderRadius: BorderRadius.circular(999),
            border: focus ? Border.all(color: t.chromeFg, width: 2) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 17, color: fg),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Search your library…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One destination of [KitTabBar].
class KitTab {
  final String path;
  final IconData icon;
  final String label;
  const KitTab(this.path, this.icon, this.label);
}

/// §30 — the tab bar, fixed at the foot: **Home, Library, the page's action,
/// Letters, Ask.** The centre is the action the page registered (its glyph in
/// an accent pill, its short label) or, where the page names none, *Add* —
/// named *Add a source* — which opens Add a source; held while the action is
/// disabled. **While generative AI is off, or not yet read, Ask is absent and
/// Shelves takes its slot** (5.29.0, ADR-186, INV-34). The active tab is
/// `--accent-text`; Letters is active on Letter settings, Shelves on the map
/// and on every shelf. While a D overlay is open its scrim covers the bar.
class KitTabBar extends StatelessWidget {
  final String route;
  final ValueChanged<String> onGo;
  final VoidCallback onAdd;
  final bool aiOn;

  const KitTabBar({
    super.key,
    required this.route,
    required this.onGo,
    required this.onAdd,
    this.aiOn = false,
  });

  static const home = KitTab('/', Icons.home_outlined, 'Home');
  static const library = KitTab(
    '/sources',
    Icons.menu_book_outlined,
    'Library',
  );
  static const letters = KitTab('/letters', Icons.mail_outlined, 'Letters');
  static const ask = KitTab('/ask', Icons.chat_bubble_outline, 'Ask');
  static final shelves = KitTab('/shelves', KitStackGlyph.icon, 'Shelves');

  bool _on(String path) {
    if (path == '/') return route == '/';
    return route == path || route.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final tabs = [home, library, null, letters, aiOn ? ask : shelves];
    final bar = Container(
      padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + bottom),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: AppShadows.ink(0.18),
            offset: const Offset(0, -2),
            blurRadius: 16,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: tab == null
                  ? const _CentreAction()
                  : _TabItem(
                      tab: tab,
                      active: _on(tab.path),
                      onTap: () => onGo(tab.path),
                    ),
            ),
        ],
      ),
    );
    return KitDShellAdd(
      onAdd: onAdd,
      child: Stack(
        children: [
          bar,
          const Positioned.fill(child: _TabBarScrim()),
        ],
      ),
    );
  }
}

/// The open D overlay's scrim over the tab bar: it fades with the page's
/// (`--dur-slow` `--ease-out`), in and out, and a tap on it dismisses.
class _TabBarScrim extends StatefulWidget {
  const _TabBarScrim();

  @override
  State<_TabBarScrim> createState() => _TabBarScrimState();
}

class _TabBarScrimState extends State<_TabBarScrim> {
  Color? _last;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<(VoidCallback, Color)?>(
        valueListenable: KitPageTools.instance.scrim,
        builder: (context, s, _) {
          if (s != null) _last = s.$2;
          final last = _last;
          if (last == null) return const SizedBox.shrink();
          return IgnorePointer(
            ignoring: s == null,
            child: AnimatedOpacity(
              opacity: s == null ? 0 : 1,
              duration: KitD.dur(context, AppMotion.durSlow),
              curve: AppMotion.easeOut,
              child: GestureDetector(
                key: const ValueKey('d-tabbar-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: s?.$1,
                child: ColoredBox(color: last),
              ),
            ),
          );
        },
      );
}

/// Hands the tab bar's default action to its centre.
class KitDShellAdd extends InheritedWidget {
  final VoidCallback onAdd;
  const KitDShellAdd({super.key, required this.onAdd, required super.child});

  @override
  bool updateShouldNotify(KitDShellAdd old) => old.onAdd != onAdd;
}

class _TabItem extends StatelessWidget {
  final KitTab tab;
  final bool active;
  final VoidCallback onTap;
  const _TabItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      key: ValueKey('d-tab-${tab.label}'),
      onTap: onTap,
      label: tab.label,
      selected: active,
      builder: (context, hover, focus) {
        final fg = active ? t.accentText : (hover ? t.fgMuted : t.fgSubtle);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smR,
            border: focus ? Border.all(color: t.accent, width: 2) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: Center(child: KitGlyph(tab.icon, size: 21, color: fg)),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.01 * 10,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CentreAction extends StatelessWidget {
  const _CentreAction();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final onAdd = context
        .dependOnInheritedWidgetOfExactType<KitDShellAdd>()
        ?.onAdd;
    return ListenableBuilder(
      listenable: KitPageTools.instance,
      builder: (context, _) {
        final a = KitPageTools.instance.action;
        final held = a?.disabled ?? false;
        return Opacity(
          opacity: held ? AppSpacing.heldOpacity : 1,
          child: KitDTap(
            key: const ValueKey('d-tab-action'),
            label: a?.label ?? 'Add a source',
            onTap: held
                ? null
                : () {
                    // The page's LATEST handler, read at the press.
                    final now = KitPageTools.instance.action;
                    if (now != null) {
                      now.onPressed();
                    } else {
                      onAdd?.call();
                    }
                  },
            builder: (context, hover, focus) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: AppRadius.smR,
                border: focus ? Border.all(color: t.accent, width: 2) : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 30,
                    margin: const EdgeInsets.only(bottom: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hover ? t.accentHover : t.accent,
                      borderRadius: AppRadius.controlR(32),
                    ),
                    child: KitGlyph(
                      a?.icon ?? Icons.add,
                      size: 20,
                      color: t.accentFg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a == null ? 'Add' : a.short,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.01 * 10,
                      color: t.fgSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// §1.2's compact rail Shelves row: the row (the shelf glyph, *Shelves*, the
/// shelf count while there are any) and, beside it, the `+` — *New shelf*,
/// drawn whatever the library holds, because it is how a first shelf gets
/// made (ADR-117).
class KitRailShelvesRow extends StatelessWidget {
  final bool active;
  final String? count;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const KitRailShelvesRow({
    super.key,
    required this.active,
    required this.onTap,
    required this.onAdd,
    this.count,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: KitNavItem(
          icon: KitStackGlyph.icon,
          label: 'Shelves',
          active: active,
          count: count,
          onTap: onTap,
        ),
      ),
      const SizedBox(width: 2),
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: KitRailAddButton(onTap: onAdd, label: 'New shelf'),
      ),
    ],
  );
}

/// What the Reader's card's Activity stub says, from ONE activity
/// subscription: [unread] (null while the feed has not answered and when it
/// was refused — drawn as the dash, never 0), whether the feed [answered]
/// and whether it [failed], and the newest event.
class KitActivityStub {
  final int? unread;
  final bool answered;
  final bool failed;
  final String? latestTitle;
  final int? latestAt;

  const KitActivityStub({
    this.unread,
    this.answered = false,
    this.failed = false,
    this.latestTitle,
    this.latestAt,
  });
}

/// The newest event's age on the stub (web `agoShort`): `now`, `{m}m`,
/// `{h}h`, `{d}d`.
String kitAgoShort(int? ms, [DateTime? now]) {
  if (ms == null || ms == 0) return '';
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final m = ((at - ms) / 60000).round().clamp(0, 1 << 31);
  if (m < 1) return 'now';
  if (m < 60) return '${m}m';
  final h = (m / 60).round();
  return h < 24 ? '${h}h' : '${(h / 24).round()}d';
}

/// §1.2 — **the Reader's card** (direction D, Xavier 2026-10-30): the account,
/// Settings and Activity as one object, a borrower's card, last in the rail.
/// Its main part opens Settings (named *Settings*): the *Reader's card*
/// eyebrow, the initials avatar, the name over the email, a gear at its
/// corner. A perforation. Its stub opens Activity: the glyph, *Activity* with
/// the newest event's age, that event's title, and the unread count at the
/// trailing edge — the attention pill above zero, `0` measured, the dash
/// refused or unread (ADR-109). *Nothing new* only for a feed that ANSWERED
/// empty. The main part is lit on Settings, the stub on Activity.
class KitReaderCard extends StatelessWidget {
  final String initials;
  final String name;
  final String email;
  final VoidCallback onSettings;
  final VoidCallback onActivity;
  final bool settingsLit;
  final bool activityLit;
  final KitActivityStub stub;

  const KitReaderCard({
    super.key,
    required this.initials,
    required this.name,
    required this.email,
    required this.onSettings,
    required this.onActivity,
    required this.stub,
    this.settingsLit = false,
    this.activityLit = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      key: const ValueKey('reader-card'),
      decoration: BoxDecoration(
        color: t.chromeCard,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.chromeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardMain(card: this),
          const _Perforation(),
          _CardStub(card: this),
        ],
      ),
    );
  }
}

class _CardMain extends StatelessWidget {
  final KitReaderCard card;
  const _CardMain({required this.card});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      key: const ValueKey('reader-card-settings'),
      onTap: card.onSettings,
      label: 'Settings',
      selected: card.settingsLit,
      builder: (context, hover, focus) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: hover || card.settingsLit ? t.chromeHover : null,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.md),
          ),
          border: focus ? Border.all(color: t.chromeFg, width: 2) : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: Text(
                    'READER’S CARD',
                    style: AppTheme.mono(
                      fontSize: 9,
                      letterSpacing: 0.14 * 9,
                      color: t.chromeLabel,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.chromeAvatar,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        card.initials,
                        style: AppTheme.serif(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.02 * 13,
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
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.serif(
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: t.chromeFg,
                              opsz: 18,
                            ),
                          ),
                          if (card.email.isNotEmpty)
                            Text(
                              card.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.mono(
                                fontSize: 10,
                                letterSpacing: 0.04 * 10,
                                color: t.chromeLabel,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: -2,
              right: -4,
              child: AnimatedContainer(
                duration: KitD.dur(context, AppMotion.durFast),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: card.settingsLit
                      ? t.chromeAccentBar
                      : (hover ? t.chromeGearHover : t.chromeBorder),
                  shape: BoxShape.circle,
                  border: card.settingsLit
                      ? null
                      : Border.all(color: t.chromeRaised),
                ),
                child: AnimatedRotation(
                  turns: hover ? 60 / 360 : 0,
                  duration: KitD.dur(context, AppMotion.durSlow),
                  curve: AppMotion.easeQuill,
                  child: Icon(
                    Icons.settings_outlined,
                    size: 16,
                    color: t.chromeFg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's perforation: a 1.5px dashed white .16 line inset 10, a 12px
/// notch in the chrome at each end.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SizedBox(
      height: 2,
      child: CustomPaint(
        painter: _PerfPainter(
          dash: t.chromeEdge,
          notch: t.chrome,
          ring: t.chromeBorder,
        ),
      ),
    );
  }
}

class _PerfPainter extends CustomPainter {
  final Color dash;
  final Color notch;
  final Color ring;
  _PerfPainter({required this.dash, required this.notch, required this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final p = Paint()
      ..color = dash
      ..strokeWidth = 1.5;
    const on = 4.0, off = 3.0;
    for (var x = 10.0; x < size.width - 10; x += on + off) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + on).clamp(0, size.width - 10), y),
        p,
      );
    }
    // The notches bite into each edge: a half disc in the chrome's colour.
    final fill = Paint()..color = notch;
    final edge = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final cx in [-1.0, size.width + 1]) {
      final r = Rect.fromCircle(center: Offset(cx, y), radius: 6);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(-1, y - 7, size.width + 2, 14));
      canvas.clipRect(
        cx < 0
            ? Rect.fromLTWH(-1, y - 7, 7, 14)
            : Rect.fromLTWH(size.width - 6, y - 7, 7, 14),
      );
      canvas.drawOval(r, fill);
      canvas.drawOval(r.deflate(0.5), edge);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PerfPainter old) =>
      old.dash != dash || old.notch != notch || old.ring != ring;
}

class _CardStub extends StatelessWidget {
  final KitReaderCard card;
  const _CardStub({required this.card});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = card.stub;
    final measured = s.unread != null && !s.failed;
    final n = s.unread ?? 0;
    final lit = measured && n > 0;
    final latestLine = s.failed || !s.answered
        ? null
        : (s.latestTitle ?? 'Nothing new');
    return KitDTap(
      key: const ValueKey('reader-card-activity'),
      onTap: card.onActivity,
      label:
          'Activity, '
          '${measured ? '$n unread' : 'unread could not be counted'}',
      selected: card.activityLit,
      builder: (context, hover, focus) {
        final fg = hover || card.activityLit ? t.chromeFg : t.chromeStub;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: hover || card.activityLit ? t.chromeHover : null,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppRadius.md),
            ),
            border: focus ? Border.all(color: t.chromeFg, width: 2) : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.timeline_outlined,
                size: 14,
                color: card.activityLit ? t.chromeUnread : fg,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            'Activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 12.5,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ),
                        if (s.answered && !s.failed && s.latestAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            kitAgoShort(s.latestAt),
                            style: AppTheme.mono(
                              fontSize: 10,
                              color: t.chromeLabel,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (latestLine != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        latestLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          fontSize: 12,
                          height: 1.3,
                          fontStyle: FontStyle.italic,
                          color: t.chromeLabel,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Container(
                key: const ValueKey('reader-card-count'),
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: lit ? t.accent : t.chromeBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  measured ? (n > 999 ? '999+' : '$n') : '—',
                  textAlign: TextAlign.center,
                  style:
                      AppTheme.mono(
                        fontSize: 11,
                        height: 18 / 11,
                        color: lit ? t.accentFg : t.chromeLabel,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
