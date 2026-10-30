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
import '../../widgets/kit/kit.dart';
import 'delivery.dart';
import 'letter_host.dart';
import 'letter_preview.dart' show copyLetter;
import 'readings_letter.dart';

/// Open in email: a `mailto:` carrying the subject (web `mailtoHref`). A URL
/// cannot carry the letter itself — a mailto body is plain text (RFC 6068) and
/// mail clients cap the URL — so the reader pastes what Copy put on the
/// clipboard.
Uri letterMailto(Newsletter n) {
  final subject = n.subject;
  return Uri.parse(
    subject == null || subject.isEmpty
        ? 'mailto:'
        : 'mailto:?subject=${Uri.encodeComponent(subject)}',
  );
}

/// A letter's title on a row or a masthead (web `letterTitle`): the subject
/// after *Your NoteLetter — *, else the whole subject, else *A Letter*.
String letterTitle(Newsletter n) {
  final s = n.subject ?? '';
  final parts = s.split(' — ');
  final rest = parts.length > 1 ? parts.sublist(1).join(' — ') : '';
  return rest.isNotEmpty ? rest : (s.isNotEmpty ? s : 'A Letter');
}

Future<bool> _launchMail(Uri uri) => launchUrl(uri);

/// One letter, opened (direction D, screens/letters.md §Composition *A
/// letter*; web `LetterRead.jsx`, the prototype's `LetterReadD`).
///
/// The crumb — §39's *All letters*, then `Letter · No. {n} · {long date}`
/// (`The readings letter · …`) — the letter's title and its lede (none for a
/// readings letter); the page's one action *Open in email* (short *Email*), and
/// no settings. The sheet *This letter*: its passages as Contents, read from
/// the drawn letter and following the scroll; its figures; *Copy the letter*.
/// The column: the letter as it was sent — a letterheaded body lifted as a
/// sheet (the screen's full width, unframed, on a phone), an older body in the
/// §11 frame, the readings letter its own document.
class LetterReaderView extends StatefulWidget {
  final Newsletter letter;
  final VoidCallback onBack;

  /// Opens the readings letter's live day view; null for a daily letter, which
  /// has no such surface.
  final VoidCallback? onSeeAll;

  /// Seams for the tests: the clipboard write, the mail handoff, and the host
  /// a letterheaded body is drawn in (a web view no widget test can mount).
  final Future<void> Function(Newsletter) copy;
  final Future<bool> Function(Uri) openMail;
  final Widget Function(Newsletter letter, Key Function(int i) headKey)? host;

  const LetterReaderView({
    super.key,
    required this.letter,
    required this.onBack,
    this.onSeeAll,
    this.copy = copyLetter,
    this.openMail = _launchMail,
    this.host,
  });

  @override
  State<LetterReaderView> createState() => _LetterReaderViewState();
}

class _LetterReaderViewState extends State<LetterReaderView> {
  bool _copied = false;
  String? _copyError;
  String? _mailError;

  late List<KitContentsItem> _heads = _headsOf(widget.letter);
  late final KitSections _sec = KitSections([for (final h in _heads) h.id]);

  @override
  void didUpdateWidget(LetterReaderView old) {
    super.didUpdateWidget(old);
    if (old.letter.id != widget.letter.id) {
      _heads = _headsOf(widget.letter);
      _sec.ids = [for (final h in _heads) h.id];
      _copied = false;
      _copyError = null;
      _mailError = null;
    }
  }

  @override
  void dispose() {
    _sec.dispose();
    super.dispose();
  }

  /// The letter's passages, as the drawn letter titles them (web reads the
  /// drawn DOM): each passage card's `<h2>` in a letterheaded letter
  /// ([kitLetterSections] reads the same tag), each reading's label in a
  /// readings letter. A frame-less body written before 4.50.0 names none.
  static List<KitContentsItem> _headsOf(Newsletter n) {
    String clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
    final labels = n.isScripture
        ? (n.status == 'empty'
              ? const <String>[]
              : [
                  for (final r in n.readings)
                    if (r.label.trim().isNotEmpty) clean(r.label),
                ])
        : [for (final s in kitLetterSections(n)) clean(s.title)];
    return [
      for (var i = 0; i < labels.length; i++) KitContentsItem('p$i', labels[i]),
    ];
  }

  Key _headKey(int i) => _sec.keyOf('p$i');

  Future<void> _copy() async {
    setState(() {
      _copied = false;
      _copyError = null;
    });
    try {
      await widget.copy(widget.letter);
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

  Future<void> _mail() async {
    setState(() => _mailError = null);
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
    setState(
      () => _mailError =
          'No mail app could be opened on this device. '
          'Copy the letter and paste it into one.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.letter;
    final readings = n.isScripture;
    final head = kitLetterHead(n);
    final count = n.chunkIdsKnown ? n.chunkIds.length : null;
    final badge = letterBadge(
      status: n.status,
      deliveryState: n.delivery?.state,
      trigger: n.trigger,
    );
    final note = deliveryNote(
      state: n.delivery?.state,
      detail: n.delivery?.detail,
      attempts: n.delivery?.attempts ?? 0,
    );
    final date = longDate(n.generatedAt);
    final title = readings ? 'Readings for $date' : letterTitle(n);
    final lede = readings ? '' : n.ledeOf(220);
    // A record with no body (a pre-2.24.0 readings letter) has nothing to
    // copy, and says so by being held.
    final canCopy = n.htmlBody.isNotEmpty;

    final Widget body;
    if (readings) {
      body = ReadingsLetterDocument(
        letter: n,
        onSeeAll: widget.onSeeAll,
        headKey: _headKey,
        inset: false,
      );
    } else if (n.hasLetterhead) {
      // The letter as it was sent, hosted BARE on its own paper (ADR-087) —
      // lifted as a sheet, or the screen's whole width on a phone.
      body = KitLiftedLetter(
        child:
            widget.host?.call(n, _headKey) ?? LetterHost(n, headKey: _headKey),
      );
    } else {
      // A frame-less body sits in the §11 sheet, through the one host the
      // letter-settings preview shares (ADR-131).
      body = LetterHost(n, inset: false);
    }

    return KitDPage(
      key: ValueKey('d-letter-${n.id}'),
      back: KitDBackControl('All letters', onTap: widget.onBack),
      // On a phone the back control stands over the folio (web's phone frame).
      crumbStacks: true,
      folio: [
        readings ? 'The readings letter' : 'Letter',
        if (head.no != null) 'No. ${head.no}',
        if (date.isNotEmpty) date,
      ].join(' · '),
      title: title,
      stand: lede.isEmpty ? null : lede,
      action: KitPageAction(
        label: 'Open in email',
        short: 'Email',
        icon: Icons.open_in_new,
        onPressed: _mail,
      ),
      // §14.2 under the masthead: the handoff that went nowhere, beside the
      // action that was pressed.
      under: _mailError == null ? null : KitSendLine(failure: _mailError),
      sections: _sec,
      sheet: KitDSheet(
        label: 'This letter',
        foldOnPick: true,
        peek: KitLetterPeek(
          no: head.no,
          title: title,
          count: count,
          items: _heads,
          sections: _sec,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_heads.isNotEmpty) ...[
              const KitDLabel('Passages', first: true),
              KitContents(items: _heads, sections: _sec, label: 'Passages'),
            ],
            KitFigures(
              label: 'This letter',
              rows: [
                ('Sent', date.isEmpty ? '—' : date),
                if (count != null) ('Passages', '$count'),
                if (count != null) ('Reading time', '~${count + 1} min'),
                // The delivery axis has the last word about the mail
                // (INV-23), and `sent` is never rendered as "Delivered".
                ('Delivery', badge.text),
              ],
            ),
            if (note != null) KitDNote(note),
            KitSheetAlso(
              children: [
                if (_copyError != null) KitFailureInline(_copyError!),
                KitAlsoButton(
                  _copied ? 'Copied' : 'Copy the letter',
                  key: const ValueKey('d-letter-copy'),
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  onTap: canCopy ? _copy : null,
                ),
              ],
            ),
          ],
        ),
      ),
      child: body,
    );
  }
}
