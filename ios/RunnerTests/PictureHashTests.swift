import UIKit
import XCTest
// 5.50.0 (ADR-202, INV-37): the camera roll's picture hash
// (`ios/Runner/CameraSweep/PictureHash.swift`, compiled into this bundle as
// the rest of `CameraSweep/` is) against `spec/picture-hash.json` — the same
// vectors the backend's `dhash_from_rgb` and Android's `PictureHash.kt` are
// held to, so the phone's hash of its thumbnail and the server's hash of the
// upload are one function. Read from the contracts checkout, never copied:
// a copy is one more place for the vectors to drift.

final class PictureHashTests: XCTestCase {

    private struct Vector: Decodable {
        let name: String
        let width: Int
        let height: Int
        let rgb: String
        let dhash: String
    }

    private struct Vectors: Decodable {
        let version: Int
        let vectors: [Vector]
    }

    /// `NoteLetter-contracts/spec/picture-hash.json`, beside this repo.
    private static let specURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RunnerTests
        .deletingLastPathComponent()   // ios
        .deletingLastPathComponent()   // NoteLetter-flutter
        .deletingLastPathComponent()   // the workspace
        .appendingPathComponent("NoteLetter-contracts/spec/picture-hash.json")

    private func vectors() throws -> [Vector] {
        let data = try Data(contentsOf: Self.specURL)
        let file = try JSONDecoder().decode(Vectors.self, from: data)
        XCTAssertEqual(file.version, 1, "a new signature version is a re-signing, not a test edit")
        return file.vectors
    }

    func testEveryVectorInTheSpec() throws {
        let all = try vectors()
        XCTAssertEqual(all.count, 8, "the spec's vectors, all of them")
        for v in all {
            let rgb = try XCTUnwrap(Data(base64Encoded: v.rgb), v.name)
            XCTAssertEqual(rgb.count, v.width * v.height * 3, v.name)
            XCTAssertEqual(PictureHash.dhash(rgb: [UInt8](rgb), width: v.width, height: v.height),
                           v.dhash, v.name)
        }
    }

    /// The RGBX path the thumbnail takes reads the same pixels the packed
    /// path does: each vector, padded with a fourth byte the hash must ignore.
    func testTheBitmapLayoutIsTheSameFunction() throws {
        for v in try vectors() {
            let rgb = [UInt8](try XCTUnwrap(Data(base64Encoded: v.rgb)))
            var rgbx = [UInt8]()
            rgbx.reserveCapacity(v.width * v.height * 4)
            for i in stride(from: 0, to: rgb.count, by: 3) {
                rgbx.append(contentsOf: [rgb[i], rgb[i + 1], rgb[i + 2], 0xA5])
            }
            let hash = rgbx.withUnsafeBytes {
                PictureHash.dhash(bytes: $0, width: v.width, height: v.height,
                                  bytesPerPixel: 4, bytesPerRow: v.width * 4)
            }
            XCTAssertEqual(hash, v.dhash, v.name)
        }
    }

    /// Through CoreGraphics: the vector drawn as a CGImage and read back by
    /// `dhash(of:)` — the call the pre-filter makes.
    func testThroughCoreGraphics() throws {
        for v in try vectors() {
            let rgb = [UInt8](try XCTUnwrap(Data(base64Encoded: v.rgb)))
            var rgbx = [UInt8]()
            for i in stride(from: 0, to: rgb.count, by: 3) {
                rgbx.append(contentsOf: [rgb[i], rgb[i + 1], rgb[i + 2], 0xFF])
            }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(rgbx) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: v.width, height: v.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: v.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent))
            XCTAssertEqual(PictureHash.dhash(of: image), v.dhash, v.name)
        }
    }

    /// Step 1, upright: a picture stored turned, as a sensor leaves it, is
    /// hashed as it is SEEN. Each vector is stored a quarter turn the other
    /// way and tagged `.right` (EXIF 6: shown turned 90° clockwise), so UIKit
    /// turns it back; the hash must be the vector's own.
    func testOrientationIsAppliedBeforeHashing() throws {
        for v in try vectors() {
            let rgb = [UInt8](try XCTUnwrap(Data(base64Encoded: v.rgb)))
            // Shown = stored turned clockwise, so stored(sx, sy) is
            // shown(W - 1 - sy, sx), stored W' = H and H' = W.
            let sw = v.height, sh = v.width
            var stored = [UInt8](repeating: 0xFF, count: sw * sh * 4)
            for sy in 0..<sh {
                for sx in 0..<sw {
                    let dx = v.width - 1 - sy, dy = sx
                    let from = (dy * v.width + dx) * 3, to = (sy * sw + sx) * 4
                    stored[to] = rgb[from]; stored[to + 1] = rgb[from + 1]; stored[to + 2] = rgb[from + 2]
                }
            }
            let raw = try XCTUnwrap(CGImage(
                width: sw, height: sh, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sw * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: CGDataProvider(data: Data(stored) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent))
            let turned = UIImage(cgImage: raw, scale: 1, orientation: .right)
            XCTAssertEqual(PictureHash.dhash(of: turned), v.dhash, "\(v.name), turned back")
        }
    }

    func testUnderNineByEightHasNoHash() {
        XCTAssertNil(PictureHash.dhash(rgb: [UInt8](repeating: 0, count: 8 * 8 * 3), width: 8, height: 8))
        XCTAssertNil(PictureHash.dhash(rgb: [UInt8](repeating: 0, count: 9 * 7 * 3), width: 9, height: 7))
        XCTAssertNil(PictureHash.dhash(rgb: [UInt8](repeating: 0, count: 10), width: 9, height: 8),
                     "a buffer shorter than its size")
    }
}
