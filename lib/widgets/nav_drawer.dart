import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/theme_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

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

class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Plum chrome, identical in light & dark (see Sidebar / web app-kit.css).
    final currentRoute = GoRouterState.of(context).uri.path;

    return Drawer(
      backgroundColor: AppColors.chrome,
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
                    style: GoogleFonts.sourceSerif4(
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
            ...(_navItems.map((item) {
              final isActive = currentRoute == item.route;
              final fg = isActive ? AppColors.chromeForeground : AppColors.chromeMuted;
              return ListTile(
                leading: Icon(item.icon, color: fg),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    color: fg,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                selected: isActive,
                selectedTileColor: AppColors.chromeActive,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.controlR(40)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(item.route);
                },
              );
            })),
            const Spacer(),
            const Divider(height: 1, color: AppColors.chromeBorder),
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
            Consumer<ThemeNotifier>(
              builder: (ctx, notifier, _) => ListTile(
                leading: Icon(notifier.modeIcon, color: AppColors.chromeMuted),
                title: Text(
                  notifier.modeLabel,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    color: AppColors.chromeForeground,
                  ),
                ),
                onTap: notifier.toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
