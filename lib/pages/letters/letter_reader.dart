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

import '../../models/newsletter.dart';
import '../../shared/dates.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';
import 'delivery.dart';
import 'readings_letter.dart';

class LetterReaderView extends StatelessWidget {
  final Newsletter letter;
  final VoidCallback onBack;

  const LetterReaderView({
    super.key,
    required this.letter,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The actions bar is **outside** the sheet (§11), and it is the §1.3
        // utility bar: a back control naming where it returns to, the crumb,
        // and the actions.
        KitUtilityBar(
          // The back control NAMES where it returns to, and its chevron
          // LEADS — a trailing one reads as "go deeper".
          leading: KitButton('All letters',
              icon: Icons.chevron_left,
              variant: KitButtonVariant.ghost,
              onPressed: onBack),
          crumb: _crumb(letter),
        ),
        Expanded(
          child: KitScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
              child: letter.hasLetterhead
                  // Hosted bare: the object that was sent, on its own paper.
                  ? KitLetterPaper(letter.htmlBody)
                  : _framed(context, letter),
            ),
          ),
        ),
      ],
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

  /// The §11 sheet this client draws around a frame-less body.
  Widget _framed(BuildContext context, Newsletter n) {
    if (n.isScripture) return ReadingsLetterDocument(letter: n);

    final count = n.chunkIds.length;
    return KitLetterSheet(
      title: 'A Letter.',
      marker: n.subject,
      standfirst: n.lede.isEmpty ? null : n.lede,
      sealText: [
        '$count ${count == 1 ? 'passage' : 'passages'}',
        // The delivery axis has the last word about the mail (INV-23), and
        // `sent` is never rendered as "Delivered".
        letterBadge(
          status: n.status,
          deliveryState: n.delivery?.state,
          trigger: n.trigger,
        ).text,
      ].join(' · '),
      children: [KitLetterBody(n.htmlBody)],
    );
  }
}
