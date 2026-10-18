import SwiftUI

/// Primary CTA button — brick accent fill, mirrors the web's .btn-primary.
struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                if isLoading {
                    ProgressView().tint(Theme.accentFg)
                }
                Text(title).font(.sans(15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s3)
            .foregroundStyle(Theme.accentFg)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        // §6.1 State — Held: busy, or disabled by the caller.
        .kitHeld(isLoading)
    }
}
