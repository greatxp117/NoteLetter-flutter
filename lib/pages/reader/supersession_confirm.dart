import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/chunk.dart';
import '../../services/firestore_service.dart';
import '../../widgets/kit/kit.dart';

/// How an operation that re-derives a document ended.
enum SupersessionOutcome {
  /// The call succeeded — through the confirm, or directly.
  done,

  /// The reader kept the document as it is. Nothing was sent.
  kept,

  /// The call ran WITHOUT a confirm (none was owed) and was refused;
  /// [SupersessionResult.message] is the server's sentence, for the caller's
  /// own §14.2 slot. A refusal inside the confirm never gets here: the §18
  /// panel renders it in its failure slot and stays open.
  refused,
}

class SupersessionResult {
  final SupersessionOutcome outcome;
  final String? message;
  const SupersessionResult(this.outcome, [this.message]);
}

/// `screens/reader.md` §Supersession confirm (2.35.0, ADR-034; a §18
/// Confirmation since 4.56.0, ADR-092): before any operation that re-derives
/// content from the source — **Update from source** among them — the client
/// MUST confirm when any chunk has `user_edited: true` or the document belongs
/// to a study program, naming both consequences. The confirming control is the
/// danger variant.
///
/// Both facts are three-valued. `null` is "we could not check", and the
/// confirm then SAYS it could not — a failed check that resolved to `false`
/// would drop the warning the dialog exists to give. Only two definite
/// `false`s skip the confirm.
class SupersessionConfirm {
  SupersessionConfirm._();

  /// Did the reader edit any passage? From [chunks] when the caller already
  /// holds them (the reader), else one quiet read — no `doc_opened`, since
  /// nobody opened anything (INV-03).
  static Future<bool?> anyEdited(String docId, {List<Chunk>? chunks}) async {
    if (chunks != null) return chunks.any((c) => c.userEdited);
    try {
      final read = await FirestoreService.instance
          .getReaderDocumentQuietly(docId)
          .timeout(const Duration(seconds: 10));
      if (read == null) return null;
      return read.$2.any((c) => c.userEdited);
    } catch (_) {
      return null;
    }
  }

  /// Is this document in a study program? `null` is "we could not check".
  /// Read off the programs subscription the Study screen already uses, once:
  /// the reference's `array-contains … limit 1` reads the same fact, and a
  /// user's programs are few.
  static Future<bool?> inStudyProgram(String docId) async {
    try {
      final programs = await FirestoreService.instance
          .subscribeStudyPrograms()
          .first
          .timeout(const Duration(seconds: 10));
      return programs.any((p) => p.documentIds.contains(docId));
    } catch (_) {
      return null;
    }
  }

  /// Owed unless both facts are a definite no.
  static bool owed({required bool? edited, required bool? inStudy}) =>
      edited != false || inStudy != false;

  /// The consequence sentences after the operation's own [lead], in order.
  static List<String> lines({
    required String lead,
    required bool? edited,
    required bool? inStudy,
  }) =>
      [
        lead,
        if (edited == true)
          'Your edits to these passages will be replaced by a fresh extraction.',
        if (edited == null)
          'We could not check whether these passages were edited. If they '
              'were, your edits will be replaced by a fresh extraction.',
        if (inStudy == true)
          'This source is in a study program — its schedule for this source '
              'will restart.',
        if (inStudy == null)
          'We could not check whether this source is in a study program. If '
              'it is, its schedule for this source will restart.',
      ];

  /// Run [action] — through the §18 confirm when it is owed, directly when
  /// it is not. [action] returns `null` on success or the sentence to show.
  /// Write before you move: nothing on the caller's screen changes until this
  /// resolves [SupersessionOutcome.done].
  static Future<SupersessionResult> run(
    BuildContext context, {
    required String docId,
    List<Chunk>? chunks,
    required String title,
    required String lead,
    required String confirmLabel,
    required Future<String?> Function() action,
    Future<bool?> Function(String docId)? studyCheck,
    Future<bool?> Function(String docId)? editCheck,
  }) async {
    final (edited, inStudy) = await (
      (editCheck ?? (id) => anyEdited(id, chunks: chunks))(docId),
      (studyCheck ?? inStudyProgram)(docId),
    ).wait;
    if (!owed(edited: edited, inStudy: inStudy)) {
      final err = await action();
      return err == null
          ? const SupersessionResult(SupersessionOutcome.done)
          : SupersessionResult(SupersessionOutcome.refused, err);
    }
    if (!context.mounted) {
      return const SupersessionResult(SupersessionOutcome.kept);
    }
    final ok = await KitConfirm.show(
      context,
      danger: true,
      title: title,
      bodyWidget: Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line
                in lines(lead: lead, edited: edited, inStudy: inStudy))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(line, style: KitText.meta(ctx)),
              ),
          ],
        ),
      ),
      confirmLabel: confirmLabel,
      cancelLabel: 'Keep it as it is',
      onConfirm: action,
    );
    return SupersessionResult(
        ok == true ? SupersessionOutcome.done : SupersessionOutcome.kept);
  }

  /// Update from source's own wording — one spelling for the reader banner
  /// and the Sources row.
  static const updateTitle = 'Update from the source?';
  static const updateConfirmLabel = 'Update from source';
  /// [provider] is the integration id (`google_drive`, …).
  static String updateLead(String? provider) =>
      'This source will be re-imported from '
      '${_providerName[provider] ?? 'its original'} and its passages '
      'replaced with a fresh extraction.';

  static const _providerName = {
    'google_drive': 'Google Drive',
    'onedrive': 'OneDrive',
    'dropbox': 'Dropbox',
    'notion': 'Notion',
  };
}
