// F-125 S1: ported VERBATIM from the retired Swift app's
// NoteLetter/NoteLetter/CameraSweep/AssetIdentity.swift (NoteLetter 910864a).
// Any change below the provenance line is listed in the F-125 S1 report; keep
// it that way, or the INV-14 key and the 80-character calibration move.

import CryptoKit
import Foundation
import Photos

/// The INV-14 asset key (contract 2.18.0, ADR-023).
///
/// The backend derives a document id from `(uid, "camera_roll", assetKey)` and
/// creates at most one document per key, so this value decides whether a sweep
/// re-ingests the library or not. INV-14 requires it to be **stable across a
/// device restore and identical on two devices syncing one library**.
///
/// `PHAsset.localIdentifier` satisfies neither: it is re-minted on restore and
/// differs per device, so keying on it means a restore silently doubles the
/// library — with no request ever failing, which is the expensive failure mode.
/// Hashing the asset's *content* would be stable, but on an iCloud-optimized
/// library it forces a full original download per asset: gigabytes of cellular
/// data and hours of latency, spent on assets the pre-filter is about to reject.
///
/// So the key is a hash of stable **metadata** — creation instant, pixel
/// dimensions, original filename. Every component is available without reading a
/// single pixel, so the key is free even for an asset that lives only in iCloud.
enum AssetIdentity {

    /// Bumped only if the derivation changes. Old keys keep resolving to their
    /// existing documents; new ones simply start a new namespace.
    static let schemeVersion = "v1"

    static func assetKey(for asset: PHAsset) -> String {
        let millis = Int((asset.creationDate ?? .distantPast).timeIntervalSince1970 * 1000)
        let name = originalFilename(for: asset) ?? "unknown"
        let material = "\(schemeVersion)|\(millis)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(name)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return "\(schemeVersion):" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Metadata only — `PHAssetResource` does not fetch bytes.
    static func originalFilename(for asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred = resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .fullSizePhoto }
            ?? resources.first
        return preferred?.originalFilename
    }
}
