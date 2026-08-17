import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity_item.dart';
import '../state/activity_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';
import '../widgets/file_uploader.dart';
import 'search_page.dart' show SearchErrorBanner;

/// Activity (`spec/screens/activity.md`).
///
/// A **move, not a rewrite**: the recent-documents feed that was the old
/// dashboard's "Today's Highlights", on the route the web reference gives it
/// and pinned in the rail as the reference pins it. Recomposed against the kit
/// — the timeline pattern, §4.2 — with the other screens (ADR-041).
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ActivityNotifier>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<ActivityNotifier>(
      builder: (context, activity, _) {
        return RefreshIndicator(
          onRefresh: () => activity.refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity',
                        style: AppTheme.serif(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activity.documents.isEmpty && !activity.isLoading
                            ? 'Nothing has come through yet.'
                            : '${activity.documents.length} documents in your library.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppColors.mutedForegroundDark
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activity.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (activity.error != null)
                  SearchErrorBanner(
                    message: activity.error!,
                    onDismiss: () => context.read<ActivityNotifier>().load(),
                  )
                else if (activity.documents.isEmpty)
                  _EmptyState(onUpload: () => _showUploadDialog(context))
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth >= 1024
                            ? 3
                            : (constraints.maxWidth >= 640 ? 2 : 1);
                        return GridView.count(
                          crossAxisCount: cols,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio:
                              constraints.maxWidth >= 1024 ? 1.0 : 1.2,
                          children: activity.documents
                              .take(12)
                              .map((item) => _ActivityCard(item: item))
                              .toList(),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Documents'),
        content: const SizedBox(width: 480, child: FileUploader()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<ActivityNotifier>().refresh();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ActivityItem item;

  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    Color statusColor;
    switch (item.status) {
      case 'complete':
        statusColor = AppColors.positive;
        break;
      case 'error':
        statusColor = AppColors.critical;
        break;
      case 'processing':
      case 'queued':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = isDark
            ? AppColors.mutedForegroundDark
            : AppColors.mutedForeground;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.controlR(20),
                ),
                child: Text(
                  item.typeLabel,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: primary, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                item.formattedDate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.mutedForegroundDark
                      : AppColors.mutedForeground,
                ),
              ),
              if (item.readTime.isNotEmpty)
                Text(
                  ' · ${item.readTime}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onUpload;

  const _EmptyState({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.cloud_upload_outlined,
                size: 48, color: primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Nothing has been indexed yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload PDFs, paste URLs, or connect cloud storage to get started.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.mutedForegroundDark
                    : AppColors.mutedForeground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload Document'),
              style: FilledButton.styleFrom(backgroundColor: primary),
            ),
          ],
        ),
      ),
    );
  }
}
