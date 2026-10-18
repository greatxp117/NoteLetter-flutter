import SwiftUI

/// A bordered, raised surface card mirroring the web's .surface card pattern.
struct AppCard<Content: View>: View {
    var padding: CGFloat = Spacing.s4
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}
