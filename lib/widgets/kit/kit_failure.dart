import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';

/// §14 — Failure (4.33.0, ADR-070).
///
/// The rendered form of the `error` state every screen's §States declares, and
/// the pattern the kit did not have: without it each screen invented one, and
/// this app's error state was a `KitCard` with a ghost button while the web
/// reference had six other shapes and iOS a seventh.
///
/// Which form to use is decided by **who acts next**. A rejection the reader
/// can fix answers beside the control that refused it ([KitFailureInline]); a
/// region that could not load answers where the content would have been
/// ([KitFailureBlock]).
///
/// **An empty state is never a failure state.** §7 is an offer; this is a
/// hole. Rendering "nothing found" for a request that did not complete is what
/// this pattern exists to prevent — it is how the reference implementation's
/// own screenshot of Search looked correct while `fn_search_notes` 500'd in
/// production for the entire life of its documented `sourceTypes` parameter
/// (ADR-065).

/// §14.1 — takes exactly the region that failed: a pane, a list, a card's
/// body. Never the whole screen when only a pane failed.
class KitFailureBlock extends StatelessWidget {
  /// What failed, in the app's own words. Names the thing — never a generic
  /// "Something went wrong", which is a sentence that tells a reader nothing
  /// and, where it replaces [detail], hides the one that would have.
  final String sentence;

  /// The server's own message, **verbatim** (`screens/sources.md` §Failure
  /// rows). Never pattern-matched into copy of ours.
  final String detail;

  /// The envelope's `request_id`. Rendered exactly when there is one — this is
  /// the id the backend's own 500 sentence tells the reader to quote, and no
  /// client rendered it anywhere before 4.33.0 although all three parse it.
  final String? requestId;

  /// Re-issues the same request. Omitted when there is nothing to retry.
  final VoidCallback? onRetry;
  final String retryLabel;

  const KitFailureBlock({
    super.key,
    required this.sentence,
    required this.detail,
    this.requestId,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: double.infinity,
      // The reference metrics, as metrics — a kit file is where the pattern's
      // numbers live (18/20 is not a step on the spacing scale, and rounding it
      // to one would be a redraw, which §How-to-read makes a recorded
      // deviation rather than a free choice).
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
        // No shadow, at rest or on hover: §5.1's card lifts because it is a
        // sheet you could pick up, and this is the absence of the content.
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sentence,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
              color: t.criticalText,
            ),
          ),
          const SizedBox(height: 6),
          // Quoted speech, not our copy — the italic serif the failed source
          // row has always used for exactly this.
          Text(
            detail,
            style: AppTheme.serif(
              fontSize: 14,
              height: 20 / 14,
              fontStyle: FontStyle.italic,
              color: t.fgLede,
            ),
          ),
          if (requestId != null) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Reference '),
                TextSpan(
                  text: requestId,
                  style: AppTheme.mono(fontSize: 11.5, color: t.fgMuted),
                ),
                const TextSpan(text: ' — quote it to support.'),
              ]),
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12,
                height: 17 / 12,
                color: t.fgSubtle,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: KitButton.primary(retryLabel, onPressed: onRetry),
            ),
          ],
        ],
      ),
    );
  }
}

/// §14.2 — one line at the control that refused, carrying the server's message
/// verbatim and **no reference id**: the reader is the one who fixes a
/// rejected value, so an id they cannot use is noise.
class KitFailureInline extends StatelessWidget {
  final String message;

  /// The smaller step, for a dense control group — a shelf chip on a passage,
  /// a composer dock.
  final bool dense;

  const KitFailureInline(this.message, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(
      message,
      style: TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: dense ? 11 : 13,
        height: dense ? 16 / 11 : 19 / 13,
        color: t.criticalText,
      ),
    );
  }
}

/// §14.2 — bring [context]'s widget into view as web's
/// `scrollIntoView({block: 'nearest'})` does: above the view → its top to the
/// top; below → its foot to the foot; already in view → nothing moves. Still
/// under reduced motion.
Future<void> kitRevealNearest(BuildContext context) async {
  final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final d = still ? Duration.zero : const Duration(milliseconds: 240);
  await Scrollable.ensureVisible(
    context,
    duration: d,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
  );
  if (!context.mounted) return;
  await Scrollable.ensureVisible(
    context,
    duration: d,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
}

/// §14.2 — a refusal under a control **comes into view when it arrives**
/// (F-194; web 19003d4: `sources/intake.jsx` useIntoView,
/// `reader/UpdateFromSourceBar.jsx` errRef). On a phone a refusal drawn under
/// a control at the scroller's foot, or under a block that pushed it below the
/// fold, lies under the tab bar where nobody reads it.
///
/// **Once per arrival, never per mount**: a host that moves its refusal to
/// another parent (the Library's empty catalogue and its slot) must not scroll
/// the page back to an old refusal nobody just made. [arrival] is one object
/// per refusal — a new `Object()` each time one arrives; null is nothing to
/// bring. Which arrivals were brought is kept here, not in a mount's state (web
/// keeps a module-level WeakSet), so a remount knows.
class KitIntoView extends StatefulWidget {
  final Object? arrival;
  final Widget child;

  const KitIntoView({super.key, required this.arrival, required this.child});

  @override
  State<KitIntoView> createState() => _KitIntoViewState();
}

class _KitIntoViewState extends State<KitIntoView> {
  static final Expando<bool> _brought = Expando('KitIntoView');

  @override
  void initState() {
    super.initState();
    _bring();
  }

  @override
  void didUpdateWidget(KitIntoView old) {
    super.didUpdateWidget(old);
    if (!identical(old.arrival, widget.arrival)) _bring();
  }

  void _bring() {
    final a = widget.arrival;
    if (a == null || _brought[a] == true) return;
    _brought[a] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) kitRevealNearest(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
