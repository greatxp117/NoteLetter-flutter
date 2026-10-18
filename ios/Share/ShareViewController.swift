import UIKit
import SwiftUI
import UniformTypeIdentifiers
import FirebaseCore
import FirebaseAuth

/// Content extracted from the host app's share sheet, ready for the upload pipeline.
enum SharedContent {
    case url(URL)
    case images([UploadItem])
    case file(UploadItem)
    /// Something was shared that this extension HANDLES, and it could not be
    /// read — an iCloud file that has not come down, a security-scoped URL the
    /// provider would not open, a photo the library refused (D6).
    ///
    /// It used to collapse into `.none`, which the sheet renders as "Nothing to
    /// share / This kind of content isn't supported yet." — the TYPE blamed for
    /// a READ failure. The reader's next move is completely different for the
    /// two: one is "share something else", the other is "wait for the download
    /// and try again", and they were told the first for both.
    case unreadable(String)
    /// A file this extension read and the server would REFUSE — outside the
    /// closed upload set (`api/uploads.md`, 4.10.0 ADR-046) or over its cap.
    /// Said before anything is uploaded, in the server's own words
    /// (`UploadTypes.rejection`). The activation rule (Info.plist) now offers
    /// NoteLetter only for the accepted types, so what is left to say here is
    /// a file over its type's cap, or one whose name and type disagree — the
    /// server still decides. Until this case existed a `.pptx`, an
    /// `.m4a` or a video went up as `application/octet-stream`, and an
    /// unsupported file's 400 was the first anyone heard of it.
    case refused(filename: String, reason: String)
    case none
}

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // The app's faces, from this bundle: an extension inherits nothing of
        // the containing app's registered fonts, and without this the sheet
        // set itself in the system font.
        FontLoader.registerBundledFonts()

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // Before any Auth use: a DEBUG extension goes where the DEBUG app beside
        // it went (EmulatorConfig reads the App Group), and a RELEASE one to
        // prod. The extension files documents of its own through `fn_*`, so it
        // needs the same escape from prod the app has.
        EmulatorConfig.activateAuthAndFunctions()
        // The keychain group the Flutter app writes its Firebase session into
        // (AppDelegate.swift, F-122) — this app's OWN, never the retired Swift
        // app's `xp.NoteLetter.shared` (ruled 2026-10-18: start fresh).
        try? Auth.auth().useUserAccessGroup("3SA8A2JP3T.xp.NoteLetter.Flutter.shared")

        Task {
            // A DEBUG build with no emulator address refuses, as the debug app
            // does (lib/main.dart): umbrella law 1.
            let content: SharedContent = EmulatorConfig.refusesProd
                ? .unreadable("This debug build is not pointed at the emulator. Open the app through tool/dev.sh first.")
                : await Self.extractContent(from: extensionContext)
            await MainActor.run {
                let shareView = ShareView(content: content) { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
                let hosting = UIHostingController(rootView: shareView)
                addChild(hosting)
                hosting.view.frame = view.bounds
                hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(hosting.view)
                hosting.didMove(toParent: self)
            }
        }
    }

    /// The provider's answer AND its rejection — the second used to be bound to
    /// `_` (D6), which is where the misattribution started.
    private static func loadItem(_ provider: NSItemProvider,
                                 typeIdentifier: String) async -> (NSSecureCoding?, Error?) {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                continuation.resume(returning: (item, error))
            }
        }
    }

    /// Reads a security-scoped URL, saying why not rather than answering nil.
    private static func readData(at url: URL) -> Result<Data, Error> {
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
        do {
            // Mapped: an extension's memory ceiling is a fraction of the app's.
            return .success(try Data(contentsOf: url, options: .alwaysMapped))
        } catch {
            return .failure(error)
        }
    }

    private static func extractContent(from context: NSExtensionContext?) async -> SharedContent {
        guard let item = context?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else { return .none }

        // Why a provider we DO handle could not be read. Held until the end:
        // a second attachment may still work, and only an empty-handed scan
        // gets to report this (D6).
        var unreadable: String?

        // A LINK is a web address. A file from Files carries a `public.url`
        // too — `public.file-url` conforms to it — and this loop used to take
        // it first: every file shared from Files was drawn as "Link ·
        // file:///…", filed as an Article, its type never checked, so the
        // `.refused` branch below was unreachable from there (seen on the
        // simulator, 2026-10-07). A file URL is held for the file branch, so
        // an image file still reaches the image branch first, as it would
        // from Photos.
        var fileURLs: [URL] = []
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let (item, error) = await loadItem(provider, typeIdentifier: UTType.url.identifier)
            if let url = item as? URL {
                if url.isFileURL { fileURLs.append(url); continue }
                return .url(url)
            }
            if let error { unreadable = unreadable ?? readFailure(error) }
        }

        var images: [UploadItem] = []
        for (index, provider) in attachments.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            switch await loadImageData(from: provider) {
            case .success(let data):
                images.append(UploadItem(data: data, filename: "image_\(index).jpg", mimeType: "image/jpeg"))
            case .failure(let error):
                unreadable = unreadable ?? readFailure(error)
            }
        }
        if !images.isEmpty {
            return .images(images)
        }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let (item, error) = await loadItem(provider, typeIdentifier: UTType.fileURL.identifier)
            if let error { unreadable = unreadable ?? readFailure(error); continue }
            if let url = item as? URL, !fileURLs.contains(url) { fileURLs.append(url) }
        }

        for url in fileURLs {
            let filename = url.lastPathComponent
            let mimeType = UploadTypes.mimeType(forFilename: filename)
            // Refused before the read, so an unsupported or oversized file is
            // never pulled into an extension's small memory budget.
            let didStartScope = url.startAccessingSecurityScopedResource()
            let size = UploadTypes.fileSize(at: url)
            if didStartScope { url.stopAccessingSecurityScopedResource() }
            if let refusal = UploadTypes.rejection(name: filename, size: size ?? 0, mimeType: mimeType) {
                return .refused(filename: filename, reason: refusal)
            }
            switch readData(at: url) {
            case .success(let data):
                return .file(UploadItem(data: data, filename: filename, mimeType: mimeType))
            case .failure(let error):
                unreadable = unreadable ?? readFailure(error)
            }
        }

        // An attachment we handle that would not open is NOT an unsupported
        // type, and this is the line that says so.
        if let unreadable { return .unreadable(unreadable) }
        return .none
    }

    /// The sentence for a provider that would not hand the item over.
    ///
    /// The system's own words, because they are the ones that distinguish the
    /// cases the reader can act on — an iCloud file that has not downloaded, a
    /// photo in a shared album, a scope that was revoked when the sheet opened
    /// — and a constant of ours would flatten all three into "couldn't read
    /// it". Named as a read failure so the sentence is never mistaken for a
    /// statement about the kind of thing that was shared.
    static func readFailure(_ error: Error) -> String {
        "It couldn’t be read — \(error.localizedDescription)"
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Result<Data, Error> {
        let (item, error) = await loadItem(provider, typeIdentifier: UTType.image.identifier)
        if let error { return .failure(error) }
        guard let item else { return .failure(CocoaError(.fileReadUnknown)) }
        if let url = item as? URL {
            return readData(at: url).map { UIImage(data: $0)?.jpegData(compressionQuality: 0.9) ?? $0 }
        }
        if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
            return .success(data)
        }
        if let data = item as? Data {
            return .success(UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data)
        }
        return .failure(CocoaError(.fileReadCorruptFile))
    }

}
