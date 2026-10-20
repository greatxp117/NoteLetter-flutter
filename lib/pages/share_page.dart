import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/upload_file.dart';
import '../services/resumable_upload.dart';
import '../services/share_intake.dart';
import '../shared/share_content.dart';
import '../shared/upload_types.dart' show kScrollHint;
import '../state/auth_notifier.dart';
import '../state/upload_notifier.dart';
import '../theme/app_spacing.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';

/// **Add to NoteLetter** (`/share`, F-123) — Android's share sheet: what
/// another app shared, filed into the library through [UploadNotifier].
///
/// The same states and copy as the iOS share extension (`ios/Share/
/// ShareView.swift`, F-122, itself the retired Swift app's), composed from the
/// kit: a §2.2 sub-screen header whose back control is the sheet's Cancel /
/// Done, then one §5.1 surface card for what was shared, then the request's
/// §14.2 rejection or its success line. SPEC GAP, as on iOS: every sentence
/// here exists only in Swift — ported verbatim, and the spec should own them.
///
/// **Write before move**: a button is disabled while its request is in
/// flight, and the sheet says it is done only once the request came back.
class SharePage extends StatefulWidget {
  final ShareIntake? intake;

  /// The widget tests' sign-in; null reads [AuthNotifier].
  final bool? signedIn;

  const SharePage({super.key, this.intake, this.signedIn});

  // The copy — iOS's ShareView, verbatim.
  static const title = 'Add to NoteLetter';
  static const cancelLabel = 'Cancel';
  static const doneLabel = 'Done';
  static const signedOutTitle = 'Sign in required';
  static const signedOutBody =
      'Sign in to NoteLetter to share content to your library.';
  static const unreadableTitle = 'Couldn’t read what you shared';
  static const refusedTitle = 'Can’t add this file';
  static const nothingTitle = 'Nothing to share';
  static const nothingBody = "This kind of content isn't supported yet.";
  static const linkEyebrow = 'Link';
  static String filesAs(String type) => 'Files as: ${linkKindLabel(type)}';
  static const addLabel = 'Add to NoteLetter';
  static const photosEyebrow = 'Photos';
  static String photosSelected(int n) =>
      '$n photo${n == 1 ? '' : 's'} selected';
  static const titlePlaceholder = 'Title (optional)';
  static const uploadPhotosLabel = 'Upload Photos';
  static const fileEyebrow = 'File';
  static const uploadFileLabel = 'Upload File';
  static const linkAdded = 'Added link for processing.';
  static String photosUploaded(int n) => 'Uploaded $n photo(s).';
  static String fileUploaded(String name) => 'Uploaded $name.';

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _setTitle = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;
  String? _success;

  ShareIntake get _intake => widget.intake ?? ShareIntake.instance;

  @override
  void initState() {
    super.initState();
    _intake.addListener(_reset);
  }

  @override
  void dispose() {
    _intake.removeListener(_reset);
    _setTitle.dispose();
    super.dispose();
  }

  /// A new share replaces the one on screen: its outcome starts over.
  void _reset() {
    if (!mounted || _busy) return;
    setState(() {
      _done = false;
      _error = null;
      _success = null;
      _setTitle.clear();
    });
  }

  Future<void> _run(Future<String?> Function() request) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? success;
    String? error;
    try {
      success = await request();
    } on ShareReadException catch (e) {
      error = e.message;
    } on _Refused catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _success = success;
      _done = success != null;
    });
  }

  /// iOS's `finish`: the success line, then the sheet closes 0.8 s later.
  Future<void> _finish() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) _intake.close();
  }

  Future<void> _addLink(SharedLink link) => _run(() async {
    final r = await context.read<UploadNotifier>().shareUrl(link.url);
    final rejection = r.rejection;
    if (rejection != null) throw _Refused(rejection);
    // A playlist is one success said with its measured count; its
    // sentences cannot be read in 0.8 s, so the sheet stays (4.114.0).
    if (r.note != null) return r.note;
    _finish();
    return SharePage.linkAdded;
  });

  Future<void> _uploadPhotos(SharedImages set) => _run(() async {
    final uploads = context.read<UploadNotifier>();
    final images =
        <({String name, int size, Uint8List bytes, String mimeType})>[];
    for (final im in set.items) {
      final copied = await _intake.copy(im);
      final Uint8List bytes;
      try {
        bytes = await File(copied.path).readAsBytes();
      } on FileSystemException catch (e) {
        throw ShareReadException(readFailure(e.message));
      }
      images.add((
        name: im.name,
        size: bytes.length,
        bytes: bytes,
        mimeType: im.mimeType.isEmpty ? 'image/jpeg' : im.mimeType,
      ));
    }
    final title = _setTitle.text.trim();
    final rowId = await uploads.addImageSet(
      images,
      title: title.isEmpty ? null : title,
    );
    _rowOutcome(uploads, rowId);
    _finish();
    return SharePage.photosUploaded(images.length);
  });

  Future<void> _uploadFile(SharedFile f) => _run(() async {
    final uploads = context.read<UploadNotifier>();
    final copied = await _intake.copy(f.item);
    final rowId = await uploads.addFile(
      f.item.name,
      copied.size,
      null,
      f.item.mimeType.isEmpty ? 'application/octet-stream' : f.item.mimeType,
      source: ChunkSource.file(copied.path, copied.size),
    );
    _rowOutcome(uploads, rowId);
    _finish();
    return SharePage.fileUploaded(f.item.name);
  });

  /// The upload row's failure, as the sheet's §14.2 line.
  void _rowOutcome(UploadNotifier uploads, String? rowId) {
    final row = uploads.files.where((r) => r.id == rowId).firstOrNull;
    if (row == null || row.status != UploadStatus.completed) {
      throw _Refused(row?.errorMessage ?? 'Upload failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        widget.signedIn ?? context.watch<AuthNotifier>().isLoggedIn;
    final t = Tokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _intake,
          builder: (context, _) => KitPage(
            width: KitFrameWidth.reading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubScreenHeader(
                  parentLabel: _done
                      ? SharePage.doneLabel
                      : SharePage.cancelLabel,
                  onBack: _intake.close,
                  eyebrow: SharePage.title,
                ),
                if (!signedIn)
                  _card(SharePage.signedOutTitle, [
                    Text(SharePage.signedOutBody, style: KitText.meta(context)),
                  ])
                else
                  _contentCard(_intake.content ?? const SharedNothing()),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  KitFailureInline(_error!),
                ],
                if (_success != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    _success!,
                    // A meta line in --positive-text (share-sheet.md).
                    style: KitText.meta(
                      context,
                    ).copyWith(color: t.positiveText),
                  ),
                ],
                const SizedBox(height: AppSpacing.s8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contentCard(SharedContent content) {
    final meta = KitText.meta(context);
    final idle = !_busy && !_done;
    switch (content) {
      case SharedLink(:final url, :final type):
        return _labelled(
          SharePage.linkEyebrow,
          [
            Text(
              middleEllipsis(url),
              style: meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // INV-07: the type is DETECTED, never asked.
            Text(SharePage.filesAs(type), style: meta),
          ],
          action: KitButton.primary(
            SharePage.addLabel,
            onPressed: idle ? () => _addLink(content) : null,
          ),
        );
      case SharedImages(:final items):
        final count = content.countRefusal;
        return _labelled(
          SharePage.photosEyebrow,
          [
            Text(SharePage.photosSelected(items.length), style: meta),
            // Verbatim (sources.md §Endpoints used, 5.10.0, ADR-170).
            Text(kScrollHint, style: meta),
            if (content.unreadable != null)
              KitFailureInline(content.unreadable!),
            if (count != null) KitFailureInline(count),
          ],
          field: KitTextField(
            controller: _setTitle,
            placeholder: SharePage.titlePlaceholder,
            face: KitFieldFace.serif,
            enabled: idle,
          ),
          action: KitButton.primary(
            SharePage.uploadPhotosLabel,
            onPressed: idle && count == null
                ? () => _uploadPhotos(content)
                : null,
          ),
        );
      case SharedFile(:final item):
        return _labelled(
          SharePage.fileEyebrow,
          [Text(item.name, style: meta)],
          action: KitButton.primary(
            SharePage.uploadFileLabel,
            onPressed: idle ? () => _uploadFile(content) : null,
          ),
        );
      case SharedUnreadable(:final reason):
        // A thing we HANDLE that would not open — not an unsupported type.
        return _card(SharePage.unreadableTitle, [KitFailureInline(reason)]);
      case SharedRefused(:final filename, :final reason):
        // Refused before an upload, in the server's own sentence. No button:
        // there is nothing this file can do but be shared as something else.
        return _card(SharePage.refusedTitle, [
          Text(filename, style: meta),
          KitFailureInline(reason),
        ]);
      case SharedNothing():
        return _card(SharePage.nothingTitle, [
          Text(SharePage.nothingBody, style: meta),
        ]);
    }
  }

  /// A state card: its title, then its lines.
  Widget _card(String title, List<Widget> lines) => KitCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: KitText.title(
            context,
            fontSize: 21,
            height: 1.2,
            tracking: -0.01,
          ),
        ),
        for (final l in lines) ...[const SizedBox(height: AppSpacing.s2), l],
      ],
    ),
  );

  /// An action card: the eyebrow and its lines, then a field, then the
  /// button.
  Widget _labelled(
    String eyebrow,
    List<Widget> lines, {
    Widget? field,
    required Widget action,
  }) => KitCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow(eyebrow),
        for (final l in lines) ...[const SizedBox(height: AppSpacing.s1), l],
        if (field != null) ...[const SizedBox(height: AppSpacing.s4), field],
        const SizedBox(height: AppSpacing.s4),
        Align(alignment: Alignment.centerLeft, child: action),
      ],
    ),
  );
}

class _Refused implements Exception {
  final String message;
  _Refused(this.message);
}
