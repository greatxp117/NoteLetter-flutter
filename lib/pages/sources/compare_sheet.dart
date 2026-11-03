import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/error_text.dart';
import '../../shared/picture_copy.dart';
import '../../widgets/kit/kit.dart';

/// **Compare** — a copy of a picture already in the library beside the
/// original (5.51.0, ADR-202 addendum 1; `screens/sources.md` §Compare; web
/// `overlays/CompareCopySheet.jsx`). Xavier, 2026-11-02: *"show what the
/// existing picture looks like along side, and how/when it was uploaded, to
/// help the user make the decision."*
///
/// §15's sheet (on a phone, the sheet quick add rises as): *Is this the same
/// picture?*, the copy's own sentence under it, **This one** beside **Already
/// in your library**, each with its picture, *Added {when}*, how and its
/// pixel size. The pictures are read only when the sheet opens — a sweep can
/// list hundreds of copies — each through `fn_get_raw_document_url`; the
/// original's record is the row's own read ([OriginalRecords]).
///
/// The foot does exactly what the row's controls do, and each closes the
/// sheet first: *Open the original* (gone with the original), *Remove this
/// copy* (the row's Remove, with its §18 confirm) and *Add anyway* (the row's,
/// on the row's own condition — [onAddAnyway] is null where the row has none).
class CompareCopySheet {
  CompareCopySheet._();

  static const title = 'Is this the same picture?';
  static const thisOne = 'This one';
  static const inLibrary = 'Already in your library';
  static const stayedOnPhone = 'This photo stayed on your phone.';
  static const loading = 'Loading the picture…';
  static const unopened = 'This picture couldn’t be opened.';
  static const noPicture = 'No picture is stored for this source.';
  static const openOriginal = 'Open the original';
  static const removeCopy = 'Remove this copy';
  static const addAnyway = 'Add anyway';

  /// [holdingThumbnail]: on the phone that holds a copy never uploaded, its
  /// own thumbnail, read on the device — drawn where every other client
  /// says *This photo stayed on your phone.*
  static Future<void> open(
    BuildContext context,
    Document copy, {
    required void Function(String originalId) onOpenOriginal,
    required VoidCallback onRemove,
    VoidCallback? onAddAnyway,
    Future<Uint8List?> Function()? holdingThumbnail,
  }) =>
      KitOverlaySheet.show(
        context,
        icon: Icons.layers_outlined,
        mark: false,
        phoneSheet: true,
        title: title,
        subtitle: copy.errorMessage,
        foot: _Foot(
          copy: copy,
          onOpenOriginal: onOpenOriginal,
          onRemove: onRemove,
          onAddAnyway: onAddAnyway,
        ),
        builder: (_) => _Body(copy: copy, holdingThumbnail: holdingThumbnail),
      );
}

List<String> _facts(Document d) =>
    [addedLine(d.createdAt), howPhrase(d), sizeLine(d)].whereType<String>().toList();

class _Body extends StatefulWidget {
  final Document copy;
  final Future<Uint8List?> Function()? holdingThumbnail;
  const _Body({required this.copy, this.holdingThumbnail});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late Future<Document?> _original;

  @override
  void initState() {
    super.initState();
    _original = _read();
  }

  Future<Document?> _read() {
    final id = widget.copy.duplicateOf;
    return id == null || id.isEmpty ? Future.value(null) : OriginalRecords.of(id);
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final neverSent = copy.skipReason == 'already_in_library_not_uploaded';
    final left = KitCompareColumn(
      eyebrow: CompareCopySheet.thisOne,
      stage: _Picture(
        docId: copy.id,
        title: copy.title,
        absent: neverSent,
        holding: neverSent ? widget.holdingThumbnail : null,
      ),
      title: copy.title.isEmpty ? 'Untitled' : copy.title,
      facts: _facts(copy),
    );
    final right = FutureBuilder<Document?>(
      future: _original,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const KitCompareColumn(
            eyebrow: CompareCopySheet.inLibrary,
            stage: KitCompareStage.note(CompareCopySheet.loading),
          );
        }
        if (snap.hasError) {
          final e = snap.error!;
          return KitCompareColumn(
            eyebrow: CompareCopySheet.inLibrary,
            stage: KitCompareStage.child(KitFailureBlock(
              sentence: originalUnread,
              detail: describeSdkError(e),
              requestId: e is ApiException ? e.requestId : null,
              onRetry: () => setState(() {
                _original = _read();
              }),
            )),
          );
        }
        final original = snap.data;
        if (original == null) {
          return const KitCompareColumn(
            eyebrow: CompareCopySheet.inLibrary,
            stage: KitCompareStage.note(originalGone),
          );
        }
        return KitCompareColumn(
          eyebrow: CompareCopySheet.inLibrary,
          stage: _Picture(docId: original.id, title: original.title),
          title: original.title.isEmpty ? 'Untitled' : original.title,
          facts: _facts(original),
        );
      },
    );
    return KitCompareColumns(left: left, right: right);
  }
}

/// One side's picture: read when the sheet opens, through
/// `fn_get_raw_document_url` (a document in any status answers) — or, for a
/// copy never uploaded, nothing on the server to read.
class _Picture extends StatefulWidget {
  final String docId;
  final String title;
  final bool absent;
  final Future<Uint8List?> Function()? holding;

  const _Picture({
    required this.docId,
    required this.title,
    this.absent = false,
    this.holding,
  });

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  Future<Object?>? _read;

  @override
  void initState() {
    super.initState();
    _read = _load();
  }

  /// The holding phone's own bytes, or the signed URL's answer. null: no
  /// question to ask (a copy never sent, off the holding phone).
  Future<Object?>? _load() {
    final holding = widget.holding;
    if (widget.absent) return holding?.call();
    return Api.instance.getRawDocumentUrl(widget.docId);
  }

  @override
  Widget build(BuildContext context) {
    final read = _read;
    if (read == null) return const KitCompareStage.note(CompareCopySheet.stayedOnPhone);
    return FutureBuilder<Object?>(
      future: read,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const KitCompareStage.note(CompareCopySheet.loading);
        }
        if (widget.absent) {
          // On the holding phone: its own thumbnail, or — not on the device
          // either — what every other client says.
          final bytes = snap.hasError ? null : snap.data as Uint8List?;
          return bytes == null
              ? const KitCompareStage.note(CompareCopySheet.stayedOnPhone)
              : KitCompareStage.bytes(bytes,
                  label: widget.title, unreadable: CompareCopySheet.unopened);
        }
        if (snap.hasError) {
          final e = snap.error!;
          return KitCompareStage.child(KitFailureBlock(
            sentence: CompareCopySheet.unopened,
            detail: describeSdkError(e),
            requestId: e is ApiException ? e.requestId : null,
            // A block body: setState's callback may not return the Future.
            onRetry: () => setState(() {
              _read = _load();
            }),
          ));
        }
        final url = (snap.data as Map?)?['signed_url'];
        // A successful answer with no object is a real answer, not §14.
        if (url is! String || url.isEmpty) {
          return const KitCompareStage.note(CompareCopySheet.noPicture);
        }
        return KitCompareStage.image(url,
            label: widget.title, unreadable: CompareCopySheet.unopened);
      },
    );
  }
}

class _Foot extends StatefulWidget {
  final Document copy;
  final void Function(String originalId) onOpenOriginal;
  final VoidCallback onRemove;
  final VoidCallback? onAddAnyway;

  const _Foot({
    required this.copy,
    required this.onOpenOriginal,
    required this.onRemove,
    this.onAddAnyway,
  });

  @override
  State<_Foot> createState() => _FootState();
}

class _FootState extends State<_Foot> {
  /// The same read the body draws from ([OriginalRecords] shares it): Open
  /// the original is gone once the original is.
  late final Future<Document?>? _original = () {
    final id = widget.copy.duplicateOf;
    return id == null || id.isEmpty ? null : OriginalRecords.of(id);
  }();

  void _then(VoidCallback act) {
    Navigator.of(context).pop();
    act();
  }

  @override
  Widget build(BuildContext context) {
    final original = _original;
    Widget foot(bool gone) => KitCompareFoot(children: [
          if (!gone && original != null)
            KitButton.ghost(CompareCopySheet.openOriginal,
                onPressed: () =>
                    _then(() => widget.onOpenOriginal(widget.copy.duplicateOf!))),
          KitButton.ghost(CompareCopySheet.removeCopy,
              onPressed: () => _then(widget.onRemove)),
          if (widget.onAddAnyway != null)
            KitButton.primary(CompareCopySheet.addAnyway,
                onPressed: () => _then(widget.onAddAnyway!)),
        ]);
    if (original == null) return foot(true);
    return FutureBuilder<Document?>(
      future: original,
      builder: (context, snap) => foot(snap.connectionState == ConnectionState.done &&
          !snap.hasError &&
          snap.data == null),
    );
  }
}
