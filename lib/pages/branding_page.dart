import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class BrandingPage extends StatelessWidget {
  const BrandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.edit_note, color: primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NoteLetter Design System',
                        style: GoogleFonts.libreBaskerville(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Visual language and design tokens that define the NoteLetter experience.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Core Principles
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Core Principles',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxis = constraints.maxWidth >= 1024 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: crossAxis,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: constraints.maxWidth >= 1024 ? 2.0 : 3.0,
                      children: const [
                        _PrincipleCard(
                          icon: Icons.spa_outlined,
                          color: Color(0xFF10B981),
                          title: 'Clarity',
                          description:
                              'Every element serves a purpose. Remove noise, amplify signal.',
                        ),
                        _PrincipleCard(
                          icon: Icons.auto_awesome_outlined,
                          color: Color(0xFF8B5CF6),
                          title: 'Warmth',
                          description:
                              'Approachable yet authoritative. Knowledge should feel inviting.',
                        ),
                        _PrincipleCard(
                          icon: Icons.speed_outlined,
                          color: Color(0xFFF59E0B),
                          title: 'Efficiency',
                          description:
                              'Respect the user\'s time. Every interaction should feel effortless.',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Typography
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Typography',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 768;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _TypographyCard(isSerif: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _TypographyCard(isSerif: false)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _TypographyCard(isSerif: true),
                        const SizedBox(height: 16),
                        _TypographyCard(isSerif: false),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Color Palette
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Color Palette',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxis = constraints.maxWidth >= 1024
                        ? 6
                        : (constraints.maxWidth >= 640 ? 3 : 2);
                    return GridView.count(
                      crossAxisCount: crossAxis,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.0,
                      children: [
                        _ColorSwatch(color: AppColors.primary, label: 'Primary', hex: '#D97706'),
                        _ColorSwatch(color: AppColors.primaryDark, label: 'Primary Dark', hex: '#E08B2A'),
                        _ColorSwatch(color: AppColors.backgroundLight, label: 'BG Light', hex: '#FDFC F9'),
                        _ColorSwatch(color: AppColors.backgroundDark, label: 'BG Dark', hex: '#151A23'),
                        _ColorSwatch(color: AppColors.foregroundLight, label: 'FG Light', hex: '#0F1826'),
                        _ColorSwatch(color: AppColors.foregroundDark, label: 'FG Dark', hex: '#E8E2D9'),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Design Language
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Design Language',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 768;
                    final children = [
                      _DesignLanguageCard(
                        title: 'Spacing & Layout',
                        points: const [
                          'Base unit: 4px',
                          'Standard padding: 16–32px',
                          'Card border radius: 8px',
                          'Sidebar width: 256px',
                        ],
                      ),
                      _DesignLanguageCard(
                        title: 'Motion & Animation',
                        points: const [
                          'Micro-interactions: 150–200ms',
                          'Page transitions: 300ms',
                          'Easing: easeOut for entries',
                          'Stagger: 80ms between items',
                        ],
                      ),
                    ];
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children
                            .expand((w) => [Expanded(child: w), const SizedBox(width: 16)])
                            .take(children.length * 2 - 1)
                            .toList(),
                      );
                    }
                    return Column(
                      children: children
                          .expand((w) => [w, const SizedBox(height: 16)])
                          .take(children.length * 2 - 1)
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrincipleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _PrincipleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.libreBaskerville(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      )),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypographyCard extends StatelessWidget {
  final bool isSerif;

  const _TypographyCard({required this.isSerif});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final name = isSerif ? 'Libre Baskerville' : 'Inter';
    final role = isSerif ? 'Headings & Display' : 'Body & UI';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: (isSerif
                  ? GoogleFonts.libreBaskerville(
                      fontSize: 22, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)
                  : GoogleFonts.inter(
                      fontSize: 22, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
            ),
            const SizedBox(height: 4),
            Text(
              role,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            ...[
              ('Regular 400', FontWeight.w400, FontStyle.normal),
              ('Italic 400', FontWeight.w400, FontStyle.italic),
              ('Bold 700', FontWeight.w700, FontStyle.normal),
            ].map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    s.$1,
                    style: isSerif
                        ? GoogleFonts.libreBaskerville(
                            fontSize: 14,
                            fontWeight: s.$2,
                            fontStyle: s.$3,
                            color: theme.colorScheme.onSurface)
                        : GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: s.$2,
                            fontStyle: s.$3,
                            color: theme.colorScheme.onSurface),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final String hex;

  const _ColorSwatch({required this.color, required this.label, required this.hex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    hex,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignLanguageCard extends StatelessWidget {
  final String title;
  final List<String> points;

  const _DesignLanguageCard({required this.title, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.libreBaskerville(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                )),
            const SizedBox(height: 12),
            ...points.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: 7, right: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(p,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                            )),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
