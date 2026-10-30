/// Suggest shelves (4.116.0, ADR-153; ruled 2026-10-08 — `screens/library.md`
/// §Suggesting shelves, `screens/onboarding.md`). Mirrors the reference's
/// `shared/SuggestShelves.jsx`.
///
/// What you read about → `fn_suggest_tags`'s proposals → keep the ones you
/// tick → one `fn_approve_tags`. The endpoint is stateless, so asking writes
/// nothing and may be repeated; the only write is the create, and it waits for
/// the reader's tick.
///
/// **Two hosts, one composition**: the §15 sheet opened beside *New shelf*
/// (which creates at once) and onboarding's shelves step (which holds the
/// ticks and creates on Finish — the wizard writes nothing before its last
/// step). Both read [ShelfSuggestions], so the two cannot answer the same
/// request two ways.
library;

import 'package:flutter/material.dart';

import '../../services/analytics.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import 'shelf_sheet.dart' show RequestBackfill, requestShelfBackfill;

/// `fn_suggest_tags`' own bound on `purposeText` (§6.9: the field enforces the
/// server's bound and draws no counter).
const purposeMax = 2000;

typedef SuggestTags = Future<Map<String, dynamic>> Function(String purposeText);
typedef ApproveTags = Future<Map<String, dynamic>> Function(
    List<Map<String, dynamic>> tags);

/// What a client may WRITE as a shelf's colour: one of the twenty (library.md
/// §Shelf color — "clients do not write hex"). A proposal outside the twenty
/// takes a swatch by position, so a kept shelf is born inside the set its
/// picker can show.
String proposalColor(Object? color, int i) {
  final names = AppColors.shelfColorLabels.keys.toList();
  return color is String && names.contains(color) ? color : names[i % names.length];
}

/// A refusal of what was typed (a 4xx) is the reader's to correct, beside the
/// button (§14.2). Anything else — a provider failure, a body that is not our
/// envelope, no answer at all — is a region that could not load (§14.1), and
/// is NEVER drawn as "no shelves to suggest": that sentence is the model's
/// considered answer, and a request that did not complete is not one.
bool correctable(Object e) =>
    e is ApiException && e.statusCode >= 400 && e.statusCode < 500;

String _detail(Object e) =>
    e is ApiException ? e.message : 'That request could not be completed.';

String _counted(int n, String one, String many) => '$n ${n == 1 ? one : many}';

class ShelfProposal {
  final String title;
  final String description;
  final Object? color;
  const ShelfProposal(this.title, this.description, this.color);
}

enum SuggestPhase { ask, reading, review }

/// The state both hosts share (web `useShelfSuggestions`).
class ShelfSuggestions extends ChangeNotifier {
  ShelfSuggestions({String seed = '', SuggestTags? suggest})
      : field = TextEditingController(text: seed),
        _suggest = suggest ?? Api.instance.suggestTags;

  final TextEditingController field;
  final SuggestTags _suggest;

  /// The seed holds until the reader types in the field (onboarding hands it
  /// the mission they wrote one step earlier).
  bool _typed = false;

  SuggestPhase phase = SuggestPhase.ask;

  /// §14.2 — the server's sentence for a refusal of what was typed.
  String? askError;

  /// §14.1 — a read that did not complete.
  Object? readError;

  List<ShelfProposal> tags = const [];

  /// 4.116.0 (ADR-153): shelves the reader already has, which the endpoint
  /// left out — said, so a short list is not a mystery.
  List<String> existing = const [];

  final Set<int> kept = {};

  void seed(String text) {
    if (!_typed && field.text != text) field.text = text;
  }

  void typed() {
    _typed = true;
    notifyListeners();
  }

  Future<void> ask() async {
    final purpose = field.text.trim();
    if (purpose.isEmpty || phase == SuggestPhase.reading) return;
    phase = SuggestPhase.reading;
    askError = null;
    readError = null;
    notifyListeners();
    try {
      final res = await _suggest(purpose);
      final list = <ShelfProposal>[
        for (final t in (res['tags'] as List? ?? const []))
          if (t is Map && t['title'] is String && (t['title'] as String).trim().isNotEmpty)
            ShelfProposal((t['title'] as String).trim(),
                ((t['description'] as String?) ?? '').trim(), t['color']),
      ];
      tags = list;
      existing = [
        for (final e in (res['existing'] as List? ?? const []))
          if (e is String && e.trim().isNotEmpty) e,
      ];
      kept
        ..clear()
        ..addAll(List.generate(list.length, (i) => i));
      phase = SuggestPhase.review;
    } catch (e) {
      if (correctable(e)) {
        askError = _detail(e);
      } else {
        readError = e;
      }
      phase = SuggestPhase.ask;
    }
    notifyListeners();
  }

  void toggle(int i) {
    kept.contains(i) ? kept.remove(i) : kept.add(i);
    notifyListeners();
  }

  /// Back to the field, the words kept.
  void back() {
    phase = SuggestPhase.ask;
    tags = const [];
    existing = const [];
    kept.clear();
    readError = null;
    notifyListeners();
  }

  /// What a create sends — the kept proposals in the order shown, each
  /// `{title, description, color}` (fn_approve_tags' per-shelf keys), the
  /// colour one of the twenty.
  List<Map<String, dynamic>> get chosen => [
        for (var i = 0; i < tags.length; i++)
          if (kept.contains(i))
            {
              'title': tags[i].title,
              'description': tags[i].description,
              'color': proposalColor(tags[i].color, i),
            },
      ];

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }
}

/// The field (§6.9, the sans face — a sentence) and the ask; [actions] are the
/// host's others, after the primary.
class SuggestAsk extends StatelessWidget {
  final ShelfSuggestions s;
  final bool autofocus;
  final List<Widget> actions;

  const SuggestAsk(
      {super.key, required this.s, this.autofocus = true, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final busy = s.phase == SuggestPhase.reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('WHAT DO YOU READ ABOUT?',
            style: KitText.capsLabel(context,
                color: Tokens.of(context).fgSubtle,
                fontSize: 10,
                letterSpacing: 0.1)),
        const SizedBox(height: 6),
        KitTextField(
          key: const ValueKey('suggest-purpose'),
          controller: s.field,
          face: KitFieldFace.sans,
          minLines: 4,
          maxLines: 6,
          maxLength: purposeMax,
          autofocus: autofocus,
          enabled: !busy,
          onChanged: (_) => s.typed(),
          placeholder: 'The subjects, projects and questions you keep coming '
              'back to — a sentence or two is enough.',
        ),
        if (s.askError != null) ...[
          const SizedBox(height: 10),
          KitFailureInline(s.askError!),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          KitButton.primary(busy ? 'Suggesting…' : 'Suggest shelves',
              onPressed: s.field.text.trim().isEmpty || busy ? null : s.ask),
          ...actions,
        ]),
      ],
    );
  }
}

/// §14.1 where the proposals would have been; its one action re-asks.
class SuggestFailure extends StatelessWidget {
  final ShelfSuggestions s;
  const SuggestFailure({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final e = s.readError;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: KitFailureBlock(
        sentence: 'Shelves could not be suggested.',
        detail: _detail(e),
        requestId: e is ApiException ? e.requestId : null,
        onRetry: s.ask,
      ),
    );
  }
}

/// The answer: a review lede over one check row per proposal, all ticked, dim
/// when unticked, then what was left out because the reader already has it.
/// An empty answer is the model's — said as one, drawn differently from a
/// failure; when everything it proposed was a shelf already, it says that.
class SuggestReview extends StatelessWidget {
  final ShelfSuggestions s;
  final bool disabled;
  const SuggestReview({super.key, required this.s, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lede = KitText.reviewLede(context);
    final em = KitText.reviewEm(context);
    final sub = KitText.ui(context, color: t.fgMuted);
    final have = s.existing.join(' · ');
    if (s.tags.isEmpty) {
      final already = s.existing.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              already
                  ? 'Every shelf NoteLetter would suggest for that is one you '
                      'already have.'
                  : 'NoteLetter had no shelves to suggest for that.',
              style: lede),
          const SizedBox(height: 8),
          Text(
              already
                  ? 'Already on your shelves: $have. Say more about what else '
                      'you read, and ask again.'
                  : 'Say a little more about what you read, and ask again.',
              style: sub),
        ],
      );
    }
    final n = s.tags.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'NoteLetter suggests '),
            TextSpan(text: '$n', style: em),
            TextSpan(
                text: ' ${n == 1 ? 'shelf' : 'shelves'} for what you read '
                    'about.'),
          ]),
          style: lede,
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: t.rule),
        for (var i = 0; i < n; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
            child: KitCheckRow(
              key: ValueKey('suggest-row-$i'),
              value: s.kept.contains(i),
              title: s.tags[i].title,
              subtitle:
                  s.tags[i].description.isEmpty ? null : s.tags[i].description,
              dimWhenOff: true,
              onChanged: disabled ? null : (_) => s.toggle(i),
            ),
          ),
        if (s.existing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Also suggested, and already on your shelves: $have.',
              style: sub.copyWith(height: 1.4)),
        ],
      ],
    );
  }
}

/// The sheet beside *New shelf* (§15, 480): iconbox the sparkle, *Suggest
/// shelves*, *Nothing is created until you choose.*
Future<void> showSuggestShelvesSheet(
  BuildContext context, {
  required bool canBackfill,
  SuggestTags? suggest,
  ApproveTags? approve,
  RequestBackfill? requestBackfill,
}) {
  final host = Navigator.of(context, rootNavigator: true).context;
  final holding = ValueNotifier<bool>(false);
  return KitOverlaySheet.show(
    context,
    icon: KitSparkle.icon,
    title: 'Suggest shelves',
    subtitle: 'Nothing is created until you choose.',
    width: 480,
    holding: holding,
    builder: (ctx) => SuggestShelvesBody(
      canBackfill: canBackfill,
      suggest: suggest,
      approve: approve,
      onBusy: (b) => holding.value = b,
      close: () => Navigator.of(ctx).pop(),
      onCreated: (titles, ids, backfill) => _announce(host, titles, ids,
          backfill: backfill, request: requestBackfill),
    ),
  ).whenComplete(holding.dispose);
}

/// Said after the sheet has gone, over what it covered (web `announce`), and
/// the follow-on fill asked for once per new shelf.
Future<void> _announce(BuildContext host, List<String> titles, List<String> ids,
    {required bool backfill, RequestBackfill? request}) async {
  if (!host.mounted) return;
  AppToast.show(host,
      'Created ${_counted(ids.length, 'shelf', 'shelves')} · ${titles.join(' · ')}',
      type: ToastType.success);
  if (!backfill || ids.isEmpty) return;
  final refusals = <String>[];
  for (final id in ids) {
    final refused = await (request ?? requestShelfBackfill)(id);
    if (refused != null) refusals.add(refused);
  }
  if (!host.mounted) return;
  final asked = ids.length - refusals.length;
  if (refusals.isNotEmpty) {
    AppToast.show(
        host,
        'Sources could not be looked for on '
        '${_counted(refusals.length, 'shelf', 'shelves')}. ${refusals.first}',
        type: ToastType.error);
  } else if (asked > 0) {
    AppToast.show(
        host,
        'Finding sources for ${_counted(asked, 'new shelf', 'new shelves')} '
        "in the background. You'll find them in For your review.");
  }
}

/// The Library sheet's body. Create is one `fn_approve_tags`; write before you
/// move — the sheet stays open (and holds its scrim and close, via [onBusy])
/// until it resolves, and a refusal keeps it open with the server's sentence.
class SuggestShelvesBody extends StatefulWidget {
  final bool canBackfill;
  final ValueChanged<bool> onBusy;
  final VoidCallback close;
  final void Function(List<String> titles, List<String> ids, bool backfill)
      onCreated;
  final SuggestTags? suggest;
  final ApproveTags? approve;

  const SuggestShelvesBody({
    super.key,
    required this.canBackfill,
    required this.onBusy,
    required this.close,
    required this.onCreated,
    this.suggest,
    this.approve,
  });

  @override
  State<SuggestShelvesBody> createState() => _SuggestShelvesBodyState();
}

class _SuggestShelvesBodyState extends State<SuggestShelvesBody> {
  late final ShelfSuggestions _s = ShelfSuggestions(suggest: widget.suggest)
    ..addListener(_changed);
  bool _backfill = true;
  bool _creating = false;
  String? _createError;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _s.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final chosen = _s.chosen;
    if (chosen.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    widget.onBusy(true);
    Map<String, dynamic> res;
    try {
      res = await (widget.approve ?? Api.instance.approveTags)(chosen);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _createError = _detail(e);
        _creating = false;
      });
      widget.onBusy(false);
      return;
    }
    final ids = [
      for (final id in (res['tagIds'] as List? ?? const []))
        if (id is String) id,
    ];
    for (var i = 0; i < ids.length; i++) {
      Analytics.track('shelf_created', {'origin': 'suggested'});
    }
    widget.onBusy(false);
    final backfill = widget.canBackfill && _backfill;
    widget.close();
    widget.onCreated([for (final c in chosen) c['title'] as String], ids,
        backfill);
  }

  @override
  Widget build(BuildContext context) {
    if (_s.phase == SuggestPhase.review) {
      final n = _s.chosen.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SuggestReview(s: _s, disabled: _creating),
          if (_s.tags.isNotEmpty && widget.canBackfill) ...[
            const SizedBox(height: 14),
            KitCheckRow(
              value: _backfill,
              title: 'Find sources that belong on them',
              subtitle: 'NoteLetter reads your library and suggests sources '
                  'for each new shelf. Nothing is filed until you choose.',
              onChanged: _creating ? null : (v) => setState(() => _backfill = v),
            ),
          ],
          if (_createError != null) ...[
            const SizedBox(height: 12),
            KitFailureInline(_createError!),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_s.tags.isNotEmpty)
              KitButton.primary(
                  _creating
                      ? 'Creating…'
                      : 'Create ${_counted(n, 'shelf', 'shelves')}',
                  onPressed: n == 0 || _creating ? null : _create),
            _s.tags.isNotEmpty
                ? KitButton.ghost('Change what I wrote',
                    onPressed: _creating ? null : _s.back)
                : KitButton.primary('Change what I wrote',
                    onPressed: _creating ? null : _s.back),
            KitButton.ghost('Not now',
                onPressed: _creating ? null : widget.close),
          ]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SuggestAsk(s: _s, actions: [
          KitButton.ghost('Cancel', onPressed: widget.close),
        ]),
        SuggestFailure(s: _s),
      ],
    );
  }
}
