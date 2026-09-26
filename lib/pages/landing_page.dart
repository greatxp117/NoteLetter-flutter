import 'package:flutter/material.dart';
import '../site/auth_modal.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nav bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flexible + ellipsis: the brand is what gives way when the
                    // bar does not fit, never the actions. At phone width the
                    // fixed layout overflowed by 3.3pt — small enough to look
                    // like nothing, and still a clipped control.
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: AppRadius.controlR(36),
                            ),
                            child: const Icon(Icons.edit_note, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'NoteLetter',
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.serif(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _showAuthDialog(context, isSignUp: false),
                          child: Text(
                            'Log In',
                            // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                            style: TextStyle(color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _showAuthDialog(context, isSignUp: true),
                          style: FilledButton.styleFrom(backgroundColor: primary),
                          child: const Text('Get Started'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Hero section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: AppRadius.pillR(28),
                        border: Border.all(color: primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'AI-Powered Knowledge Management',
                        // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your Knowledge Base,\nAutomatically Curated',
                      textAlign: TextAlign.center,
                      style: AppTheme.serif(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Upload documents, connect cloud storage, and let AI transform your research into personalized newsletters delivered straight to your inbox.',
                      textAlign: TextAlign.center,
                      // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _showAuthDialog(context, isSignUp: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                          // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                          label: const Text('Start for Free', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () => _showAuthDialog(context, isSignUp: false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          icon: const Icon(Icons.login, size: 18),
                          // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                          label: const Text('Log In', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Features section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Column(
                  children: [
                    Text(
                      'Everything you need to manage your knowledge',
                      textAlign: TextAlign.center,
                      style: AppTheme.serif(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _FeatureCard(
                          icon: Icons.upload_file_outlined,
                          title: 'Smart Upload',
                          description: 'Upload PDFs, Word docs, images, and YouTube videos. Our AI processes and indexes everything automatically.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.search_outlined,
                          title: 'Semantic Search',
                          description: 'Find exactly what you\'re looking for with AI-powered vector search across all your documents.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.mail_outline,
                          title: 'Auto Newsletters',
                          description: 'Receive curated digests of your knowledge base, personalized to your interests and schedule.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.cloud_outlined,
                          title: 'Cloud Sync',
                          description: 'Connect Google Drive, OneDrive, Dropbox, and Notion to automatically sync your documents.',
                          color: primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Text(
                  '© 2025 NoteLetter. All rights reserved.',
                  textAlign: TextAlign.center,
                  // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
                  style: TextStyle(
                    color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // F-44a: the Material dialog this page drew is gone; both doors open the
  // reference's modal, as LandingActual's nav does. F-44b replaces the page.
  void _showAuthDialog(BuildContext context, {required bool isSignUp}) {
    showAuthModal(context, isSignUp ? AuthMode.signup : AuthMode.signin);
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: AppRadius.nestR(AppRadius.control(44), 24),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: AppRadius.controlR(44),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTheme.serif(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            // kit-ok: F-44 — the pre-redesign landing, replaced whole, not restyled
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
