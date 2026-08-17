import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../models/upload_file.dart';
import '../state/upload_notifier.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'kit/kit.dart';

/// The add flows (`screens/sources.md` §Composition body 1): the **drop zone**,
/// the link row, and the files currently in flight.
///
/// Composed from the kit (ADR-041): the zone is [KitDropZone], the actions are
/// [KitButton]s and an in-flight file is a §4.1 row. It previously drew its own
/// dashed container, its own Material progress bar and its own status chips in
/// `Colors.green`/`Colors.orange` — palette steps that belong to no token file
/// and do not flip with the theme.
///
/// The zone **opens** the Sources screen (contract 4.5.3): a dropped source
/// lands where the reader is already looking.
class FileUploader extends StatefulWidget {
  final VoidCallback? onUploadComplete;
  final void Function(String message)? onUploadError;

  const FileUploader({
    super.key,
    this.onUploadComplete,
    this.onUploadError,
  });

  @override
  State<FileUploader> createState() => FileUploaderState();
}

/// Public so the screen can drive it from elsewhere — the browse section's
/// empty state offers "Add your first file", and an offer that does nothing is
/// an apology wearing the pattern.
class FileUploaderState extends State<FileUploader> {
  bool _showUrlInput = false;
  final _urlCtrl = TextEditingController();
  final _urlFocus = FocusNode();
  bool _urlSubmitting = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  /// Open the system file picker.
  Future<void> pickFiles() => _pickFiles(context.read<UploadNotifier>());

  /// Reveal the link field and put the cursor in it.
  void revealLinkField() {
    setState(() => _showUrlInput = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _urlFocus.requestFocus());
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

  // Multi-image note capture (contract 1.1.0): pick ≤20 images → one image_set.
  Future<void> _pickImageSet(UploadNotifier notifier) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;

    final images = <({String name, int size, Uint8List bytes, String mimeType})>[];
    for (final f in result.files.take(20)) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      images.add((
        name: f.name,
        size: f.size,
        bytes: bytes,
        mimeType: lookupMimeType(f.name) ?? 'image/jpeg',
      ));
    }
    if (images.isEmpty) return;

    await notifier.addImageSet(images);
    if (!mounted) return;
    final match = notifier.files.lastWhere((f) => f.mimeType == 'image/*',
        orElse: () => UploadFile(id: '', name: '', size: 0));
    if (match.status == UploadStatus.completed) {
      widget.onUploadComplete?.call();
    } else if (match.status == UploadStatus.error) {
      widget.onUploadError?.call(match.errorMessage ?? 'Image upload failed.');
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
    return Consumer<UploadNotifier>(
      builder: (context, notifier, _) {
        final uploading = notifier.files
            .any((f) => f.status == UploadStatus.uploading);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitDropZone(
              icon: Icons.upload_outlined,
              title: uploading
                  ? 'Uploading…'
                  : 'Drop files, or tap to add a few',
              help: 'PDF, Word, Markdown, plain text, images — '
                  'up to 100 MB each',
              formats: const [
                KitTag('PDF'),
                KitTag('DOCX'),
                KitTag('EPUB'),
                KitTag('Markdown'),
                KitTag('PNG / JPG'),
              ],
              onTap: () => _pickFiles(notifier),
            ),
            const SizedBox(height: 12),

            if (!_showUrlInput)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  KitButton.ghost('Paste a link or YouTube URL',
                      icon: Icons.link, onPressed: revealLinkField),
                  KitButton.ghost('Add an image set (up to 20)',
                      icon: Icons.photo_library_outlined,
                      onPressed: () => _pickImageSet(notifier)),
                ],
              )
            else
              _LinkRow(
                controller: _urlCtrl,
                focusNode: _urlFocus,
                submitting: _urlSubmitting,
                onSubmit: () => _submitUrl(notifier),
                onCancel: () {
                  _urlCtrl.clear();
                  setState(() => _showUrlInput = false);
                },
              ),

            if (notifier.files.isNotEmpty) ...[
              const SizedBox(height: 12),
              KitRowList(
                rows: [
                  for (final f in notifier.files)
                    _InFlightRow(file: f, notifier: notifier),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The link row: a field and an Add-link button. `fn_ingest_url` (INV-07).
class _LinkRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _LinkRow({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.controlR(38),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 15, color: t.fgSubtle),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 14,
                      color: t.fg,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Paste a link — article, video, or podcast…',
                      hintStyle: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 14,
                        color: t.fgSubtle,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        KitButton.secondary(submitting ? 'Adding…' : 'Add link',
            icon: Icons.add, onPressed: submitting ? null : onSubmit),
        const SizedBox(width: 4),
        KitIconButton(Icons.close, tooltip: 'Cancel', onPressed: onCancel),
      ],
    );
  }
}

/// A file mid-upload. The §4.1 row, carrying its state in the subtitle slot and
/// the **only determinate progress this screen has**: the client's own PUT.
/// Both server phases are indeterminate by contract (ADR-024) — a synthesised
/// percentage there would be a number with no measurement behind it.
class _InFlightRow extends StatelessWidget {
  final UploadFile file;
  final UploadNotifier notifier;

  const _InFlightRow({required this.file, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (label, failed) = switch (file.status) {
      UploadStatus.completed => ('Queued for processing', false),
      UploadStatus.uploading => ('Uploading', false),
      UploadStatus.error => (file.errorMessage ?? 'Upload failed', true),
      _ => ('Waiting', false),
    };

    return Column(
      children: [
        KitSourceRow(
          leading: const KitFileBadge('note'),
          title: file.name.isEmpty ? 'Untitled' : file.name,
          subtitle: file.sizeLabel.isEmpty
              ? label
              : '$label · ${file.sizeLabel}',
          trailing: KitIconButton(
            Icons.close,
            tooltip: 'Remove',
            color: failed ? t.critical : null,
            onPressed: () => notifier.removeFile(file.id),
          ),
        ),
        if (file.status == UploadStatus.uploading)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: ClipRRect(
              borderRadius: AppRadius.pillR(4),
              child: LinearProgressIndicator(
                value: file.progress,
                minHeight: 4,
                backgroundColor: t.surfaceSunken,
                color: t.accent,
              ),
            ),
          ),
      ],
    );
  }
}
