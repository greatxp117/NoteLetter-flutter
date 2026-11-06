import SwiftUI

/// §20.1's Shelf picker on the share sheet (5.73.0, ADR-238): find a shelf by
/// typing, or make the one that does not exist yet, over the card and full-width
/// (`share-sheet.md` §Shelves). In §20.2's select form it takes a none row and the
/// value, and with no [onCreate] it has no create row: the form's *Inside* select
/// cannot open a second form. The rules are `ShelfPick` and `ShelfTree`.
///
/// While the read is on its way the list has nothing to say yet, so it says
/// nothing and offers no create row: *No shelves yet.* would be a claim about a
/// read that has not landed, and a name cannot be checked against what has not
/// arrived.
struct ShelfPicker: View {
    /// Every shelf, for the tree order and the path prefix.
    let shelves: [Shelf]
    let phase: ShelfStore.Phase
    /// What the item already carries, which the list leaves out.
    let onItem: [Shelf]
    /// §20.2: the none row's label, first while nothing is typed.
    let none: String?
    /// §20.2: the value, `""` for none. The chosen row carries a check.
    let selected: String?
    let onPick: (String) -> Void
    /// The create row, with the query. nil draws no create row.
    let onCreate: ((String) -> Void)?
    let onClose: () -> Void

    /// Built once per picker: every row reads it, and a library's shelves number in
    /// the hundreds.
    private let tree: ShelfTree

    @State private var q = ""
    @State private var active = 0
    @FocusState private var focused: Bool

    init(
        shelves: [Shelf],
        phase: ShelfStore.Phase,
        onItem: [Shelf] = [],
        none: String? = nil,
        selected: String? = nil,
        onPick: @escaping (String) -> Void,
        onCreate: ((String) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.shelves = shelves
        self.phase = phase
        self.onItem = onItem
        self.none = none
        self.selected = selected
        self.onPick = onPick
        self.onCreate = onCreate
        self.onClose = onClose
        self.tree = ShelfTree(shelves)
    }

    private var addable: [Shelf] {
        let carried = Set(onItem.map(\.id))
        return tree.ordered().filter { !carried.contains($0.id) }
    }

    private var creates: Bool { onCreate != nil && phase == .loaded }

    private var lead: Int { none != nil && q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0 }

    var body: some View {
        let addable = self.addable
        let rows = ShelfPick.rows(addable, q)
        let state = ShelfPick.state(onItem: onItem, addable: addable, q: q, rows: rows)
        let count = lead + rows.count + (creates ? 1 : 0)
        let cur = max(0, min(active, count - 1))

        VStack(spacing: 0) {
            field(rows: rows, state: state, cur: cur, count: count)
            Divider().overlay(Theme.rule)
            list(rows: rows, state: state, cur: cur)
            if creates {
                Divider().overlay(Theme.rule)
                row(index: lead + rows.count, cur: cur) {
                    createRow(state.createName)
                } action: {
                    choose(lead + rows.count, rows: rows, state: state)
                }
                .padding(5)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceRaised))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow2()
        .onAppear { focused = true }
        .background(
            // Esc on a hardware keyboard closes and writes nothing.
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    private func field(rows: [ShelfPick.Row], state: ShelfPick.State, cur: Int, count: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgSubtle)
            TextField(
                "",
                text: Binding(get: { q }, set: { q = $0; active = 0 }),
                prompt: Text("Find or create a shelf…")
                    .font(.serifItalic(16))
                    .foregroundColor(Theme.fgSubtle)
            )
            .font(.serif(16))
            .foregroundStyle(Theme.fg)
            .focused($focused)
            .autocorrectionDisabled()
            .submitLabel(.done)
            // A soft keyboard's Done chooses the active row.
            .onSubmit { choose(cur, rows: rows, state: state) }
            .modifier(ArrowKeys(active: $active, cur: cur, count: count))
            .accessibilityLabel("Find or create a shelf")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    @ViewBuilder
    private func list(rows: [ShelfPick.Row], state: ShelfPick.State, cur: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if lead > 0, let none {
                        row(index: 0, cur: cur) {
                            noneRow(none)
                        } action: {
                            choose(0, rows: rows, state: state)
                        }
                        .id(0)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.shelf.id) { i, r in
                        row(index: lead + i, cur: cur) {
                            shelfRow(r)
                        } action: {
                            choose(lead + i, rows: rows, state: state)
                        }
                        .id(lead + i)
                    }
                    switch phase {
                    case .loading:
                        ProgressView()
                            .tint(Theme.fgSubtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Reading your shelves")
                    case .failed:
                        sentence("Your shelves couldn’t be read.")
                    case .loaded:
                        if let empty = state.empty { sentence(empty) }
                    }
                }
                .padding(5)
            }
            // §20.1's list scrolls at 240, and stays no taller than it needs.
            .frame(maxHeight: min(240, listHeight(rows: rows.count + lead)))
            .onChange(of: cur) { i in
                if i < lead + rows.count { proxy.scrollTo(i) }
            }
        }
    }

    /// `ScrollView` would otherwise take all the height it is offered.
    private func listHeight(rows: Int) -> CGFloat {
        rows == 0 ? 56 : CGFloat(rows) * (Self.rowHeight + 1) + 9
    }

    private static let rowHeight: CGFloat = 40

    private func sentence(_ text: String) -> some View {
        Text(text)
            .font(.serifItalic(14))
            .foregroundStyle(Theme.fgMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 7, leading: 8, bottom: 8, trailing: 8))
    }

    private func row<Content: View>(
        index: Int,
        cur: Int,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(index == cur ? Theme.hoverStrong : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func shelfRow(_ r: ShelfPick.Row) -> some View {
        HStack(spacing: 9) {
            ShelfDot(size: 8, color: Theme.shelfColor(r.shelf.color))
            titleText(r)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Only a stored count is a figure (ADR-109). `--fg-muted`, not
            // `--fg-subtle`: it can sit on the active row's `--hover-strong`.
            if let n = r.shelf.documentCount {
                Text("\(n)")
                    .font(.mono(11))
                    .foregroundStyle(Theme.fgMuted)
            }
            if selected == r.shelf.id { check }
        }
    }

    /// The ancestor path, muted and never matched, then the title with its matched
    /// run at 600.
    private func titleText(_ r: ShelfPick.Row) -> Text {
        let title = r.shelf.title
        let base = Text("").font(.sans(13))
        var out = base
        if tree.parent[r.shelf.id] != nil {
            out = out + Text(tree.pathLabel(r.shelf.id) + ShelfTree.pathSeparator)
                .font(.sans(13))
                .foregroundColor(Theme.fgMuted)
        }
        if let run = r.match.run {
            out = out
                + Text(String(title[title.startIndex..<run.lowerBound])).font(.sans(13)).foregroundColor(Theme.fg)
                + Text(String(title[run])).font(.sans(13, weight: .semibold)).foregroundColor(Theme.fg)
                + Text(String(title[run.upperBound..<title.endIndex])).font(.sans(13)).foregroundColor(Theme.fg)
        } else {
            out = out + Text(title).font(.sans(13)).foregroundColor(Theme.fg)
        }
        return out
    }

    private func noneRow(_ none: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .stroke(Theme.borderStrong, lineWidth: 1)
                .frame(width: 8, height: 8)
            Text(none)
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected == "" { check }
        }
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12))
            .foregroundStyle(Theme.fgMuted)
    }

    private func createRow(_ name: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accentSoft))
            Group {
                if name.isEmpty {
                    Text("New shelf…").font(.sans(13))
                } else {
                    Text("Create ").font(.sans(13))
                        + Text("“\(name)”").font(.sans(13, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.fg)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func choose(_ i: Int, rows: [ShelfPick.Row], state: ShelfPick.State) {
        switch ShelfPick.choice(at: i, lead: lead, rows: rows, state: state, creates: creates) {
        case .none?:
            onPick("")
        case .shelf(let id)?:
            onPick(id)
        case .create(let name)?:
            onCreate?(name)
        case nil:
            break
        }
    }
}

/// ↑/↓ move the active row through the list and on to the create row, stopping at
/// the ends. A hardware keyboard's: `onKeyPress` is iOS 17, and the extension's
/// floor is 16, where the row is chosen by a press.
private struct ArrowKeys: ViewModifier {
    @Binding var active: Int
    let cur: Int
    let count: Int

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .onKeyPress(.downArrow) {
                    active = min(cur + 1, count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    active = max(cur - 1, 0)
                    return .handled
                }
        } else {
            content
        }
    }
}
