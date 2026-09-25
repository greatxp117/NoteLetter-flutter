/// Creating a shelf and filling it (contract 4.83.0, ADR-117, INV-29 —
/// `screens/library.md` §Creating a shelf, §Backfill review). Mirrors the
/// reference's `ShelfFormFields`, `ShelfBackfillReview` and `ShelfSheet` in
/// `NoteLetter-web/src/shared/ShelfForm.jsx`.
///
/// **One form for both entry points** — the rail's `+` and the Shelves index's
/// *New shelf* card — so the two cannot drift into creating shelves
/// differently. The index card had its own form until F-38: a name and a
/// colour, no description, so a shelf made on a phone carried nothing for the
/// backfill (or anything else embedded) to read.
library;

import 'package:flutter/material.dart';

import '../../services/analytics.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'reshelve_sheet.dart' show ApplyBackfill;
import 'shelf_parts.dart';

const shelfTitleMax = 50;
const shelfDescriptionMax = 300;

typedef CreateTag = Future<Map<String, dynamic>> Function(String title,
    {String? description, String? color});
typedef SuggestBackfill = Future<Map<String, dynamic>> Function(String tagId);

/// What the form hands on — only after `fn_create_tag` resolved.
class ShelfCreated {
  final String tagId;
  final String title;

  /// The reader asked to fill it AND there is something to fill it from.
  final bool backfill;
  const ShelfCreated(this.tagId, this.title, this.backfill);
}

/// A shelf the review reads for. [created] says where *Not now* goes: a
/// shelf this sheet just made is opened (it exists now, and the reader came to
/// make it); a shelf opened from its own page is simply left.
class BackfillFor {
  final String tagId;
  final String title;
  final bool created;
  const BackfillFor(this.tagId, this.title, {this.created = false});
}

/// §15's sheet (480) over whatever the reader was on. Opens at the form, or —
/// with [backfillFor] — straight at the review. Every exit that lands, lands
/// through [land] on the shelf, whose count arrives by subscription.
///
/// A write in flight holds the sheet open — scrim, back gesture and close
/// included — so a create or a filing cannot be dismissed into looking like it
/// never ran.
Future<void> showShelfSheet(
  BuildContext context, {
  required bool canBackfill,
  required ValueChanged<String> land,
  BackfillFor? backfillFor,
  CreateTag? create,
  SuggestBackfill? suggest,
  ApplyBackfill? apply,
}) {
  final holding = ValueNotifier<bool>(false);
  final heading = ValueNotifier<KitSheetHeading>(backfillFor == null
      ? _newHeading
      : _fillHeading(backfillFor.title));
  return KitOverlaySheet.show(
    context,
    icon: Icons.layers_outlined,
    title: heading.value.title,
    subtitle: heading.value.subtitle,
    width: 480,
    holding: holding,
    heading: heading,
    builder: (ctx) => ShelfSheetBody(
      canBackfill: canBackfill,
      backfillFor: backfillFor,
      onBusy: (b) => holding.value = b,
      onHeading: (h) => heading.value = h,
      close: () => Navigator.of(ctx).pop(),
      land: (id) {
        Navigator.of(ctx).pop();
        land(id);
      },
      create: create,
      suggest: suggest,
      apply: apply,
    ),
  ).whenComplete(() {
    holding.dispose();
    heading.dispose();
  });
}

const _newHeading =
    KitSheetHeading('New shelf', 'Group sources by subject or project.');
KitSheetHeading _fillHeading(String title) => KitSheetHeading('Fill $title',
    'Sources already in your library that belong on this shelf.');

/// The sheet's content: the form, then — when asked for — the review, in the
/// same sheet.
class ShelfSheetBody extends StatefulWidget {
  final bool canBackfill;
  final BackfillFor? backfillFor;
  final ValueChanged<bool> onBusy;
  final ValueChanged<KitSheetHeading> onHeading;
  final VoidCallback close;
  final ValueChanged<String> land;

  /// Seams for the widget test; default to the canonical builders.
  final CreateTag? create;
  final SuggestBackfill? suggest;
  final ApplyBackfill? apply;

  const ShelfSheetBody({
    super.key,
    required this.canBackfill,
    required this.onBusy,
    required this.onHeading,
    required this.close,
    required this.land,
    this.backfillFor,
    this.create,
    this.suggest,
    this.apply,
  });

  @override
  State<ShelfSheetBody> createState() => _ShelfSheetBodyState();
}

class _ShelfSheetBodyState extends State<ShelfSheetBody> {
  late BackfillFor? _review = widget.backfillFor;

  void _created(ShelfCreated c) {
    if (!c.backfill) {
      widget.land(c.tagId);
      return;
    }
    setState(() => _review = BackfillFor(c.tagId, c.title, created: true));
    widget.onHeading(_fillHeading(c.title));
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: review == null
          ? ShelfFormFields(
              canBackfill: widget.canBackfill,
              onCreated: _created,
              onCancel: widget.close,
              onBusy: widget.onBusy,
              create: widget.create,
            )
          : ShelfBackfillReview(
              key: ValueKey(review.tagId),
              tagId: review.tagId,
              title: review.title,
              onBusy: widget.onBusy,
              onDone: () => widget.land(review.tagId),
              onCancel: () =>
                  review.created ? widget.land(review.tagId) : widget.close(),
              suggest: widget.suggest,
              apply: widget.apply,
            ),
    );
  }
}

/// The form. [onCreated] runs only after the write resolved; a refusal stays
/// here with the server's sentence (§14.2) and nothing else changes — write
/// before you move. [canBackfill] is false when the library holds no complete
/// source: there is nothing to scan, so the choice is absent rather than a
/// no-op.
class ShelfFormFields extends StatefulWidget {
  final bool canBackfill;
  final ValueChanged<ShelfCreated> onCreated;
  final VoidCallback? onCancel;
  final ValueChanged<bool> onBusy;
  final String submitLabel;
  final CreateTag? create;

  const ShelfFormFields({
    super.key,
    required this.canBackfill,
    required this.onCreated,
    this.onCancel,
    this.onBusy = _noBusy,
    this.submitLabel = 'Create shelf',
    this.create,
  });

  static void _noBusy(bool _) {}

  @override
  State<ShelfFormFields> createState() => _ShelfFormFieldsState();
}

class _ShelfFormFieldsState extends State<ShelfFormFields> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _color = AppColors.shelfColors.keys.first;
  bool _backfill = true;
  bool _busy = false;
  String? _error;

  CreateTag get _create => widget.create ?? Api.instance.createTag;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _name.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusy(true);
    try {
      final res = await _create(title,
          description: _desc.text.trim(), color: _color);
      if (!mounted) return;
      final tagId = res['tagId'] as String?;
      if (tagId == null || tagId.isEmpty) {
        // A 2xx with no id is not a shelf we can open or fill.
        throw const ApiException(0, 'The shelf was not created.');
      }
      // `origin` says HOW a shelf came to exist, never its name.
      Analytics.track('shelf_created', {'origin': 'manual'});
      widget.onBusy(false);
      widget.onCreated(
          ShelfCreated(tagId, title, widget.canBackfill && _backfill));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _detail(e);
        _busy = false;
      });
      widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(
          context,
          'Name',
          KitTextField(
            key: const ValueKey('shelf-form-name'),
            controller: _name,
            placeholder: 'Shelf name…',
            face: KitFieldFace.serif,
            maxLength: shelfTitleMax,
            autofocus: true,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        _field(
          context,
          'What belongs here?',
          KitTextField(
            key: const ValueKey('shelf-form-description'),
            controller: _desc,
            placeholder: 'Optional — a sentence helps NoteLetter recognise '
                'what to file here.',
            maxLength: shelfDescriptionMax,
            face: KitFieldFace.sans,
            minLines: 2,
            maxLines: 4,
            enabled: !_busy,
          ),
        ),
        const SizedBox(height: 14),
        _field(
          context,
          'Colour',
          ShelfSwatches(
            selected: _color,
            enabled: !_busy,
            onPick: (name) => setState(() => _color = name),
          ),
        ),
        if (widget.canBackfill) ...[
          const SizedBox(height: 14),
          KitCheckRow(
            value: _backfill,
            title: 'Find sources that belong here',
            subtitle: 'NoteLetter reads your library and suggests sources '
                'for this shelf. Nothing is filed until you choose.',
            onChanged: _busy ? null : (v) => setState(() => _backfill = v),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          KitFailureInline(_error!),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            KitButton.primary(
              _busy ? 'Creating…' : widget.submitLabel,
              onPressed: _name.text.trim().isEmpty || _busy ? null : _submit,
            ),
            if (widget.onCancel != null)
              KitButton.ghost('Cancel',
                  onPressed: _busy ? null : widget.onCancel),
          ],
        ),
      ],
    );
  }

  /// `.sf-field`: a mono caps label at `--fg-subtle` over its control.
  Widget _field(BuildContext context, String label, Widget control) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: KitText.capsLabel(context,
                  color: Tokens.of(context).fgSubtle,
                  fontSize: 10,
                  letterSpacing: 0.1)),
          const SizedBox(height: 6),
          control,
        ],
      );
}

/// The review (INV-29): reading → proposal | nothing fits | failure.
///
/// The failure is a §14.1 block and is **never** drawn as "nothing fits": that
/// sentence is a considered answer from the model, and a read that did not
/// happen is not one. Applying keeps the sheet open until the call resolves
/// (§18 rule 1), and a refusal stays here with its sentence.
class ShelfBackfillReview extends StatefulWidget {
  final String tagId;
  final String title;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  final ValueChanged<bool> onBusy;
  final SuggestBackfill? suggest;
  final ApplyBackfill? apply;

  const ShelfBackfillReview({
    super.key,
    required this.tagId,
    required this.title,
    required this.onDone,
    required this.onCancel,
    this.onBusy = ShelfFormFields._noBusy,
    this.suggest,
    this.apply,
  });

  @override
  State<ShelfBackfillReview> createState() => _ShelfBackfillReviewState();
}

class _ShelfBackfillReviewState extends State<ShelfBackfillReview> {
  bool _reading = true;
  Object? _readError;
  int _scanned = 0;
  List<Map<String, dynamic>> _candidates = const [];
  final Set<String> _kept = {};
  bool _applying = false;
  String? _applyError;

  SuggestBackfill get _suggest =>
      widget.suggest ?? Api.instance.suggestShelfBackfill;
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
    try {
      final res = await _suggest(widget.tagId);
      if (!mounted) return;
      final candidates = [
        for (final c in (res['candidates'] as List?) ?? const [])
          (c as Map).cast<String, dynamic>(),
      ];
      setState(() {
        _scanned = (res['scanned'] as num?)?.toInt() ?? 0;
        _candidates = candidates;
        _kept
          ..clear()
          ..addAll(candidates.map((c) => c['documentId'] as String));
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

  Future<void> _file() async {
    if (_kept.isEmpty || _applying) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    widget.onBusy(true);
    try {
      // Pool order — the list the reader saw, top to bottom.
      final ids = [
        for (final c in _candidates)
          if (_kept.contains(c['documentId'])) c['documentId'] as String,
      ];
      await _apply(widget.tagId, ids);
      if (!mounted) return;
      widget.onBusy(false);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyError = _detail(e);
        _applying = false;
      });
      widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lede = KitText.reviewLede(context);
    final em = KitText.reviewEm(context);

    if (_readError != null) {
      final e = _readError!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KitFailureBlock(
            sentence:
                'Your library could not be matched against ${widget.title}.',
            detail: _detail(e),
            requestId: e is ApiException ? e.requestId : null,
            onRetry: _read,
          ),
          const SizedBox(height: 14),
          _actions([KitButton.ghost('Not now', onPressed: widget.onCancel)]),
        ],
      );
    }
    // No figure: `scanned` does not exist until the answer does.
    if (_reading) {
      return Text('Reading your library…', style: lede);
    }
    if (_candidates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'Nothing in your library looks like it belongs on '),
              TextSpan(text: widget.title, style: em),
              const TextSpan(text: ' yet.'),
            ]),
            style: lede,
          ),
          const SizedBox(height: 8),
          Text('New sources are still shelved as they are indexed.',
              style: KitText.ui(context, color: t.fgMuted)),
          const SizedBox(height: 14),
          _actions([KitButton.primary('Done', onPressed: widget.onCancel)]),
        ],
      );
    }

    final n = _kept.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${_candidates.length}', style: em),
            const TextSpan(text: ' of your '),
            TextSpan(text: '$_scanned', style: em),
            const TextSpan(text: ' sources look like they belong on '),
            TextSpan(text: widget.title, style: em),
            const TextSpan(text: '.'),
          ]),
          style: lede,
        ),
        const SizedBox(height: 14), // `.bf-review` gap
        Container(height: 1, color: t.rule),
        for (final c in _candidates) _row(t, c),
        if (_applyError != null) ...[
          const SizedBox(height: 10),
          KitFailureInline(_applyError!),
        ],
        const SizedBox(height: 14),
        _actions([
          KitButton.primary(
            _applying
                ? 'Filing…'
                : 'File $n ${n == 1 ? 'source' : 'sources'}',
            onPressed: n == 0 || _applying ? null : _file,
          ),
          KitButton.ghost('Not now',
              onPressed: _applying ? null : widget.onCancel),
        ]),
      ],
    );
  }

  Widget _row(Tokens t, Map<String, dynamic> c) {
    final id = c['documentId'] as String;
    final title = (c['title'] as String?) ?? '';
    final reason = (c['reason'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      child: KitCheckRow(
        key: ValueKey('backfill-row-$id'),
        value: _kept.contains(id),
        title: title.isEmpty ? 'Untitled' : title,
        subtitle: reason.isEmpty ? null : reason,
        dimWhenOff: true,
        onChanged: _applying
            ? null
            : (on) => setState(() => on ? _kept.add(id) : _kept.remove(id)),
      ),
    );
  }

  Widget _actions(List<Widget> buttons) =>
      Wrap(spacing: 8, runSpacing: 8, children: buttons);
}

String _detail(Object e) =>
    e is ApiException ? e.message : 'That request could not be completed.';
