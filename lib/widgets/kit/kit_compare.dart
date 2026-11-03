import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart' show KitD;
import 'kit_text.dart';

// ── A picture already in the library: the row's line and the Compare sheet ──
//
// 5.51.0, ADR-202 addendum 1 (`screens/sources.md` §Compare; web
// `overlays/CompareCopySheet.jsx` and `app-responsive.css` `.cc-*`,
// `.proc-orig`). The sheet itself is §15's [KitOverlaySheet]; these are the
// parts inside it, and the one quiet line a copy's row gains.

/// `.proc-orig` — one quiet line under a copy's sentence: *In your library
/// since Oct 12 · from your camera roll*, or why the original could not be
/// drawn from. Sans 12.5 at `--fg-muted`, 4 under the sentence.
class KitProcOriginLine extends StatelessWidget {
  final String text;
  const KitProcOriginLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: KitText.note(context)),
      );
}

/// `.cc-cols` — the copy beside the original: two columns 18 apart, stacked
/// on a phone (web's 640; this client's phone width, `KitD.phone`).
class KitCompareColumns extends StatelessWidget {
  final Widget left;
  final Widget right;
  const KitCompareColumns({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) => Padding(
        // `.qa-body`: 16 20.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: KitD.phone(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [left, const SizedBox(height: 18), right],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 18),
                  Expanded(child: right),
                ],
              ),
      );
}

/// `.cc-col` — one side: its [eyebrow] (mono 10 caps `.14em`, `--fg-muted`),
/// its [stage], its [title] (sans 600 at `--fg`) and its [facts] (sans 13 at
/// `--fg-muted`, 2 apart), 8 apart. No title while its record is unread.
class KitCompareColumn extends StatelessWidget {
  final String eyebrow;
  final Widget stage;
  final String? title;
  final List<String> facts;

  const KitCompareColumn({
    super.key,
    required this.eyebrow,
    required this.stage,
    this.title,
    this.facts = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(eyebrow.toUpperCase(),
            style: KitText.capsLabel(context,
                fontSize: 10, letterSpacing: 0.14, color: t.fgMuted)),
        const SizedBox(height: 8),
        stage,
        if (title != null) ...[
          const SizedBox(height: 8),
          Text(title!, style: KitText.ui(context, weight: FontWeight.w600)),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            Text(facts[i], style: KitText.ui(context, color: t.fgMuted)),
          ],
        ],
      ],
    );
  }
}

/// `.cc-stage` — where a side's picture sits: 3:4, a 1px `--rule` edge at
/// `--r-md` on `--surface-sunken`, the picture contained in it. In place of
/// the picture: a centred `.cc-note` sentence ([KitCompareStage.note]), or
/// any region the caller hands it ([KitCompareStage.child] — the §14.1 block
/// a failed read is).
class KitCompareStage extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final String? note;
  final Widget? child;

  /// The picture's name for assistive technology.
  final String? label;

  /// Said in the picture's place when its bytes will not draw.
  final String unreadable;

  const KitCompareStage.image(String this.url,
      {super.key, this.label, required this.unreadable})
      : bytes = null,
        note = null,
        child = null;

  const KitCompareStage.bytes(Uint8List this.bytes,
      {super.key, this.label, required this.unreadable})
      : url = null,
        note = null,
        child = null;

  const KitCompareStage.note(String this.note, {super.key})
      : url = null,
        bytes = null,
        child = null,
        label = null,
        unreadable = '';

  const KitCompareStage.child(Widget this.child, {super.key})
      : url = null,
        bytes = null,
        note = null,
        label = null,
        unreadable = '';

  @override
  Widget build(BuildContext context) {
    final region = child;
    // A §14.1 block takes the region as it is; it is not framed as a picture.
    if (region != null) return region;
    final t = Tokens.of(context);
    Widget noteText(String s) => Padding(
          padding: const EdgeInsets.all(18),
          child: Text(s,
              textAlign: TextAlign.center,
              style: KitText.ui(context, color: t.fgMuted)),
        );
    Widget? picture;
    if (url != null) {
      picture = Image.network(url!,
          fit: BoxFit.contain,
          semanticLabel: label,
          errorBuilder: (_, _, _) => noteText(unreadable));
    } else if (bytes != null) {
      picture = Image.memory(bytes!,
          fit: BoxFit.contain,
          semanticLabel: label,
          errorBuilder: (_, _, _) => noteText(unreadable));
    }
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          border: Border.all(color: t.rule),
          borderRadius: AppRadius.mdR,
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: picture ?? noteText(note ?? ''),
      ),
    );
  }
}

/// `.qa-foot.cc-acts` — the sheet's choices, trailing, 8 apart, wrapping on a
/// narrow screen; §15's foot ground and rule are the sheet's own.
class KitCompareFoot extends StatelessWidget {
  final List<Widget> children;
  const KitCompareFoot({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: children,
        ),
      );
}
