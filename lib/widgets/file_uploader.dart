import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../state/upload_notifier.dart';
import '../models/upload_file.dart';
import '../theme/app_colors.dart';

class FileUploader extends StatefulWidget {
  final VoidCallback? onUploadComplete;
  final void Function(String message)? onUploadError;

  const FileUploader({
    super.key,
    this.onUploadComplete,
    this.onUploadError,
  });

  @override
  State<FileUploader> createState() => _FileUploaderState();
}

class _FileUploaderState extends State<FileUploader> {
  bool _isDragOver = false;
  bool _showUrlInput = false;
  final _urlCtrl = TextEditingController();
  bool _urlSubmitting = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles(UploadNotifier notifier) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
      notifier.addFile(file.name, file.size, bytes, mimeType).then((_) {
        if (!mounted) return;
        final match = notifier.files.lastWhere(
          (f) => f.name == file.name,
          orElse: () => UploadFile(id: '', name: '', size: 0),
        );
        if (match.status == UploadStatus.completed) {
          widget.onUploadComplete?.call();
        } else if (match.status == UploadStatus.error) {
          widget.onUploadError
              ?.call(match.errorMessage ?? 'Upload failed.');
        }
      });
    }
  }

  Future<void> _submitUrl(UploadNotifier notifier) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() => _urlSubmitting = true);
    try {
      await notifier.addUrl(url);
      if (!mounted) return;
      _urlCtrl.clear();
      setState(() => _showUrlInput = false);
      widget.onUploadComplete?.call();
    } catch (e) {
      if (!mounted) return;
      final match = notifier.files.lastWhere(
        (f) => f.name.contains(url.length > 30 ? url.substring(0, 30) : url),
        orElse: () => UploadFile(id: '', name: '', size: 0),
      );
      widget.onUploadError
          ?.call(match.errorMessage ?? 'Failed to ingest URL.');
    } finally {
      if (mounted) setState(() => _urlSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<UploadNotifier>(
      builder: (context, notifier, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DragTarget<Object>(
              onWillAcceptWithDetails: (_) {
                setState(() => _isDragOver = true);
                return true;
              },
              onLeave: (_) => setState(() => _isDragOver = false),
              onAcceptWithDetails: (_) {
                setState(() => _isDragOver = false);
              },
              builder: (context, _, __) => GestureDetector(
                onTap: () => _pickFiles(notifier),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: _isDragOver
                        ? primary.withValues(alpha: 0.08)
                        : (isDark
                            ? AppColors.backgroundDark
                            : AppColors.backgroundLight),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isDragOver
                          ? primary
                          : (isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                      width: _isDragOver ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined,
                          size: 36, color: primary),
                      const SizedBox(height: 12),
                      Text(
                        'Drop files here or click to upload',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PDF, DOCX, images supported · max 100 MB',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.mutedForegroundDark
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // URL input toggle
            if (!_showUrlInput)
              TextButton.icon(
                onPressed: () => setState(() => _showUrlInput = true),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Paste a URL or YouTube link'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText:
                            'https://example.com/article or youtube.com/watch?v=…',
                        prefixIcon:
                            const Icon(Icons.link, size: 18),
                        suffixIcon: _urlSubmitting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _submitUrl(notifier),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _urlSubmitting
                        ? null
                        : () => _submitUrl(notifier),
                    style:
                        FilledButton.styleFrom(backgroundColor: primary),
                    child: const Text('Add'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _urlCtrl.clear();
                      setState(() => _showUrlInput = false);
                    },
                  ),
                ],
              ),
            if (notifier.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...notifier.files
                  .map((file) => _FileItem(file: file, notifier: notifier)),
            ],
          ],
        );
      },
    );
  }
}

class _FileItem extends StatelessWidget {
  final UploadFile file;
  final UploadNotifier notifier;

  const _FileItem({required this.file, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    Color statusColor;
    String statusLabel;
    switch (file.status) {
      case UploadStatus.completed:
        statusColor = Colors.green;
        statusLabel = 'Queued';
        break;
      case UploadStatus.uploading:
        statusColor = Colors.orange;
        statusLabel = 'Uploading';
        break;
      case UploadStatus.error:
        statusColor = Colors.red;
        statusLabel = 'Error';
        break;
      default:
        statusColor =
            isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
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
              Icon(Icons.description_outlined, size: 20, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (file.sizeLabel.isNotEmpty) ...[
                Text(
                  file.sizeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.mutedForegroundDark
                        : AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => notifier.removeFile(file.id),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                color: isDark
                    ? AppColors.mutedForegroundDark
                    : AppColors.mutedForeground,
              ),
            ],
          ),
          if (file.status == UploadStatus.uploading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: file.progress,
              backgroundColor:
                  isDark ? AppColors.borderDark : AppColors.borderLight,
              color: primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (file.status == UploadStatus.error &&
              file.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              file.errorMessage!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.red.shade400),
            ),
          ],
        ],
      ),
    );
  }
}
