import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/organization_suggestion.dart';
import '../../state/org_notifier.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';


/// The suggestion review queue (`screens/sources.md` §Suggestion review
/// queue) — one component for its two hosts, Sources' organization section
/// and For your review's *Suggested changes* (4.100.0). [suggestions] are the
/// host's pending list; the approvals this session made are followed to their
/// outcome through [OrgNotifier] either way, so an approval made on one screen
/// is still answered on the other.
class SuggestionQueue extends StatefulWidget {
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
  State<SuggestionQueue> createState() => _SuggestionQueueState();
}

/// The reference's `SuggestionQueue` (F-106): the cards, the **batch select**
/// the spec requires (§Suggestion review queue: "Approve/decline per card +
/// batch select (≤20/call)") — this client had per-card buttons only — one
/// resolve handler for both, and its refusal under the list.
class _SuggestionQueueState extends State<SuggestionQueue> {
  final Set<String> _selected = {};

  /// One resolve at a time, every control held while it runs — the
  /// reference's `busy`, which is the queue's and not a card's.
  bool _busy = false;
  String? _notice;

  void _toggle(String id) => setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  /// ≤20 ids a call, as the endpoint takes them. Approvals are followed to
  /// their outcome by [OrgNotifier.resolve].
  Future<void> _resolve(List<String> ids, String action) async {
    final org = context.read<OrgNotifier>();
    setState(() {
      _busy = true;
      _notice = null;
    });
    String? err;
    for (var i = 0; i < ids.length && err == null; i += 20) {
      err = await org.resolve(
          ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20), action);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = err;
      if (err == null) _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgNotifier>();
    final pending = widget.suggestions;
    final error = widget.error;
    final outcomes = org.outcomes;
    final eyebrow = widget.eyebrow;
    // A selection whose card has left the queue is not a selection.
    _selected.removeWhere((id) => !pending.any((x) => x.id == id));

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
    final n = _selected.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          error != null ? eyebrow : '$eyebrow · ${pending.length}',
          // The batch, beside the count while anything is chosen.
          tools: n == 0
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  KitSettingLink('Approve $n',
                      icon: null,
                      onTap: _busy
                          ? null
                          : () => _resolve([..._selected], 'approve')),
                  Text(' · ', style: KitText.small(context)),
                  KitSettingLink('Decline $n',
                      icon: null,
                      onTap: _busy
                          ? null
                          : () => _resolve([..._selected], 'decline')),
                ]),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(error),
          ),
        // `.proc-list`: one card per suggestion, 10 apart.
        for (var i = 0; i < pending.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SuggestionCard(
            key: ValueKey('sugg-${pending[i].id}'),
            suggestion: pending[i],
            selected: _selected.contains(pending[i].id),
            busy: _busy,
            onToggle: () => _toggle(pending[i].id),
            onResolve: (action) => _resolve([pending[i].id], action),
          ),
        ],
        // §14.2 — a refusal (a 400 `UNKNOWN_KEYS`, a 404) under the list, in
        // the server's words, as the reference draws its notice.
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KitFailureInline(_notice!),
          ),
        // What this session's approvals came to (4.92.0, ADR-126): the queue
        // reads `pending` only, so without these an approved card vanished
        // and a `failed` one — an interrupted move that may already have
        // landed — never reached the screen.
        // `.proc-list`, 10 apart, as the cards above.
        for (final o in outcomes) ...[
          const SizedBox(height: 10),
          _ApprovalOutcome(key: ValueKey('outcome-${o.id}'), suggestion: o),
        ],
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

  /// The reference's `ApprovalOutcome` (F-106): a `.proc-row` card with no
  /// badge — the title, then the *Applying* work pill or *Clear* — and a
  /// failure's sentence under it. It was a §4.1 row.
  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final failed = s.status == 'failed';
    return KitFolderCard(
      title: s.outcomeTitle,
      trailing: [
        if (failed)
          KitSettingLink('Clear',
              icon: null,
              onTap: () => context.read<OrgNotifier>().clearOutcome(s.id))
        else
          const KitProcPill('Applying', tone: KitProcTone.work),
      ],
      below: failed
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: KitFailureInline(
                  s.resolutionError ?? 'This change could not be made.',
                  dense: true),
            )
          : null,
    );
  }
}

/// One pending suggestion — the reference's `SuggestionCard`, a `.proc-row`
/// card (F-106): the selection box in the badge slot · the action as the
/// title, its subject in bold ("Move **taxes.pdf** → /Docs/Finance"; Notion's
/// move is a Copy, ADR-005 §3) over `from {path} · {reason}` · the
/// confidence as a work-tone pill · then Approve (or *Review plan…*) and
/// Decline. It was a §5.1 card titled by type ("Move a file") with a
/// "60% sure" status pill and no selection.
class _SuggestionCard extends StatelessWidget {
  final OrganizationSuggestion suggestion;
  final bool selected;
  final bool busy;
  final VoidCallback onToggle;
  final ValueChanged<String> onResolve;

  const _SuggestionCard({
    super.key,
    required this.suggestion,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    // The subject in the title's own face, bolder (`<strong>` in `.proc-title`).
    final bold = KitText.title(context,
        fontSize: 15, weight: FontWeight.w700, color: t.fg);
    final verb = s.type == 'move'
        ? (s.provider == 'notion' ? 'Copy' : 'Move')
        : s.type == 'placement'
            ? 'Place in'
            : '';
    final title = switch (s.type) {
      'move' => <InlineSpan>[
          TextSpan(text: '$verb '),
          TextSpan(text: s.fileName ?? 'file', style: bold),
          TextSpan(text: ' → ${s.toPath ?? ''}'),
        ],
      'placement' => <InlineSpan>[
          TextSpan(text: '$verb '),
          TextSpan(text: s.toPath ?? '', style: bold),
        ],
      'readme' => const <InlineSpan>[TextSpan(text: 'Adopt README edits')],
      'reorganize' =>
        const <InlineSpan>[TextSpan(text: 'Reorganize this document')],
      _ => <InlineSpan>[TextSpan(text: s.title)],
    };
    final sub = [
      if (s.type == 'move' && s.fromPath != null) 'from ${s.fromPath}',
      if (s.reason.isNotEmpty) s.reason,
    ].join(' · ');
    final actions = [
      // `reorganize` never executes from here (INV-13): the plan opens in
      // the reader, where its sheet is.
      if (s.type == 'reorganize')
        KitButton.primary('Review plan…',
            onPressed: busy || s.documentId == null
                ? null
                : () => context.push('/reader/${s.documentId}'))
      else
        // Pessimistic: the status transition arrives on the same
        // subscription, so nothing is rendered as done before it lands.
        KitButton.primary(busy ? 'Working…' : 'Approve',
            onPressed: busy ? null : () => onResolve('approve')),
      KitButton.ghost('Decline',
          onPressed: busy ? null : () => onResolve('decline')),
    ];
    return KitProcCard(
      kind: '',
      mark: SizedBox(
        width: 32,
        child: KitCheckbox(
          value: selected,
          onChanged: busy ? null : onToggle,
          semanticsLabel: 'Select suggestion',
        ),
      ),
      title: s.title,
      titleSpans: title,
      subtitle: sub,
      infoExtra: [
        // 4.92.0 (ADR-126 §3): approving a README adoption changes the
        // folder's charter and writes nothing at the provider — the card
        // says both, because "Approve" alone reads as a file operation.
        if (s.type == 'readme') ...[
          if (s.proposedCharter != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('“${s.proposedCharter}”',
                  style: KitText.monoMeta(context, letterSpacing: 0)
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          Text(s.adoptionNote,
              style: KitText.monoMeta(context, letterSpacing: 0)),
        ],
      ],
      pill: KitProcPill('${(s.confidence * 100).round()}%',
          tone: KitProcTone.work, spin: false),
      // `.proc-error-actions` with no strip: under the row, at its end on a
      // phone.
      foot: Padding(
        padding: EdgeInsets.only(left: compact ? 0 : 30, bottom: 14),
        child: Wrap(
          alignment: compact ? WrapAlignment.end : WrapAlignment.start,
          spacing: 6,
          runSpacing: 6,
          children: actions,
        ),
      ),
    );
  }
}
