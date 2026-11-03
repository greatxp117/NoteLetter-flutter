// 5.50.0 (ADR-202, INV-37): the picture hash, computed by the camera roll
// from the pre-filter's own thumbnail so the server can recognise a photo the
// library already holds BEFORE it is read off iCloud or sent
// (`spec/features/picture-dedupe.md` §The picture hash). Not a port: the
// retired Swift app had no such thing. Three implementations compute it —
// the backend (`functions/picture_signature.py` `dhash_from_rgb`), this file,
// and Android's `PictureHash.kt` — and all three are tested against
// `spec/picture-hash.json` (here: `RunnerTests/PictureHashTests.swift`).

import CoreGraphics
import Foundation
import UIKit

enum PictureHash {

    /// A cell must lead its right neighbour by MORE than this many levels for
    /// its bit to be 1 (ADR-202 §Calibration: without it a JPEG re-encode of a
    /// page with wide margins flipped 14 of 64 bits). Changing it is a `v` bump.
    static let margin = 1

    /// The hash of pixels already upright, read through `bytesPerPixel` and
    /// `bytesPerRow` so the test's packed RGB and a bitmap context's RGBX are
    /// one code path. R, G, B are the first three bytes of each pixel.
    ///
    /// 1. brightness is the integer luma `(R·299 + G·587 + B·114) / 1000`;
    /// 2. pixel (x, y) of a W×H picture is in cell `(x·9 / W, y·8 / H)`;
    /// 3. bit `r·8 + c` is 1 when `sum_l·count_r − sum_r·count_l >
    ///    margin·count_l·count_r` — compared exactly, in integers;
    /// 4. row-major, most significant first, 16 lowercase hex digits.
    ///
    /// nil under 9×8 pixels (a cell would be empty), or for a buffer too short
    /// for the size it claims.
    static func dhash(bytes: UnsafeRawBufferPointer, width: Int, height: Int,
                      bytesPerPixel: Int, bytesPerRow: Int) -> String? {
        guard width >= 9, height >= 8, bytesPerPixel >= 3, bytesPerRow >= width * bytesPerPixel,
              bytes.count >= (height - 1) * bytesPerRow + width * bytesPerPixel else { return nil }
        var sums = [Int](repeating: 0, count: 72)
        var counts = [Int](repeating: 0, count: 72)
        var column = [Int](repeating: 0, count: width)
        for x in 0..<width { column[x] = x * 9 / width }
        for y in 0..<height {
            let row = (y * 8 / height) * 9
            var i = y * bytesPerRow
            for x in 0..<width {
                let luma = (Int(bytes[i]) * 299 + Int(bytes[i + 1]) * 587 + Int(bytes[i + 2]) * 114) / 1000
                let cell = row + column[x]
                sums[cell] += luma
                counts[cell] += 1
                i += bytesPerPixel
            }
        }
        var value: UInt64 = 0
        for r in 0..<8 {
            for c in 0..<8 {
                let a = r * 9 + c, b = a + 1
                let brighter = sums[a] * counts[b] - sums[b] * counts[a] > margin * counts[a] * counts[b]
                value = (value << 1) | (brighter ? 1 : 0)
            }
        }
        return String(format: "%016llx", value)
    }

    /// Packed RGB, row-major — the shape `spec/picture-hash.json` holds.
    static func dhash(rgb: [UInt8], width: Int, height: Int) -> String? {
        rgb.withUnsafeBytes {
            dhash(bytes: $0, width: width, height: height, bytesPerPixel: 3, bytesPerRow: width * 3)
        }
    }

    /// The hash of a thumbnail, made upright first: `requestImage` hands back
    /// a `UIImage` whose `cgImage` is the sensor's orientation, and the hash is
    /// defined on the picture as it is seen (step 1). Drawn at its own pixel
    /// size, scale 1, into sRGB.
    static func dhash(of image: UIImage) -> String? {
        let upright: CGImage?
        if image.imageOrientation == .up {
            upright = image.cgImage
        } else {
            let size = CGSize(width: (image.size.width * image.scale).rounded(),
                              height: (image.size.height * image.scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }.cgImage
        }
        return upright.flatMap(dhash(of:))
    }

    /// The hash of an image already upright: drawn into an 8-bit RGBX sRGB
    /// bitmap at its own size, then read as above.
    static func dhash(of cgImage: CGImage) -> String? {
        let width = cgImage.width, height = cgImage.height
        guard width >= 9, height >= 8,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = UnsafeRawBufferPointer(start: data, count: context.bytesPerRow * height)
        return dhash(bytes: bytes, width: width, height: height,
                     bytesPerPixel: 4, bytesPerRow: context.bytesPerRow)
    }
}
