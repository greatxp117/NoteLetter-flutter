import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_headers.dart';
import 'kit_cards.dart';
import 'kit_text.dart';

/// One content image, as the manuscript rehosted it: the `data-nl-image-id`
/// content hash, the URL that draws it, and the machine caption.
///
/// Read out of the chunk HTML rather than out of `images[]`, exactly as the
/// reference does — `images[]` stores Storage object **paths**, which are not
/// renderable, while the manuscript's `<img>` already carries a URL that is.
class RecipeImage {
  final String id;
  final String url;
  final String caption;

  const RecipeImage({required this.id, required this.url, this.caption = ''});
}

/// Component kit §5.4 · Recipe body (4.6.0, ADR-042).
///
/// Not a card: a full body treatment that **replaces the passage cards** inside
/// the Reading frame, under the reader's existing header. A body swap, never a
/// new tab and never a second header.
///
/// Required parts, in this order — serif `.h1` title · lead figure · the §8
/// Stat cluster carrying **only the figures the source actually stated** ·
/// Ingredients (§3) over grouped lists · Method (§3) over an ordered list with
/// serif numerals and each step's bound figure inline · Notes · the gallery of
/// any image no step claimed.
///
/// Ingredients before Method, always: a cook reads the whole ingredient list
/// before starting, and the order is the pattern, not a preference.
///
/// Two rules that are easy to get wrong, both of them about not inventing:
///  - **Check state is client-local and unpersisted.** It is a cooking session,
///    not a fact about the document — nothing is written, no endpoint is
///    called, and it does not survive a reload. A client MUST NOT invent a
///    field for it.
///  - **A step time is never synthesised.** `start` is null far more often than
///    not (INV-20c makes the backend refuse rather than estimate) and the gap
///    is not a client's to fill.
class KitRecipeBody extends StatefulWidget {
  final Recipe recipe;

  /// The manuscript's images by content hash, for the lead, the step figures
  /// and the gallery.
  final List<RecipeImage> images;

  /// Where a step's time chip sends the reader when this document has real
  /// audio (`screens/reader.md` §Step jump, branch 1). Null when it has none —
  /// and then the chip is **not a control**: it renders as plain text rather
  /// than as something that looks live and does nothing.
  final ValueChanged<double>? onSeek;

  /// Branch 2 — a `source_url` on a platform that takes a time parameter
  /// (YouTube `?t=`). Resolved by the composing screen, which owns launching.
  final String? Function(double start)? deepLink;
  final ValueChanged<String>? onOpenLink;

  /// Opens one image full size, shared with the manuscript's own images.
  final void Function(RecipeImage image)? onOpenImage;

  const KitRecipeBody({
    super.key,
    required this.recipe,
    this.images = const [],
    this.onSeek,
    this.deepLink,
    this.onOpenLink,
    this.onOpenImage,
  });

  @override
  State<KitRecipeBody> createState() => _KitRecipeBodyState();
}

class _KitRecipeBodyState extends State<KitRecipeBody> {
  /// The cooking session. Local, unpersisted, and deliberately not a field.
  final Set<String> _checked = <String>{};

  RecipeImage? _image(String? id) {
    if (id == null) return null;
    for (final im in widget.images) {
      if (im.id == id) return im;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final gallery = r.gallery.map(_image).whereType<RecipeImage>().toList();
    final lead = gallery.isNotEmpty ? gallery.first : null;
    final rest = gallery.length > 1 ? gallery.sublist(1) : const <RecipeImage>[];

    // Only the figures the source actually stated. An absent stat is ABSENT —
    // not a zero and not an em-dash, because a placeholder reads as a measured
    // value (§8).
    final stats = <KitStat>[
      if (r.yield_ != null) KitStat(r.yield_!, 'Yield'),
      if (r.prepTime != null) KitStat(r.prepTime!, 'Prep'),
      if (r.cookTime != null) KitStat(r.cookTime!, 'Cook'),
      if (r.totalTime != null) KitStat(r.totalTime!, 'Total'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §5.4: "Title serif 28/1.15/500 (the header's scale)" — not the
        // page `.h1`, which set a recipe's name at twice the reader's own.
        Text(r.title,
            style: AppTheme.serif(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.018 * 28,
              color: Tokens.of(context).fg,
            )),
        if (lead != null) ...[
          const SizedBox(height: AppSpacing.s4),
          KitFigure(
              url: lead.url,
              caption: lead.caption,
              onOpen: widget.onOpenImage == null
                  ? null
                  : () => widget.onOpenImage!(lead),
            ),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          // The `--ruled` modifier, and this is the surface it is FOR: a
          // full-width report band across the measure, not a header inside a
          // frame (§8, corrected at 4.46.0).
          KitStatCluster(stats: stats, ruled: true),
        ],
        // §5.4 names these a §3 **Section header**, whose one required part is
        // a caps eyebrow — and §5.4's own reference metrics say nothing about
        // the heading at all. The web draws `.rc-h`, serif 20/500, which is a
        // different type role from the one the pattern names; this client
        // follows the spec, by Xavier's decision (2026-09-14), and the web's
        // spelling is booked as the half to reconcile.
        const SectionHeader('Ingredients'),
        for (var gi = 0; gi < r.ingredients.length; gi++)
          _Group(
            group: r.ingredients[gi],
            // A group heading is rendered only where the SOURCE grouped: a
            // single-group recipe shows none.
            showLabel: r.ingredients.length > 1 &&
                (r.ingredients[gi].group?.isNotEmpty ?? false),
            isChecked: (i) => _checked.contains('$gi:$i'),
            onToggle: (i) => setState(() {
              final key = '$gi:$i';
              _checked.contains(key) ? _checked.remove(key) : _checked.add(key);
            }),
          ),
        const SectionHeader('Method'),
        for (var si = 0; si < r.steps.length; si++)
          _Step(
            index: si,
            step: r.steps[si],
            image: _image(r.steps[si].imageId),
            onSeek: widget.onSeek,
            deepLink: widget.deepLink,
            onOpenLink: widget.onOpenLink,
            onOpenImage: widget.onOpenImage,
          ),
        if (r.notes.isNotEmpty) ...[
          const SectionHeader('Notes'),
          for (final n in r.notes) _Bullet(n),
        ],
        if (rest.isNotEmpty) ...[
          const SectionHeader('Photos'),
          for (final im in rest) ...[
            KitFigure(
              url: im.url,
              caption: im.caption,
              onOpen: widget.onOpenImage == null
                  ? null
                  : () => widget.onOpenImage!(im),
            ),
            const SizedBox(height: AppSpacing.s3),
          ],
        ],
      ],
    );
  }
}

/// A figure, at the measure. Captioned where the extractor captioned it — the
/// caption is the machine's, and it is the `<img alt>` too.
///
/// Shared rather than private to §5.4: the Original panel draws the captured
/// screenshot with exactly this anatomy, and two spellings of "an image with a
/// line under it" is the split every other pattern here exists to prevent.
class KitFigure extends StatelessWidget {
  final String url;
  final String caption;
  final VoidCallback? onOpen;

  const KitFigure({super.key, required this.url, this.caption = '', this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final picture = ClipRRect(
      borderRadius: AppRadius.mdR,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        // A picture that will not load is not a broken frame with a caption
        // under it: the caption still says what the picture was.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        onOpen == null
            ? picture
            : GestureDetector(onTap: onOpen, child: picture),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(caption, style: KitText.meta(context).copyWith(color: t.fgSubtle)),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  final RecipeGroup group;
  final bool showLabel;
  final bool Function(int) isChecked;
  final ValueChanged<int> onToggle;

  const _Group({
    required this.group,
    required this.showLabel,
    required this.isChecked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const SizedBox(height: AppSpacing.s3),
          Text(group.group!.toUpperCase(),
              style: KitText.capsLabel(context,
                  fontSize: 10, letterSpacing: 0.1, color: t.fgSubtle)),
          const SizedBox(height: 4),
        ],
        for (var i = 0; i < group.items.length; i++)
          _Ingredient(
            text: group.items[i],
            on: isChecked(i),
            onTap: () => onToggle(i),
          ),
      ],
    );
  }
}

/// One ingredient line: a tick, then the item, over a `--rule` separator.
class _Ingredient extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;

  const _Ingredient({required this.text, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 3, right: 12),
              // `.rc-tick`: a square at `--r-xs` on `--surface`, filled
              // `--positive` when ticked — a checkbox, not a radio.
              decoration: BoxDecoration(
                color: on ? t.positive : t.surface,
                border: Border.all(color: on ? t.positive : t.borderStrong),
                borderRadius: AppRadius.xsR,
              ),
              child: on
                  ? Icon(Icons.check, size: 12, color: t.surface)
                  : null,
            ),
            Expanded(
              child: Text(
                text,
                style: KitText.body(context).copyWith(
                  height: 26 / 15,
                  // Checked is struck AND dimmed: a cooking list read at arm's
                  // length across a kitchen needs more than one channel, the
                  // same reason the passage mark changes width as well as hue.
                  color: on ? t.fgSubtle : t.fg,
                  decoration: on ? TextDecoration.lineThrough : null,
                  decorationColor: t.fgSubtle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final RecipeStep step;
  final RecipeImage? image;
  final ValueChanged<double>? onSeek;
  final String? Function(double start)? deepLink;
  final ValueChanged<String>? onOpenLink;
  final void Function(RecipeImage image)? onOpenImage;

  const _Step({
    required this.index,
    required this.step,
    this.image,
    this.onSeek,
    this.deepLink,
    this.onOpenLink,
    this.onOpenImage,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}.',
              style: AppTheme.serif(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: t.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    if (step.start != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _StepTime(
                            start: step.start!,
                            onSeek: onSeek,
                            deepLink: deepLink,
                            onOpenLink: onOpenLink,
                          ),
                        ),
                      ),
                    TextSpan(text: step.text),
                  ]),
                  style: KitText.bodyReading(context),
                ),
                if (image != null) ...[
                  const SizedBox(height: AppSpacing.s3),
                  KitFigure(
                    url: image!.url,
                    caption: image!.caption,
                    onOpen: onOpenImage == null
                        ? null
                        : () => onOpenImage!(image!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The optional time chip — mono caps in the `.meta` role, leading the step.
///
/// Its target is decided by what the document actually HAS, in the order
/// `screens/reader.md` §Step jump sets out: real audio → seek the Listen
/// panel · a time-parameter platform → open the source there · otherwise
/// **plain text, not a control**. That third branch is the whole point: a
/// control that looks live and does nothing is the dead-endpoint defect in
/// miniature.
class _StepTime extends StatelessWidget {
  final double start;
  final ValueChanged<double>? onSeek;
  final String? Function(double start)? deepLink;
  final ValueChanged<String>? onOpenLink;

  const _StepTime({
    required this.start,
    this.onSeek,
    this.deepLink,
    this.onOpenLink,
  });

  static String fmt(double seconds) {
    final s = seconds < 0 ? 0 : seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final label = fmt(start);
    // §5.4's metrics say `--seal` here, and the reference draws `--accent-text`
    // (`.rc-time.is-live`). The gate settles it: `--seal` is floored as a
    // GRAPHIC at 3.0 and this is text, so seal on a live chip fails the
    // small-text floor — a token's floor is a claim about what it is for.
    final live = KitText.capsLabel(context,
        fontSize: 11, letterSpacing: 0.04, color: t.accentText);
    final inert = KitText.capsLabel(context,
        fontSize: 11, letterSpacing: 0.04, color: t.fgSubtle);

    if (onSeek != null) {
      return _chip(Icons.headset_outlined, label, live, () => onSeek!(start));
    }
    final deep = deepLink?.call(start);
    if (deep != null && onOpenLink != null) {
      return _chip(
          Icons.open_in_new, label, live, () => onOpenLink!(deep));
    }
    return Text(label, style: inert);
  }

  Widget _chip(IconData icon, String label, TextStyle style, VoidCallback tap) =>
      GestureDetector(
        onTap: tap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: style.color),
            const SizedBox(width: 4),
            Text(label, style: style),
          ],
        ),
      );
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: t.fgSubtle, shape: BoxShape.circle),
            ),
          ),
          Expanded(child: Text(text, style: KitText.body(context))),
        ],
      ),
    );
  }
}
