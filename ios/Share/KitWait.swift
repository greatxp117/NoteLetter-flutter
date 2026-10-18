import SwiftUI
import UIKit

// MARK: - §6.1 · State — Waiting

/// A control's label while a cooldown runs (4.107.0, ADR-140): the idle label
/// followed by the remaining time as ` · m:ss`, in tabular figures so the
/// label does not shift as it counts (web's `.btn-wait`). At zero there is no
/// suffix at all — the label alone, exactly as before the refusal. It inherits
/// the control's face and colour; it sets neither.
struct KitWaitLabel: View {
    let label: String
    let left: Int

    init(_ label: String, left: Int) {
        self.label = label
        self.left = left
    }

    var body: some View {
        let suffix = waitSuffix(left)
        if suffix.isEmpty {
            Text(label)
        } else {
            (Text(label) + Text(suffix).monospacedDigit())
                .accessibilityLabel(label + suffix)
        }
    }
}

/// The label suffix of a waiting control: ` · 0:42`, ` · 4:58`; "" at zero —
/// never an empty run of text that would still take a gap in an HStack. Web's
/// `waitSuffix`. Here and not beside the registry because the share extension
/// compiles the kit's failure block, which draws it, and not the registry.
nonisolated func waitSuffix(_ left: Int) -> String {
    guard left >= 1 else { return "" }
    let s = left % 60
    return " · \(left / 60):\(s < 10 ? "0" : "")\(s)"
}

// MARK: - §6.1 · The calm caption

/// A cooldown's sentence while its control waits — **calm everywhere**
/// (4.108.0, ADR-145; component-kit §6.1): the server's words verbatim in
/// `--fg-muted` UI sans, in the slot under or beside the held control. A
/// cooldown is a wait, not a failure: the request was early, what the reader
/// is looking at is correct, and waiting fixes it. Red (§14.2,
/// ``KitFailureInline``) stays for a refusal that will not lift by waiting —
/// `retry_after_s` decides, which is to say: only a `Cooldowns` sentence is
/// drawn here. Web's `.wait-note` (sans 12.5/18, `--fg-muted`), Flutter's
/// `KitWaitNote`.
struct KitWaitNote: View {
    let sentence: String

    init(_ sentence: String) {
        self.sentence = sentence
    }

    /// Geist's own line at 12.5, read from the face (16.25 by its metrics) —
    /// the fallback's only input. The stash wrote "~15" down and spaced by 3;
    /// SwiftUI's own line here is 17, so that drew 20 where web's is 18, and
    /// spacing by 18 − 16.25 still drew 18.75 (measured at 4x) — the slip
    /// §7's leading had (`EmptyStateLeadingTests`).
    static let faceLine = (UIFont(name: AppFont.sans, size: 12.5) ?? .systemFont(ofSize: 12.5)).lineHeight

    var body: some View {
        Text(sentence)
            .font(.sans(12.5))
            // 18 is the LINE HEIGHT, exact on iOS 26 (`CalmCaptionTests`).
            .kitLine(18, face: Self.faceLine)
            .foregroundStyle(Theme.fgMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("kit-wait-note")
    }
}

extension View {
    /// A line of exactly `points`. iOS 26's `lineHeight` sets it; before 26,
    /// `lineSpacing` can only ADD to the face's own line (SwiftUI ignores a
    /// negative one), so a line tighter than the face — the §7 title's 1.1 —
    /// draws at the face's line there, and a looser one is close but not
    /// exact: SwiftUI's own line for Geist at 12.5 measured 0.75 over
    /// `UIFont.lineHeight`. Here, not in KitEmptyState, because the share
    /// extension compiles this file and the calm caption uses it.
    @ViewBuilder func kitLine(_ points: CGFloat, face: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            lineHeight(.exact(points: points))
        } else {
            lineSpacing(max(0, points - face))
        }
    }
}

// MARK: - §6.1 · State — Held

/// A control that cannot be pressed right now — **disabled** for any reason,
/// **waiting** out a cooldown, or **busy** with its own request — is drawn
/// held: the whole control at `--held-opacity` (`Held.opacity`), its fill,
/// label and countdown together (4.108.0, ADR-145; every such control since
/// 2026-10-13). Web's `:disabled` rules; Flutter's `AppSpacing.heldOpacity`.
///
/// It reads the ENVIRONMENT, so a control disabled by an ancestor
/// (`PrimaryButton(…).disabled(!canSubmit)`) is held too. Here and not in its
/// own file because the share extension compiles the kit's buttons, which
/// use it, and compiles this file.
///
/// Never on a `.plain` button: `.plain` halves a disabled label on its own,
/// so the two together draw a held control at a quarter (`HeldTests`).
struct KitHeldOpacity: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : Held.opacity)
    }
}

extension View {
    /// Disable this control when `held`, and draw it held whenever it is
    /// disabled — by `held` or by an ancestor's `.disabled`.
    func kitHeld(_ held: Bool = false) -> some View {
        modifier(KitHeldOpacity()).disabled(held)
    }

    /// A text or icon action the SYSTEM styled — a toolbar item, a form row's
    /// Save, a bar's "Edit text", the speed-read ± — drawn in its live accent
    /// and held at the token when it cannot be pressed (ruled 2026-10-13:
    /// every control that cannot be pressed, not only a kit Button). Left to
    /// the system, a disabled one is RECOLOURED grey from the tint rather than
    /// dimmed, so "you cannot press this" read two ways on one screen — the
    /// Manuscript dock's Save grey beside a held kit button. The accent is set
    /// as the label's own foreground, which `.borderless` keeps when disabled
    /// (`HeldTests`), and `.borderless` keeps the system's pressed feedback.
    ///
    /// A word is `--accent-text` (the 4.5 floor applies below 14pt bold, and
    /// `--accent` is 3.67:1 in dark, ADR-069 — the tint drew these words at
    /// it); a glyph is `--accent`, a graphic.
    func kitHeldAction(_ held: Bool = false, glyph: Bool = false) -> some View {
        foregroundStyle(glyph ? Theme.accent : Theme.accentText)
            .buttonStyle(.borderless)
            .kitHeld(held)
    }
}
