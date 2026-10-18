import SwiftUI

/// Component kit §14 — Failure (contract 4.33.0, ADR-070).
///
/// The rendered form of the `error` state every screen's §States declares. It
/// is the first file in this app's kit layer: `Views/Components/` holds pieces
/// this app invented, and the kit holds the patterns the contract names, one
/// file per pattern (`spec/component-kit.md`).
///
/// Which form to use is decided by **who acts next**. A rejection the reader
/// can fix answers beside the control that refused it (``KitFailureInline``); a
/// region that could not load answers where the content would have been
/// (``KitFailureBlock``).
///
/// **An empty state is never a failure state.** §7 is an offer; this is a hole.
/// Rendering "no results" for a request that did not complete is what this
/// pattern exists to prevent — it is how the web reference's own screenshot of
/// Search looked correct while `fn_search_notes` 500'd in production for the
/// entire life of its documented `sourceTypes` parameter (ADR-065).

// MARK: - §14.1 · Failure block

/// Takes exactly the region that failed — a pane, a list, a card's body. Never
/// the whole screen when only a pane failed.
struct KitFailureBlock: View {
    /// What failed, in the app's own words. Names the thing: this app's old
    /// `ErrorView` led with "Something went wrong", which tells a reader
    /// nothing — and the sentence that would have was set beneath it as meta.
    let sentence: String

    /// The server's own message, **verbatim** (`screens/sources.md` §Failure
    /// rows). Never pattern-matched into copy of ours.
    let detail: String

    /// The envelope's `request_id`, rendered exactly when there is one. Every
    /// client has parsed this since it existed and none rendered it before
    /// 4.33.0 — while `_err`'s own 500 sentence has said "contact support with
    /// your request ID" since 1.0.0.
    var requestId: String? = nil

    /// Re-issues the same request. Omitted when there is nothing to retry.
    var onRetry: (() -> Void)? = nil
    var retryLabel: String = "Try again"

    /// Seconds left on a cooldown the retry's own request was refused with
    /// (component-kit §6.1 Waiting, ADR-140): the retry is held and counts it
    /// down. 0 = not waiting.
    var retryWaitLeft: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sentence)
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.criticalText)

            // Quoted speech, not our copy — the italic serif the web's failed
            // source row has always used for exactly this.
            Text(detail)
                .font(.serifItalic(14))
                .foregroundStyle(Theme.fgLede)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let requestId {
                (Text("Reference ")
                    + Text(requestId).font(.mono(11.5)).foregroundColor(Theme.fgMuted)
                    + Text(" — quote it to support."))
                    .font(.sans(12))
                    .foregroundStyle(Theme.fgSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let onRetry {
                KitFailureRetry(label: retryLabel, waitLeft: retryWaitLeft, action: onRetry)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The reference metrics as metrics: 18/20 is not a step on the spacing
        // scale, and rounding it to one is a redraw — which §How to read a
        // pattern makes a recorded deviation, not a free choice.
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.border, lineWidth: 1)
        )
        // No shadow, at rest or on hover: §5.1's card lifts because it is a
        // sheet you could pick up, and this is the absence of the content.
        .accessibilityElement(children: .combine)
    }
}

/// §6.1 primary, at the size the block wants: left-aligned with the copy, not
/// the full-width `PrimaryButton` this app uses in forms. iOS has no kit Button
/// yet — when it gets one this collapses into it.
private struct KitFailureRetry: View {
    let label: String
    var waitLeft: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KitWaitLabel(label, left: waitLeft)
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.accentFg)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        // `.borderless`, never `.plain`: `.plain` halves a disabled label on its
        // own, so a held control drew at a quarter (HeldTests).
        .buttonStyle(.borderless)
        // §6.1 State — Held at the token (ADR-145). It drew 0.6 by eye, which
        // `.plain` halved again to 0.3.
        .kitHeld(waitLeft > 0)
    }
}

// MARK: - §14.2 · Inline rejection

/// One line at the control that refused, carrying the server's message verbatim
/// and **no reference id**: the reader is the one who fixes a rejected value,
/// so an id they cannot use is noise.
struct KitFailureInline: View {
    let message: String

    /// The smaller step, for a dense control group — a shelf chip on a passage,
    /// a composer dock.
    var dense: Bool = false

    init(_ message: String, dense: Bool = false) {
        self.message = message
        self.dense = dense
    }

    var body: some View {
        Text(message)
            .font(.sans(dense ? 11 : 13))
            .foregroundStyle(Theme.criticalText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
