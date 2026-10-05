/// One letter, opened.
///
/// **The letter decides its own frame** (4.50.0, ADR-087). A body carrying
/// `data-nl-letterhead` is the complete letter — seal, masthead, folio, theme,
/// note, contents, cards and foot — and is hosted BARE; framing it would draw
/// the app's masthead above the letter's own. A body without the attribute is
/// the frame-less card list every letter written before 4.50.0 holds, and this
/// client draws the §11 sheet around it as it always did.
///
/// Deciding by the ATTRIBUTE rather than by a version or a date is what lets an
/// archive of both shapes render correctly, in either deploy order.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/newsletter.dart';
import '../../services/error_text.dart';
import '../../shared/dates.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';
import 'letter_host.dart';
import 'letter_preview.dart' show copyLetter;
import 'readings_letter.dart';

/// Open in email: a `mailto:` carrying the subject (web `mailtoHref`). A URL
/// cannot carry the letter itself — a mailto body is plain text (RFC 6068) and
/// mail clients cap the URL — so the reader pastes what Copy put on the
/// clipboard.
Uri letterMailto(Newsletter n) {
  final subject = n.subject;
  return Uri.parse(subject == null || subject.isEmpty
      ? 'mailto:'
      : 'mailto:?subject=${Uri.encodeComponent(subject)}');
}

Future<bool> _launchMail(Uri uri) => launchUrl(uri);

class LetterReaderView extends StatelessWidget {
  final Newsletter letter;
  final VoidCallback onBack;

  /// Opens the readings letter's live day view; null for a daily letter, which
  /// has no such surface.
  final VoidCallback? onSeeAll;

  /// Seams for the tests: the clipboard write and the mail handoff.
  final Future<void> Function(Newsletter) copy;
  final Future<bool> Function(Uri) openMail;

  const LetterReaderView({
    super.key,
    required this.letter,
    required this.onBack,
    this.onSeeAll,
    this.copy = copyLetter,
    this.openMail = _launchMail,
  });

  @override
  Widget build(BuildContext context) {
    return _LetterBar(
      letter: letter,
      onBack: onBack,
      crumb: _crumb(letter),
      copy: copy,
      openMail: openMail,
      body: Expanded(
          child: KitScrollView(
            // A letter with its own letterhead is hosted BARE, flush under
            // the bar — web `.letter-sheet` has "no padding that would fight
            // the letter's own"; a band of app ground above the paper was a
            // frame the sent object does not have. The frame-less shapes keep
            // theirs (`.letter-page`).
            child: letter.hasLetterhead
                ? LetterHost(letter)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                    // Scripture has its own document; a daily letter goes
                    // through the one host the letter-settings preview shares
                    // (ADR-131).
                    child: letter.isScripture
                        ? ReadingsLetterDocument(
                            letter: letter, onSeeAll: onSeeAll)
                        : LetterHost(letter),
                  ),
          ),
      ),
    );
  }

  static String _crumb(Newsletter n) {
    if (n.isScripture) {
      return 'Readings · ${longDate(n.generatedAt)}';
    }
    final subject = n.subject;
    return (subject != null && subject.isNotEmpty)
        ? subject
        : longDate(n.generatedAt);
  }
}

/// The reader's bar (`.lr-bar`, letters.md §Composition *The letter*): the back
/// control, the crumb, then **Copy** and **Open in email**. Both were absent
/// here — web drew them with no handler until 4.98.0 (`d153111`), and this
/// client never drew them at all.
class _LetterBar extends StatefulWidget {
  final Newsletter letter;
  final VoidCallback onBack;
  final String crumb;
  final Future<void> Function(Newsletter) copy;
  final Future<bool> Function(Uri) openMail;
  final Widget body;

  const _LetterBar({
    required this.letter,
    required this.onBack,
    required this.crumb,
    required this.copy,
    required this.openMail,
    required this.body,
  });

  @override
  State<_LetterBar> createState() => _LetterBarState();
}

class _LetterBarState extends State<_LetterBar> {
  bool _copied = false;
  String? _error;

  /// The back control and both labelled actions need about 392px — measured
  /// on iPhone 17 Pro's 402. Narrower, the actions keep their glyphs and lose
  /// their labels, which is the reference's own phone rule
  /// (`.lr-actions .btn span { display: none }`) — a row that overflows is not
  /// a smaller version of the bar, it is a broken one.
  static const double _labelledWidth = 400;

  Future<void> _copy() async {
    setState(() {
      _copied = false;
      _error = null;
    });
    try {
      await widget.copy(widget.letter);
      if (!mounted) return;
      setState(() => _copied = true);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = 'The letter could not be copied — ${describeSdkError(e)}');
    }
  }

  Future<void> _mail() async {
    setState(() => _error = null);
    var opened = false;
    try {
      opened = await widget.openMail(letterMailto(widget.letter));
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened) return;
    // A handoff that went nowhere is said, never swallowed: launchUrl answers
    // false when no mail app is set up, and a control that does nothing reads
    // exactly like one that worked.
    setState(() => _error = 'No mail app could be opened on this device. '
        'Copy the letter and paste it into one.');
  }

  @override
  Widget build(BuildContext context) {
    final labelled =
        MediaQuery.sizeOf(context).width >= _labelledWidth;
    final canCopy = widget.letter.htmlBody.isNotEmpty;
    final copyLabel = _copied ? 'Copied' : 'Copy';
    final copyIcon = _copied ? Icons.check : Icons.copy_outlined;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The actions bar is **outside** the sheet (§11), and it is the §1.3
        // utility bar: a back control naming where it returns to, the crumb,
        // and the actions.
        KitUtilityBar(
          // The back control NAMES where it returns to, and its chevron
          // LEADS — a trailing one reads as "go deeper".
          leading: KitButton(
            'All letters',
            icon: Icons.chevron_left,
            variant: KitButtonVariant.ghost,
            onPressed: widget.onBack,
          ),
          crumb: widget.crumb,
          actions: labelled
              ? [
                  // A record with no body (a pre-2.24.0 readings letter) has
                  // nothing to copy, and says so by being disabled.
                  KitButton.ghost(copyLabel,
                      icon: copyIcon, onPressed: canCopy ? _copy : null),
                  KitButton.secondary('Open in email',
                      icon: Icons.open_in_new, onPressed: _mail),
                ]
              : [
                  KitIconButton(copyIcon,
                      tooltip: copyLabel, onPressed: canCopy ? _copy : null),
                  KitIconButton(Icons.open_in_new,
                      tooltip: 'Open in email', onPressed: _mail),
                ],
        ),
        // §14.2 beside the control that refused — under the bar, since a 48px
        // bar has no room for a sentence.
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4, AppSpacing.s2, AppSpacing.s4, 0),
            child: KitFailureInline(_error!),
          ),
        widget.body,
      ],
    );
  }
}
