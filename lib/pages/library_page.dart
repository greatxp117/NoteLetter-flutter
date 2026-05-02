import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/activity_item.dart';
import '../state/activity_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/file_uploader.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ActivityNotifier>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Consumer<ActivityNotifier>(
      builder: (context, activity, _) {
        final docs = activity.documents
            .where((d) =>
                d.title.toLowerCase().contains(_search.toLowerCase()))
            .toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Knowledge Base',
                      style: GoogleFonts.libreBaskerville(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your uploaded documents and data sources.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.mutedForegroundDark
                            : AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              // Upload card
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload Documents',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        FileUploader(
                          onUploadComplete: () {
                            activity.refresh();
                            AppToast.show(
                              context,
                              'Document queued for processing.',
                              type: ToastType.success,
                            );
                          },
                          onUploadError: (msg) =>
                              AppToast.show(context, msg, type: ToastType.error),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Search + actions row
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : AppColors.cardLight,
                          border: Border.all(
                              color: isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            Icon(Icons.search,
                                size: 16,
                                color: isDark
                                    ? AppColors.mutedForegroundDark
                                    : AppColors.mutedForeground),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                style: theme.textTheme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: 'Filter files...',
                                  hintStyle: theme.textTheme.bodySmall?.copyWith(
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
                                onChanged: (v) => setState(() => _search = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => activity.refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
              // File list
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                child: Card(
                  child: Column(
                    children: [
                      // Header row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text('Name',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.mutedForegroundDark
                                        : AppColors.mutedForeground,
                                  )),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Added',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.mutedForegroundDark
                                        : AppColors.mutedForeground,
                                  )),
                            ),
                            Expanded(
                              child: Text('Words',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.mutedForegroundDark
                                        : AppColors.mutedForeground,
                                  )),
                            ),
                            Expanded(
                              child: Text('Status',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.mutedForegroundDark
                                        : AppColors.mutedForeground,
                                  )),
                            ),
                            const SizedBox(width: 32),
                          ],
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                      if (activity.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (activity.error != null)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            activity.error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      else ...[
                        ...docs.map((d) => _DocumentRow(item: d)),
                        if (docs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                activity.documents.isEmpty
                                    ? 'No documents yet. Upload some files to get started.'
                                    : 'No files match your search.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? AppColors.mutedForegroundDark
                                      : AppColors.mutedForeground,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentRow extends StatefulWidget {
  final ActivityItem item;

  const _DocumentRow({required this.item});

  @override
  State<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends State<_DocumentRow> {
  bool _hovered = false;

  IconData get _icon {
    switch (widget.item.type) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'docx':
        return Icons.description_outlined;
      case 'youtube':
        return Icons.play_circle_outline;
      case 'url':
        return Icons.link;
      case 'image':
      case 'image_set':
        return Icons.image_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  Color get _iconColor {
    switch (widget.item.type) {
      case 'pdf':
        return Colors.red;
      case 'docx':
        return Colors.blue;
      case 'youtube':
        return Colors.red.shade700;
      case 'url':
        return Colors.teal;
      case 'image':
      case 'image_set':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;

    Color statusColor;
    String statusLabel;
    switch (item.status) {
      case 'complete':
        statusColor = Colors.green;
        statusLabel = 'Indexed';
        break;
      case 'error':
        statusColor = Colors.red;
        statusLabel = 'Error';
        break;
      case 'skipped':
        statusColor = Colors.grey;
        statusLabel = 'Skipped';
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = 'Processing';
    }

    final wordCount = item.wordCount;
    final wordLabel = wordCount != null && wordCount > 0
        ? wordCount >= 1000
            ? '${(wordCount / 1000).toStringAsFixed(1)}k'
            : '$wordCount'
        : '—';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered
            ? (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.02))
            : Colors.transparent,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(_icon, size: 18, color: _iconColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.title,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.formattedDate,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  wordLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: statusColor),
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz,
                        size: 16,
                        color: isDark
                            ? AppColors.mutedForegroundDark
                            : AppColors.mutedForeground),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'open', child: Text('Open Source')),
                    ],
                    onSelected: (action) {
                      // Future: open document detail
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
