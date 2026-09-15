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

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final res = await Api.instance.regenerateSummary(widget.docId);
      if (!mounted) return;
      widget.onRegenerated(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _note = e.statusCode == 429
          ? 'Just regenerated — give it a minute before trying again.'
          : 'The summary could not be regenerated just now; the existing one is unchanged.');
    } catch (_) {
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
        // No eyebrow of its own: the reader's §19 rail stacks this section
        // under a §3 section header that says `Summary` (4.64.0, ADR-100), and
        // two headers on one section is the panel and the page each thinking
        // it opens the scroll.
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
