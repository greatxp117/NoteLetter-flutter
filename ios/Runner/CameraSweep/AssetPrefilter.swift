// F-125 S1: ported VERBATIM from the retired Swift app's
// NoteLetter/NoteLetter/CameraSweep/AssetPrefilter.swift (NoteLetter 910864a).
// Any change below the provenance line is listed in the F-125 S1 report; keep
// it that way, or the INV-14 key and the 80-character calibration move.

import Foundation
import Photos
import UIKit
import Vision

/// The on-device gate that decides whether a photo is worth uploading.
///
/// Normative in `spec/features/camera-roll-sweep.md`, not an implementation
/// detail: if one client uploaded everything and another pre-filtered, the same
/// library would produce wildly different bills and different libraries.
///
/// Classification and extraction are the same Vision call on the backend, so
/// there is no cheap server-side probe — the only way to avoid paying for a
/// photo of a beach is to not send it. Apple's text recognition runs free and
/// offline, so that decision happens here.
enum AssetPrefilter {

    /// Stamped into every `noText` verdict. Bump it when the rules below change
    /// so a better filter revisits what an older one rejected.
    static let version = 1

    /// Deliberately the backend's own `_FACE_TEXT_THRESHOLD` (image_processor.py).
    /// That is the boundary the server uses to separate "a photo that happens to
    /// contain text" from "a photo"; pinning to it stops the client drifting into
    /// a private definition of "has text".
    static let minimumCharacters = 80

    /// Long edge of the thumbnail we recognize against. Big enough for body text,
    /// small enough that a full-library pass is cheap.
    private static let thumbnailEdge: CGFloat = 1024

    enum Verdict {
        case candidate
        case noText
        /// Not on this device. Deferred, never downloaded — a sweep must not
        /// silently spend the user's cellular data — and never recorded as
        /// "no text", which would be a permanent wrong answer.
        case notLocallyAvailable
    }

    static func examine(_ asset: PHAsset) async -> Verdict {
        await examination(of: asset).verdict
    }

    /// PORT CHANGE 1 (F-125 S1): `examine`'s body, unchanged, also reporting
    /// what it measured — the character count and the thumbnail it read — so
    /// the bridge can show the verdict's evidence. The verdict expressions are
    /// the original's, line for line.
    struct Examination {
        let verdict: Verdict
        /// nil when no recognition ran (a screenshot, or no local thumbnail).
        let characters: Int?
        let thumbnailWidth: Int?
        let thumbnailHeight: Int?
    }

    static func examination(of asset: PHAsset) async -> Examination {
        // Apple already tags screenshots, and they are the highest-value class
        // here. Free, high precision, no recognition pass needed.
        if PhotoLibraryAccess.isScreenshot(asset) {
            return Examination(verdict: .candidate, characters: nil,
                               thumbnailWidth: nil, thumbnailHeight: nil)
        }

        guard let image = await localThumbnail(for: asset) else {
            return Examination(verdict: .notLocallyAvailable, characters: nil,
                               thumbnailWidth: nil, thumbnailHeight: nil)
        }
        guard let cgImage = image.cgImage else {
            return Examination(verdict: .noText, characters: nil,
                               thumbnailWidth: nil, thumbnailHeight: nil)
        }

        let text = await recognizeText(in: cgImage)
        return Examination(verdict: text.count >= minimumCharacters ? .candidate : .noText,
                           characters: text.count,
                           thumbnailWidth: cgImage.width, thumbnailHeight: cgImage.height)
    }

    // MARK: - Local-only image access

    /// `isNetworkAccessAllowed = false` is the load-bearing line: without it a
    /// sweep would pull originals down from iCloud for every asset it is about to
    /// reject. The cost is that an optimized asset yields a degraded placeholder,
    /// which is exactly why a degraded result is reported as `notLocallyAvailable`
    /// rather than being recognized against and written off.
    private static func localThumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        let target = CGSize(width: thumbnailEdge, height: thumbnailEdge)

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: options
            ) { image, info in
                // requestImage can call back twice (degraded, then full). Only the
                // final one is a verdict.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(returning: inCloud ? nil : image)
            }
        }
    }

    private static func recognizeText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            // PORT CHANGE 2 (F-125 S1): resume once. If Vision reports a failure
            // through BOTH the completion handler and `perform`'s throw, the
            // original resumed twice — a checked continuation's fatal error, which
            // here would kill the whole Flutter app. Whether Vision ever does both
            // is unproven; the guard changes nothing when it does not.
            var resumed = false
            func finish(_ text: String) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: text)
            }
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                finish(text)
            }
            // .fast is the right trade for a gate: we are counting characters to
            // decide whether to upload, not transcribing. The backend does the
            // real reading.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                finish("")
            }
        }
    }

    // MARK: - Upload bytes

    /// A **rendered representation**, never the original asset resource.
    ///
    /// The backend routes on `image/*` and normalizes HEIC (2.10.0), but a camera
    /// roll also holds formats Vision cannot read — RAW/DNG above all, and
    /// `image/x-adobe-dng` passes the `image/*` check, reaches Vision and dies at
    /// `status: error`. That is the 2.10.0 HEIC defect exactly, and asking the
    /// system to render avoids shipping it again. It also resolves a Live Photo to
    /// its still and gives one predictable declared MIME type.
    static func renderedJPEG(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true   // by now the user has opted in to this asset
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.9))
            }
        }
    }
}
