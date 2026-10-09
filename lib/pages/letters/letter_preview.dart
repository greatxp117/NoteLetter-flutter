/// The letter-settings preview (4.98.0, ADR-131; `spec/screens/letters.md`
/// §The letter-settings preview; web `LetterSettings.jsx` `.letter-preview-pane`
/// at 596edef).
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
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'letter_host.dart';

/// Copy copies the stored `html_body`. The platform clipboard here takes ONE
/// flavour, so it takes the HTML — that is the object being copied (web
/// `copyLetter`'s single-flavour branch); `text_body` rides along only where a
/// clipboard takes two, which this one does not.
Future<void> copyLetter(Newsletter n) =>
    Clipboard.setData(ClipboardData(text: n.htmlBody));

/// The pane: the letter (or the sentence saying there is none, or the §14.2
/// line saying it could not be read), then the actions row.
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

  /// The side inset of everything AROUND the letter — the failure line, "No
  /// letter has been built yet." and `.letter-actions` (`padding: 0 6px`) —
  /// for a pane that has no gutter of its own. On a phone the pane is web's
  /// `.letter-preview-pane`: the letter's own `34px 20px` padding is its
  /// margin, so a frame gutter around it doubled the inset to 40.
  final double inset;

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
    this.inset = 0,
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
  /// the Letters card: held for the wait, the sentence in the send slot.
  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: WaitKey.letterSend(),
        builder: _pane,
      );

  Widget _pane(BuildContext context, CooldownWait wait) {
    final t = Tokens.of(context);
    final n = widget.letter;
    final figures = n == null ? null : letterFigures(n);
    // The cooldown is the calm caption, any other refusal §14.2 (letters.md,
    // 4.108.0, ADR-145 — calm everywhere).
    final sendSlot = kitRefusalSlot(wait, widget.sendError);
    Widget around(Widget child) => widget.inset == 0
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.inset),
            child: child,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error != null) ...[
          around(KitFailureInline(
            "Today's letter could not be read — ${widget.error}",
          )),
          const SizedBox(height: 10),
        ],
        if (n != null)
          LetterHost(n)
        else if (widget.loaded && widget.error == null)
          // `.letter-none`: a sentence, never a letter-shaped placeholder.
          around(const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Lede(
              'No letter has been built yet.',
              fontSize: 16,
              height: 24,
              maxWidth: 640,
            ),
          )),
        const SizedBox(height: 14),
        // `.letter-actions`: the figures, then Copy and Send now.
        around(Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.s3,
          runSpacing: AppSpacing.s2,
          children: [
            if (figures != null)
              Text(
                figures.toUpperCase(),
                style: KitText.capsLabel(
                  context,
                  color: t.fgSubtle,
                  letterSpacing: 0.06,
                ),
              ),
            KitActionFlow(
              children: [
                KitButton(
                  _copied ? 'Copied' : 'Copy',
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  variant: KitButtonVariant.ghost,
                  onPressed: n == null ? null : () => _copy(n),
                ),
                KitButton(
                  widget.sending ? 'Sending…' : 'Send now',
                  // web `IcoSend`: a right arrow, never a paper plane.
                  icon: Icons.arrow_forward,
                  wait: widget.sending ? 0 : wait.left,
                  onPressed: widget.onSend,
                ),
              ],
            ),
          ],
        )),
        if (_copyError != null) ...[
          const SizedBox(height: AppSpacing.s2),
          around(KitFailureInline(_copyError!)),
        ],
        if (sendSlot != null) ...[
          const SizedBox(height: AppSpacing.s2),
          around(sendSlot),
        ] else if (widget.sendMessage != null) ...[
          const SizedBox(height: AppSpacing.s2),
          around(KitRowNote(widget.sendMessage!)),
        ],
      ],
    );
  }
}
