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
import 'letter_host.dart';
import 'readings_letter.dart';

class LetterReaderView extends StatelessWidget {
  final Newsletter letter;
  final VoidCallback onBack;

  /// Opens the readings letter's live day view; null for a daily letter, which
  /// has no such surface.
  final VoidCallback? onSeeAll;

  const LetterReaderView({
    super.key,
    required this.letter,
    required this.onBack,
    this.onSeeAll,
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
          leading: KitButton(
            'All letters',
            icon: Icons.chevron_left,
            variant: KitButtonVariant.ghost,
            onPressed: onBack,
          ),
          crumb: _crumb(letter),
        ),
        Expanded(
          child: KitScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
              // Scripture has its own document; a daily letter goes through
              // the one host the letter-settings preview shares (ADR-131).
              child: letter.isScripture && !letter.hasLetterhead
                  ? ReadingsLetterDocument(letter: letter, onSeeAll: onSeeAll)
                  : LetterHost(letter),
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
}
