import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../state/search_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';
import '../widgets/vector_search.dart';

/// Search (`spec/screens/search.md`).
///
/// A **move, not a rewrite**: this is the search field and results block that
/// were embedded in the old dashboard, given the route the chrome rail has
/// always pointed at. `/search` was in the rail and in no route table, so the
/// rail's Search item landed on the not-found page — nothing failed, the screen
/// simply was not there.
///
/// Still composed inline; it is recomposed against the kit with the other
/// screens (ADR-041).
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<SearchNotifier>(
      builder: (context, search, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search',
                      style: AppTheme.serif(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search your library by meaning.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.mutedForegroundDark
                            : AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const VectorSearch(),
                  ],
                ),
              ),
              if (search.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (search.error != null)
                SearchErrorBanner(
                  message: search.error!,
                  onDismiss: search.clear,
                )
              else if (search.hasResults)
                _SearchResultsSection(results: search.results),
            ],
          ),
        );
      },
    );
  }
}

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
                style: AppTheme.serif(
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
          if (result.document.themes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: result.document.themes.take(3).map((t) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                    borderRadius: AppRadius.controlR(20),
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

/// The dismissible failure banner shared by Search and Activity.
class SearchErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const SearchErrorBanner(
      {super.key, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.critical.withValues(alpha: 0.08),
          border:
              Border.all(color: AppColors.critical.withValues(alpha: 0.3)),
          borderRadius: AppRadius.mdR,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.critical, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: AppColors.critical, fontSize: 13)),
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
