import 'package:flutter/material.dart';

import '../../models/chunk.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';
import 'supersession_confirm.dart';

/// "Treat as recipe" / "Not a recipe" (4.6.0, ADR-042) — the reader's
/// standing instruction, `fn_update_document {contentForm}`. Reference:
/// `ContentFormAction` in `ReaderView.jsx`.
///
/// The only document action that re-derives content, so it carries the
/// §Supersession confirm (`screens/reader.md`, a §18 Confirmation): authored
/// passages are replaced by a fresh extraction, and a study program's schedule
/// for this document restarts. **Write before you move**: nothing changes on
/// screen until the call returns; the document then moves queued → processing
/// → complete under the live data, which [onQueued] reloads.
class ContentFormAction extends StatelessWidget {
  final String docId;
  final Document doc;
  final List<Chunk> chunks;
  final VoidCallback onQueued;

  const ContentFormAction({
    super.key,
    required this.docId,
    required this.doc,
    required this.chunks,
    required this.onQueued,
  });

  /// Offered on a finished or a failed document only — the reference's rule.
  static bool offeredFor(Document doc) =>
      doc.status == DocumentStatus.complete ||
      doc.status == DocumentStatus.error;

  /// Is this document in a study program? Three answers, not two: `null` is
  /// "we could not check", and the confirm then SAYS it could not — a failed
  /// check that resolved to `false` dropped the warning the dialog exists to
  /// give (the reference's own note).
  ///
  /// Read off the programs subscription the Study screen already uses, once:
  /// the reference's `array-contains … limit 1` reads the same fact, and a
  /// user's programs are few.
  static Future<bool?> inStudyProgram(String docId) =>
      SupersessionConfirm.inStudyProgram(docId);

  bool get _isRecipe => doc.recipe != null;

  Future<void> _open(BuildContext context) async {
    final inStudy = await inStudyProgram(docId);
    if (!context.mounted) return;
    final edited = chunks.any((c) => c.userEdited);
    final next = _isRecipe ? 'none' : 'recipe';
    final ok = await KitConfirm.show(
      context,
      danger: true,
      title: _isRecipe ? 'Restore the full text?' : 'Reduce this to the recipe?',
      bodyWidget: Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in supersessionLines(
                isRecipe: _isRecipe, edited: edited, inStudy: inStudy))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(line, style: KitText.meta(ctx)),
              ),
          ],
        ),
      ),
      confirmLabel: _isRecipe ? 'Restore full text' : 'Reduce to recipe',
      cancelLabel: 'Keep it as it is',
      onConfirm: () async {
        try {
          await Api.instance.updateDocument(docId, {'contentForm': next});
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'Could not update this source.';
        }
      },
    );
    if (ok == true) onQueued();
  }

  /// The confirm's sentences, in order — the reference's, word for word.
  static List<String> supersessionLines({
    required bool isRecipe,
    required bool edited,
    required bool? inStudy,
  }) =>
      SupersessionConfirm.lines(
        lead: isRecipe
            ? 'This source will be re-read from the original and its passages '
                'replaced with the full text.'
            : 'This source will be re-read and its passages replaced with just '
                'the recipe — ingredients, steps and pictures. The full '
                'original text is kept, and stays available in the Original '
                'panel.',
        edited: edited,
        inStudy: inStudy,
      );

  @override
  Widget build(BuildContext context) {
    if (!offeredFor(doc)) return const SizedBox.shrink();
    return KitButton.ghost(
      _isRecipe ? 'Not a recipe' : 'Treat as recipe',
      icon: Icons.title,
      onPressed: () => _open(context),
    );
  }
}
