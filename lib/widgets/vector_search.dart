import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/search_notifier.dart';
import '../theme/app_colors.dart';

class VectorSearch extends StatefulWidget {
  final String placeholder;

  const VectorSearch({
    super.key,
    this.placeholder = 'Search your knowledge base...',
  });

  @override
  State<VectorSearch> createState() => _VectorSearchState();
}

class _VectorSearchState extends State<VectorSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      context.read<SearchNotifier>().clear();
    } else {
      context.read<SearchNotifier>().search(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<SearchNotifier>(
      builder: (context, search, _) {
        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            border: Border.all(
              color: search.isLoading
                  ? primary
                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              search.isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: primary),
                    )
                  : Icon(
                      Icons.search,
                      size: 18,
                      color: isDark
                          ? AppColors.mutedForegroundDark
                          : AppColors.mutedForeground,
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: widget.placeholder,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.mutedForegroundDark
                          : AppColors.mutedForeground,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              if (search.hasResults || _controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: primary),
                  onPressed: () {
                    _controller.clear();
                    context.read<SearchNotifier>().clear();
                  },
                  tooltip: 'Clear search',
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  constraints: const BoxConstraints(),
                )
              else
                IconButton(
                  icon: Icon(Icons.auto_awesome, size: 16, color: primary),
                  onPressed: _search,
                  tooltip: 'Vector search',
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        );
      },
    );
  }
}
