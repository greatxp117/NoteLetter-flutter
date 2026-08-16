/// Pinned for the next letter (contract 2.33.0).
///
/// ADR-032 shipped the pin with a surface in the browser extension only, so a
/// pin could be MADE and then neither seen nor undone anywhere else — the one
/// place the product was incoherent between clients rather than merely
/// incomplete. This block states the three things a reader cannot otherwise
/// know, and is the only place a pin can be undone outside the extension.
library;

import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../models/newsletter_settings.dart';
import '../../services/api.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

class PinnedSources extends StatefulWidget {
  const PinnedSources({super.key, required this.settings});

  /// Read from settings, never defaulted. A letter carries at most HALF its
  /// items as pins, so the count is half of `itemsPerNewsletter` — guessing it
  /// would state a promise the letter does not make.
  final NewsletterSettings? settings;

  @override
  State<PinnedSources> createState() => _PinnedSourcesState();
}

class _PinnedSourcesState extends State<PinnedSources> {
  String? _busy;
  String? _error;

  Future<void> _unpin(Document doc) async {
    setState(() {
      _busy = doc.id;
      _error = null;
    });
    try {
      await Api.instance.setNextLetter(doc.id, false);
      // The subscription removes the row. Deliberately NOT optimistic: a row
      // that vanishes and comes back is worse than one that takes a moment.
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not unpin that.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return StreamBuilder<List<Document>>(
      stream: FirestoreService.instance.subscribePinnedDocuments(),
      builder: (context, snap) {
        final pinned = snap.data ?? const <Document>[];
        if (pinned.isEmpty) return const SizedBox.shrink();

        // At most half a letter's items are pins. Absent settings means we do
        // not KNOW the cap, so the sentence about how many arrive is omitted
        // rather than guessed.
        final perLetter = widget.settings?.itemsPerNewsletter;
        final cap = perLetter == null ? null : (perLetter / 2).floor();
        final overflow = cap != null && pinned.length > cap;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight),
            borderRadius: AppRadius.mdR,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pinned for the next letter',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              // What a reader cannot otherwise know: how many will actually
              // arrive, and that the rest are carried rather than dropped.
              // Nine pinned and two delivered is the rule, not a bug.
              if (cap != null)
                Text(
                  overflow
                      ? 'The next letter carries $cap of these. The rest stay '
                          'pinned and come in the letters after it.'
                      : 'These come in the next letter.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              const SizedBox(height: 10),
              for (final doc in pinned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(doc.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium),
                            // A pin on a source still being indexed is a WAIT,
                            // not a failure — it simply cannot be carried yet.
                            if (doc.status != DocumentStatus.complete)
                              Text(
                                doc.status == DocumentStatus.error
                                    ? 'This source could not be indexed, so it '
                                        'cannot be included.'
                                    : 'Still being indexed — it will be '
                                        'included once it is ready.',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // A LABELLED control, not a bare ×. The glyph every
                      // interface uses for "dismiss this notice" is the wrong
                      // affordance for the only undo a pin has, and a label is
                      // also what lets it say "Unpinning…" while in flight.
                      TextButton(
                        onPressed: _busy == doc.id ? null : () => _unpin(doc),
                        child: Text(_busy == doc.id ? 'Unpinning…' : 'Unpin'),
                      ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.critical)),
              ],
            ],
          ),
        );
      },
    );
  }
}
