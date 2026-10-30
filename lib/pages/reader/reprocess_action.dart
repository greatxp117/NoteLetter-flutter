import 'package:flutter/material.dart';

import '../../models/chunk.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/error_text.dart';
import '../../widgets/kit/kit.dart';
import 'supersession_confirm.dart';

/// **Re-process** (5.27.0, ADR-183; `screens/reader.md` §Re-process) — the
/// document read again from its original with nothing about it changed, run
/// as an UPDATE IN PLACE (ADR-172's semantics): passages that come out the
/// same keep their ids, read marks, shelves and study schedule; the rest are
/// rebuilt. Reference: `ReprocessAction` in web's `ReaderView.jsx`.
///
/// One of the sheet's quieter *Also* rows (kit §29), after the content-form
/// action and before Delete. Confirmed **always**, a §18 danger panel. Like
/// Update from source its only consequence is an edited passage that changes —
/// the study schedule survives an update in place, so no study read is made —
/// and the edit fact comes from the chunks this screen already holds.
///
/// **Write before you move**: the confirm holds until the 202 and nothing on
/// the screen changes before it. The document then moves queued → processing →
/// complete through the same reload the content-form action uses ([onQueued]).
/// A 409 or 500 stays in the confirm's failure slot, in the server's words.
class ReprocessAction extends StatelessWidget {
  final String docId;
  final Document doc;
  final List<Chunk> chunks;
  final VoidCallback onQueued;

  const ReprocessAction({
    super.key,
    required this.docId,
    required this.doc,
    required this.chunks,
    required this.onQueued,
  });

  /// Whether Re-process is drawn: a document at rest (`complete | error`),
  /// that is not a captured passage, and that HAS an original to read again —
  /// a stored file, a set of them, or a link. The endpoint refuses the other
  /// two by name (409), and a client that draws the action by this rule never
  /// sends either. Web's `canReprocess`, where an empty string is no original.
  static bool offeredFor(Document doc) {
    if (doc.status != DocumentStatus.complete &&
        doc.status != DocumentStatus.error) {
      return false;
    }
    if (doc.sourcePassage != null) return false;
    return (doc.gcsPath?.isNotEmpty ?? false) ||
        doc.gcsPaths.isNotEmpty ||
        (doc.sourceUrl?.isNotEmpty ?? false);
  }

  /// The confirm's sentences, in order — web's `SupersessionBody` with
  /// `REPROCESS`: the lead, then the edit consequence only when a passage is
  /// edited. Never the study line: an update in place keeps the schedule.
  static List<String> confirmLines({required bool edited}) =>
      SupersessionConfirm.lines(
        lead: SupersessionConfirm.reprocessLead,
        edited: edited,
        inStudy: false,
        editedLine: SupersessionConfirm.reprocessEditedLine,
      );

  Future<void> _open(BuildContext context) async {
    final edited = chunks.any((c) => c.userEdited);
    final ok = await KitConfirm.show(
      context,
      danger: true,
      title: SupersessionConfirm.reprocessTitle,
      bodyWidget: Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in confirmLines(edited: edited))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(line, style: KitText.meta(ctx)),
              ),
          ],
        ),
      ),
      confirmLabel: SupersessionConfirm.reprocessConfirmLabel,
      cancelLabel: SupersessionConfirm.reprocessCancelLabel,
      busyLabel: SupersessionConfirm.reprocessBusyLabel,
      onConfirm: () async {
        try {
          await Api.instance.updateDocument(docId, {'reprocess': true});
          return null;
        } catch (e) {
          // A 409 (still processing, a passage, no original, a legacy
          // format) or a refused enqueue's 500 — in the panel, in the
          // server's words; an SDK failure in what the SDK said (§14.3).
          return describeSdkError(e);
        }
      },
    );
    if (ok == true) onQueued();
  }

  @override
  Widget build(BuildContext context) {
    if (!offeredFor(doc)) return const SizedBox.shrink();
    return KitAlsoButton(
      'Re-process',
      icon: Icons.refresh,
      onTap: () => _open(context),
    );
  }
}
