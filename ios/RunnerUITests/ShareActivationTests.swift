import XCTest

/// The share extension, from another app's share sheet: what NoteLetter is
/// OFFERED for, and what it makes of a file once it opens. Driven through the
/// Files app, whose share sheet's app row is in the accessibility tree
/// (`activityCollectionView` › `shareCell`).
///
/// Before (2026-10-07, this simulator): the rule was
/// `NSExtensionActivationSupportsFileWithMaxCount = 1`, so a `.zip` and a `.py`
/// were both offered NoteLetter; and opening it on ANY file from Files drew
/// "LINK · file:///…/paper-sample.pdf · Files as: Article" with a live Add
/// button — the extension took the file's `public.file-url` for a web link,
/// so its type was never checked and the refusal card was unreachable.
///
/// **Requires** four files in Files › On My iPhone, placed from the Mac
/// (the runner's sandbox cannot write another app's container):
///
/// ```
/// D=$(dirname "$(find ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Shared/AppGroup \
///       -maxdepth 2 -name '.com.apple.mobile_container_manager.metadata.plist' \
///       -exec grep -l FileProvider.LocalStorage {} +)")/File\ Provider\ Storage
/// cp archive-sample.zip paper-sample.pdf "$D/"; printf 'print(1)\n' > "$D/script-sample.py"
/// mkfile -n 101m "$D/oversize-sample.pdf"     # sparse: no disk, but over the 100 MB cap
/// ```
///
/// **Install the built app yourself first** (`xcrun simctl install <udid>
/// …/Debug-iphonesimulator/Runner.app`): `xcodebuild test-without-building`
/// left the PREVIOUS appex's Info.plist installed (2026-10-07), so a rule
/// change was tested against the old rule with nothing saying so.
///
/// Run them on the device itself, never on xcodebuild's clones:
///
/// ```
/// xcodebuild -workspace Runner.xcworkspace -scheme Runner \
///   -destination id=<udid> -parallel-testing-enabled NO \
///   -only-testing:RunnerUITests/ShareActivationTests test
/// ```
///
/// It skips without them rather than passing. Nothing is ever uploaded — the
/// extension's own buttons are never pressed. (F-122, the Flutter port: a
/// DEBUG extension reads the emulator address the debug app wrote into the
/// App Group, and REFUSES when there is none, so these cards are drawn only
/// after the app has been opened through tool/dev.sh on this simulator.)
final class ShareActivationTests: XCTestCase {
    /// The share sheet's tile: the extension's CFBundleDisplayName
    /// (ios/Share/Info.plist), the app's own name since 858e644.
    static let tile = "NoteLetter Flutter"

    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["SHOT_DIR"] else { return }
        let theme = env["SHOT_THEME"] ?? "light"
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).ios.\(theme).png"))
    }

    private struct Stop: Error {}
    private var files: XCUIApplication?
    private func must(_ ok: Bool, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        guard ok else {
            shot("failure")
            if let files { print("── accessibility tree at failure ──\n" + files.debugDescription) }
            XCTFail(message, file: file, line: line)
            throw Stop()
        }
    }

    /// Files, at On My iPhone, with the share sheet open on `name`.
    ///
    /// Twice if need be. On iOS 26.5 Files' context menu never reports idle,
    /// so each step waits out XCTest's 60 s quiescence timeout. The sheet was
    /// never found in a run that included RunnerTests with parallel testing
    /// ON — xcodebuild then runs everything on CLONES of the simulator — and
    /// was found every time with `-parallel-testing-enabled NO` (2026-10-18,
    /// the Flutter port). The second attempt is a guard, not the fix.
    private func shareSheet(for name: String) throws -> XCUIApplication {
        for attempt in 1...2 {
            let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
            self.files = files
            files.terminate()
            files.launch()
            let browse = files.tabBars.buttons["Browse"]
            if browse.waitForExistence(timeout: 15) { browse.tap(); browse.tap() }
            let onMy = files.staticTexts["On My iPhone"].firstMatch
            try must(onMy.waitForExistence(timeout: 15), "Files shows no On My iPhone")
            onMy.tap()
            let cell = files.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
            guard cell.waitForExistence(timeout: 15) else {
                throw XCTSkip("“\(name)” is not in Files › On My iPhone — place it first (see the header)")
            }
            cell.press(forDuration: 1.2)
            let share = files.buttons["Share"].firstMatch
            try must(share.waitForExistence(timeout: 10), "the file's menu has no Share")
            share.tap()
            sleep(3)
            if files.collectionViews["activityCollectionView"].waitForExistence(timeout: 15) {
                sleep(2)
                return files
            }
            print("── share sheet not found, attempt \(attempt) ──")
        }
        try must(false, "the share sheet never opened")
        throw Stop()
    }

    private func appCell(_ files: XCUIApplication, _ label: String) -> XCUIElement {
        files.cells.matching(NSPredicate(format: "identifier == 'shareCell' AND label == %@", label)).firstMatch
    }

    /// NoteLetter where the sheet offers it: in the app row, or — the row
    /// shows only what it suggests (a PDF's row is Preview and More) — in the
    /// full list behind its More. Nil when it is in NEITHER: "not offered".
    ///
    /// What is proven is the ROW: every activated run (the old rule, a
    /// TRUEPREDICATE rule, the narrowed one on a PDF, a link, a photo) drew
    /// NoteLetter there, and the zip test goes red under TRUEPREDICATE. The
    /// tap on More has NOT been seen to open the full list on this simulator
    /// (2026-10-07), so that branch is a hope, not a check.
    private func offered(_ files: XCUIApplication) -> XCUIElement? {
        let inRow = appCell(files, Self.tile)
        if inRow.exists { return inRow }
        let more = appCell(files, "More")
        guard more.exists else { return nil }
        more.tap()
        sleep(3)
        print("── More ──\n" + files.debugDescription)
        let anywhere = files.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", Self.tile)).firstMatch
        return anywhere.waitForExistence(timeout: 5) ? anywhere : nil
    }

    private func isOffered(_ files: XCUIApplication) -> Bool { offered(files) != nil }

    func testAZipIsNotOffered() throws {
        let files = try shareSheet(for: "archive-sample.zip")
        shot("share-zip-sheet")
        try must(!isOffered(files), "NoteLetter is offered for a .zip, which the server refuses")
    }

    func testAScriptIsNotOffered() throws {
        let files = try shareSheet(for: "script-sample.py")
        try must(!isOffered(files), "NoteLetter is offered for a .py, which the server refuses")
    }

    /// Offered, and opened as a FILE: its name, the File card, no Link card.
    func testAPdfIsOfferedAndOpensAsAFile() throws {
        let files = try shareSheet(for: "paper-sample")
        let found = offered(files)
        shot("share-pdf-sheet")
        let cell = try XCTUnwrap(found, "NoteLetter is not offered for a PDF")
        cell.tap()
        let name = files.staticTexts["paper-sample.pdf"].firstMatch
        try must(name.waitForExistence(timeout: 20), "the extension never named the file")
        try must(files.buttons["Upload File"].exists, "the file card offers no upload")
        try must(!files.staticTexts.matching(NSPredicate(format: "label ==[c] 'Link'")).firstMatch.exists,
                 "a file from Files was drawn as a LINK")
        try must(!files.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Files as:'")).firstMatch.exists,
                 "a file from Files was given a link's type")
        sleep(1)
        shot("share-pdf-file")
        // Never "Upload File": the extension is not on the emulator.
        files.buttons["Cancel"].firstMatch.tap()
    }

    /// The extension's first job, which the narrowed rule must not lose: a
    /// web page from Safari is offered and opens as a LINK.
    func testAWebPageIsOfferedAndOpensAsALink() throws {
        XCUIDevice.shared.system.open(URL(string: "https://example.com/")!)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        self.files = safari
        try must(safari.wait(for: .runningForeground, timeout: 30), "Safari never came up")
        sleep(4)
        // iOS 26 Safari keeps Share behind the toolbar's More (`MoreMenuButton`).
        let more = safari.buttons["MoreMenuButton"]
        try must(more.waitForExistence(timeout: 20), "Safari's toolbar has no More")
        let share = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Share' OR identifier CONTAINS[c] 'share'")).firstMatch
        // A tap while the page is still settling opens nothing on iOS 26.5
        // (2026-10-18, the Flutter port's first run): tap, look, tap again.
        for _ in 0..<3 where !share.exists {
            more.tap()
            sleep(3)
            if share.waitForExistence(timeout: 5) { break }
        }
        if !share.exists { print("── Safari More ──\n" + safari.debugDescription) }
        try must(share.exists, "Safari's More offers no Share")
        share.tap()
        try must(safari.collectionViews["activityCollectionView"].waitForExistence(timeout: 15),
                 "Safari's share sheet never opened")
        sleep(2)
        let cell = appCell(safari, Self.tile)
        shot("share-link-sheet")
        try must(cell.exists, "NoteLetter is not offered for a web page")
        cell.tap()
        try must(safari.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Files as:'")).firstMatch
                    .waitForExistence(timeout: 20), "a web page did not open as a link")
        try must(safari.staticTexts.matching(NSPredicate(format: "label CONTAINS 'example.com'")).firstMatch.exists,
                 "the link card does not show the page's address")
        sleep(1)
        shot("share-link")
        // Never "Add to NoteLetter": the extension is not on the emulator.
        safari.buttons["Cancel"].firstMatch.tap()
    }

    /// End to end, against the EMULATOR only (F-122): the extension is signed
    /// in through the app's shared keychain group — no "Sign in required" —
    /// and a link added from Safari is filed by `fn_ingest_url` and said so.
    ///
    /// Runs only when asked (`TEST_RUNNER_SHARE_E2E=1`), with the alt-port
    /// suite up (tool/emu_alt.sh) and the debug app opened once through
    /// tool/dev.sh, which wrote the emulator's address into the App Group. A
    /// DEBUG extension without that address refuses rather than reach prod,
    /// so this cannot file into the real library.
    func testALinkIsFiledThroughTheEmulator() throws {
        guard env["SHARE_E2E"] == "1" else {
            throw XCTSkip("SHARE_E2E is not set — this press files into the emulator library")
        }
        XCUIDevice.shared.system.open(URL(string: "https://example.com/share-e2e")!)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        self.files = safari
        try must(safari.wait(for: .runningForeground, timeout: 30), "Safari never came up")
        sleep(4)
        let more = safari.buttons["MoreMenuButton"]
        try must(more.waitForExistence(timeout: 20), "Safari's toolbar has no More")
        let share = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Share' OR identifier CONTAINS[c] 'share'")).firstMatch
        for _ in 0..<3 where !share.exists {
            more.tap()
            sleep(3)
            if share.waitForExistence(timeout: 5) { break }
        }
        try must(share.exists, "Safari's More offers no Share")
        share.tap()
        try must(safari.collectionViews["activityCollectionView"].waitForExistence(timeout: 15),
                 "Safari's share sheet never opened")
        sleep(2)
        let cell = appCell(safari, Self.tile)
        try must(cell.exists, "NoteLetter is not offered for a web page")
        cell.tap()
        try must(!safari.staticTexts["Sign in required"].waitForExistence(timeout: 8),
                 "the extension is signed out — the shared keychain group did not carry the session")
        let add = safari.buttons["Add to NoteLetter"].firstMatch
        try must(add.waitForExistence(timeout: 20), "the link card has no Add")
        add.tap()
        let done = safari.staticTexts["Added link for processing."].firstMatch
        let ok = done.waitForExistence(timeout: 30)
        shot("share-link-added")
        try must(ok, "the link was not filed (no success line)")
    }

    /// A photo from Photos is offered (the image clause), as it was before.
    func testAPhotoIsOffered() throws {
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        self.files = photos
        photos.launch()
        // The grid's tiles; the tab bar's own glyph is also an image named
        // "photo…", so the tile is found by the grid's identifier only.
        let tile = photos.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // 60 s, not 20: on this simulator Photos drew an empty grid for 20 s
        // in 3 of 4 runs (2026-10-16) with the library full — it was still
        // loading, not empty.
        try must(tile.waitForExistence(timeout: 60), "Photos shows no photo — the simulator library is empty")
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)
        let share = photos.buttons.matching(NSPredicate(format: "label == 'Share' OR identifier == 'Share'")).firstMatch
        if !share.waitForExistence(timeout: 10) { print("── Photos one-up ──\n" + photos.debugDescription) }
        try must(share.exists, "the photo has no Share")
        share.tap()
        try must(photos.collectionViews["activityCollectionView"].waitForExistence(timeout: 15),
                 "Photos' share sheet never opened")
        sleep(2)
        shot("share-photo-sheet")
        let cell = appCell(photos, Self.tile)
        try must(cell.exists, "NoteLetter is not offered for a photo")
        // The extension's own photo card: its title field on --surface and
        // its Cancel at --accent-text (ruled 2026-10-14). Never "Upload
        // Photos": the extension is not on the emulator.
        cell.tap()
        let title = photos.textFields["Title (optional)"].firstMatch
        try must(title.waitForExistence(timeout: 20), "the photo card has no title field")
        sleep(1)
        shot("share-photo")
        photos.buttons["Cancel"].firstMatch.tap()
    }

    /// The refusal the extension draws, reachable from Files at last: a PDF
    /// over its type's cap is offered (its type is accepted) and refused on
    /// screen, in the server's sentence, before a byte is read.
    func testAnOversizedPdfIsRefusedOnScreen() throws {
        let files = try shareSheet(for: "oversize-sample")
        let cell = try XCTUnwrap(offered(files), "NoteLetter is not offered for a PDF")
        cell.tap()
        try must(files.staticTexts["Can’t add this file"].waitForExistence(timeout: 20),
                 "an oversized PDF was not refused on screen")
        try must(files.staticTexts["That file is over the 100 MB limit."].exists,
                 "the refusal is not the server's sentence")
        try must(!files.buttons["Upload File"].exists, "a refused file still offers an upload")
        sleep(1)
        shot("share-pdf-refused")
        files.buttons["Cancel"].firstMatch.tap()
    }
}
