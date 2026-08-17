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

/// The scroll container every screen body sits in (`component-kit.md` §1.4).
///
/// **Every screen's body scrolls inside its own container.** This is a shipped
/// defect, not a hypothetical: four web pages were bare padded roots and were
/// unscrollable for their whole lives the moment content exceeded the viewport
/// (contract 4.3.1). A screen that renders a bare [Column] under the shell has
/// the same bug, and it will not show up until the content grows.
///
/// Only a **real gesture** proves scrollability — driving the controller
/// programmatically moves even a pane that a user cannot scroll.
class KitScrollView extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;

  const KitScrollView({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: controller,
        primary: controller == null ? null : false,
        child: child,
      );
}

/// A frame and its scroller together — the shape almost every screen wants.
class KitPage extends StatelessWidget {
  final KitFrameWidth width;
  final Widget child;
  final ScrollController? controller;

  const KitPage({
    super.key,
    this.width = KitFrameWidth.listing,
    required this.child,
    this.controller,
  });

  @override
  Widget build(BuildContext context) => KitScrollView(
        controller: controller,
        child: KitFrame(width: width, child: child),
      );
}
