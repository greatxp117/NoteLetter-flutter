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

class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final currentRoute = GoRouterState.of(context).uri.path;

    return Drawer(
      backgroundColor: isDark ? AppColors.sidebarDark : AppColors.sidebarLight,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
            const SizedBox(height: 8),
            ...(_navItems.map((item) {
              final isActive = currentRoute == item.route;
              return ListTile(
                leading: Icon(
                  item.icon,
                  color: isActive
                      ? primary
                      : (isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground),
                ),
                title: Text(
                  item.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isActive ? primary : theme.colorScheme.onSurface,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                selected: isActive,
                selectedTileColor: primary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(item.route);
                },
              );
            })),
            const Spacer(),
            Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
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
            Consumer<ThemeNotifier>(
              builder: (ctx, notifier, _) => ListTile(
                leading: Icon(
                  notifier.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                ),
                title: Text(notifier.isDark ? 'Light Mode' : 'Dark Mode',
                    style: theme.textTheme.bodyMedium),
                onTap: notifier.toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
