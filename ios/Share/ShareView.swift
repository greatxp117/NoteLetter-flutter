import SwiftUI
import FirebaseAuth

struct ShareView: View {
    let content: SharedContent
    let onDone: () -> Void

    @StateObject private var vm = UploadViewModel()
    @State private var imageSetTitle: String = ""
    @State private var successMessage: String?
    @State private var didComplete = false

    private let isSignedIn = Auth.auth().currentUser != nil

    init(content: SharedContent, onDone: @escaping () -> Void) {
        self.content = content
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
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

                Spacer()
            }
            .padding(Spacing.s4)
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
                PrimaryButton(title: "Upload File", isLoading: vm.isUploading) {
                    Task { await uploadFile(item) }
                }
                .disabled(vm.isUploading || didComplete)
            }
        }
    }

    private func ingest(_ url: URL) async {
        guard let answer = await vm.ingestUrl(url.absoluteString, type: URLContentType.classify(url)) else { return }
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
        if await vm.uploadImageSet(items, title: title.isEmpty ? nil : title) {
            await finish(message: "Uploaded \(items.count) photo(s).")
        }
    }

    private func uploadFile(_ item: UploadItem) async {
        if await vm.uploadSingleFile(item) {
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
