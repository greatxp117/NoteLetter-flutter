// F-125 S4. Ported from the retired Swift app's
// `NoteLetter/NoteLetter/CameraSweep/CameraSweepUploader.swift` (NoteLetter
// 910864a). Port changes, each marked PORT below:
//   1. Flutter's OWN session identifier, never the Swift app's.
//   2. What a task is FOR rides in its `taskDescription`, which the background
//      session keeps across relaunches. Swift kept it in a dictionary in
//      memory, so a completion delivered to a relaunched app found no
//      `localIdentifier` and recorded nothing.
//   3. A finished upload is WRITTEN DOWN before anyone is told, and stays
//      until the Dart side acknowledges it — the result of an upload that
//      lands while the app is dead, or while Flutter is not listening yet,
//      reaches the ledger at the next launch instead of being lost.
//   4. The bytes are staged under Application Support by RENAMING the
//      rendered JPEG (the system never purges it, unlike tmp/), BEFORE the
//      capture session is opened — so the step between a session and its
//      upload cannot fail on the disk.
//   5. The Dart side asks which uploads are still in flight, so a pass never
//      starts a second upload of a photo whose first is on its way.
//   6. From staging to hand-off the app is held awake
//      (`beginBackgroundTask`): leaving the app between a capture session
//      and its upload would otherwise suspend it there, with a document
//      waiting for bytes nothing is sending.
import Flutter
import Foundation
import UIKit

/// Signed-URL PUTs for the sweep, on a **background** URLSession, so an upload
/// survives the app being suspended mid-sweep. The same INV-08 discipline as
/// every other upload — bare PUT, the declared Content-Type, **no
/// Authorization header** — with different plumbing.
///
/// A background session cannot upload from `Data`, so every payload is a file.
final class CameraSweepUploader: NSObject {
    static let shared = CameraSweepUploader()

    /// PORT 1: this app's own; the Swift app's was `xp.NoteLetter.camerasweep.upload`.
    static let sessionIdentifier = "xp.NoteLetter.Flutter.camerasweep.upload"

    /// The Dart side's signal channel: one event whenever a result is waiting.
    static let eventsName = "xp.noteletter/camera_sweep/uploads"

    /// Where results wait for the Dart side (PORT 3).
    static let finishedKey = "nl.sweep.uploads.finished"

    /// Set when the system wakes or relaunches the app to finish uploads.
    private var backgroundCompletionHandler: (() -> Void)?

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// PORT 6: the assertion held for each staged upload until it is started
    /// or discarded. Main thread only.
    private var handOffs: [String: UIBackgroundTaskIdentifier] = [:]
    private let events = UploadEvents()

    /// When the system woke this process for this session's events, and when
    /// it said they were all delivered (ms since 1970) — what the device test
    /// reads to tell "finished in the background" from "finished on resume".
    private(set) var wakes: [Double] = []
    private(set) var eventsDelivered: [Double] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    /// Created at launch (AppDelegate), not on first use: a session with this
    /// identifier is what the system delivers an earlier launch's completions
    /// to, so it has to exist before they can arrive.
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    static func register(with messenger: FlutterBinaryMessenger) {
        FlutterEventChannel(name: eventsName, binaryMessenger: messenger)
            .setStreamHandler(shared.events)
    }

    // MARK: - Staging (PORT 4)

    static var stagingDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("camera-sweep-uploads", isDirectory: true)
    }

    /// Moves the rendered JPEG under this uploader's own name. The file is the
    /// upload's from here on: [start] sends it, [discard] or the completion
    /// deletes it.
    func stage(renderedPath: String) throws -> (uploadId: String, bytes: Int) {
        let dir = Self.stagingDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let uploadId = UUID().uuidString
        let staged = dir.appendingPathComponent(uploadId + ".jpg")
        try FileManager.default.moveItem(at: URL(fileURLWithPath: renderedPath), to: staged)
        let size = (try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)?
            .intValue ?? 0
        holdAwake(uploadId)
        return (uploadId, size)
    }

    func discard(uploadId: String) {
        try? FileManager.default.removeItem(at: Self.stagingDirectory.appendingPathComponent(uploadId + ".jpg"))
        letSleep(uploadId)
    }

    /// PORT 6. If the system's time runs out first, the assertion is simply
    /// ended: what is left is the window §6's replay recovers.
    private func holdAwake(_ uploadId: String) {
        let id = UIApplication.shared.beginBackgroundTask(withName: "NoteLetter camera sweep hand-off") {
            [weak self] in self?.letSleep(uploadId)
        }
        if id != .invalid { handOffs[uploadId] = id }
    }

    private func letSleep(_ uploadId: String) {
        guard let id = handOffs.removeValue(forKey: uploadId) else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Uploading

    /// Hands the staged file to the background session. Deliberately not
    /// awaited: the result is [finished]'s, whenever it lands — in this
    /// launch or a later one.
    func start(uploadId: String, signedURL: String, mimeType: String,
               localIdentifier: String, assetKey: String) throws {
        guard let url = URL(string: signedURL), url.scheme == "https" || url.scheme == "http" else {
            throw UploaderError.invalidURL
        }
        let staged = Self.stagingDirectory.appendingPathComponent(uploadId + ".jpg")
        guard FileManager.default.fileExists(atPath: staged.path) else {
            throw UploaderError.notStaged
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: request, fromFile: staged)
        task.taskDescription = UploadRecord(
            uploadId: uploadId, localIdentifier: localIdentifier, assetKey: assetKey,
            startedAtMs: Self.nowMs()
        ).encoded()
        task.resume()
        letSleep(uploadId)   // the system has it now
    }

    /// PORT 5: the uploads the session still holds, by what they are for.
    func inFlight(_ done: @escaping ([[String: Any]]) -> Void) {
        session.getAllTasks { tasks in
            let records = tasks
                .filter { $0.state != .completed }
                .compactMap { $0.taskDescription.flatMap(UploadRecord.decode) }
                .map { $0.wire }
            DispatchQueue.main.async { done(records) }
        }
    }

    // MARK: - Results (PORT 3)

    // Each result is kept as a JSON string: a result carries `error: null`,
    // and NSNull is not a property-list value — UserDefaults throws on it,
    // which killed the app on its first finished upload.

    func finished() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return stored().compactMap(Self.decode)
    }

    /// The Dart side recorded these; forget them.
    func acknowledge(_ uploadIds: Set<String>) {
        lock.lock()
        let kept = stored().filter { s in
            !uploadIds.contains(Self.decode(s)?["uploadId"] as? String ?? "")
        }
        defaults.set(kept, forKey: Self.finishedKey)
        lock.unlock()
    }

    /// Writes one result down (the delegate, before anyone is told).
    func record(_ result: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: result) else {
            // Only property-list-like values are ever put in a result.
            NSLog("NoteLetter: camera sweep upload result not encodable — %@", "\(result)")
            return
        }
        lock.lock()
        var all = stored()
        all.append(String(decoding: data, as: UTF8.self))
        defaults.set(all, forKey: Self.finishedKey)
        lock.unlock()
    }

    private func stored() -> [String] {
        defaults.array(forKey: Self.finishedKey) as? [String] ?? []
    }

    private static func decode(_ s: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }

    // MARK: - Woken by the system

    /// The system woke (or relaunched) the app because this session's tasks
    /// finished. The handler is called once their events are delivered, and
    /// after the Dart side has had a moment to record them.
    func wokeForEvents(_ completionHandler: @escaping () -> Void) {
        wakes.append(Self.nowMs())
        NSLog("NoteLetter: camera sweep woken for handleEventsForBackgroundURLSession (%@)",
              Self.sessionIdentifier)
        backgroundCompletionHandler = completionHandler
        _ = session
    }

    /// How long a wake waits for the Dart side to acknowledge before the
    /// system is told the events are handled (and suspends the app again).
    /// Nothing is lost either way: an unacknowledged result is still written
    /// down for the next launch.
    static let acknowledgeGrace: TimeInterval = 5

    fileprivate func callCompletionHandlerWhenAcknowledged(deadline: Date) {
        if finished().isEmpty || Date() >= deadline || !events.listening {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.callCompletionHandlerWhenAcknowledged(deadline: deadline)
        }
    }

    static func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    enum UploaderError: LocalizedError {
        case invalidURL, notStaged
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid upload URL"
            case .notStaged:  return "The photo to upload is no longer on this phone."
            }
        }
    }
}

/// What a background task is for, kept in its `taskDescription` (PORT 2).
struct UploadRecord: Codable, Equatable {
    let uploadId: String
    let localIdentifier: String
    let assetKey: String
    let startedAtMs: Double

    func encoded() -> String {
        // Four strings and a number: encoding cannot fail.
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ s: String) -> UploadRecord? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UploadRecord.self, from: data)
    }

    var wire: [String: Any] {
        ["uploadId": uploadId, "localIdentifier": localIdentifier, "assetKey": assetKey,
         "startedAtMs": startedAtMs]
    }
}

extension CameraSweepUploader {
    /// The result the Dart side reads (`SweepUploadResult.fromWire`).
    /// `statusCode` 0 with an `error` is URLSession's own failure — a dropped
    /// connection, a transfer the system gave up on; a status with no error is
    /// the bucket's answer, and only 2xx landed. `appState` is
    /// `UIApplication.applicationState` when the result arrived: 2 is
    /// background.
    static func result(for record: UploadRecord, statusCode: Int, error: Error?,
                       appState: Int) -> [String: Any] {
        let ok = error == nil && (200..<300).contains(statusCode)
        var r = record.wire
        r["ok"] = ok
        r["statusCode"] = statusCode
        r["error"] = error.map { $0.localizedDescription } as Any? ?? NSNull()
        r["finishedAtMs"] = nowMs()
        r["appState"] = appState
        return r
    }
}

extension CameraSweepUploader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let record = task.taskDescription.flatMap(UploadRecord.decode) else { return }
        // The file only: this is the delegate's queue, and the hand-off's
        // assertion (main thread) ended when the task started.
        try? FileManager.default.removeItem(
            at: Self.stagingDirectory.appendingPathComponent(record.uploadId + ".jpg"))
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        // Read on the main thread, as UIKit requires; the result is written
        // down before anyone is told.
        DispatchQueue.main.async { [self] in
            let state = UIApplication.shared.applicationState.rawValue
            self.record(Self.result(for: record, statusCode: code, error: error, appState: state))
            events.signal()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [self] in
            eventsDelivered.append(Self.nowMs())
            callCompletionHandlerWhenAcknowledged(deadline: Date().addingTimeInterval(Self.acknowledgeGrace))
        }
    }
}

/// "A result is waiting", to the Dart side while it listens.
final class UploadEvents: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    var listening: Bool { sink != nil }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    func signal() { sink?("finished") }
}
