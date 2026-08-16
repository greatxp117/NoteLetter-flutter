import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../state/theme_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  const _NavItem(this.icon, this.label, this.route);
}

const _navItems = [
  _NavItem(Icons.dashboard_outlined, 'Daily Digest', '/'),
  _NavItem(Icons.menu_book_outlined, 'Knowledge Base', '/library'),
  _NavItem(Icons.label_outline, 'Tags', '/tags'),
  _NavItem(Icons.chat_bubble_outline, 'Chat', '/chat'),
  _NavItem(Icons.mail_outline, 'Letters', '/letters'),
  _NavItem(Icons.school_outlined, 'Study', '/study'),
  _NavItem(Icons.cloud_outlined, 'Sources', '/sources'),
  _NavItem(Icons.auto_awesome_outlined, 'Welcome', '/landing'),
  _NavItem(Icons.palette_outlined, 'Branding', '/branding'),
  _NavItem(Icons.settings_outlined, 'Settings', '/settings'),
];

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    // Plum chrome — identical in light & dark (web app-kit.css `.sb`):
    // background --chrome (plum-600), foreground --paper-50. Never keyed off
    // Theme.brightness; the chrome "stays warm either way".
    final currentRoute = GoRouterState.of(context).uri.path;

    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: AppColors.chrome,
        border: Border(right: BorderSide(color: AppColors.chromeBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.edit_note, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'NoteLetter',
                  style: AppTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.chromeForeground,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.chromeBorder),
          const SizedBox(height: 8),
          // Nav items
          ...(_navItems.map((item) {
            final isActive = currentRoute == item.route;
            return _SidebarNavItem(item: item, isActive: isActive);
          })),
          const Spacer(),
          const Divider(height: 1, color: AppColors.chromeBorder),
          // Storage
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2.1 GB / 6 GB used',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: AppColors.chromeSubtle,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: 0.35,
                  backgroundColor: AppColors.chromeBorder,
                  color: AppColors.primary,
                  borderRadius: AppRadius.pillR(4),
                ),
              ],
            ),
          ),
          // Theme toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Consumer<ThemeNotifier>(
              builder: (ctx, notifier, _) => IconButton(
                onPressed: notifier.toggle,
                icon: Icon(notifier.modeIcon, color: AppColors.chromeMuted),
                tooltip: '${notifier.modeLabel} — tap to change',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final _NavItem item;
  final bool isActive;

  const _SidebarNavItem({required this.item, required this.isActive});

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // On plum chrome the foreground is always paper-toned (web `.sb-item`):
    // idle rgba(255,255,255,.62); hover/active promote to paper-50 with a
    // white-alpha fill; the active item also carries a brick-400 left bar.
    Color bgColor = Colors.transparent;
    if (widget.isActive) {
      bgColor = AppColors.chromeActive;
    } else if (_hovered) {
      bgColor = AppColors.chromeHover;
    }
    final fg = (widget.isActive || _hovered)
        ? AppColors.chromeForeground
        : AppColors.chromeMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(widget.item.route),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: AppRadius.controlR(36),
              ),
              child: Row(
                children: [
                  Icon(widget.item.icon, size: 18, color: fg),
                  const SizedBox(width: 10),
                  Text(
                    widget.item.label,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      color: fg,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Active accent bar — brick-400, mirrors web `.sb-item.active::before`.
            if (widget.isActive)
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AppColors.chromeAccentBar,
                    borderRadius: AppRadius.pillR(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
