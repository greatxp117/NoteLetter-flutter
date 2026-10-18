import Flutter
import Foundation
import Photos

/// F-125 S1: the camera-roll sweep's native bridge (INV-14,
/// `spec/features/camera-roll-sweep.md`). Nothing above it yet: no ledger, no
/// screens, no background task, no uploads — those are S2-S4.
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

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in handle(call, result) }
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

    /// One enumerated asset. Every field is metadata: no pixel is read, so this
    /// is as free for an iCloud-only asset as for a local one.
    static func describe(_ asset: PHAsset) -> [String: Any] {
        [
            "localIdentifier": asset.localIdentifier,
            "assetKey": AssetIdentity.assetKey(for: asset),
            // The exact Double the key's millisecond figure was derived from,
            // so a caller can recompute the key and get the same bytes.
            "creationSeconds": asset.creationDate.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
            "pixelWidth": asset.pixelWidth,
            "pixelHeight": asset.pixelHeight,
            "originalFilename": AssetIdentity.originalFilename(for: asset) as Any? ?? NSNull(),
            "isScreenshot": PhotoLibraryAccess.isScreenshot(asset),
            "isRepresentative": PhotoLibraryAccess.isRepresentative(asset),
        ]
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

        case "fetchImages", "examine", "renderedJpeg":
            let access = PhotoLibraryAccess.current
            if let code = refusal(for: access) {
                return result(FlutterError(
                    code: code, message: "photo library access is \(wire(access))", details: nil))
            }
            switch call.method {
            case "fetchImages":  fetchImages(args, result)
            case "examine":      examine(args, result)
            default:             renderedJpeg(args, result)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let ms = (value as? NSNumber)?.int64Value else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    /// A page of `PhotoLibraryAccess.fetchImages` — images only, newest first —
    /// with every asset's key. Bursts are NOT filtered here: each asset says
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
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = PhotoLibraryAccess.fetchImages(since: since, until: until)
            let total = fetched.count
            var assets: [[String: Any]] = []
            if offset < total {
                for index in offset..<min(offset + limit, total) {
                    assets.append(describe(fetched.object(at: index)))
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
}
