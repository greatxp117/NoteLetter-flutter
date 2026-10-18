import Foundation
import UniformTypeIdentifiers

/// The upload allowlist, client side (4.10.0, ADR-046; video 4.13.0, ADR-049).
///
/// The backend's `fn_create_upload_session` is the authority and refuses with a
/// 400 — this exists so the picker can filter, so the share extension can say
/// "not this file" before it uploads anything, and so a refusal says the
/// server's words. It never replaces that check: every call site still renders
/// the server's message.
///
/// Mirror of `NoteLetter-web/src/uploadTypes.js` and Flutter's
/// `lib/shared/upload_types.dart`; spec `api/uploads.md` §The accepted set is
/// closed. **Compiled into BOTH targets** (app and share extension), like
/// `URLContentType.swift`, so the two cannot disagree.
///
/// Until this file iOS knew three extensions — `.pdf`, `.docx`, `.txt` — and
/// sent everything else as `application/octet-stream`. The picker offered only
/// those three, so a deck, a recording or a video could not be chosen at all,
/// and the share extension sent a `.pptx` or an `.m4a` as "unknown".
enum UploadTypes {
    static let audioExts = ["m4a", "mp3", "wav", "aac", "m4b", "ogg", "oga", "opus",
                            "flac", "caf", "aiff", "aif", "wma", "amr"]
    static let imageExts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp",
                            "tif", "tiff", "avif"]
    static let textExts = ["txt", "text", "md", "markdown", "rst"]
    /// 'mp4'/'webm'/'3gp' are on THIS list and on the audio MIME branch — the
    /// MIME separates `audio/mp4` from `video/mp4` — and absent from
    /// `audioExts`, so an untyped one resolves to video, as on the server.
    /// `ts` is deliberately absent: it is also TypeScript, which `codeExts`
    /// claims first.
    static let videoExts = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv", "flv",
                            "3gp", "mpg", "mpeg", "mts", "m2ts", "ogv"]

    static let docxMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    static let pptxMime = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    /// 4.115.0 (ADR-152) — a book, read by the server in spine order.
    static let epubMime = "application/epub+zip"

    /// Source files decode as valid UTF-8 and would make a *correct* document —
    /// a product rule, not a defect fix, so the refusal says what they are.
    static let codeExts: Set<String> = [
        "py", "pyw", "ipynb", "js", "mjs", "cjs", "jsx", "ts", "tsx", "json", "jsonl",
        "yaml", "yml", "toml", "ini", "cfg", "env", "css", "scss", "sass", "less",
        "html", "htm", "xml", "svg", "vue", "svelte", "sh", "bash", "zsh", "fish",
        "ps1", "bat", "cmd", "sql", "graphql", "proto", "java", "kt", "kts", "swift",
        "m", "mm", "rb", "go", "rs", "c", "h", "cpp", "cc", "hpp", "cs", "php",
        "pl", "pm", "lua", "r", "jl", "scala", "clj", "ex", "exs", "erl", "hs",
        "dart", "gradle", "cmake", "mk", "dockerfile", "tf", "patch", "diff", "lock",
    ]

    /// Every extension the server accepts, for the picker.
    static var allowedExtensions: [String] {
        ["pdf", "docx", "pptx", "epub"] + imageExts + textExts + audioExts + videoExts
    }

    /// The reference's help copy, kept beside the list so they cannot drift.
    static let acceptHelp =
        "PDF, EPUB, Word, PowerPoint, Markdown, plain text, images, audio recordings, or video"

    /// The picker's filter: one type per accepted extension — the table, not a
    /// family. `.movie` would also admit `.ts`, which the server refuses.
    static var pickerTypes: [UTType] {
        var out: [UTType] = []
        for ext in allowedExtensions {
            guard let t = UTType(filenameExtension: ext), !out.contains(t) else { continue }
            out.append(t)
        }
        return out
    }

    // MARK: The per-type cap (4.13.0, ADR-049)

    static let capMBDefault = 100
    static let capMB: [String: Int] = ["video": 2048]

    static func capLabel(_ mb: Int) -> String { mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB" }

    static func ext(of name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    // MARK: The MIME this client declares

    /// The MIME to declare for a file this client only knows by NAME — a
    /// picked URL, a shared file. Derived from the extension by a fixed table,
    /// so it is the same on every OS version and always one the server's
    /// allowlist row for that extension accepts. An extension outside the set
    /// gets `application/octet-stream`, and `rejection` then refuses it in the
    /// server's own words before anything is uploaded.
    static func mimeType(forFilename name: String) -> String {
        let e = ext(of: name)
        switch e {
        case "pdf": return "application/pdf"
        case "docx": return docxMime
        case "pptx": return pptxMime
        case "epub": return epubMime
        case "jpg", "jpeg": return "image/jpeg"
        case "tif", "tiff": return "image/tiff"
        case "m4a", "m4b": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "aif", "aiff": return "audio/aiff"
        case "caf": return "audio/x-caf"
        case "wma": return "audio/x-ms-wma"
        case "oga": return "audio/ogg"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "mkv": return "video/x-matroska"
        case "avi": return "video/x-msvideo"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp": return "video/3gpp"
        case "mpg", "mpeg": return "video/mpeg"
        case "mts", "m2ts": return "video/mp2t"
        case "ogv": return "video/ogg"
        default:
            if imageExts.contains(e) { return "image/\(e)" }
            if textExts.contains(e) { return "text/plain" }
            if audioExts.contains(e) { return "audio/\(e)" }
            if videoExts.contains(e) { return "video/\(e)" }
            return "application/octet-stream"
        }
    }

    // MARK: The rule

    /// Mirror of the backend rule. A refusal sentence, or nil when the file is
    /// worth sending — nil is NOT an accept; the server still decides.
    static func rejection(name: String, size: Int, mimeType: String) -> String? {
        let mime = (mimeType.split(separator: ";").first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()
        let e = ext(of: name)

        if codeExts.contains(e) {
            return "Source code files aren’t supported (.\(e))."
        }
        // Legacy binary Office formats name their own remedy: every route to
        // reading one is a system binary the backend does not carry.
        if e == "ppt" || mime == "application/vnd.ms-powerpoint" {
            return "Legacy .ppt files aren’t supported — re-save as .pptx and upload again."
        }
        if e == "doc" || mime == "application/msword" {
            return "Legacy .doc files aren’t supported — re-save as .docx and upload again."
        }
        if mime.hasPrefix("application/vnd.google-apps.") {
            return "“\(name)” isn’t a supported file type. \(acceptHelp)."
        }

        // The class is resolved BEFORE the size, because the cap is per-type.
        func tooBig(_ docType: String) -> String? {
            let cap = capMB[docType] ?? capMBDefault
            return size > cap * 1024 * 1024 ? "That file is over the \(capLabel(cap)) limit." : nil
        }

        let classes: [(Bool, [String], String)] = [
            (mime == "application/pdf", ["pdf"], "pdf"),
            (mime.contains("word"), ["docx"], "docx"),
            (mime.contains("presentation"), ["pptx"], "pptx"),
            (mime == epubMime, ["epub"], "epub"),
            (mime.hasPrefix("image/"), imageExts, "image"),
            (mime.hasPrefix("audio/"), audioExts + ["mp4", "webm", "3gp"], "audio"),
            (mime.hasPrefix("video/"), videoExts, "video"),
            (mime == "text/plain", textExts + [""], "plain"),
        ]
        for (matches, exts, docType) in classes where matches {
            if !e.isEmpty, !exts.contains(e) {
                return "“\(name)” is declared as \(mime) but has a .\(e) extension."
            }
            return tooBig(docType)
        }

        // MIME unhelpful (empty / octet-stream / vendor) — the extension decides.
        let byExt: [([String], String)] = [
            (["pdf"], "pdf"), (["docx"], "docx"), (["pptx"], "pptx"), (["epub"], "epub"),
            (imageExts, "image"), (textExts, "plain"),
            (audioExts, "audio"), (videoExts, "video"),
        ]
        for (exts, docType) in byExt where exts.contains(e) {
            return tooBig(docType)
        }
        return "“\(name)” isn’t a supported file type. \(acceptHelp)."
    }

    /// The file's size without reading it — the cap is checked BEFORE a
    /// multi-gigabyte video is pulled into memory. Nil when the provider will
    /// not say, and then the server's 413 is the answer.
    static func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}
