import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_text.dart';

/// §15.1 and §15.2 — the two viewers for a document's own bytes, and the
/// full-size image view they both open into.
///
/// §15's overlay **sheet** ([KitOverlaySheet]) lands here at F-13, in the
/// commit that first composes it — the tray is its consumer, and a kit widget
/// nothing mounts is read by the next person as a spec (the dead-CSS class
/// trap, 4.43.2). The reader keeps drawing the two viewers **inline** in its
/// Original panel, exactly as the reference reader does: the sheet is how the
/// Sources tray shows a source, not a second home for the viewers.

/// One member of a `set`-shaped document — a page, as uploaded.
///
/// [signedUrl] is null **at its own index** for a page whose bytes have not
/// landed. That is a state, not an omission: `members` is the full set in page
/// order and is never compacted, because compacting it renumbers every page
/// after the gap and tells the reader their 12-page set is 11 pages long
/// (§6.4.2 rule 3, §15.2 rule 1).
/// §15 · **Overlay sheet** (4.37.0) — the container.
///
/// A panel that opens **over** the current screen without leaving it, for
/// something the reader wants beside what they are already doing: an add flow,
/// a reference sheet, a source they are about to retry.
///
/// Required parts, in order: a **scrim** covering the viewport, which closes on
/// press · a **panel** (`--surface`, 1px `--border`, `--r-xl`, `--shadow-3`,
/// clipped, a column that scrolls **inside its body** and never the page) · a
/// **head** — a 36px iconbox on `--accent-soft`, a serif title, a sans
/// subtitle, and a close control on the trailing side · a **body**, the only
/// part that scrolls · an optional **foot** on `--surface-raised` behind a 1px
/// `--rule`.
///
/// **Esc closes it, and so does the scrim** — a sheet with only a button to
/// close it is a sheet a keyboard cannot leave. `showDialog`'s barrier is both,
/// which is why this is a dialog rather than a hand-rolled Stack (rule 4: one
/// shape; the second overlay shape on this app lived from 2.35.0 to 4.56.0).
///
/// **A sheet is not a route**: nothing behind it unmounts, and closing restores
/// exactly the scroll position the reader left.
class KitOverlaySheet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  /// Replaces the icon tile at the head — the source sheet leads with the
  /// document's FILE BADGE (`.sf-mark`), which says what the source is before
  /// the title does; a generic file glyph said nothing.
  final Widget? lead;

  /// Per-instance width and height — the only two values §15 lets an instance
  /// choose. The source viewers are the 860/88% pair.
  final double width;
  final double heightFactor;

  /// True while a write the sheet started is in flight. The sheet then cannot
  /// be dismissed — not by the scrim, Esc, the back gesture or its own close —
  /// so a filing cannot be closed into looking like it never ran (§15, the
  /// reference's `busy` hold).
  final ValueListenable<bool>? holding;

  /// A head that moves on with the flow inside it — one sheet that begins as
  /// a form and continues into a review (`screens/library.md` §Creating a
  /// shelf: "the same sheet continues"). Overrides [title]/[subtitle] while
  /// set; the sheet is not closed and reopened, so nothing behind it moves.
  final ValueListenable<KitSheetHeading>? heading;

  const KitOverlaySheet({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.width = 860,
    this.heightFactor = 0.88,
    this.holding,
    this.heading,
    this.lead,
  });

  static Future<void> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required WidgetBuilder builder,
    double width = 860,
    double heightFactor = 0.88,
    ValueListenable<bool>? holding,
    ValueListenable<KitSheetHeading>? heading,
    Widget? lead,
  }) =>
      showDialog<void>(
        context: context,
        barrierColor: Tokens.of(context).scrim,
        // §15's scrim is tinted AND blurred 3px; the barrier alone is the tint,
        // so the screen behind read sharp through it.
        builder: (ctx) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: KitOverlaySheet(
            icon: icon,
            title: title,
            subtitle: subtitle,
            width: width,
            heightFactor: heightFactor,
            holding: holding,
            heading: heading,
            lead: lead,
            child: Builder(builder: builder),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final head = heading;
    if (head == null) return _held(context, title, subtitle);
    return ValueListenableBuilder<KitSheetHeading>(
      valueListenable: head,
      builder: (context, h, _) => _held(context, h.title, h.subtitle),
    );
  }

  Widget _held(BuildContext context, String title, String? subtitle) {
    final hold = holding;
    if (hold == null) return _sheet(context, false, title, subtitle);
    return ValueListenableBuilder<bool>(
      valueListenable: hold,
      builder: (context, held, _) => PopScope(
          canPop: !held, child: _sheet(context, held, title, subtitle)),
    );
  }

  Widget _sheet(
      BuildContext context, bool held, String title, String? subtitle) {
    final t = Tokens.of(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: size.height * heightFactor,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.xlR,
            border: Border.all(color: t.border),
            boxShadow: AppShadows.s3,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                // `.qa-head` is `align-items: flex-start`: a subtitle that
                // wraps grows DOWN from the mark, it does not re-centre it.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    lead ??
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.accentSoft,
                            borderRadius: AppRadius.smR,
                          ),
                          child: Icon(icon, size: 18, color: t.accentText),
                        ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // `.qa-title` serif 21/1.1 600 and `.qa-sub` sans
                          // 13 at `--fg-muted`, 3px under it. Both WRAP on the
                          // web: a one-line ellipsis cut "Fill <shelf>"'s
                          // subtitle mid-sentence on a phone.
                          Text(title,
                              style: AppTheme.serif(
                                fontSize: 21,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color: t.fg,
                              )),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(subtitle,
                                style: KitText.ui(context, color: t.fgMuted)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    KitIconButton(
                      Icons.close,
                      tooltip: 'Close',
                      onPressed:
                          held ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: t.rule),
              // **The body scrolls, the page does not.**
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The head of a [KitOverlaySheet] whose flow moves on inside it.
class KitSheetHeading {
  final String title;
  final String? subtitle;
  const KitSheetHeading(this.title, [this.subtitle]);
}

class KitSetMember {
  final String name;
  final String? signedUrl;

  const KitSetMember({required this.name, this.signedUrl});

  factory KitSetMember.fromJson(Map<String, dynamic> j) => KitSetMember(
        name: j['name'] as String? ?? '',
        signedUrl: j['signed_url'] as String?,
      );
}

/// What a client can draw of a stored object. Everything else is **named** and
/// pointed at the toolbar — a stage that renders nothing reads as a broken
/// viewer, which is the dead end DOCX used to hit (§15.1 rule 1).
enum KitStage { image, video, audio, none }

KitStage kitStageFor({String? type, String? mimeType}) {
  final m = mimeType ?? '';
  if (type == 'image' || m.startsWith('image/')) return KitStage.image;
  // 4.13.0 (ADR-049). The picture is shown here and was never READ: a video is
  // indexed from its audio track alone. Rendering the source is not a claim
  // that anything in it was indexed.
  if (type == 'video' || m.startsWith('video/')) return KitStage.video;
  if (type == 'audio' || m.startsWith('audio/')) return KitStage.audio;
  // A PDF is `KitStage.none` on this client and that is not a gap in the
  // vocabulary: the web frames one, and nothing here embeds a PDF renderer, so
  // the honest answer is the sentence plus the toolbar rather than an empty
  // frame that looks like a viewer which failed.
  return KitStage.none;
}

/// Component kit §15.1 · Source file view (4.37.0, ADR-075) — the document's
/// own bytes, rendered.
///
/// **This is the `file` shape's viewer, and only that** (§6.4.2). A `set` has n
/// stored objects and gets [KitSourceSetGallery]; a `link` has none and gets no
/// viewer at all.
///
/// It draws the stored object and **nothing else** (§15.1 rule 3). The
/// extraction — chunks, captured HTML, the pre-distillation original — belongs
/// to the panel that composes this one, which is why the reader shows both and
/// a processing tray shows only this.
class KitSourceFileView extends StatelessWidget {
  /// The toolbar's leading text: the document title, in the mono face.
  final String title;

  /// The signed URL. Never null here — a null URL is a **state** the composing
  /// panel renders as its own sentence, not a failure and not an empty stage
  /// (§15.1 rule 2).
  final String url;

  final KitStage stage;

  /// The two trailing controls. Both take the same URL; the composing screen
  /// owns launching, because this widget knows nothing about how a platform
  /// opens a file.
  final ValueChanged<String>? onDownload;
  final ValueChanged<String>? onOpen;

  /// Names the type in the fallback sentence (`A DOCX can't be displayed…`).
  final String typeLabel;

  const KitSourceFileView({
    super.key,
    required this.title,
    required this.url,
    required this.stage,
    this.onDownload,
    this.onOpen,
    this.typeLabel = 'file',
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        // `--border-strong` (web 0ad8858): a card inside a card, and in dark
        // `--border` left the frame's sides nearly invisible.
        border: Border.all(color: t.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(fontSize: 13, color: t.fg),
                  ),
                ),
                if (onDownload != null)
                  KitIconButton(
                    Icons.download_outlined,
                    tooltip: 'Download original',
                    onPressed: () => onDownload!(url),
                  ),
                if (onOpen != null)
                  KitIconButton(
                    Icons.open_in_new,
                    tooltip: 'Open in a new tab',
                    onPressed: () => onOpen!(url),
                  ),
              ],
            ),
          ),
          _stage(context, t),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context, Tokens t) {
    switch (stage) {
      case KitStage.image:
        return Container(
          width: double.infinity,
          color: t.surfaceSunken,
          padding: const EdgeInsets.all(AppSpacing.s4),
          // `.orig-imagefile`: the image is its own page on the stage —
          // `--r-sm` corners and `--shadow-2`, not a bare rectangle.
          child: Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: AppRadius.smR,
                boxShadow: AppShadows.s2,
              ),
              child: ClipRRect(
                borderRadius: AppRadius.smR,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      case KitStage.video:
        // No player is embedded here, and the matte is not drawn over nothing:
        // the frame says what it holds and the toolbar opens it. A black box
        // with no controls is the blank stage §15.1 rule 1 refuses.
        return _sentence(context, t,
            'A video opens in the system player — open or download it above.');
      case KitStage.audio:
        return _sentence(context, t,
            'An audio file opens in the system player — open or download it '
            'above. The Listen panel plays the same recording in place.');
      case KitStage.none:
        return _sentence(context, t,
            'A $typeLabel can’t be displayed here — open or download '
            'it above.');
    }
  }

  Widget _sentence(BuildContext context, Tokens t, String text) => Container(
        width: double.infinity,
        color: t.surfaceSunken,
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: KitProcNote(text, padding: EdgeInsets.zero),
      );
}

/// Component kit §15.2 · Source set gallery (4.38.0, ADR-076) — an
/// `image_set`'s **pages**, as uploaded.
///
/// A separate pattern rather than a mode of §15.1, because §15.1 rule 3 is
/// *the renderer draws the stored object* and "the" is load-bearing: a set has
/// n. One name over two anatomies is the `docKind()`/`KIND_ORDER` split with
/// pictures.
///
/// These are the **uploaded originals**. The rehosted `<figure>` per page is
/// the Manuscript's, and the two legitimately differ — a page that failed
/// extraction still has a tile here (§15.2 rule 3).
///
/// The toolbar carries **no title**: every surface that composes this one draws
/// it already, and the first web render printed it twice, one line apart, at
/// the same weight. The count is the fact that has nowhere else to live.
class KitSourceSetGallery extends StatelessWidget {
  final List<KitSetMember> members;
  final void Function(int index, KitSetMember member)? onOpenPage;

  const KitSourceSetGallery({
    super.key,
    required this.members,
    this.onOpenPage,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);

    // Not an empty state and not a failure: `members: []` is the backend
    // answering "a set with no members", which differs from `null` (not a set)
    // and from a request that failed — the caller renders those.
    if (members.isEmpty) {
      return const KitProcNote('This image set has no pages stored.');
    }

    final landed = members.where((m) => m.signedUrl != null).length;
    final count = landed < members.length
        ? '$landed of ${members.length} uploaded'
        : '${members.length} ${members.length == 1 ? 'page' : 'pages'}';

    // `.srcset` (app-kit.css): `--r-lg` on `--surface`, its bar on
    // `--surface-raised`; count, placeholder sentence and caption all sans 11-12
    // in `--fg-muted` — the map of the set, not a page of prose.
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Eyebrow('Pages'),
                Text(count,
                    style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12,
                        color: t.fgMuted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s3),
            child: LayoutBuilder(
              builder: (context, c) {
                // `auto-fill` from a 150px minimum, so a 2-page set does not
                // stretch to fill the sheet.
                final columns = (c.maxWidth / 150).floor().clamp(1, 6);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.s3,
                    mainAxisSpacing: AppSpacing.s3,
                    // The tile is a fixed 3:4 plus its caption line. A grid
                    // that honoured each page's own ratio would be ragged, and
                    // this grid is the MAP of the set; the full-size view is
                    // where a page is seen uncropped.
                    childAspectRatio: 3 / 4.6,
                  ),
                  itemBuilder: (context, i) => _Tile(
                    index: i,
                    member: members[i],
                    onOpen: members[i].signedUrl == null || onOpenPage == null
                        ? null
                        : () => onOpenPage!(i, members[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final int index;
  final KitSetMember member;
  final VoidCallback? onOpen;

  const _Tile({required this.index, required this.member, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pending = member.signedUrl == null;
    final small = TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 11,
        height: 1.4,
        color: t.fgMuted);
    final frame = Container(
      // `.srcset-pending .srcset-frame`: a DASHED border on `--surface-sunken`
      // — the footprint of a page that is not there, not a blank page.
      foregroundDecoration: pending
          ? _DashedBorder(color: t.border, radius: AppRadius.md)
          : null,
      decoration: BoxDecoration(
        color: pending ? t.surfaceSunken : t.surfaceRaised,
        borderRadius: AppRadius.mdR,
        border: pending ? null : Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: pending
          // §15.2 rule 1 — a page whose bytes have not landed draws a
          // placeholder in the SAME FOOTPRINT, never an omission.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'This page hasn’t finished uploading yet.',
                  textAlign: TextAlign.center,
                  style: small,
                ),
              ),
            )
          : Image.network(member.signedUrl!, fit: BoxFit.cover),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: onOpen == null
              ? frame
              : GestureDetector(
                  onTap: onOpen,
                  child: SizedBox(width: double.infinity, child: frame),
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('${index + 1}',
                style: AppTheme.mono(fontSize: 11, color: t.fgSubtle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small),
            ),
          ],
        ),
      ],
    );
  }
}

/// One image, full size, over whatever opened it.
///
/// Deliberately **not a carousel** (§15.2 rule 2): a manuscript image has
/// nothing to page to, and a set's grid is one press behind this — and is the
/// only place the whole set is visible at once.
class KitLightbox extends StatelessWidget {
  final String url;
  final String? caption;

  const KitLightbox({super.key, required this.url, this.caption});

  static Future<void> show(BuildContext context,
          {required String url, String? caption}) =>
      showDialog<void>(
        context: context,
        // The scrim is the dialog's own barrier, and pressing it closes —
        // a sheet with only a button to close it is one a gesture cannot leave.
        barrierColor: Tokens.of(context).scrim,
        builder: (_) => KitLightbox(url: url, caption: caption),
      );

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.s4),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: ClipRRect(
                    borderRadius: AppRadius.mdR,
                    child: InteractiveViewer(
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(caption!,
                      style: KitText.meta(context).copyWith(color: t.chromeFg)),
                ],
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: KitIconButton(
              Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dashed rounded border, painted over its box (`border-style: dashed`).
class _DashedBorder extends Decoration {
  final Color color;
  final double radius;

  const _DashedBorder({required this.color, required this.radius});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedBorderPainter(this);
}

class _DashedBorderPainter extends BoxPainter {
  final _DashedBorder d;

  _DashedBorderPainter(this.d);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null) return;
    final rect = (offset & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(d.radius)));
    final paint = Paint()
      ..color = d.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        canvas.drawPath(metric.extractPath(at, at + 4), paint);
      }
    }
  }
}
