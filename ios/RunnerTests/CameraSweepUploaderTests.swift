import XCTest
// F-125 S4: the sweep's background uploader (`ios/Runner/CameraSweep/
// CameraSweepUploader.swift`), compiled into this bundle as the S1 port is.
// What is tested here is what the device test cannot reach on purpose: the
// record a task carries across relaunches, what counts as landed, and that a
// result stays written down until the Dart side acknowledges it.
final class CameraSweepUploaderTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "CameraSweepUploaderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let record = UploadRecord(
        uploadId: "u-1", localIdentifier: "ABC/L0/001", assetKey: "v1:é|日本", startedAtMs: 1760800000123)

    func testTheRecordATaskCarriesSurvivesItsDescription() {
        let s = record.encoded()
        XCTAssertFalse(s.isEmpty)
        XCTAssertEqual(UploadRecord.decode(s), record)
        XCTAssertNil(UploadRecord.decode("not json"), "a description that is not ours is no record")
        XCTAssertNil(UploadRecord.decode("{\"uploadId\":\"u\"}"), "a partial record is no record")
    }

    func testOnlyA2xxWithNoErrorLanded() {
        func ok(_ code: Int, _ error: Error? = nil) -> Bool {
            CameraSweepUploader.result(for: record, statusCode: code, error: error, appState: 2)["ok"] as! Bool
        }
        XCTAssertTrue(ok(200))
        XCTAssertTrue(ok(201))
        XCTAssertFalse(ok(403), "an expired link")
        XCTAssertFalse(ok(501), "the shim's download URL")
        XCTAssertFalse(ok(0, URLError(.networkConnectionLost)))
        XCTAssertFalse(ok(200, URLError(.cancelled)), "an error wins over a status")
        let r = CameraSweepUploader.result(
            for: record, statusCode: 0, error: URLError(.notConnectedToInternet), appState: 2)
        XCTAssertEqual(r["localIdentifier"] as? String, record.localIdentifier)
        XCTAssertEqual(r["assetKey"] as? String, record.assetKey)
        XCTAssertEqual(r["appState"] as? Int, 2)
        XCTAssertFalse((r["error"] as? String ?? "").isEmpty, "URLSession's own words")
        XCTAssertTrue(CameraSweepUploader.result(for: record, statusCode: 200, error: nil, appState: 0)["error"] is NSNull)
    }

    func testAResultStaysUntilAcknowledged() {
        let u = CameraSweepUploader(defaults: defaults)
        XCTAssertTrue(u.finished().isEmpty)
        // What `didCompleteWithError` writes, before anyone is told — through
        // the same call. A result with `error: null` once killed the app
        // here: NSNull is not a property-list value.
        u.record(CameraSweepUploader.result(for: record, statusCode: 200, error: nil, appState: 2))
        u.record(CameraSweepUploader.result(
            for: UploadRecord(uploadId: "u-2", localIdentifier: "x", assetKey: "k", startedAtMs: 0),
            statusCode: 0, error: URLError(.networkConnectionLost), appState: 0))
        XCTAssertEqual(u.finished().count, 2)
        XCTAssertTrue(u.finished()[0]["error"] is NSNull, "null survives the store")
        XCTAssertEqual(u.finished()[0]["ok"] as? Bool, true)
        XCTAssertEqual(u.finished()[1]["statusCode"] as? Int, 0)
        u.acknowledge(["u-1"])
        XCTAssertEqual(u.finished().map { $0["uploadId"] as? String }, ["u-2"])
        // A relaunch reads the same store.
        XCTAssertEqual(CameraSweepUploader(defaults: defaults).finished().count, 1)
        u.acknowledge(["u-2", "never-was"])
        XCTAssertTrue(u.finished().isEmpty)
    }

    func testStagingMovesTheRenderedFile() throws {
        let u = CameraSweepUploader(defaults: defaults)
        let rendered = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-sweep-test-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]).write(to: rendered)
        let staged = try u.stage(renderedPath: rendered.path)
        XCTAssertEqual(staged.bytes, 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rendered.path), "moved, not copied")
        let file = CameraSweepUploader.stagingDirectory.appendingPathComponent(staged.uploadId + ".jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(file.path.contains("/tmp/"), "never under tmp/, which the system purges")
        XCTAssertThrowsError(try u.start(uploadId: staged.uploadId, signedURL: "not a url",
                                         mimeType: "image/jpeg", localIdentifier: "x", assetKey: "k"))
        u.discard(uploadId: staged.uploadId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertThrowsError(try u.start(uploadId: staged.uploadId, signedURL: "https://storage.example/x",
                                         mimeType: "image/jpeg", localIdentifier: "x", assetKey: "k"),
                             "a file no longer staged is refused, never sent empty")
    }
}
