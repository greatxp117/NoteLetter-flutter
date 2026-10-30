/// Pinned for the next letter (contract 2.33.0).
///
/// ADR-032 shipped the pin with a surface in the browser extension only, so a
/// pin could be MADE and then neither seen nor undone anywhere else — the one
/// place the product was incoherent between clients rather than merely
/// incomplete. This block states the three things a reader cannot otherwise
/// know, and is the only place a pin can be undone outside the extension.
library;

import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../models/newsletter_settings.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/error_text.dart';
import '../../services/firestore_service.dart';
import '../../widgets/kit/kit.dart';

/// In direction D the block is part of the Letters sheet (screens/letters.md
/// §Composition *Letters*, sheet 3): sheet rows under a mono caps label —
/// the source's title (opening it, where the page passes [onOpen]), what is
/// keeping it, and the labelled *Unpin* (web `PinnedSources.jsx`).
class PinnedSources extends StatefulWidget {
  const PinnedSources({super.key, required this.settings, this.onOpen});

  /// Read from settings, never defaulted. A letter carries at most HALF its
  /// items as pins, so the count is half of `itemsPerNewsletter` — guessing it
  /// would state a promise the letter does not make.
  final NewsletterSettings? settings;

  /// Opens a pinned source in the reader.
  final void Function(Document doc)? onOpen;

  @override
  State<PinnedSources> createState() => _PinnedSourcesState();
}

class _PinnedSourcesState extends State<PinnedSources> {
  String? _busy;
  String? _error;

  /// One subscription for the block's life (INV-02). Opened in a build it
  /// was a NEW query on every rebuild of the page around it.
  late final Stream<List<Document>> _pins = FirestoreService.instance
      .subscribePinnedDocuments();

  Future<void> _unpin(Document doc) async {
    setState(() {
      _busy = doc.id;
      _error = null;
    });
    try {
      await Api.instance.setNextLetter(doc.id, false);
      // The subscription removes the row. Deliberately NOT optimistic: a row
      // that vanishes and comes back is worse than one that takes a moment.
    } on ApiException catch (e) {
      // C6: the server's sentence, not four words of ours. A pin that is
      // already gone, one that belongs to a letter already sent, and an
      // expired session are three different answers, and this rendered one.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'That could not be unpinned. Please check your connection and '
              'try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// What the next letter carries (web, verbatim): all of them, or the cap
  /// and where the rest go. Null while the cap is unread — a guess there is a
  /// wrong promise.
  static String? _sentence(int pinned, int? cap) {
    if (cap == null || pinned == 0) return null;
    final arriving = pinned < cap ? pinned : cap;
    final carried = pinned - arriving;
    if (arriving == pinned) {
      return '${pinned == 1 ? 'One source' : 'All $pinned sources'} will be '
          'carried, ahead of everything else.';
    }
    return '$arriving of $pinned will be carried — a letter is never more '
        'than half pins. The other '
        '${carried == 1 ? 'one arrives' : '$carried arrive'} in the letter '
        'after.';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Document>>(
      stream: _pins,
      builder: (context, snap) {
        // §14.2 before the empty check (C3). `snap.data ?? const []` made a
        // failed stream and an empty one one value, and the panel's answer to
        // empty is to REMOVE ITSELF — so a reader who had pinned sources for
        // the next letter saw no panel at all, which reads as having pinned
        // nothing. A StreamBuilder that never asks `hasError` cannot tell the
        // two apart (INV-24, ADR-071).
        if (snap.hasError) {
          return KitPinnedBlock(
            rows: const [],
            error: describeSdkError(snap.error!),
          );
        }

        final pinned = snap.data ?? const <Document>[];
        if (pinned.isEmpty) return const SizedBox.shrink();

        // At most half a letter's items are pins. Absent settings means we do
        // not KNOW the cap, so the sentence about how many arrive is omitted
        // rather than guessed — and no row is called overflow.
        final perLetter = widget.settings?.itemsPerNewsletter;
        final cap = perLetter == null ? null : (perLetter / 2).floor();

        return KitPinnedBlock(
          sentence: _sentence(pinned.length, cap),
          error: _error,
          rows: [
            for (var i = 0; i < pinned.length; i++)
              KitPinnedRow(
                key: ValueKey('d-pin-${pinned[i].id}'),
                title: pinned[i].title.isEmpty ? 'Untitled' : pinned[i].title,
                // Overflow is carried, never dropped: dimmed, not struck.
                overflow: cap != null && i >= cap,
                // A pin on a source still being read is a WAIT, not a
                // failure — the build skips it and keeps the pin. One that
                // could not be read says so.
                note: pinned[i].status == DocumentStatus.error
                    ? 'This source could not be indexed, so it cannot be '
                          'included.'
                    : pinned[i].status != DocumentStatus.complete
                    ? 'still being read — it keeps its place'
                    : (cap != null && i >= cap)
                    ? 'in the letter after'
                    : null,
                onOpen: widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(pinned[i]),
                // HELD while its write is in flight (kit §6.1, ruled by
                // Xavier 2026-10-14): steady at the held opacity, no taps;
                // the row leaves only when the subscription says so.
                busy: _busy == pinned[i].id,
                onUnpin: () => _unpin(pinned[i]),
              ),
          ],
        );
      },
    );
  }
}
