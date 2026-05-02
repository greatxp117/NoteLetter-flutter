import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/activity_item.dart';
import '../models/search_result.dart';
import '../state/activity_notifier.dart';
import '../state/search_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/file_uploader.dart';
import '../widgets/vector_search.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ActivityNotifier>().load();
    });
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _dayName {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return days[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer2<ActivityNotifier, SearchNotifier>(
      builder: (context, activity, search, _) {
        return RefreshIndicator(
          onRefresh: () async {
            search.clear();
            await activity.refresh();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero section
                Stack(
                  children: [
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -20,
                      left: 60,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "$_greeting! Here's your digest",
                                style: GoogleFonts.libreBaskerville(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _dayName,
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: primary),
                                ),
                              ),
                            ],
                          ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1),
                          const SizedBox(height: 8),
                          Text(
                            activity.items.isEmpty && !activity.isLoading
                                ? 'Upload your first documents to get started.'
                                : '${activity.documents.length} documents in your knowledge base.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isDark
                                  ? AppColors.mutedForegroundDark
                                  : AppColors.mutedForeground,
                            ),
                          ).animate().fadeIn(delay: 100.ms, duration: 500.ms),
                        ],
                      ),
                    ),
                  ],
                ),
                // Search + Upload row
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 640) {
                        return Row(
                          children: [
                            Expanded(child: VectorSearch()),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () => _showUploadDialog(context),
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Upload Document'),
                              style: FilledButton.styleFrom(
                                backgroundColor: primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          VectorSearch(),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _showUploadDialog(context),
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Upload Document'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: primary),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
                // Content area: search results OR activity feed
                if (search.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (search.error != null)
                  _ErrorBanner(
                    message: search.error!,
                    onDismiss: search.clear,
                  )
                else if (search.hasResults)
                  _SearchResultsSection(results: search.results)
                else ...[
                  // Section heading
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Today's Highlights",
                          style: GoogleFonts.libreBaskerville(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Activity grid or states
                  if (activity.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (activity.error != null)
                    _ErrorBanner(
                      message: activity.error!,
                      onDismiss: () => context
                          .read<ActivityNotifier>()
                          .load(),
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
                                .take(6)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              return _ActivityCard(item: entry.value)
                                  .animate()
                                  .fadeIn(
                                    delay: Duration(
                                        milliseconds: 300 + entry.key * 80),
                                    duration: 500.ms,
                                  )
                                  .slideY(begin: 0.15, curve: Curves.easeOut);
                            }).toList(),
                          );
                        },
                      ),
                    ),
                ],
                // Deep dive CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ready for a deeper dive?',
                                  style: GoogleFonts.libreBaskerville(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Chat with your AI assistant to explore topics across all your sources.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.mutedForegroundDark
                                        : AppColors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: () => context.go('/chat'),
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 16),
                            label: const Text('Start Chat'),
                            style:
                                FilledButton.styleFrom(backgroundColor: primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
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
        content: SizedBox(
          width: 480,
          child: Consumer<ActivityNotifier>(
            builder: (_, activity, __) => const FileUploader(),
          ),
        ),
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

// ── Search results ────────────────────────────────────────────────────────────

class _SearchResultsSection extends StatelessWidget {
  final List<SearchResult> results;

  const _SearchResultsSection({required this.results});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${results.length} result${results.length == 1 ? '' : 's'}',
                style: GoogleFonts.libreBaskerville(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.read<SearchNotifier>().clear(),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...results.map((r) => _SearchResultCard(result: r, primary: primary)),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final Color primary;

  const _SearchResultCard({required this.result, required this.primary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final excerpt = result.chunk.text.length > 300
        ? '${result.chunk.text.substring(0, 300)}…'
        : result.chunk.text;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
        borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.document.type.toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: primary, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.document.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            excerpt,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.mutedForegroundDark
                  : AppColors.mutedForeground,
              height: 1.5,
            ),
          ),
          if (result.chunk.topics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: result.chunk.topics.take(3).map((t) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(t, style: theme.textTheme.labelSmall),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Activity card ─────────────────────────────────────────────────────────────

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
        statusColor = Colors.green;
        break;
      case 'error':
        statusColor = Colors.red;
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
        borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(4),
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
              if (item.readTime.isNotEmpty) ...[
                Text(
                  ' · ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
                Text(
                  item.readTime,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

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
              'Your knowledge base is empty',
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

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
            TextButton(
              onPressed: onDismiss,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
