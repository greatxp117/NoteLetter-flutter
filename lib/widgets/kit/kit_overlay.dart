import 'package:flutter/material.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_text.dart';

/// §15.1 and §15.2 — the two viewers for a document's own bytes, and the
/// full-size image view they both open into.
///
/// §15's overlay **sheet** itself is not here yet, deliberately. It is the
/// shell the Sources processing tray opens these in, and this client has no
/// tray until F-13; a kit widget nothing mounts is read by the next person as
/// a spec (the dead-CSS class trap, 4.43.2), so the shell lands in the commit
/// that first composes it. On this client the reader draws these **inline** in
/// its Original panel, exactly as the reference reader does.

/// One member of a `set`-shaped document — a page, as uploaded.
///
/// [signedUrl] is null **at its own index** for a page whose bytes have not
/// landed. That is a state, not an omission: `members` is the full set in page
/// order and is never compacted, because compacting it renumbers every page
/// after the gap and tells the reader their 12-page set is 11 pages long
/// (§6.4.2 rule 3, §15.2 rule 1).
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
        border: Border.all(color: t.border),
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
          child: Image.network(url, fit: BoxFit.contain),
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

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Eyebrow('Pages'),
                Text(count, style: KitText.meta(context)),
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
    final frame = Container(
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: member.signedUrl == null
          // §15.2 rule 1 — a page whose bytes have not landed draws a
          // placeholder in the SAME FOOTPRINT, never an omission.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'This page hasn’t finished uploading yet.',
                  textAlign: TextAlign.center,
                  style: KitText.meta(context),
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
                  overflow: TextOverflow.ellipsis,
                  style: KitText.meta(context)),
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
