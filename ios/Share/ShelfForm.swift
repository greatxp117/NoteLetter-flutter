import SwiftUI

/// `screens/library.md` §Creating a shelf's form on a capture surface (kit §20.3,
/// 5.73.0, ADR-238): the name, *What belongs here?*, *Inside* and the colour, and
/// no *Find sources that belong here*, whose proposal waits in For your review, a
/// screen this surface does not have. An extension cannot open its app, so the
/// form is here. The card gives way to it and comes back with the shelf chosen;
/// Cancel or a swipe-down writes nothing and loses nothing of the share. A refusal
/// stays here in the server's sentence (§14.2).
struct ShelfForm: View {
    static let titleMax = 50
    static let descriptionMax = 300

    let shelves: [Shelf]
    let onCreated: (Shelf) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var description = ""
    @State private var color = Theme.shelfSwatches[0].id
    @State private var inside = ""
    @State private var pickingInside = false
    @State private var busy = false
    @State private var error: String?

    init(initialName: String, shelves: [Shelf], onCreated: @escaping (Shelf) -> Void, onCancel: @escaping () -> Void) {
        self.shelves = shelves
        self.onCreated = onCreated
        self.onCancel = onCancel
        _name = State(initialValue: String(
            initialName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.titleMax)
        ))
    }

    private var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("It goes on what you add next.").metaStyle()
                    labelled("Name") {
                        TextField(
                            "Shelf name…",
                            text: Binding(get: { name }, set: { name = String($0.prefix(Self.titleMax)) })
                        )
                        .font(.serif(16))
                        .kitField()
                        .disabled(busy)
                    }
                    labelled("What belongs here?") {
                        TextField(
                            "Optional — a sentence helps NoteLetter recognise what to file here.",
                            text: Binding(
                                get: { description },
                                set: { description = String($0.prefix(Self.descriptionMax)) }
                            ),
                            axis: .vertical
                        )
                        .font(.sans(14))
                        .lineLimit(2...4)
                        .kitField()
                        .disabled(busy)
                    }
                    if !shelves.isEmpty {
                        labelled("Inside") { insideTrigger }
                    }
                    labelled("Colour") { swatches }
                    if let error { KitFailureInline(error) }
                    PrimaryButton(title: busy ? "Creating…" : "Create shelf", isLoading: busy) {
                        Task { await create() }
                    }
                    .disabled(title.isEmpty || busy)
                }
                .padding(Spacing.s4)
            }
            if pickingInside {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { pickingInside = false }
                ShelfPicker(
                    shelves: shelves,
                    phase: .loaded,
                    none: "Top level",
                    selected: inside,
                    onPick: { id in
                        inside = id
                        pickingInside = false
                    },
                    onClose: { pickingInside = false }
                )
                .padding(Spacing.s4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .navigationTitle("New shelf")
        .navigationBarTitleDisplayMode(.inline)
        // A swipe-down is this sheet's own Cancel. Held while the write is in flight,
        // so a create cannot be dismissed into looking like it never ran.
        .interactiveDismissDisabled(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // As the sheet's own bar word. `.borderless` here cut it to "Ca…" on a
                // real frame, so this does not take `kitHeldAction`.
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Theme.accentText)
                    // Esc, on a hardware keyboard, unless the select is open: then
                    // it closes the select.
                    .keyboardShortcut(pickingInside ? nil : .cancelAction)
                    .kitHeld(busy)
            }
        }
    }

    /// `.sf-field`: a mono caps label at `--fg-subtle` over its control.
    private func labelled<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.mono(10))
                .tracking(1)
                .foregroundStyle(Theme.fgSubtle)
            control()
        }
    }

    /// §20.2's trigger: the chosen shelf's dot and title, or the none label, and a
    /// chevron.
    private var insideTrigger: some View {
        let chosen = shelves.first { $0.id == inside }
        return Button {
            pickingInside = true
        } label: {
            HStack(spacing: 8) {
                if let chosen {
                    ShelfDot(size: 8, color: Theme.shelfColor(chosen.color))
                } else {
                    Circle()
                        .stroke(Theme.borderStrong, lineWidth: 1)
                        .frame(width: 8, height: 8)
                }
                Text(chosen?.title ?? "Top level")
                    .font(.sans(13))
                    .foregroundStyle(chosen == nil ? Theme.fgMuted : Theme.fg)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSubtle)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(minWidth: 180)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .kitHeld(busy)
        .accessibilityLabel("The shelf this one goes inside")
        .accessibilityValue(chosen?.title ?? "Top level")
    }

    private var swatches: some View {
        ShelfFlow(spacing: 4) {
            ForEach(Theme.shelfSwatches, id: \.id) { swatch in
                Button {
                    color = swatch.id
                } label: {
                    // `.ss-swatch`: one 24 circle whatever its state, the 2px
                    // --fg ring on its edge when chosen and the hairline inside.
                    Circle()
                        .fill(Theme.shelfColor(swatch.id) ?? Theme.fgSubtle)
                        .overlay(Circle().inset(by: color == swatch.id ? 2 : 0).stroke(Theme.border, lineWidth: 1))
                        .overlay(Circle().inset(by: 1).stroke(color == swatch.id ? Theme.fg : Color.clear, lineWidth: 2))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .kitHeld(busy)
                .accessibilityLabel(swatch.label)
                .accessibilityAddTraits(color == swatch.id ? .isSelected : [])
            }
        }
    }

    /// Write before you move: `fn_create_tag`, and the sheet comes back only once
    /// it resolved. The key set is closed (`api/tags.md`).
    private func create() async {
        let title = self.title
        guard !title.isEmpty, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }

        var body: [String: Any] = [
            "title": title,
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "color": color,
        ]
        if !inside.isEmpty { body["parentTagId"] = inside }

        do {
            let answer = try await APIClient.call("fn_create_tag", method: .post, body: body)
            guard let id = answer["tagId"] as? String, !id.isEmpty else {
                // A 2xx with no id is not a shelf that can go on anything.
                error = "The shelf was not created."
                return
            }
            onCreated(Shelf(
                id: id,
                title: title,
                color: color,
                documentCount: 0,
                parentId: inside.isEmpty ? nil : inside
            ))
        } catch let e as ApiError {
            error = e.message
        } catch let e {
            error = e.localizedDescription
        }
    }
}
