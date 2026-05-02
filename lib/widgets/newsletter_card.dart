import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/newsletter_item.dart';
import '../theme/app_colors.dart';

class NewsletterCard extends StatefulWidget {
  final NewsletterItem item;

  const NewsletterCard({super.key, required this.item});

  @override
  State<NewsletterCard> createState() => _NewsletterCardState();
}

class _NewsletterCardState extends State<NewsletterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final border = _hovered
        ? primary.withValues(alpha: 0.4)
        : (isDark ? AppColors.borderDark : AppColors.borderLight);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.item.source,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.auto_awesome, size: 14, color: primary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.item.date,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.item.title,
                style: GoogleFonts.libreBaskerville(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                widget.item.body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ...widget.item.tags.take(3).map((tag) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.secondaryDark : AppColors.secondaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                            ),
                          ),
                        ),
                      )),
                  const Spacer(),
                  Text(
                    widget.item.readTime,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
