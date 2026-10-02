/// Re-shelving what a deleted shelf held (contract 4.85.0, ADR-119, INV-29 —
/// `screens/library.md` §Re-shelve review). Mirrors the reference's
/// `ShelfReshelveReview` in `NoteLetter-web/src/shared/ShelfForm.jsx`.
///
/// `sources` were captured BEFORE the delete — after it, no query can find
/// them. Every source gets a row and a picker preset to the proposal: the one
/// the model could not place is the one the reader most needs to choose for.
/// Filing is one `fn_apply_shelf_backfill` per destination, in turn; a shelf
/// already filed is not re-sent on retry.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tag.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../state/tags_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'shelf_sheet.dart' show showShelfSheet;

/// `{id, title}` — a captured source.
class ReshelveItem {
  final String id;
  final String title;
  const ReshelveItem(this.id, this.title);
}

const reshelveSlice = 150;

/// The re-shelve review **from a stored proposal** (4.101.0, ADR-136 —
/// `screens/review.md` §Proposals): a `shelf_delete` task's `result` (the
/// `fn_suggest_reshelve` body) seeds the rows, and filing is ONE
/// `fn_resolve_task apply` with every assignment — the writer reports what it
/// could not file in `skipped`, which the sheet says before Done.
class StoredReshelve {
  /// The task and the moment its proposal landed: a later snapshot of the same
  /// proposal must not re-seed the reader's choices.
  final String key;
  final Map<String, dynamic> result;

  /// Complete members past the 500 the capture holds — said, never hidden.
  final int unconsidered;
  final Future<Map<String, dynamic>> Function(
      List<Map<String, String>> assignments) apply;

  const StoredReshelve({
    required this.key,
    required this.result,
    required this.unconsidered,
    required this.apply,
  });
}
const _unshelved = '';

typedef SuggestReshelve = Future<Map<String, dynamic>> Function(
    List<String> documentIds);
typedef ApplyBackfill = Future<Map<String, dynamic>> Function(
    String tagId, List<String> documentIds);

/// Opens the re-shelve review over a stored `shelf_delete` proposal, in a §15
/// sheet: rows from `capture.sources`, presets from `result.proposals`, the
/// selects over the live shelves (`deleting` ones are already gone from the
/// tags stream). Not now closes it and the proposal keeps waiting.
Future<void> showStoredReshelveSheet(
  BuildContext context, {
  required String title,
  required String deletedId,
  required List<ReshelveItem> sources,
  required StoredReshelve stored,
}) {
  final holding = ValueNotifier<bool>(false);
  return KitOverlaySheet.show(
    context,
    icon: Icons.drive_file_move_outline,
    title: 'Re-shelve $title',
    subtitle: 'The shelf is deleted. Choose where its sources go next.',
    width: 560,
    holding: holding,
    builder: (ctx) => Consumer<TagsNotifier>(
      builder: (ctx, tags, _) => ShelfReshelveReview(
        title: title,
        sources: sources,
        shelves: [
          for (final t in tags.tags)
            if (t.id != deletedId) t,
        ],
        stored: stored,
        onBusy: (b) => holding.value = b,
        onDone: () => Navigator.of(ctx).pop(),
      ),
    ),
  ).whenComplete(holding.dispose);
}

class ShelfReshelveReview extends StatefulWidget {
  final String title;
  final List<ReshelveItem> sources;

  /// Every remaining shelf — whole tags, for the §20.2 selects.
  final List<Tag> shelves;
  final VoidCallback onDone;
  final ValueChanged<bool> onBusy;

  /// Seams for the widget test; default to the canonical builders.
  final SuggestReshelve? suggest;
  final ApplyBackfill? apply;

  /// Set: the review of a stored proposal (no read, one apply).
  final StoredReshelve? stored;

  /// A row's create row, with the query; default opens §Creating a shelf's
  /// form, and calls back with the new id once `fn_create_tag` resolved.
  final void Function(String name, ValueChanged<String> created)? create;

  const ShelfReshelveReview({
    super.key,
    required this.title,
    required this.sources,
    required this.shelves,
    required this.onDone,
    this.onBusy = _noBusy,
    this.suggest,
    this.apply,
    this.create,
    this.stored,
  });

  static void _noBusy(bool _) {}

  @override
  State<ShelfReshelveReview> createState() => _ShelfReshelveReviewState();
}

class _ShelfReshelveReviewState extends State<ShelfReshelveReview> {
  bool _reading = true;
  Object? _readError;
  int _shelfCount = 0;
  List<Map<String, dynamic>> _proposals = const [];
  final Map<String, String> _choice = {};
  final Set<String> _filed = {};
  bool _applying = false;
  String? _applyError;

  /// A stored apply that could not file everything: `{filed, skipped}`.
  Map<String, dynamic>? _summary;

  SuggestReshelve get _suggest =>
      widget.suggest ?? Api.instance.suggestReshelve;
  ApplyBackfill get _apply => widget.apply ?? Api.instance.applyShelfBackfill;

  @override
  void initState() {
    super.initState();
    final stored = widget.stored;
    if (stored != null) {
      _seed(stored.result);
    } else {
      _read();
    }
  }

  @override
  void didUpdateWidget(covariant ShelfReshelveReview old) {
    super.didUpdateWidget(old);
    final stored = widget.stored;
    if (stored != null && stored.key != old.stored?.key) _seed(stored.result);
  }

  void _seed(Map<String, dynamic> result) {
    final proposals = [
      for (final x in (result['proposals'] as List?) ?? const [])
        (x as Map).cast<String, dynamic>(),
    ];
    _choice
      ..clear()
      ..addEntries(widget.sources.map((s) => MapEntry(s.id, _unshelved)));
    for (final p in proposals) {
      _choice[p['documentId'] as String] = p['tagId'] as String;
    }
    _proposals = proposals;
    _shelfCount = (result['shelves'] as num?)?.toInt() ?? 0;
    _reading = false;
  }

  Future<void> _applyStored(StoredReshelve stored) async {
    final assignments = [
      for (final s in widget.sources)
        if ((_choice[s.id] ?? _unshelved).isNotEmpty)
          {'documentId': s.id, 'tagId': _choice[s.id]!},
    ];
    if (assignments.isEmpty) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    widget.onBusy(true);
    try {
      final res = await stored.apply(assignments);
      if (!mounted) return;
      final sk = (res['skipped'] as Map?)?.cast<String, dynamic>() ?? const {};
      int n(String k) => ((sk[k] as List?) ?? const []).length;
      final missed = n('deleted') + n('not_ready') + n('shelf_gone');
      setState(() => _applying = false);
      widget.onBusy(false);
      if (missed > 0) {
        setState(() => _summary = {'filed': res['filed'] ?? 0, 'skipped': sk});
        return;
      }
      widget.onDone();
    } catch (e) {
      // §18 rule 2's shape: the sheet stays, with the sentence.
      if (!mounted) return;
      setState(() {
        _applyError = _detail(e);
        _applying = false;
      });
      widget.onBusy(false);
    }
  }

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _readError = null;
    });
    final ids = [for (final s in widget.sources) s.id];
    final slices = <List<String>>[
      for (var i = 0; i < ids.length; i += reshelveSlice)
        ids.sublist(i, (i + reshelveSlice).clamp(0, ids.length)),
    ];
    try {
      // Any failed slice fails the whole read: a partial answer would present
      // the rest as sources nothing fits (INV-29).
      final parts = await Future.wait(slices.map(_suggest));
      if (!mounted) return;
      var shelves = 0;
      final proposals = <Map<String, dynamic>>[];
      for (final p in parts) {
        final n = (p['shelves'] as num?)?.toInt() ?? 0;
        if (n > shelves) shelves = n;
        for (final x in (p['proposals'] as List?) ?? const []) {
          proposals.add((x as Map).cast<String, dynamic>());
        }
      }
      setState(() {
        _choice
          ..clear()
          ..addEntries(widget.sources.map((s) => MapEntry(s.id, _unshelved)));
        for (final p in proposals) {
          _choice[p['documentId'] as String] = p['tagId'] as String;
        }
        _proposals = proposals;
        _shelfCount = shelves;
        _reading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _readError = e;
        _reading = false;
      });
    }
  }

  int get _pending => widget.sources.where((s) {
        final t = _choice[s.id] ?? _unshelved;
        return t.isNotEmpty && !_filed.contains(t);
      }).length;

  Future<void> _file() async {
    if (_applying) return;
    final stored = widget.stored;
    if (stored != null) return _applyStored(stored);
    final groups = <String, List<String>>{};
    for (final s in widget.sources) {
      final t = _choice[s.id] ?? _unshelved;
      if (t.isNotEmpty && !_filed.contains(t)) {
        (groups[t] ??= []).add(s.id);
      }
    }
    if (groups.isEmpty) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    widget.onBusy(true);
    for (final entry in groups.entries) {
      try {
        await _apply(entry.key, entry.value);
        if (!mounted) return;
        setState(() => _filed.add(entry.key));
      } catch (e) {
        if (!mounted) return;
        final name = widget.shelves
                .where((s) => s.id == entry.key)
                .firstOrNull
                ?.title ??
            'a shelf';
        setState(() {
          _applyError = '$name: ${_detail(e)}';
          _applying = false;
        });
        widget.onBusy(false);
        return;
      }
    }
    widget.onBusy(false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final n = widget.sources.length;
    if (_readError != null) {
      final e = _readError!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KitFailureBlock(
            sentence: 'New shelves could not be suggested for these sources.',
            detail: _detail(e),
            requestId: e is ApiException ? e.requestId : null,
            onRetry: _read,
          ),
          const SizedBox(height: 14),
          _actions([KitButton.ghost('Not now', onPressed: widget.onDone)]),
        ],
      );
    }
    // `.bf-lede` is KitText.reviewLede (upright serif 17 at fg) with the
    // figures and the shelf name in reviewEm — not the italic standfirst
    // `lede`, which set the whole answer italic and muted (F-38's finding).
    final lede = KitText.reviewLede(context);
    final em = KitText.reviewEm(context);
    if (_reading) {
      return Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Finding new shelves for '),
          TextSpan(text: '$n', style: em),
          TextSpan(text: n == 1 ? ' source…' : ' sources…'),
        ]),
        style: lede,
      );
    }
    if (_shelfCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('You have no other shelves to move these sources to.',
              style: lede),
          const SizedBox(height: 14),
          _actions([KitButton.primary('Done', onPressed: widget.onDone)]),
        ],
      );
    }

    final summary = _summary;
    if (summary != null) {
      final sk = summary['skipped'] as Map<String, dynamic>;
      int k(String key) => ((sk[key] as List?) ?? const []).length;
      final said = [
        if (k('deleted') > 0)
          '${k('deleted')} ${k('deleted') == 1 ? 'was' : 'were'} deleted since '
              'this was suggested',
        if (k('not_ready') > 0)
          '${k('not_ready')} ${k('not_ready') == 1 ? 'is' : 'are'} being '
              'processed again',
        if (k('shelf_gone') > 0)
          '${k('shelf_gone')} ${k('shelf_gone') == 1 ? 'was' : 'were'} going '
              'to a shelf that is gone',
      ];
      final filed = (summary['filed'] as num).toInt();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Filed '),
              TextSpan(text: '$filed', style: em),
              TextSpan(
                  text: ' ${filed == 1 ? 'source' : 'sources'}. Of the rest, '
                      '${said.join('; ')} — those were left as they are.'),
            ]),
            style: lede,
          ),
          const SizedBox(height: 14),
          _actions([KitButton.primary('Done', onPressed: widget.onDone)]),
        ],
      );
    }

    final t = Tokens.of(context);
    final m = _proposals.length;
    final unconsidered = widget.stored?.unconsidered ?? 0;
    final reasons = {
      for (final p in _proposals)
        p['documentId'] as String: (p['reason'] as String?) ?? ''
    };
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m > 0)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$m', style: em),
              const TextSpan(text: ' of '),
              TextSpan(text: '$n', style: em),
              const TextSpan(text: ' sources from '),
              TextSpan(text: widget.title, style: em),
              const TextSpan(text: ' have a suggested shelf.'),
            ]),
            style: lede,
          )
        else
          Text(
            'None of your shelves looked like a clear fit — choose one for '
            'any source you want to file.',
            style: lede,
          ),
        if (unconsidered > 0)
          KitProcNote(
              '$unconsidered more ${unconsidered == 1 ? 'source' : 'sources'} '
              'on this shelf ${unconsidered == 1 ? 'was' : 'were'} not asked '
              'about.'),
        const SizedBox(height: 12),
        for (final s in widget.sources)
          _row(context, t, s, _choice[s.id] ?? _unshelved, reasons[s.id]),
        if (_applyError != null) ...[
          const SizedBox(height: 10),
          KitFailureInline(_applyError!),
        ],
        const SizedBox(height: 14),
        _actions([
          KitButton.primary(
            _applying
                ? 'Filing…'
                : 'File $pending ${pending == 1 ? 'source' : 'sources'}',
            onPressed: pending == 0 || _applying ? null : _file,
          ),
          KitButton.ghost('Not now',
              onPressed: _applying ? null : widget.onDone),
        ]),
      ],
    );
  }

  Widget _row(BuildContext context, Tokens t, ReshelveItem s, String tagId,
      String? reason) {
    final filed = tagId.isNotEmpty && _filed.contains(tagId);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title.isEmpty ? 'Untitled' : s.title,
            style: KitText.body(context)),
        if (reason != null && reason.isNotEmpty)
          Text(reason,
              style: KitText.meta(context).copyWith(color: t.fgMuted)),
      ],
    );
    final control = filed
        ? Text('Filed', style: KitText.meta(context))
        : KitShelfSelect(
            key: ValueKey('reshelve-pick-${s.id}'),
            value: tagId,
            shelves: widget.shelves,
            none: 'Leave unshelved',
            label: 'Shelf for ${s.title.isEmpty ? 'Untitled' : s.title}',
            disabled: _applying,
            onChanged: (v) => setState(() => _choice[s.id] = v),
            onCreate: (name) => _create(name, (id) {
              if (mounted) setState(() => _choice[s.id] = id);
            }),
          );
    // `.rs-row`: the select beside the title, gap 10; at ≤ 560 it drops under
    // the title and takes the whole line.
    final phone = MediaQuery.sizeOf(context).width <= 560;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 10), control],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 10),
                control,
              ],
            ),
    );
  }

  void _create(String name, ValueChanged<String> created) {
    final seam = widget.create;
    if (seam != null) return seam(name, created);
    showShelfSheet(
      context,
      canBackfill: true,
      land: null,
      initialName: name,
      createSubtitle: "It becomes this source's choice. Nothing is filed "
          'until you choose File.',
      onCreated: created,
    );
  }

  Widget _actions(List<Widget> buttons) => Wrap(
        spacing: 10,
        runSpacing: 8,
        children: buttons,
      );
}

String _detail(Object e) =>
    e is ApiException ? e.message : 'That request could not be completed.';
