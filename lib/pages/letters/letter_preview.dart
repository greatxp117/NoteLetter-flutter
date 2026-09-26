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

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final n = widget.letter;
    final figures = n == null ? null : letterFigures(n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error != null) ...[
          KitFailureInline(
            "Today's letter could not be read — ${widget.error}",
          ),
          const SizedBox(height: 10),
        ],
        if (n != null)
          LetterHost(n)
        else if (widget.loaded && widget.error == null)
          // `.letter-none`: a sentence, never a letter-shaped placeholder.
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Lede(
              'No letter has been built yet.',
              fontSize: 16,
              height: 24,
              maxWidth: 640,
            ),
          ),
        const SizedBox(height: 14),
        // `.letter-actions`: the figures, then Copy and Send now.
        Wrap(
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
                  icon: Icons.send_outlined,
                  onPressed: widget.onSend,
                ),
              ],
            ),
          ],
        ),
        if (_copyError != null) ...[
          const SizedBox(height: AppSpacing.s2),
          KitFailureInline(_copyError!),
        ],
        if (widget.sendError != null) ...[
          const SizedBox(height: AppSpacing.s2),
          KitFailureInline(widget.sendError!),
        ] else if (widget.sendMessage != null) ...[
          const SizedBox(height: AppSpacing.s2),
          KitRowNote(widget.sendMessage!),
        ],
      ],
    );
  }
}
