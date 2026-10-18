import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../../theme/app_spacing.dart';

/// The page-frame ceilings (`component-kit.md` §1.5). Chosen by **what the
/// screen is for**, never by eye.
enum KitFrameWidth {
  /// 1100 — search: the only screen that puts two panes side by side.
  wide(AppSpacing.frameWide),

  /// 980 — library, sources, activity, study: anything that lists.
  ///
  /// The spec calls this frame **Index**; the value is `listing` because Dart
  /// gives every enum an `index` member of its own.
  listing(AppSpacing.frameIndex),

  /// 760 — reader, ask thread, settings: prose, and long forms.
  reading(AppSpacing.frameReading),

  /// 640 — the letter paper.
  sheet(AppSpacing.frameSheet);

  final double maxWidth;
  const KitFrameWidth(this.maxWidth);
}

/// The centred column a screen's content lives in.
///
/// The **inline gutter is constant across all four widths** — only the ceiling
/// moves. A screen that changes its gutter to fit its content has left the grid.
/// The one sanctioned exception is narrow viewports, where the 56px reference
/// gutter is wrong on a phone; that scale-down is applied here, once, so no
/// screen re-decides it (and it is recorded in CLAUDE.md §Composition
/// deviations).
class KitFrame extends StatelessWidget {
  final KitFrameWidth width;
  final Widget child;
  final double? top;
  final double? bottom;

  const KitFrame({
    super.key,
    this.width = KitFrameWidth.listing,
    required this.child,
    this.top,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final gutter = compact
        ? AppSpacing.frameGutterCompact
        : AppSpacing.frameGutter;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width.maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            top ?? (compact ? AppSpacing.s5 : AppSpacing.frameGutterTop),
            gutter,
            bottom ?? AppSpacing.s20,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// [KitFrame]'s horizontal half: the centred column and its gutter, with no
/// vertical padding of its own.
///
/// A screen built out of SLIVERS cannot wrap its whole body in one [KitFrame] —
/// each sliver is laid out by the viewport — so every band of such a screen
/// frames itself with this, and the frame stays one decision rather than one
/// per band. The vertical padding is then the first and last band's, once.
class KitFrameBand extends StatelessWidget {
  final KitFrameWidth width;
  final Widget child;

  const KitFrameBand({
    super.key,
    this.width = KitFrameWidth.listing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final gutter = compact
        ? AppSpacing.frameGutterCompact
        : AppSpacing.frameGutter;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width.maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}

/// INV-22 (5.19.0, ADR-173) — the support footer the shell composed, handed
/// down to the screen's **primary** scroll container, which renders it last.
///
/// The shell ([SupportShell]) is still the only place the footer is
/// composed, and no screen names it: a screen gets it by scrolling the way
/// every screen scrolls — [KitPage], [KitScrollView], [KitLoadingPage], or the
/// reader's [KitShellFooterSliver] — never by rendering it. Until 5.19.0 the
/// shell drew it below the routed view, always on screen; Xavier meant the end
/// of each screen's scroll, "out of the way but present" (ADR-173).
class KitShellFooter extends InheritedWidget {
  final Widget footer;

  const KitShellFooter({super.key, required this.footer, required super.child});

  /// The footer to end this screen's primary scroll with, or null outside the
  /// shell (a widget test, the pre-auth landing).
  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitShellFooter>()?.footer;

  @override
  bool updateShouldNotify(KitShellFooter oldWidget) =>
      footer != oldWidget.footer;
}

/// The scroll container every screen body sits in (`component-kit.md` §1.4).
///
/// **Every screen's body scrolls inside its own container.** This is a shipped
/// defect, not a hypothetical: four web pages were bare padded roots and were
/// unscrollable for their whole lives the moment content exceeded the viewport
/// (contract 4.3.1). A screen that renders a bare [Column] under the shell has
/// the same bug, and it will not show up until the content grows.
///
/// **The primary one ends with the shell's footer** (§1.4, §13; ADR-173). The
/// screen's content is the body, which grows to fill the container, and the
/// footer the shell composed ([KitShellFooter]) is its last element. So a
/// screen shorter than the pane keeps the footer at the pane's bottom edge, and
/// a longer one reaches it at the end of the scroll. Any OTHER scroller a
/// screen owns — a preview beside a form, a sheet — is
/// [KitScrollView.secondary], which says why and never carries it (web
/// `data-scroll-secondary`).
///
/// Only a **real gesture** proves scrollability — driving the controller
/// programmatically moves even a pane that a user cannot scroll.
class KitScrollView extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;

  /// Content shorter than the viewport rests at its BOTTOM, footer below it,
  /// as a chat's does (Ask's `.ask-thread { margin: auto auto 0 }`).
  final bool anchorBottom;

  /// The height a docked bar floating over this scroller takes (Ask's and
  /// Support's composer, §10). The footer ends the content ABOVE it, inside
  /// the space the dock reserves, and the dock stays docked (ADR-173).
  final double dockReserve;

  /// Why this scroller is not the screen's primary one. Null: it is.
  final String? secondaryReason;

  const KitScrollView({
    super.key,
    required this.child,
    this.controller,
    this.anchorBottom = false,
    this.dockReserve = 0,
  }) : secondaryReason = null;

  /// A scroller that is not the screen's primary column (§1.4): it never
  /// carries the footer, and it has to say why.
  const KitScrollView.secondary({
    super.key,
    required String reason,
    required this.child,
    this.controller,
  })  : secondaryReason = reason,
        anchorBottom = false,
        dockReserve = 0;

  @override
  Widget build(BuildContext context) {
    final reason = secondaryReason;
    if (reason != null) {
      assert(reason.trim().length >= 8,
          'a secondary scroller says why it is not the primary one');
      return SingleChildScrollView(
        controller: controller,
        primary: controller == null ? null : false,
        child: child,
      );
    }
    final footer = KitShellFooter.of(context);
    final tail = footer == null && dockReserve == 0
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?footer,
              if (dockReserve > 0) SizedBox(height: dockReserve),
            ],
          );
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        controller: controller,
        primary: controller == null ? null : false,
        child: ConstrainedBox(
          // The body grows to fill the pane: short content keeps the footer at
          // the pane's bottom edge, never mid-screen under its last line.
          constraints:
              BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
          child: Column(
            mainAxisAlignment: anchorBottom
                ? MainAxisAlignment.end
                : MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child, ?tail],
          ),
        ),
      ),
    );
  }
}

/// A frame and its scroller together — the shape almost every screen wants.
/// The PRIMARY one by default, so it ends with the shell's footer.
class KitPage extends StatelessWidget {
  final KitFrameWidth width;
  final Widget child;
  final ScrollController? controller;

  /// Content shorter than the viewport rests at its BOTTOM, as a chat's does
  /// (Ask's `.ask-thread { margin: auto auto 0 }`): one turn sits against the
  /// composer, not under the header with the screen empty below it (F-90
  /// (5)). Longer content scrolls exactly as it would without this.
  final bool anchorBottom;

  /// [KitScrollView.dockReserve].
  final double dockReserve;

  /// [KitScrollView.secondaryReason].
  final String? secondaryReason;

  const KitPage({
    super.key,
    this.width = KitFrameWidth.listing,
    required this.child,
    this.controller,
    this.anchorBottom = false,
    this.dockReserve = 0,
  }) : secondaryReason = null;

  /// A framed scroller that is not the screen's primary column (§1.4) — the
  /// letter studio's preview beside its form. It never carries the footer.
  const KitPage.secondary({
    super.key,
    required String reason,
    this.width = KitFrameWidth.listing,
    required this.child,
    this.controller,
  })  : secondaryReason = reason,
        anchorBottom = false,
        dockReserve = 0;

  @override
  Widget build(BuildContext context) {
    final frame = KitFrame(width: width, child: child);
    final reason = secondaryReason;
    if (reason != null) {
      return KitScrollView.secondary(
          reason: reason, controller: controller, child: frame);
    }
    return KitScrollView(
      controller: controller,
      anchorBottom: anchorBottom,
      dockReserve: dockReserve,
      child: frame,
    );
  }
}

/// A screen still loading: the spinner centred in the pane, and the screen's
/// primary scroll ending with the shell's footer as any other does (INV-22 —
/// a screen does not lose its way out while it loads).
class KitLoadingPage extends StatelessWidget {
  const KitLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final footer = KitShellFooter.of(context);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(
                    child: Center(child: CircularProgressIndicator())),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The footer as the LAST SLIVER of a screen built from slivers — the reader,
/// whose section rail is sticky (§19). It ends the document, and when the
/// document is shorter than the pane it sits at the pane's bottom edge
/// (ADR-173: "Reader — at the end of the document").
class KitShellFooterSliver extends StatelessWidget {
  const KitShellFooterSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final footer = KitShellFooter.of(context);
    if (footer == null) return const SliverToBoxAdapter();
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [footer],
      ),
    );
  }
}

/// Reports its child's laid-out size after the frame — how a screen learns the
/// height of a dock that floats over its scroller, so the scroller can reserve
/// it ([KitScrollView.dockReserve]).
class KitMeasure extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;

  const KitMeasure({super.key, required this.onSize, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMeasure).onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
