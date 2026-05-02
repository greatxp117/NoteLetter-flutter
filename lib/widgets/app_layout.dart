import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'sidebar.dart';
import 'nav_drawer.dart';

class AppLayout extends StatelessWidget {
  final Widget child;

  const AppLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        if (constraints.maxWidth >= 768) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: Row(
              children: [
                const Sidebar(),
                Expanded(child: child),
              ],
            ),
          );
        } else {
          final isDark = theme.brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: isDark ? AppColors.sidebarDark : AppColors.sidebarLight,
              elevation: 0,
              centerTitle: true,
              title: Text(
                'NoteLetter',
                style: GoogleFonts.libreBaskerville(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
            ),
            drawer: const NavDrawer(),
            body: child,
          );
        }
      },
    );
  }
}
