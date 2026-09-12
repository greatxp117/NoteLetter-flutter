import 'package:flutter/widgets.dart';
import '../../shared/extraction_markers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §17 · Extraction marker (4.52.0, ADR-089).
///
/// A marker is a statement ABOUT the document made by the extractor, not a
/// sentence in it. Drawn in the body type role the two are indistinguishable —
/// a 4.50.0 letter closed a quotation with *"[On screen: 10 habits that make
/// you ridiculously well spoken]."* and every gate was green.
///
/// Two shapes, chosen by what the marker sits in (the §14 split, for the same
/// reason): its own block is the **aside** ([KitMarkerAside], §17.1); inside a
/// run of text it is **inline** ([KitMarkerInline] / [KitMarkedText], §17.2).
/// Semantic tokens only, and **no ground fill** — `--fg-subtle` on
/// `--surface-sunken` is 4.12:1, under the small-text floor (ADR-073); a
/// leading rule on the parent's own ground never enters that pair.
///
/// Position is meaning: a marker is rendered where it sits in document order,
/// never hoisted, grouped or collapsed. Never stripped, either (§17).

/// §17.1 — a marker that is its own block (the transcript case).
///
/// Required parts, in order: the channel name in `.caps-label`, then the body
/// as sans copy. No glyph, no action, no dismiss, no timestamp of its own.
/// Full-width inside the reading measure, 2px leading rule in `--rule` with
/// 12px after it, 10px above and below; label 10px at `--fg-subtle`, 3px
/// below it the body sans 14/21 at `--fg-muted`. Not a card: no radius, no
/// shadow, no raised surface.
class KitMarkerAside extends StatelessWidget {
  final String label;
  final String body;

  const KitMarkerAside({super.key, required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.rule, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: KitText.capsLabel(context,
                  fontSize: 10, color: t.fgSubtle)),
          const SizedBox(height: 3),
          Text(
            body,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 14,
              height: 21 / 14,
              color: t.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// §17.2 — a marker inside a run of text (a caption, a search snippet, an Ask
/// citation, any single-line surface).
///
/// Required parts, in order: the channel name in `.caps-label`, then the body,
/// both at `--fg-subtle`, the whole run **quieter than the copy around it**.
/// No brackets — the label replaces them, and a rendered `[` is the defect.
/// Label 10px, body sans at 0.88em of the host, 0.4em of space before and
/// after the run. No rule, no ground, no radius: a block treatment inside a
/// sentence breaks the line box, which is the whole reason this shape exists.
///
/// [hostFontSize] is the size of the copy this sits in — the `em` the metrics
/// are relative to. Inside a [KitMarkedText] it is supplied for you.
class KitMarkerInline extends StatelessWidget {
  final String label;
  final String body;
  final double hostFontSize;

  const KitMarkerInline({
    super.key,
    required this.label,
    required this.body,
    this.hostFontSize = 16,
  });

  /// The run as an [InlineSpan], so it sits in the line box of its host text.
  static InlineSpan span(BuildContext context, MarkerPiece piece,
      {required double hostFontSize}) {
    final t = Tokens.of(context);
    final gap = 0.4 * hostFontSize;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: piece.label.toUpperCase(),
              style: KitText.capsLabel(context, fontSize: 10, color: t.fgSubtle),
            ),
            if (piece.body.isNotEmpty) const TextSpan(text: ' '),
            TextSpan(
              text: piece.body,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 0.88 * hostFontSize,
                color: t.fgSubtle,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        span(context, MarkerPiece.mark(label, body),
            hostFontSize: hostFontSize),
      ]));
}

/// `chunk.text` with its markers drawn as §17.2 — the mirror of the web's
/// `MarkedText.jsx`.
///
/// `text` is the representation that carries `[Image: {alt}]` (the derivation
/// writes it there and never into `html`), so a client that annotates only
/// the HTML path fixes the reader and leaves the search row, the reading pane,
/// Ask and the letter exactly as they were. This is the other half. Inline,
/// always: these surfaces draw a snippet or a single line.
class KitMarkedText extends StatelessWidget {
  final String text;

  /// The host copy's style — the run is measured against its `fontSize`.
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  const KitMarkedText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final host = style.fontSize ?? 16;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final p in splitMarkers(text))
            p.isMark
                ? KitMarkerInline.span(context, p, hostFontSize: host)
                : TextSpan(text: p.text),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
