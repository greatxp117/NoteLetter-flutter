/// The letter-settings preview (4.98.0, ADR-131; `spec/screens/letters.md`
/// §The letter-settings preview; web `LetterSettings.jsx` `.letter-preview-pane`)
/// — in direction D, Letter settings' last section, *The latest letter*.
///
/// A preview of the **last letter the backend built**, and nothing else: the
/// newest daily record with an `html_body` that is not `empty`/`error`
/// ([FirestoreService.getLatestLetter]), rendered read-only by [LetterHost] —
/// the Letters reader's own host. Never a dry run, never cut to the form's
/// count (the letter was built under the settings of its day), no figure the
/// record does not carry (ADR-109).
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/newsletter.dart';
import '../../services/error_text.dart';
import '../../shared/cooldown.dart';
import '../../widgets/kit/kit.dart';
import 'letter_host.dart';

/// Copy copies the stored `html_body`. The platform clipboard here takes ONE
/// flavour, so it takes the HTML — that is the object being copied (web
/// `copyLetter`'s single-flavour branch); `text_body` rides along only where a
/// clipboard takes two, which this one does not.
Future<void> copyLetter(Newsletter n) =>
    Clipboard.setData(ClipboardData(text: n.htmlBody));

/// The pane: the §14.2 line when the read failed, the letter (or the sentence
/// saying there is none), then `.letter-actions` — the record's figures,
/// Copy and Send now — and what those answered.
class LetterPreviewPane extends StatefulWidget {
  /// The stored record; null with [loaded] and no [error] means none built.
  final Newsletter? letter;
  final bool loaded;

  /// The read failed (INV-24): §14.2, never "No letter has been built yet."
  final String? error;

  final bool sending;

  /// Null disables Send now (no delivery address, or a send in flight).
  final VoidCallback? onSend;
  final String? sendMessage;
  final String? sendError;

  /// The clipboard write — a seam for the tests.
  final Future<void> Function(Newsletter) copy;

  const LetterPreviewPane({
    super.key,
    required this.letter,
    required this.loaded,
    required this.error,
    required this.sending,
    required this.onSend,
    this.sendMessage,
    this.sendError,
    this.copy = copyLetter,
  });

  @override
  State<LetterPreviewPane> createState() => _LetterPreviewPaneState();
}

class _LetterPreviewPaneState extends State<LetterPreviewPane> {
  bool _copied = false;
  String? _copyError;

  @override
  void didUpdateWidget(LetterPreviewPane old) {
    super.didUpdateWidget(old);
    if (old.letter?.id != widget.letter?.id) {
      _copied = false;
      _copyError = null;
    }
  }

  Future<void> _copy(Newsletter n) async {
    setState(() {
      _copied = false;
      _copyError = null;
    });
    try {
      await widget.copy(n);
      if (!mounted) return;
      setState(() => _copied = true);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _copyError =
            'The letter could not be copied — ${describeSdkError(e)}',
      );
    }
  }

  /// Send now's cooldown is the CALLER's (4.107.0, ADR-140) — one clock with
  /// the Letters page: held for the wait, the sentence in the send slot.
  @override
  Widget build(BuildContext context) =>
      KitWait(waitKey: WaitKey.letterSend(), builder: _pane);

  Widget _pane(BuildContext context, CooldownWait wait) {
    final n = widget.letter;
    // The cooldown is the calm caption, any other refusal §14.2 (letters.md,
    // 4.108.0, ADR-145 — calm everywhere).
    final sendSlot = kitRefusalSlot(wait, widget.sendError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error != null)
          // It names no day (ADR-132): the record it could not read has none.
          KitFailureInline(
            'Your latest letter could not be read — ${widget.error}',
          ),
        if (n != null)
          KitDSlot(
            // The Letters reader's own placement (ADR-131: the same host):
            // a letter with its letterhead lifted as a sheet on a desk and
            // the screen's whole width on a phone; a frame-less one in its
            // §11 sheet at the column's width.
            n.hasLetterhead
                ? KitLiftedLetter(child: LetterHost(n))
                : LetterHost(n, inset: false),
            top: widget.error == null ? 0 : 10,
          )
        else if (widget.loaded && widget.error == null)
          // `.letter-none`: a sentence, never a letter-shaped placeholder.
          const KitDLetterNone('No letter has been built yet.'),
        KitDLetterActions(
          figures: n == null ? null : letterFigures(n),
          actions: KitActionFlow(
            children: [
              KitButton(
                _copied ? 'Copied' : 'Copy',
                key: const ValueKey('lset-copy'),
                icon: _copied ? Icons.check : Icons.copy_outlined,
                variant: KitButtonVariant.ghost,
                onPressed: n == null ? null : () => _copy(n),
              ),
              KitButton(
                widget.sending ? 'Sending…' : 'Send now',
                key: const ValueKey('lset-send-now'),
                // web `IcoSend`: a right arrow, never a paper plane.
                icon: Icons.arrow_forward,
                wait: widget.sending ? 0 : wait.left,
                onPressed: widget.onSend,
              ),
            ],
          ),
          notes: [
            if (_copyError != null) KitFailureInline(_copyError!),
            if (sendSlot != null)
              sendSlot
            else if (widget.sendMessage != null)
              KitRowNote(widget.sendMessage!),
          ],
        ),
      ],
    );
  }
}
