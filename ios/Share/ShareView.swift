import SwiftUI
import FirebaseAuth

struct ShareView: View {
    let content: SharedContent
    let onDone: () -> Void

    @StateObject private var vm = UploadViewModel()
    /// Kit §20.3 (5.73.0, ADR-238): a share starts with none chosen, for the life
    /// of this sheet.
    @StateObject private var shelves = ShelfStore()
    @State private var imageSetTitle: String = ""
    @State private var successMessage: String?
    @State private var didComplete = false
    /// §20.1's picker, over the card.
    @State private var picking = false
    /// The create form: the card gives way to it, and everything shared, typed and
    /// chosen here waits underneath, whichever way the form is left.
    @State private var creating = false
    @State private var creatingName = ""

    private let isSignedIn = Auth.auth().currentUser != nil

    init(content: SharedContent, onDone: @escaping () -> Void) {
        self.content = content
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView { cards }
                if picking { picker }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg)
            .navigationTitle("Add to NoteLetter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Nothing is cancelled once the request has landed.
                    Button(didComplete ? "Done" : "Cancel") { onDone() }
                        // A word in the bar: --accent-text (ruled 2026-10-14).
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        // Its own sheet, so a swipe-down closes the form and not the share: pushed
        // onto this stack, the same swipe would take the whole extension with it.
        .sheet(isPresented: $creating) {
            NavigationStack {
                ShelfForm(
                    initialName: creatingName,
                    shelves: shelves.shelves,
                    onCreated: { shelf in
                        shelves.adopt(shelf)
                        creating = false
                    },
                    onCancel: { creating = false }
                )
            }
        }
        .onAppear {
            // Only for a reader with something to add: a signed-out sheet, or one
            // with nothing it can file, asks for nobody's shelves.
            if isSignedIn && hasAcceptedItem { shelves.start() }
        }
    }

    /// A card for what was shared, then the request's §14.2 line or its success.
    private var cards: some View {
        VStack(spacing: Spacing.s4) {
            if !isSignedIn {
                signedOutCard
            } else {
                switch content {
                case .url(let url):
                    linkCard(url)
                case .images(let items):
                    imagesCard(items)
                case .file(let item):
                    fileCard(item)
                case .unreadable(let reason):
                    unreadableCard(reason)
                case .refused(let filename, let reason):
                    refusedCard(filename: filename, reason: reason)
                case .none:
                    unsupportedCard
                }
            }

            // §14.2, from the kit: the same 13pt critical line this drew by
            // hand, in the one component that owns the shape (D6).
            if let errorMessage = vm.errorMessage {
                KitFailureInline(errorMessage)
            }
            if let successMessage {
                Text(successMessage).foregroundStyle(Theme.positiveText).metaStyle()
            }
        }
        .padding(Spacing.s4)
    }

    private var hasAcceptedItem: Bool {
        switch content {
        case .url, .images, .file: return true
        case .unreadable, .refused, .none: return false
        }
    }

    /// Kit §20.3, between a card's lines and its button.
    private var shelfRow: some View {
        ShelfRow(store: shelves, disabled: vm.isUploading || didComplete) {
            picking = true
        }
    }

    /// §20.1, full-width over the card. A press outside closes it and writes
    /// nothing.
    @ViewBuilder
    private var picker: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { picking = false }
        ShelfPicker(
            shelves: shelves.shelves,
            phase: shelves.phase,
            onItem: shelves.chosenShelves,
            onPick: { id in
                shelves.choose(id)
                picking = false
            },
            onCreate: { name in
                picking = false
                creatingName = name
                creating = true
            },
            onClose: { picking = false }
        )
        .padding(Spacing.s4)
    }

    private var signedOutCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Sign in required").h3Style()
                Text("Sign in to NoteLetter to share content to your library.")
                    .metaStyle()
            }
        }
    }

    /// A thing we HANDLE that would not open. Distinct from the card below,
    /// because "wait for the download and try again" and "share something
    /// else" are different next moves and both were told the second (D6).
    private func unreadableCard(_ reason: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Couldn’t read what you shared").h3Style()
                KitFailureInline(reason)
            }
        }
    }

    /// A file outside the closed upload set, or over its cap — refused here,
    /// before an upload, in the server's own sentence (§14.2). No upload
    /// button: there is nothing this file can do but be shared as something
    /// else.
    private func refusedCard(filename: String, reason: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Can’t add this file").h3Style()
                Text(filename).metaStyle()
                KitFailureInline(reason)
            }
        }
    }

    private var unsupportedCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Nothing to share").h3Style()
                Text("This kind of content isn't supported yet.")
                    .metaStyle()
            }
        }
    }

    @ViewBuilder
    private func linkCard(_ url: URL) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Link").eyebrowStyle()
                    Text(url.absoluteString)
                        .metaStyle()
                        .lineLimit(2)
                        .truncationMode(.middle)
                    // INV-07: the type is DETECTED, never asked. The picker
                    // this replaced offered four types and no podcast.
                    Text("Files as: " + URLContentType.label(URLContentType.classify(url)))
                        .metaStyle()
                }
                shelfRow
                PrimaryButton(title: "Add to NoteLetter", isLoading: vm.isUploading) {
                    Task { await ingest(url) }
                }
                .disabled(vm.isUploading || didComplete)
            }
        }
    }

    @ViewBuilder
    private func imagesCard(_ items: [UploadItem]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Photos").eyebrowStyle()
                    Text("\(items.count) photo\(items.count == 1 ? "" : "s") selected")
                        .metaStyle()
                    // Verbatim (sources.md §Endpoints used, 5.10.0, ADR-170):
                    // a share is always one set, and the server joins one that
                    // is a scroll into one picture.
                    Text("Screenshots of one long scroll are joined into one picture.")
                        .metaStyle()
                }
                TextField("Title (optional)", text: $imageSetTitle)
                    .kitField()
                shelfRow
                PrimaryButton(title: "Upload Photos", isLoading: vm.isUploading) {
                    Task { await uploadImages(items) }
                }
                .disabled(vm.isUploading || didComplete)
            }
        }
    }

    @ViewBuilder
    private func fileCard(_ item: UploadItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("File").eyebrowStyle()
                    Text(item.filename).metaStyle()
                }
                shelfRow
                PrimaryButton(title: "Upload File", isLoading: vm.isUploading) {
                    Task { await uploadFile(item) }
                }
                .disabled(vm.isUploading || didComplete)
            }
        }
    }

    private func ingest(_ url: URL) async {
        guard let answer = await vm.ingestUrl(url.absoluteString, type: URLContentType.classify(url), tagIds: shelves.chosen) else { return }
        // A playlist is one success said with its measured count (4.114.0,
        // ADR-151; the cut last, 5.2.0). Up to four sentences cannot be read
        // in the 0.8 s a single link's line is given, so the sheet stays until
        // the reader closes it.
        if let playlist = PlaylistAnswer.sentence(answer) {
            successMessage = playlist
            didComplete = true
            return
        }
        await finish(message: UploadViewModel.linkAdded(answer))
    }

    private func uploadImages(_ items: [UploadItem]) async {
        let title = imageSetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if await vm.uploadImageSet(items, title: title.isEmpty ? nil : title, tagIds: shelves.chosen) {
            await finish(message: "Uploaded \(items.count) photo(s).")
        }
    }

    private func uploadFile(_ item: UploadItem) async {
        if await vm.uploadSingleFile(item, tagIds: shelves.chosen) {
            await finish(message: "Uploaded \(item.filename).")
        }
    }

    private func finish(message: String) async {
        successMessage = message
        didComplete = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        onDone()
    }
}
