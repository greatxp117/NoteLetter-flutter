import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/error_text.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// One segment of the Priority row: what it is called and what it sends.
/// `null` is **Default** — `fn_update_document {sourcePriority: null}` hands
/// the source back to the default (0.5, the stamp deleted; ADR-155 §2).
typedef PriorityChoice = ({String id, String label, double? value});

/// `screens/reader.md` §Source priority — the reference's `PRIORITY_CHOICES`.
const List<PriorityChoice> priorityChoices = [
  (id: 'default', label: 'Default', value: null),
  (id: 'low', label: 'Low', value: 0.2),
  (id: 'normal', label: 'Normal', value: 0.5),
  (id: 'high', label: 'High', value: 0.8),
];

/// Which segment is lit — **read off the stamp, never the number** (ADR-155
/// §3). A stored 0.5 is the default or a choice and only
/// `source_priority_set_at` says which, so no stamp is Default whatever the
/// value. A stamped number lights the band it falls in (≤ 0.3 Low, ≥ 0.8
/// High, between Normal): a number another client chose is drawn, not
/// refused. The reference's `priorityChoice`.
String priorityChoice(Document doc) {
  if (doc.sourcePrioritySetAt == null) return 'default';
  final v = doc.sourcePriority;
  if (v == null) return 'default';
  if (v <= 0.3) return 'low';
  if (v >= 0.8) return 'high';
  return 'normal';
}

/// §Source priority (4.118.0, ADR-155; built on web 2026-10-12, ruled into the
/// reader 2026-10-13). Under the Shelves row and in its anatomy: the mono caps
/// label, a kit §34 Switch (§6.8's Segmented control until D), the stored
/// number in mono beside the label, and
/// one quiet line under them. A finished source's own settings — its shelves,
/// its priority and Delete — live here, the one screen about a single source
/// (ADR-138 §Rationale); the library rows carry no control (`sources.md`
/// §Per-source affordances).
///
/// **Write before you move.** The pressed segment reads *Saving…* and the
/// track is held until the call resolves; the document — and with it the lit
/// segment — changes only through [onSaved], after the server accepted the
/// write. A refusal renders under the row (§14.2) and nothing moves. Pressing
/// the lit segment sends nothing.
class SourcePriorityRow extends StatefulWidget {
  final String docId;
  final Document doc;

  /// The value the server accepted (`null` = Default). The reader commits it
  /// with [Document.withSourcePriority].
  final ValueChanged<double?> onSaved;

  /// Seam for the widget test; null is [Api.updateDocument].
  final Future<void> Function(String docId, double? value)? update;

  const SourcePriorityRow({
    super.key,
    required this.docId,
    required this.doc,
    required this.onSaved,
    this.update,
  });

  @override
  State<SourcePriorityRow> createState() => _SourcePriorityRowState();
}

class _SourcePriorityRowState extends State<SourcePriorityRow> {
  /// The segment whose write is in flight; while set the track is held.
  String? _busy;
  String? _error;

  Future<void> _choose(PriorityChoice c) async {
    if (_busy != null || c.id == priorityChoice(widget.doc)) return;
    setState(() {
      _busy = c.id;
      _error = null;
    });
    final run = widget.update ??
        (String id, double? v) =>
            Api.instance.updateDocument(id, {'sourcePriority': v});
    String? err;
    var saved = false;
    try {
      await run(widget.docId, c.value);
      saved = true;
    } on ApiException catch (e) {
      err = e.message;
    } catch (e) {
      err = describeSdkError(e);
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
    if (saved) widget.onSaved(c.value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final on = priorityChoice(widget.doc);
    final value = widget.doc.sourcePriority;

    final label = Text('PRIORITY', style: KitText.monoCaps(context));
    // The stored number, never one solved for: a document with none draws no
    // figure.
    final figure = value == null
        ? null
        : Text(value.toStringAsFixed(2),
            style: KitText.monoMeta(context,
                fontSize: 12, letterSpacing: 0.02, color: t.fgMuted));
    // Kit §34's sliding switch, the `pri` variant (§6.8's segmented control
    // until direction D). It moves only when `on` moves — after the write —
    // and while one is in flight the whole switch is held and the pressed
    // option says so.
    final track = KitSlideSwitch<String>(
      label: 'Priority',
      variant: KitSlideVariant.priority,
      held: _busy != null,
      value: on,
      options: [
        for (final c in priorityChoices)
          KitSlideOption(c.id, _busy == c.id ? 'Saving…' : c.label,
              disabled: _busy != null),
      ],
      onChanged: (id) =>
          _choose(priorityChoices.firstWhere((c) => c.id == id)),
    );
    const gapX = SizedBox(width: 10);
    const gapY = SizedBox(height: 8);

    // In Source details (kit §28): the label and the figure on one line, the
    // switch under them at its own width, then the quiet line — web's
    // `.doc-priority` wrap in the panel (reader-details, light and phone).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [label, if (figure != null) ...[gapX, figure]]),
        gapY,
        track,
        gapY,
        Text(
          'How much this source weighs in search and your letters — a '
          'nudge, not a guarantee.',
          style: KitText.note(context),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          KitFailureInline(_error!),
        ],
      ],
    );
  }
}
