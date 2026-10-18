import XCTest
// F-122: the Flutter app's share extension (ios/Share), ported with its rule
// from the retired Swift app's NoteLetterShare (add943d). `UploadTypes.swift`
// is compiled into this bundle from ios/Share (tool/add_share_target.rb), so
// the accepted set these tests read is the extension's own.
import UniformTypeIdentifiers

/// The share extension's activation rule is the closed upload set
/// (`api/uploads.md`, 4.10.0 ADR-046) — the same list the picker filters to.
///
/// It was `NSExtensionActivationSupportsFileWithMaxCount = 1`: NoteLetter was
/// offered in the share sheet for ANY file — a `.zip`, a `.py`, anything — and
/// the refusal it was meant to fall back on (`SharedContent.refused`) was never
/// reached, because a file from Files also carries a `public.url` and the
/// extension filed it as a LINK (`file:///…`, "Files as: Article"), with an
/// enabled Add button. Both seen on the simulator (`DeviceRun/
/// ShareActivationTests`), 2026-10-07.
///
/// The rule is now a predicate. It is written by hand in `NoteLetterShare/
/// Info.plist` — a plist cannot call `UploadTypes` — so this is what keeps the
/// two lists one: every accepted non-image type is in the file clause, nothing
/// else is, and the predicate is EVALUATED here against the attachments the
/// share sheet hands over (Files gives a PDF `com.adobe.pdf` +
/// `public.file-url`, read off the extension on the simulator).
///
/// Evaluated with `NSPredicate`, which is NOT what the share sheet runs: a
/// rule this file passes can still be dropped whole by the sheet (see
/// `testTheRuleUsesOnlyWhatTheShareSheetEvaluates`). The acceptance is the
/// device run, `DeviceRun/ShareActivationTests`; this is what keeps the list
/// honest between device runs.
///
/// The file clause matches each type EXACTLY (`UTI-EQUALS`), one per accepted
/// extension — the table, not a family. Conformance admitted the families'
/// other members: `public.plain-text` let in `.csv` (and `.log`, and every
/// script), which the server refuses. The identifiers are the ones THIS OS
/// derives from each extension (`.mts`, `.ogv` and `.markdown` are dynamic
/// types on iOS, not what macOS names them), so the list is regenerated from
/// the failure message below, never from a Mac.
final class ShareActivationRuleTests: XCTestCase {

    /// The clause names that are structure, not the accepted set.
    private static let structural: Set<String> = [
        "public.url", "public.file-url", "public.image", "public.source-code",
    ]

    private func rule() throws -> String {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Share/Info.plist")
        let data = try Data(contentsOf: plist)
        let root = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ext = try XCTUnwrap(root["NSExtension"] as? [String: Any])
        let attrs = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        return try XCTUnwrap(attrs["NSExtensionActivationRule"] as? String,
                             "the activation rule is not a predicate string — a dictionary rule "
                             + "(`…SupportsFileWithMaxCount`) offers NoteLetter for ANY file")
    }

    /// Every quoted type identifier in the rule.
    private func quoted(_ rule: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "\"([^\"]+)\"")
        return re.matches(in: rule, range: NSRange(rule.startIndex..., in: rule)).compactMap {
            Range($0.range(at: 1), in: rule).map { String(rule[$0]) }
        }
    }

    /// The accepted set the file clause must list: the picker's own types,
    /// less the images (the image clause takes those, and the extension
    /// re-encodes every image it is handed).
    private var acceptedFileTypes: Set<String> {
        Set(UploadTypes.pickerTypes.filter { !$0.conforms(to: .image) }.map(\.identifier))
    }

    func testTheRuleIsAPredicateThatParses() throws {
        let rule = try rule()
        XCTAssertNoThrow(NSPredicate(format: rule), "NSPredicate cannot read the rule")
    }

    /// The share sheet is not `NSPredicate.evaluate`. With the photo clause
    /// written `.@count BETWEEN {1, 20}` every test below was green and the
    /// sheet offered NoteLetter for NOTHING — not a PDF, not a link: the whole
    /// rule fell, silently, with no log line (bisected on the simulator,
    /// 2026-10-07: the same rule with the bound as `>= 1 AND … <= 20` works).
    /// Constructs the device run has proven are the only ones allowed.
    func testTheRuleUsesOnlyWhatTheShareSheetEvaluates() throws {
        let rule = try rule()
        XCTAssertFalse(rule.contains("BETWEEN"),
                       "BETWEEN on a SUBQUERY count drops the whole rule in the share sheet")
    }

    func testTheFileClauseIsExactlyTheAcceptedSet() throws {
        let listed = Set(quoted(try rule())).subtracting(Self.structural)
        let expected = acceptedFileTypes
        XCTAssertEqual(listed.subtracting(expected).sorted(), [],
                       "the rule offers NoteLetter for types the server refuses")
        XCTAssertEqual(expected.subtracting(listed).sorted(), [],
                       "accepted types the rule never offers NoteLetter for — paste: "
                       + expected.sorted().map { "\"\($0)\"" }.joined(separator: ", "))
    }

    /// The source-code exclusion must not knock out an accepted type: a
    /// format that is both would vanish from the sheet with nothing red.
    func testNoAcceptedTypeIsSourceCode() {
        for t in UploadTypes.pickerTypes {
            XCTAssertFalse(t.conforms(to: .sourceCode), "\(t.identifier) is accepted AND source code")
        }
    }

    // MARK: - Evaluated, the way the share sheet asks

    private func offered(_ attachments: [[String]], items: Int = 1) throws -> Bool {
        let predicate = NSPredicate(format: try rule())
        let item: [String: Any] = ["attachments": attachments.map { ["registeredTypeIdentifiers": $0] }]
        return predicate.evaluate(with: ["extensionItems": Array(repeating: item, count: items)])
    }

    private func id(_ ext: String) throws -> String {
        try XCTUnwrap(UTType(filenameExtension: ext)).identifier
    }

    func testEveryAcceptedFileIsOffered() throws {
        for ext in UploadTypes.allowedExtensions {
            XCTAssertTrue(try offered([[try id(ext), UTType.fileURL.identifier]]),
                          ".\(ext) from Files is not offered NoteLetter")
        }
    }

    func testARefusedFileIsNotOffered() throws {
        for ext in ["zip", "py", "swift", "js", "sh", "json", "html", "doc", "ppt", "xlsx", "csv", "tsv",
                    "log", "ts", "rtf", "pages", "key"] {
            guard let t = UTType(filenameExtension: ext) else { continue }
            XCTAssertFalse(try offered([[t.identifier, UTType.fileURL.identifier]]),
                           ".\(ext) from Files is offered NoteLetter, and the server refuses it")
        }
    }

    func testAWebLinkAndPhotosAreOffered() throws {
        XCTAssertTrue(try offered([[UTType.url.identifier]]), "a Safari link is not offered")
        XCTAssertTrue(try offered([[UTType.url.identifier, UTType.plainText.identifier]]),
                      "a link carrying its title is not offered")
        XCTAssertTrue(try offered([[UTType.heic.identifier]]), "a photo is not offered")
        XCTAssertTrue(try offered(Array(repeating: [UTType.jpeg.identifier], count: 20)),
                      "twenty photos are not offered")
        XCTAssertFalse(try offered(Array(repeating: [UTType.jpeg.identifier], count: 21)),
                       "the extension takes twenty photos; twenty-one were offered")
    }

    /// What the extension cannot read is not offered: a bare text selection
    /// has no link, no image and no file behind it, so the sheet used to open
    /// on "Nothing to share".
    func testWhatTheExtensionCannotReadIsNotOffered() throws {
        XCTAssertFalse(try offered([[UTType.plainText.identifier]]), "a text selection is offered")
        XCTAssertFalse(try offered([[UTType.pdf.identifier]]),
                       "a PDF with no file behind it is offered, and the extension reads files by URL")
        XCTAssertFalse(try offered([[UTType.zip.identifier, UTType.fileURL.identifier]]),
                       "a file is offered through the LINK clause")
        XCTAssertFalse(try offered([[try id("pdf"), UTType.fileURL.identifier],
                                    [try id("pdf"), UTType.fileURL.identifier]]),
                       "two files are offered; the extension sends one")
    }
}
