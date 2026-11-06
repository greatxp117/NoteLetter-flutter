import SwiftUI

/// Kit §20.3 Shelves at add (5.73.0, ADR-238): the caps label, the §20 row of
/// chips and `+ Shelf`, and the sentence, over a local choice. Nothing is written
/// until the card adds, so a chip comes and goes at once. The sheet has one add,
/// so [disabled] holds the row while it is in flight. At ten chosen the add control
/// is held and the sentence says why: an eleventh is held here rather than refused
/// by the endpoint. The card's §14.2 line is the host's.
struct ShelfRow: View {
    @ObservedObject var store: ShelfStore
    let disabled: Bool
    let onAdd: () -> Void

    private var full: Bool { store.chosen.count >= ShelfPick.maxAtAdd }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHELVES")
                .font(.mono(10))
                .tracking(1.3)
                .foregroundStyle(Theme.fgSubtle)
            ShelfFlow(spacing: 5) {
                ForEach(store.chosenShelves) { shelf in
                    ShelfChip(shelf: shelf, disabled: disabled) { store.takeOff(shelf.id) }
                }
                ShelfAddControl(disabled: disabled || full, action: onAdd)
            }
            Text(full ? "Ten is the most one add can carry." : "Optional. NoteLetter still adds its own as it reads.")
                .font(.sans(12))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// §20's direct chip: a 6px dot in the shelf's colour, the border in that colour,
/// the title, and a remove control that says what comes off.
private struct ShelfChip: View {
    let shelf: Shelf
    let disabled: Bool
    let onRemove: () -> Void

    var body: some View {
        let colour = Theme.shelfColor(shelf.color)
        HStack(spacing: 0) {
            ShelfDot(size: 6, color: colour)
            Text(shelf.title)
                .font(.sans(11))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
                .padding(.leading, 5)
                .padding(.trailing, 3)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.fgSubtle)
                    .frame(width: 16, height: 16)
                    // A 16px mark on a phone: the press reaches past it.
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.borderless)
            .kitHeld(disabled)
            .accessibilityLabel("Take \(shelf.title) off")
        }
        .frame(height: 20)
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(colour ?? Theme.borderStrong, lineWidth: 1)
        )
    }
}

/// §20's add control: dashed, `+ Shelf`, always present.
private struct ShelfAddControl: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Shelf").font(.sans(11))
            }
            .foregroundStyle(Theme.fgSubtle)
            .frame(height: 20)
            .padding(.horizontal, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.borderless)
        .kitHeld(disabled)
        .accessibilityLabel("Add a shelf")
    }
}

/// A shelf's dot: its stored colour with the hairline every swatch carries (§6.2).
struct ShelfDot: View {
    let size: CGFloat
    let color: Color?

    var body: some View {
        Circle()
            .fill(color ?? Theme.fgSubtle)
            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// Children left to right, wrapping (§20's row, and the form's swatches).
struct ShelfFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let spots = arrange(subviews, width: width)
        return CGSize(
            width: proposal.width ?? spots.width,
            height: spots.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let spots = arrange(subviews, width: bounds.width)
        for (subview, spot) in zip(subviews, spots.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + spot.minX, y: bounds.minY + spot.minY),
                proposal: ProposedViewSize(spot.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, widest, y + line)
    }
}
