import Flutter
import Foundation
import Photos
import UIKit

/// F-125 S1: the camera-roll sweep's native bridge (INV-14,
/// `spec/features/camera-roll-sweep.md`). S3 added what its screens need: a
/// card's thumbnail, the "Open Settings" action, and the library's change
/// events. S4 added the background uploader's methods (`CameraSweepUploader`);
/// the background task has its own channel (`SweepBackgroundTask`).
///
/// Everything the sweep decides on the device is the retired Swift app's own
/// code, ported verbatim beside this file: the asset key (`AssetIdentity`,
/// byte-identical, or every photo that app already swept uploads again), the
/// Vision pre-filter (`AssetPrefilter`, 80 characters on a ~1024 px
/// thumbnail, network off, so the calibration does not move) and enumeration
/// (`PhotoLibraryAccess`, images newest first). This file only carries them
/// across the channel. The Dart side is `lib/services/camera_sweep_bridge.dart`.
///
/// **Partial access is refused HERE, not by a caller** (feature spec §1): every
/// method that touches the library answers `FlutterError(code: "limited")` or
/// `"denied"` unless access is full, so a sweep over twelve hand-picked photos
/// cannot run through this bridge at all. The sentence that explains it is the
/// Swift app's, and lives on the Dart side with the rest of the copy.
enum CameraSweepChannel {
    static let name = "xp.noteletter/camera_sweep"

    /// F-125 S3: one event per photo-library change, while the Dart side
    /// listens. What runs the sweep again when a photo is taken with the app
    /// open (Swift `CameraSweepService: PHPhotoLibraryChangeObserver`).
    static let changesName = "xp.noteletter/camera_sweep/changes"

    /// The stream handler is held here: an event channel keeps only a weak
    /// reference to it.
    private static let changes = LibraryChanges()

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in handle(call, result) }
        FlutterEventChannel(name: changesName, binaryMessenger: messenger)
            .setStreamHandler(changes)
        CameraSweepUploader.register(with: messenger)
    }

    // MARK: - Pure rules (RunnerTests/CameraSweepBridgeTests)

    static func wire(_ access: PhotoLibraryAccess.Access) -> String {
        switch access {
        case .granted: return "granted"
        case .limited: return "limited"
        case .denied:  return "denied"
        }
    }

    /// The error code a library method answers instead of running; nil means
    /// it may run. Only full access runs — the Swift service's own guard
    /// (`startIfEnabled`: `case .granted = PhotoLibraryAccess.current`).
    static func refusal(for access: PhotoLibraryAccess.Access) -> String? {
        switch access {
        case .granted: return nil
        case .limited: return "limited"
        case .denied:  return "denied"
        }
    }

    static func wire(_ verdict: AssetPrefilter.Verdict) -> String {
        switch verdict {
        case .candidate:           return "candidate"
        case .noText:              return "noText"
        case .notLocallyAvailable: return "notLocallyAvailable"
        }
    }

    /// One listed asset (5.40.0, ADR-195): what deciding whether to look at it
    /// needs, read off the `PHAsset` alone. No key and no filename: both are a
    /// `PHAssetResource` lookup, and most listed assets are skipped by the
    /// ledger. `describe` adds them, for a candidate.
    static func listing(_ asset: PHAsset) -> [String: Any] {
        [
            "localIdentifier": asset.localIdentifier,
            // The exact Double the key's millisecond figure is derived from,
            // so a caller can recompute the key and get the same bytes.
            "creationSeconds": asset.creationDate.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
            "pixelWidth": asset.pixelWidth,
            "pixelHeight": asset.pixelHeight,
            "isScreenshot": PhotoLibraryAccess.isScreenshot(asset),
            "isRepresentative": PhotoLibraryAccess.isRepresentative(asset),
        ]
    }

    /// One identified asset: its listing, the INV-14 key and the original
    /// filename. Every field is metadata: no pixel is read, so this is as free
    /// for an iCloud-only asset as for a local one.
    static func describe(_ asset: PHAsset) -> [String: Any] {
        var described = listing(asset)
        described["assetKey"] = AssetIdentity.assetKey(for: asset)
        described["originalFilename"] = AssetIdentity.originalFilename(for: asset) as Any? ?? NSNull()
        return described
    }

    /// `PhotoLibraryAccess.fetchImages`' filter and order over the named assets
    /// only (a pass from a change token, 5.40.0). That file is the Swift app's,
    /// verbatim, so its options are restated here rather than edited there.
    static func fetchImages(localIdentifiers: [String], since: Date?, until: Date?) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let since { predicates.append(NSPredicate(format: "creationDate >= %@", since as NSDate)) }
        if let until { predicates.append(NSPredicate(format: "creationDate < %@", until as NSDate)) }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: options)
    }

    // MARK: - Dispatch

    private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "constants":
            result([
                "schemeVersion": AssetIdentity.schemeVersion,
                "prefilterVersion": AssetPrefilter.version,
                "minimumCharacters": AssetPrefilter.minimumCharacters,
            ])

        case "access":
            result(wire(PhotoLibraryAccess.current))

        case "requestAccess":
            Task {
                let access = await PhotoLibraryAccess.request()
                await MainActor.run { result(wire(access)) }
            }

        case "openSettings":
            // Both refusals carry this action (feature spec §1): this app's own
            // page in the system settings, where photo access is changed.
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return result(false)
            }
            UIApplication.shared.open(url) { opened in result(opened) }

        // F-125 S4: the uploads. They touch no photo, so they answer whatever
        // the library access — an upload handed off before access was revoked
        // still lands, and its result is still recorded.
        case "stageUpload", "startUpload", "discardUpload", "uploadsInFlight",
             "finishedUploads", "acknowledgeUploads":
            upload(call.method, args, result)

        case "fetchImages", "identify", "examine", "renderedJpeg", "thumbnail",
             "changeToken", "changesSince":
            let access = PhotoLibraryAccess.current
            if let code = refusal(for: access) {
                return result(FlutterError(
                    code: code, message: "photo library access is \(wire(access))", details: nil))
            }
            switch call.method {
            case "fetchImages":  fetchImages(args, result)
            case "identify":     identify(args, result)
            case "examine":      examine(args, result)
            case "thumbnail":    thumbnail(args, result)
            case "changeToken":  result(LibraryHistory.token())
            case "changesSince": changesSince(args, result)
            default:             renderedJpeg(args, result)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func upload(_ method: String, _ args: [String: Any],
                               _ result: @escaping FlutterResult) {
        let u = CameraSweepUploader.shared
        func fail(_ error: Error) {
            result(FlutterError(code: "uploadFailed", message: error.localizedDescription, details: nil))
        }
        func string(_ key: String) -> String? {
            guard let v = args[key] as? String, !v.isEmpty else {
                result(FlutterError(code: "badArgs", message: "\(key) is required", details: nil))
                return nil
            }
            return v
        }
        switch method {
        case "stageUpload":
            guard let path = string("path") else { return }
            do {
                let staged = try u.stage(renderedPath: path)
                result(["uploadId": staged.uploadId, "bytes": staged.bytes])
            } catch { fail(error) }

        case "startUpload":
            guard let id = string("uploadId"), let url = string("url"),
                  let mime = string("mimeType"), let local = string("localIdentifier"),
                  let key = string("assetKey") else { return }
            do {
                try u.start(uploadId: id, signedURL: url, mimeType: mime,
                            localIdentifier: local, assetKey: key)
                result(nil)
            } catch { fail(error) }

        case "discardUpload":
            guard let id = string("uploadId") else { return }
            u.discard(uploadId: id)
            result(nil)

        case "uploadsInFlight":
            u.inFlight { result($0) }

        case "finishedUploads":
            result(u.finished())

        default: // acknowledgeUploads
            let ids = Set(args["uploadIds"] as? [String] ?? [])
            u.acknowledge(ids)
            result(nil)
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let ms = (value as? NSNumber)?.int64Value else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    /// A page of `PhotoLibraryAccess.fetchImages` — images only, newest first —
    /// as listings, with no key (5.40.0). With `localIdentifiers`, only those
    /// assets. Bursts are NOT filtered here: each asset says
    /// `isRepresentative`, and the sweep skips the rest, as the Swift loop did.
    private static func fetchImages(_ args: [String: Any], _ result: @escaping FlutterResult) {
        let offset = (args["offset"] as? NSNumber)?.intValue ?? 0
        let limit = (args["limit"] as? NSNumber)?.intValue ?? 0
        guard offset >= 0, limit > 0 else {
            return result(FlutterError(code: "badArgs",
                                       message: "offset must be >= 0 and limit > 0", details: nil))
        }
        let since = date(args["sinceMs"])
        let until = date(args["untilMs"])
        let ids = args["localIdentifiers"] as? [String]
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = ids.map { fetchImages(localIdentifiers: $0, since: since, until: until) }
                ?? PhotoLibraryAccess.fetchImages(since: since, until: until)
            let total = fetched.count
            var assets: [[String: Any]] = []
            if offset < total {
                for index in offset..<min(offset + limit, total) {
                    assets.append(listing(fetched.object(at: index)))
                }
            }
            DispatchQueue.main.async { result(["total": total, "assets": assets]) }
        }
    }

    private static func asset(_ args: [String: Any], _ result: FlutterResult) -> PHAsset? {
        guard let id = args["localIdentifier"] as? String, !id.isEmpty else {
            result(FlutterError(code: "badArgs", message: "localIdentifier is required", details: nil))
            return nil
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            result(FlutterError(code: "notFound", message: "no asset \(id)", details: nil))
            return nil
        }
        return asset
    }

    /// A candidate's key and filename, with the rest of its listing: since
    /// 5.40.0 the only call that derives the key.
    private static func identify(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let asset = asset(args, result) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let described = describe(asset)
            DispatchQueue.main.async { result(described) }
        }
    }

    /// What changed since a token, or nil when only a walk will do.
    private static func changesSince(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let token = args["token"] as? String, !token.isEmpty else {
            return result(FlutterError(code: "badArgs", message: "token is required", details: nil))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let changes = LibraryHistory.changes(since: token)
            DispatchQueue.main.async {
                result(changes.map { ["token": $0.token, "localIdentifiers": $0.localIdentifiers] })
            }
        }
    }

    /// The on-device text check. Never downloads an original: an asset that is
    /// not on the device answers `notLocallyAvailable` (deferred, never "no text").
    private static func examine(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let asset = asset(args, result) else { return }
        Task {
            let e = await AssetPrefilter.examination(of: asset)
            let answer: [String: Any] = [
                "verdict": wire(e.verdict),
                "characters": e.characters as Any? ?? NSNull(),
                "thumbnailWidth": e.thumbnailWidth as Any? ?? NSNull(),
                "thumbnailHeight": e.thumbnailHeight as Any? ?? NSNull(),
                "prefilterVersion": AssetPrefilter.version,
            ]
            await MainActor.run { result(answer) }
        }
    }

    /// The upload bytes (`AssetPrefilter.renderedJPEG`, never the original
    /// resource), written to a temporary file so a later background upload can
    /// read it from disk. nil when the system rendered nothing. This one MAY use
    /// the network: by now the user has chosen the asset.
    private static func renderedJpeg(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let asset = asset(args, result) else { return }
        Task {
            guard let data = await AssetPrefilter.renderedJPEG(for: asset) else {
                await MainActor.run { result(nil) }
                return
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera-sweep", isDirectory: true)
            let name = AssetIdentity.assetKey(for: asset).replacingOccurrences(of: ":", with: "-")
            let file = dir.appendingPathComponent(name + ".jpg")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                await MainActor.run { result(["path": file.path, "bytes": data.count]) }
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "writeFailed",
                                        message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// A review card's picture (Swift `SweepReviewSection.CandidateCard`): the
    /// asset at the card's size, as JPEG bytes. Network OFF, as in Swift — a
    /// card never downloads an iCloud original just to be looked at — so an
    /// asset that is not on the device answers nil and the card draws its
    /// ground. One answer only (`.highQualityFormat`), where Swift's
    /// opportunistic request skipped the degraded one by hand.
    private static func thumbnail(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let asset = asset(args, result) else { return }
        let width = (args["width"] as? NSNumber)?.doubleValue ?? 216
        let height = (args["height"] as? NSNumber)?.doubleValue ?? 280
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: width, height: height),
            contentMode: .aspectFill, options: options
        ) { image, _ in
            let data = image?.jpegData(compressionQuality: 0.8)
            DispatchQueue.main.async {
                result(data.map { FlutterStandardTypedData(bytes: $0) })
            }
        }
    }
}

/// The library's persistent change history (5.40.0, ADR-195; spec §7): after
/// a walk that finished, a pass reads only the assets inserted or updated
/// since it. iOS 16 and later; before that Photos keeps no history, both
/// calls answer nil, and every pass walks the library.
enum LibraryHistory {
    /// The current token, archived for the Dart side to keep.
    static func token() -> String? {
        guard #available(iOS 16, *) else { return nil }
        return archive(PHPhotoLibrary.shared().currentChangeToken)
    }

    /// Inserted or updated assets since `wire`, and the token to keep next;
    /// nil when the token cannot answer (unreadable, expired, history
    /// unavailable) and only a walk will do. Deletions are not reported: the
    /// sweep needs nothing for them.
    static func changes(since wire: String) -> (token: String, localIdentifiers: [String])? {
        guard #available(iOS 16, *) else { return nil }
        guard let data = Data(base64Encoded: wire),
              let since = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClass: PHPersistentChangeToken.self, from: data),
              // Read BEFORE the changes: one landing between the two is read
              // again by the next pass, never missed.
              let next = archive(PHPhotoLibrary.shared().currentChangeToken)
        else { return nil }
        let history: PHPersistentChangeFetchResult
        do {
            history = try PHPhotoLibrary.shared().fetchPersistentChanges(since: since)
        } catch {
            // `persistentChangeTokenExpired` or `persistentChangeDetailsUnavailable`.
            return nil
        }
        var ids = Set<String>()
        for change in history {
            guard let details = try? change.changeDetails(for: .asset) else { return nil }
            ids.formUnion(details.insertedLocalIdentifiers)
            ids.formUnion(details.updatedLocalIdentifiers)
        }
        return (next, Array(ids))
    }

    @available(iOS 16, *)
    private static func archive(_ token: PHPersistentChangeToken) -> String? {
        (try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))?
            .base64EncodedString()
    }
}

/// The library's change events, while someone listens (F-125 S3). It
/// registers with Photos only with FULL access — registering is not asking,
/// but there is nothing to watch for a sweep that cannot run, and the refusal
/// is the same one every library method answers.
final class LibraryChanges: NSObject, FlutterStreamHandler, PHPhotoLibraryChangeObserver {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        let access = PhotoLibraryAccess.current
        if let code = CameraSweepChannel.refusal(for: access) {
            return FlutterError(code: code,
                                message: "photo library access is \(CameraSweepChannel.wire(access))",
                                details: nil)
        }
        if sink == nil { PHPhotoLibrary.shared().register(self) }
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if sink != nil { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        sink = nil
        return nil
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.sink?("changed") }
    }
}
