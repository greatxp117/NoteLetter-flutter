import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/organization_suggestion.dart';
import '../../state/org_notifier.dart';
import '../../widgets/kit/kit.dart';


/// The suggestion review queue (`screens/sources.md` §Suggestion review
/// queue) — one component for its two hosts, Sources' organization section
/// and For your review's *Suggested changes* (4.100.0). [suggestions] are the
/// host's pending list; the approvals this session made are followed to their
/// outcome through [OrgNotifier] either way, so an approval made on one screen
/// is still answered on the other.
class SuggestionQueue extends StatelessWidget {
  final String eyebrow;
  final List<OrganizationSuggestion> suggestions;

  /// The host's subscription failure, when the host draws it here. For your
  /// review draws its own §14.1 block in the group's place instead.
  final String? error;

  const SuggestionQueue({
    super.key,
    required this.eyebrow,
    required this.suggestions,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgNotifier>();
    final pending = suggestions;
    final error = this.error;
    final outcomes = org.outcomes;

    // No suggestions and unreadable suggestions are the same empty list
    // downstream, and this section's answer to empty is to vanish (C3).
    if (error != null && pending.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(eyebrow),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KitFailureInline(error),
          ),
        ],
      );
    }
    if (pending.isEmpty && outcomes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            error != null ? eyebrow : '$eyebrow · ${pending.length}'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error),
          ),
        // What this session's approvals came to (4.92.0, ADR-126): the queue
        // reads `pending` only, so without these an approved card vanished
        // and a `failed` one — an interrupted move that may already have
        // landed — never reached the screen.
        if (outcomes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KitRowList(rows: [
              for (final o in outcomes)
                _ApprovalOutcome(
                    key: ValueKey('outcome-${o.id}'), suggestion: o),
            ]),
          ),
        for (final s in pending)
          _SuggestionCard(key: ValueKey('sugg-${s.id}'), suggestion: s),
      ],
    );
  }
}

/// One approval this session made, until it lands: `approved` works
/// (spinner), `failed` says the worker's sentence verbatim (§14.2) and offers
/// Clear. `applied` never reaches here — the notifier drops it.
class _ApprovalOutcome extends StatelessWidget {
  final OrganizationSuggestion suggestion;
  const _ApprovalOutcome({super.key, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final failed = s.status == 'failed';
    final row = KitSourceRow(
      title: s.outcomeTitle,
      trailing: failed
          ? KitButton.ghost('Clear',
              onPressed: () =>
                  context.read<OrgNotifier>().clearOutcome(s.id))
          : const KitStatusPill('Applying'),
    );
    if (!failed) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
          child: KitFailureInline(
              s.resolutionError ?? 'This change could not be made.',
              dense: true),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  final OrganizationSuggestion suggestion;
  const _SuggestionCard({super.key, required this.suggestion});

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  /// §14.2 — the resolve's refusal on the card it is about (a 400
  /// `UNKNOWN_KEYS`, a 404), not a toast that is gone before it is read.
  String? _error;

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    final org = context.read<OrgNotifier>();
    final busy = org.isResolving(suggestion.id);

    Future<void> act(String action) async {
      setState(() => _error = null);
      final err = await org.resolve([suggestion.id], action);
      if (mounted) setState(() => _error = err);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KitCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(suggestion.title, style: KitText.h4(context))),
                const SizedBox(width: 12),
                KitStatusPill('${(suggestion.confidence * 100).round()}% sure'),
              ],
            ),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(suggestion.reason,
                  style: KitText.lede(context, fontSize: 15, height: 22)),
            ],
            if (suggestion.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(suggestion.detail, style: KitText.meta(context)),
            ],
            // 4.92.0 (ADR-126 §3): approving a README adoption changes the
            // folder's charter and writes nothing at the provider — the card
            // says both, because "Approve" alone reads as a file operation.
            if (suggestion.type == 'readme') ...[
              const SizedBox(height: 4),
              Text(suggestion.adoptionNote, style: KitText.meta(context)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              KitFailureInline(_error!),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (busy) ...[
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                ],
                KitButton.ghost('Decline',
                    onPressed: busy ? null : () => act('decline')),
                const SizedBox(width: 8),
                // Pessimistic: the status transition arrives on the same
                // subscription, so nothing is rendered as done before it lands.
                KitButton.primary('Approve',
                    onPressed: busy ? null : () => act('approve')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

