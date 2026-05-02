import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '404',
              style: GoogleFonts.libreBaskerville(
                fontSize: 80,
                fontWeight: FontWeight.w700,
                color: primary.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Page not found',
              style: GoogleFonts.libreBaskerville(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The page you\'re looking for doesn\'t exist.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              style: FilledButton.styleFrom(backgroundColor: primary),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
