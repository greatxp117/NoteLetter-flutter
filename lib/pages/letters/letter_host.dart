/// The one host for a stored daily letter body — the Letters reader and the
/// letter-settings preview both render through it (4.98.0, ADR-131: "the same
/// host, not a second renderer"; a preview drawn any other way is a third look
/// for one object, ADR-087). Web `pages/letters/LetterHost.jsx`.
///
/// A body carrying `data-nl-letterhead` is the complete letter and is hosted
/// BARE on its own paper; framing it would draw the app's masthead above the
/// letter's own. A frame-less body written before 4.50.0 sits in the §11
/// sheet. The body is the backend's own deterministic render and is NOT
/// re-sanitised, rewritten, re-quoted, truncated or re-themed here.
library;

import 'package:flutter/widgets.dart';

import '../../models/newsletter.dart';
import '../../widgets/kit/kit.dart';
import 'delivery.dart';

class LetterHost extends StatelessWidget {
  final Newsletter letter;

  const LetterHost(this.letter, {super.key});

  @override
  Widget build(BuildContext context) {
    final n = letter;
    if (n.hasLetterhead) return KitLetterPaper(n.htmlBody);
    // A record with no `chunk_ids` draws no count rather than a `0` (ADR-109).
    final figures = n.chunkIdsKnown
        ? '${n.chunkIds.length} '
              '${n.chunkIds.length == 1 ? 'passage' : 'passages'}'
        : null;
    return KitLetterSheet(
      title: 'A Letter.',
      marker: n.subject,
      standfirst: n.lede.isEmpty ? null : n.lede,
      sealText: [
        ?figures,
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
