import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/theme_notifier.dart';
import '../theme/app_colors.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  const _NavItem(this.icon, this.label, this.route);
}

const _navItems = [
  _NavItem(Icons.dashboard_outlined, 'Daily Digest', '/'),
  _NavItem(Icons.menu_book_outlined, 'Knowledge Base', '/library'),
  _NavItem(Icons.chat_bubble_outline, 'Chat', '/chat'),
  _NavItem(Icons.auto_awesome_outlined, 'Welcome', '/landing'),
  _NavItem(Icons.palette_outlined, 'Branding', '/branding'),
  _NavItem(Icons.settings_outlined, 'Settings', '/settings'),
];

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.sidebarDark : AppColors.sidebarLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final currentRoute = GoRouterState.of(context).uri.path;

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: border)),
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
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          const SizedBox(height: 8),
          // Nav items
          ...(_navItems.map((item) {
            final isActive = currentRoute == item.route;
            return _SidebarNavItem(item: item, isActive: isActive);
          })),
          const Spacer(),
          Divider(height: 1, color: border),
          // Storage
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2.1 GB / 6 GB used',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: 0.35,
                  backgroundColor: isDark ? AppColors.borderDark : AppColors.borderLight,
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
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
                icon: Icon(
                  notifier.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                ),
                tooltip: notifier.isDark ? 'Light mode' : 'Dark mode',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    Color bgColor = Colors.transparent;
    if (widget.isActive) {
      bgColor = primary.withValues(alpha: 0.1);
    } else if (_hovered) {
      bgColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(widget.item.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                size: 18,
                color: widget.isActive
                    ? primary
                    : (isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground),
              ),
              const SizedBox(width: 10),
              Text(
                widget.item.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.isActive ? primary : theme.colorScheme.onSurface,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
