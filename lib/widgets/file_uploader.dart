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
import '../shared/upload_types.dart';
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

  const FileUploader({super.key, this.onUploadComplete, this.onUploadError});

  @override
  State<FileUploader> createState() => FileUploaderState();
}

/// Public so the screen can drive it from elsewhere — the browse section's
/// empty state offers "Add your first file", and an offer that does nothing is
/// an apology wearing the pattern.
class FileUploaderState extends State<FileUploader> {
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

  /// Put the cursor in the link field. The field is always on screen (the
  /// reference's `.link-add`); this is the empty state's "Add a link" offer.
  void revealLinkField() => _urlFocus.requestFocus();

  /// The §14.2 slot for a file or a link this client refused **before** any
  /// request. Every other ingest failure has a document row to carry its
  /// reason; a refusal at the door creates none, so without this the refusal is
  /// not rendered anywhere (4.19.3).
  String? _rejection;

  void _reject(String? message) {
    if (!mounted) return;
    setState(() => _rejection = message);
  }

  Future<void> _pickFiles(UploadNotifier notifier) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      // The contracted set (4.10.0, ADR-046), not `FileType.any`. Advisory
      // only — a share sheet and a paste bypass it entirely — which is why
      // every file still goes through `uploadRejection` below.
      type: FileType.custom,
      allowedExtensions: uploadAllowedExtensions,
    );
    if (result == null) return;
    _reject(null);

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
      // The same words the server would use, without the round trip — and a
      // `null` is not an accept, it is "worth sending". The server still
      // decides, and its message still reaches the row.
      final refused = uploadRejection(
        name: file.name,
        size: file.size,
        mimeType: mimeType,
      );
      if (refused != null) {
        _reject(refused);
        continue;
      }
      // By ROW ID, never by name: two drops of the same filename are two rows,
      // and `lastWhere(name)` reported the later row's status for both — a
      // failed upload read as complete because a later one of the same name
      // succeeded.
      notifier.addFile(file.name, file.size, bytes, mimeType).then((rowId) {
        if (!mounted) return;
        final match = notifier.files.firstWhere(
          (f) => f.id == rowId,
          orElse: () => UploadFile(id: '', name: '', size: 0),
        );
        if (match.status == UploadStatus.completed) {
          widget.onUploadComplete?.call();
        } else if (match.status == UploadStatus.error) {
          widget.onUploadError?.call(match.errorMessage ?? 'Upload failed.');
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

    final images =
        <({String name, int size, Uint8List bytes, String mimeType})>[];
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

    final rowId = await notifier.addImageSet(images);
    if (!mounted || rowId == null) return;
    final match = notifier.files.firstWhere(
      (f) => f.id == rowId,
      orElse: () => UploadFile(id: '', name: '', size: 0),
    );
    if (match.status == UploadStatus.completed) {
      widget.onUploadComplete?.call();
    } else if (match.status == UploadStatus.error) {
      widget.onUploadError?.call(match.errorMessage ?? 'Image upload failed.');
    }
  }

  Future<void> _submitUrl(UploadNotifier notifier) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _urlSubmitting = true;
      _rejection = null;
    });
    try {
      final refused = await notifier.addUrl(url);
      if (!mounted) return;
      if (refused != null) {
        // **Keep the field, keep the text, say why.** Clearing it on a
        // rejection is the 4.19.3 defect exactly: the paste disappears, no row
        // appears, and the reader is left with nothing to correct.
        _reject(refused);
        return;
      }
      _urlCtrl.clear();
      widget.onUploadComplete?.call();
    } finally {
      if (mounted) setState(() => _urlSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadNotifier>(
      builder: (context, notifier, _) {
        final uploading = notifier.files.any(
          (f) => f.status == UploadStatus.uploading,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitDropZone(
              icon: Icons.upload_outlined,
              title: uploading
                  ? 'Uploading…'
                  : 'Drop files, or tap to add a few',
              // Copy from the one declaration, so the zone cannot promise a
              // class the picker does not offer or omit one it does. The cap
              // is **per type** (4.13.0, ADR-049): a flat "100 MB each" is
              // wrong for video by a factor of twenty, and a reader with a
              // phone-shot clip reads it as a refusal that has not happened.
              help: '$uploadAcceptHelp — up to 100 MB each, 2 GB for video',
              // No format pills here: the reference's add panel has none (the
              // help line already names every class), and "What can I add?"
              // in the section header is where the detail lives.
              onTap: () => _pickFiles(notifier),
            ),
            const SizedBox(height: 12),

            // The link row is the zone's sibling, not a control hidden
            // behind a button (`screens/sources.md` §Composition body 1: "the
            // drop zone, then the link row (a field and an Add-link button)").
            _LinkRow(
              controller: _urlCtrl,
              focusNode: _urlFocus,
              submitting: _urlSubmitting,
              onSubmit: () => _submitUrl(notifier),
            ),
            // Multi-image capture (1.1.0) is a device capability the web has
            // no surface for; it stays, as a quiet offer under the row.
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: KitButton.ghost(
                'Add an image set (up to 20)',
                icon: Icons.photo_library_outlined,
                onPressed: () => _pickImageSet(notifier),
              ),
            ),

            // §14.2 — the rejection this client made itself, in the place the
            // reader is looking. Dense: it sits under a control group.
            if (_rejection != null) ...[
              const SizedBox(height: 10),
              KitFailureInline(_rejection!),
            ],

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

  const _LinkRow({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // `.link-add`: a plain field (no glyph — the button carries it) at
    // `11px 14px` on `--surface`, `--r-sm`, and the Add-link button beside it.
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: focusNode,
              builder: (context, field) => Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: AppRadius.smR,
                  border: Border.all(
                    color: focusNode.hasFocus ? t.accent : t.border,
                  ),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.url,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 14,
                    color: t.fg,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    // The box above IS the field; the theme's own outline
                    // would draw a second, pill-shaped one inside it.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
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
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => KitButton.secondary(
              submitting ? 'Adding…' : 'Add link',
              icon: Icons.link,
              // Disabled on an empty field, as the reference's is.
              onPressed: submitting || controller.text.trim().isEmpty
                  ? null
                  : onSubmit,
            ),
          ),
        ],
      ),
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
