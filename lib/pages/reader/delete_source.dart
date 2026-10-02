import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';

/// §Deleting a source (`screens/reader.md`, 4.105.0, ADR-138). Reference:
/// `DeleteSource` in `ReaderView.jsx`.
///
/// The ghost *Delete* at the end of the header's actions, and its §18
/// confirmation: it names what is lost and what is kept, holds until
/// `fn_delete_document` answers, keeps a refusal inside the panel, and on
/// success hands back to the reader, which returns to where it was opened
/// from. Nothing is removed from any list by hand — every list loses the
/// document by its own subscription. An in-progress document is cancelled from
/// its processing row instead, so it is not offered here.
class DeleteSourceAction extends StatelessWidget {
  final String docId;
  final Document doc;

  /// The passage count this screen read.
  final int passages;

  /// The tags subscription, to name the shelves the document comes off.
  final List<Tag> shelves;
  final VoidCallback onDeleted;

  /// Seam for the widget test; defaults to [Api.deleteDocument].
  final Future<void> Function(String docId)? delete;

  const DeleteSourceAction({
    super.key,
    required this.docId,
    required this.doc,
    required this.passages,
    required this.shelves,
    required this.onDeleted,
    this.delete,
  });

  static const _deletable = {
    DocumentStatus.complete,
    DocumentStatus.error,
    DocumentStatus.skipped,
  };

  static bool offeredFor(Document doc) => _deletable.contains(doc.status);

  Future<void> _confirm(BuildContext context) async {
    final run = delete ?? Api.instance.deleteDocument;
    final ok = await KitConfirm.show(
      context,
      title: 'Delete “${doc.title.isEmpty ? 'Untitled' : doc.title}”?',
      body: deleteSourceBody(doc, passages, shelves),
      confirmLabel: 'Delete source',
      cancelLabel: 'Keep it',
      danger: true,
      onConfirm: () async {
        try {
          await run(docId);
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'That request could not be completed.';
        }
      },
    );
    if (ok == true) onDeleted();
  }

  @override
  Widget build(BuildContext context) => KitButton.ghost(
        'Delete',
        icon: Icons.delete_outline,
        onPressed: () => _confirm(context),
      );
}

/// `counted()`'s `toLocaleString()` — 1,234.
String _grouped(int n) =>
    '$n'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

String _andList(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// The §18 body: what is lost, then what is not. `{n}` is singular at 1, and
/// at 0 the body starts at the original file; the shelves clause names the
/// shelves the document carries, resolved against the tags subscription, and
/// is absent when it carries none.
String deleteSourceBody(Document doc, int passages, List<Tag> shelves) {
  final names = [
    for (final id in doc.tagIds)
      if (shelves.where((s) => s.id == id).firstOrNull case final s?) s.title,
  ];
  final lost = passages > 0
      ? 'Its ${_grouped(passages)} ${passages == 1 ? 'passage' : 'passages'}, its original '
          'file and its reading history are deleted for good'
      : 'Its original file and its reading history are deleted for good';
  final off = names.isEmpty ? '' : ', and it comes off ${_andList(names)}';
  return '$lost$off. Letters you have already received keep their passages, '
      'and your shelves and other sources stay as they are. A study program '
      'that uses it drops its passages at its next session.';
}
