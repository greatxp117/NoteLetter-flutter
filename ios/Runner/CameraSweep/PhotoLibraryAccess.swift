// F-125 S1: ported VERBATIM from the retired Swift app's
// NoteLetter/NoteLetter/CameraSweep/PhotoLibraryAccess.swift (NoteLetter 910864a).
// Any change below the provenance line is listed in the F-125 S1 report; keep
// it that way, or the INV-14 key and the 80-character calibration move.

import Foundation
import Photos

/// Photo-library authorization and asset enumeration for the camera-roll sweep.
enum PhotoLibraryAccess {

    enum Access {
        case granted
        /// The user picked a handful of photos rather than granting the library.
        /// A sweep over twelve hand-picked assets is a sweep that appears to work
        /// and does nothing, so this is refused with an explanation (ADR-023),
        /// never silently accepted.
        case limited
        case denied
    }

    /// Requested only when the user turns the sweep on — never at launch.
    /// Same rule as push permission (`PushService`, 2.6.0).
    static func request() async -> Access {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return map(status)
    }

    static var current: Access {
        map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .authorized:  return .granted
        case .limited:     return .limited
        default:           return .denied
        }
    }

    // MARK: - Enumeration

    /// Still images only, newest first.
    ///
    /// Videos are out of scope (`fn_ingest_url` covers video sources). A burst
    /// contributes only its representative asset — otherwise one burst uploads
    /// twenty near-identical frames. Live Photos are ordinary images here; the
    /// still is what the renderer hands back.
    static func fetchImages(since: Date?, until: Date?) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let since { predicates.append(NSPredicate(format: "creationDate >= %@", since as NSDate)) }
        if let until { predicates.append(NSPredicate(format: "creationDate < %@", until as NSDate)) }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return PHAsset.fetchAssets(with: options)
    }

    /// A burst frame that is not the one the system picked is skipped.
    static func isRepresentative(_ asset: PHAsset) -> Bool {
        guard asset.representsBurst || asset.burstIdentifier != nil else { return true }
        return asset.representsBurst
    }

    /// Apple already tags screenshots, and they are the highest-value class here
    /// (they map almost exactly onto the backend's `screenshot`/`article_title`),
    /// so they bypass the text threshold entirely.
    static func isScreenshot(_ asset: PHAsset) -> Bool {
        asset.mediaSubtypes.contains(.photoScreenshot)
    }
}
