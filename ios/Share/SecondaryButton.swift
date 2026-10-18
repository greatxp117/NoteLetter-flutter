import SwiftUI

/// Secondary CTA button — plum/chrome fill, mirrors the web's .btn-secondary.
struct SecondaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                if isLoading {
                    ProgressView().tint(Theme.secondaryFg)
                }
                Text(title).font(.sans(15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s3)
            .foregroundStyle(Theme.secondaryFg)
            .background(Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        // §6.1 State — Held: busy, or disabled by the caller.
        .kitHeld(isLoading)
    }
}
