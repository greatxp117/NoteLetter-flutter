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

import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// `{id, title}` — a captured source, or a remaining shelf.
class ReshelveItem {
  final String id;
  final String title;
  const ReshelveItem(this.id, this.title);
}

const reshelveSlice = 150;
const _unshelved = '';

typedef SuggestReshelve = Future<Map<String, dynamic>> Function(
    List<String> documentIds);
typedef ApplyBackfill = Future<Map<String, dynamic>> Function(
    String tagId, List<String> documentIds);

/// Opens §15's sheet on the review. Held open while a filing is in flight.
Future<void> showReshelveSheet(
  BuildContext context, {
  required String title,
  required List<ReshelveItem> sources,
  required List<ReshelveItem> shelves,
}) {
  final holding = ValueNotifier<bool>(false);
  return KitOverlaySheet.show(
    context,
    icon: Icons.drive_file_move_outline,
    title: 'Re-shelve $title',
    subtitle: 'The shelf is deleted. Choose where its sources go next.',
    width: 560,
    holding: holding,
    builder: (ctx) => ShelfReshelveReview(
      title: title,
      sources: sources,
      shelves: shelves,
      onBusy: (b) => holding.value = b,
      onDone: () => Navigator.of(ctx).pop(),
    ),
  ).whenComplete(holding.dispose);
}

class ShelfReshelveReview extends StatefulWidget {
  final String title;
  final List<ReshelveItem> sources;
  final List<ReshelveItem> shelves;
  final VoidCallback onDone;
  final ValueChanged<bool> onBusy;

  /// Seams for the widget test; default to the canonical builders.
  final SuggestReshelve? suggest;
  final ApplyBackfill? apply;

  const ShelfReshelveReview({
    super.key,
    required this.title,
    required this.sources,
    required this.shelves,
    required this.onDone,
    this.onBusy = _noBusy,
    this.suggest,
    this.apply,
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

  SuggestReshelve get _suggest =>
      widget.suggest ?? Api.instance.suggestReshelve;
  ApplyBackfill get _apply => widget.apply ?? Api.instance.applyShelfBackfill;

  @override
  void initState() {
    super.initState();
    _read();
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
    if (_reading) {
      return Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Finding new shelves for '),
          TextSpan(
              text: '$n',
              // kit-ok: span emphasis inside a kit role, not a type of its own
              style: const TextStyle(fontStyle: FontStyle.italic)),
          TextSpan(text: n == 1 ? ' source…' : ' sources…'),
        ]),
        style: KitText.lede(context),
      );
    }
    if (_shelfCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('You have no other shelves to move these sources to.',
              style: KitText.lede(context)),
          const SizedBox(height: 14),
          _actions([KitButton.primary('Done', onPressed: widget.onDone)]),
        ],
      );
    }

    final t = Tokens.of(context);
    final m = _proposals.length;
    final reasons = {
      for (final p in _proposals)
        p['documentId'] as String: (p['reason'] as String?) ?? ''
    };
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          m > 0
              ? '$m of $n sources from ${widget.title} have a suggested shelf.'
              : 'None of your shelves looked like a clear fit — choose one '
                  'for any source you want to file.',
          style: KitText.lede(context),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title.isEmpty ? 'Untitled' : s.title,
                    style: KitText.body(context)),
                if (reason != null && reason.isNotEmpty)
                  Text(reason,
                      style: KitText.meta(context)
                          .copyWith(color: t.fgMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (filed)
            Text('Filed', style: KitText.meta(context))
          else
            SizedBox(
              width: 200,
              child: KitSelect<String>(
                key: ValueKey('reshelve-pick-${s.id}'),
                value: tagId,
                options: [_unshelved, for (final sh in widget.shelves) sh.id],
                label: (id) => id.isEmpty
                    ? 'Leave unshelved'
                    : widget.shelves
                            .where((sh) => sh.id == id)
                            .firstOrNull
                            ?.title ??
                        id,
                onChanged: _applying
                    ? null
                    : (v) => setState(() => _choice[s.id] = v),
              ),
            ),
        ],
      ),
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
