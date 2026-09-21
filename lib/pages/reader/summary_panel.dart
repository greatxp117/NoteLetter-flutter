import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';

/// Regenerate summary (spec/screens/reader.md §Regenerate summary, 4.3.0,
/// ADR-040).
///
/// **Non-optimistic**: the panel updates from the RESPONSE BODY via
/// [onRegenerated] — the reader document is a one-shot fetch, so there is no
/// subscription that would ever deliver the new fields, and re-fetching to
/// learn what we were just told is explicitly not the path.
///
/// A 429 is the 60s per-document cooldown and renders as **calm copy, never an
/// error state**: the summary on screen is still correct. Any failure leaves
/// the existing summary visible and untouched — the backend guarantees it
/// wrote nothing (ADR-040 §6), so there is nothing to roll back.
///
/// The two outcomes are drawn apart deliberately, as on the reference. A
/// cooldown is a condition the backend measured and the panel is still
/// correct, so it stays the calm note in the caption slot; anything else is a
/// request that did not complete, which is §14.2 beside the button that
/// refused it — carrying the server's own sentence, never a constant of ours
/// standing in for one (component-kit §14, ADR-070, C11).
class _RegenerateControl extends StatefulWidget {
  final String docId;
  final ValueChanged<Map<String, dynamic>> onRegenerated;
  const _RegenerateControl({required this.docId, required this.onRegenerated});

  @override
  State<_RegenerateControl> createState() => _RegenerateControlState();
}

class _RegenerateControlState extends State<_RegenerateControl> {
  bool _busy = false;
  String? _note;

  /// §14.2's line, composed once. Null on the cooldown branch — a wait is not
  /// a failure.
  String? _failure;

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
      _failure = null;
    });
    try {
      final res = await Api.instance.regenerateSummary(widget.docId);
      if (!mounted) return;
      widget.onRegenerated(res);
    } on ApiException catch (e) {
      // C6. The 429 branch was the sharper half: the cooldown sentence is the
      // SERVER's, because the endpoint knows how long is left and a constant
      // here ("give it a minute") is a guess that goes stale invisibly the
      // day the window changes. ADR-070 — quote what was sent, never
      // pattern-match a status into copy of ours. The constant survives for
      // exactly one case: a 429 that carried no sentence at all, which
      // `e.message` then fills with a phrase of `_handle`'s own that says
      // nothing about the wait (C11).
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 429) {
          _note = cooldownSentence(
              e, 'Just regenerated — give it a minute before trying again.');
        } else {
          _failure = 'The summary could not be regenerated — ${e.message}';
          // The reassurance goes in the caption, not after the sentence: the
          // server's half is often a fragment with no full stop and §14.2
          // renders it verbatim, so nothing may follow it on the line.
          _note = 'The existing one is unchanged.';
        }
      });
    } catch (_) {
      // A request that never reached a server has no sentence to quote, so
      // this arm keeps its constant and is right to.
      if (!mounted) return;
      setState(() => _note =
          'The summary could not be regenerated just now; the existing one is unchanged.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KitButton.secondary(
                _busy ? 'Regenerating…' : 'Regenerate summary',
                onPressed: _busy ? null : _regenerate,
              ),
              // 4.3.1: regenerate applies the CURRENT prompt, so a reader
              // looking at a summary they want different is one step from the
              // field that changes it. Permissive (SHOULD).
              KitSettingLink('Edit your summary style',
                  icon: Icons.arrow_forward,
                  onTap: () => context.go('/settings')),
            ],
          ),
          if (_failure != null) ...[
            const SizedBox(height: 8),
            KitFailureInline(_failure!),
          ],
          const SizedBox(height: 6),
          // The 429 is the 60s cooldown and reads as CALM COPY in the note's
          // own voice — never a §14 failure, because the summary on screen is
          // still correct and nothing was blanked.
          Lede(
            _note ??
                'Rewrites the summary, key points and themes under your summary '
                    'style. The title and passages don’t change.',
            fontSize: 14,
            height: 21,
            maxWidth: 440,
          ),
        ],
      ),
    );
  }
}

/// Reader → Summary panel: `summary`, `key_points`, `themes` off the document.
/// `questions` is deprecated and NEVER rendered (ADR-008), even when present on
/// pre-1.5.0 docs. Per reader.md.
class SummaryPanel extends StatelessWidget {
  final Document doc;

  /// Applied to the reader's in-memory document (4.3.0). Null hides the
  /// control — it is the reader page that owns the document.
  final ValueChanged<Map<String, dynamic>>? onRegenerated;

  const SummaryPanel({super.key, required this.doc, this.onRegenerated});

  bool get _canRegenerate =>
      onRegenerated != null && doc.status == DocumentStatus.complete;

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final hasSummary = (doc.summary?.isNotEmpty ?? false) ||
        doc.keyPoints.isNotEmpty ||
        doc.themes.isNotEmpty;

    if (!hasSummary) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ui.intro('Summary'),
          // The empty state is where regenerate matters MOST: it is what a
          // failed analysis parse leaves behind — so it IS the §7 offer here,
          // not a control stranded under an apology.
          ui.empty(
            Icons.auto_awesome_outlined,
            'No summary yet.',
            "This source hasn't been summarized.",
            // Bounded: §7's action row lays its children out with an
            // UNBOUNDED main axis, and the control wraps its button and link.
            action: _canRegenerate
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _RegenerateControl(
                        docId: doc.id, onRegenerated: onRegenerated!),
                  )
                : null,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Every section opens on its OWN eyebrow — §19's rail jumps to it, and
        // it is the label that does the work the tab label used to (ADR-100).
        // The page draws none: it tried to at 4.64.0 and every section got two,
        // which is what the fidelity pair caught.
        ui.intro('Summary'),
        if (doc.summary?.isNotEmpty ?? false) ui.note(doc.summary!),
        const SizedBox(height: 20),
        if (doc.themes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in doc.themes) KitTag(t)],
          ),
          const SizedBox(height: 24),
        ],
        if (doc.keyPoints.isNotEmpty) ...[
          // A mono caps label, as the reference sets it — the eyebrow opens the
          // PANEL and a second one inside it would read as a second panel.
          Text('Key points', style: KitText.capsLabel(context, fontSize: 11)),
          const SizedBox(height: 10),
          // Key points are prose the model wrote about the document, so they
          // take the reading serif and the reading measure — not the UI sans.
          KitText.readingMeasure(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final kp in doc.keyPoints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, right: 12),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: ui.subtle, shape: BoxShape.circle),
                          ),
                        ),
                        Expanded(
                          child:
                              Text(kp, style: KitText.bodyReading(context)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_canRegenerate)
          _RegenerateControl(docId: doc.id, onRegenerated: onRegenerated!),
      ],
    );
  }
}
