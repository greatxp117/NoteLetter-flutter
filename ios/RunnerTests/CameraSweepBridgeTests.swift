import ObjectiveC
import Photos
import XCTest
// F-125 S1: the camera-roll sweep's native bridge. `ios/Runner/CameraSweep/*`
// is compiled into this bundle (as `UploadTypes.swift` is for the share
// rules), so these tests read the PORT's own source.

/// The asset key is the one thing this port may not move by a byte: the
/// backend dedupes on it (INV-14), so a different key re-uploads every photo
/// the retired Swift app already swept, with no request failing.
///
/// The goldens below are what the ORIGINAL `AssetIdentity.assetKey(for:)`
/// (`NoteLetter/NoteLetter/CameraSweep/AssetIdentity.swift`, compiled unchanged
/// with `swiftc` over these same fakes, 2026-10-18) produced. The port must
/// produce them through its own `assetKey(for:)` — the PHAsset path, not a
/// helper beside it. The fakes stand in for exactly what that path reads:
/// `creationDate`, `pixelWidth`, `pixelHeight`, and
/// `PHAssetResource.assetResources(for:)` (swizzled for the duration).
final class CameraSweepBridgeTests: XCTestCase {

    private final class FakeAsset: PHAsset, @unchecked Sendable {
        var date: Date?
        var width = 0
        var height = 0
        var resources: [PHAssetResource] = []
        var id = "fake/L0/001"
        override var creationDate: Date? { date }
        override var pixelWidth: Int { width }
        override var pixelHeight: Int { height }
        override var localIdentifier: String { id }
        override var mediaSubtypes: PHAssetMediaSubtype { [] }
        override var representsBurst: Bool { false }
        override var burstIdentifier: String? { nil }
    }

    private final class FakeResource: PHAssetResource, @unchecked Sendable {
        var kind: PHAssetResourceType = .photo
        var name = ""
        override var type: PHAssetResourceType { kind }
        override var originalFilename: String { name }
    }

    private static let selector = NSSelectorFromString("assetResourcesForAsset:")
    private static var original: IMP?
    /// Every `assetResources(for:)` the code under test made.
    private static var resourceReads = 0

    override class func setUp() {
        super.setUp()
        let method = class_getClassMethod(PHAssetResource.self, selector)!
        let fake: @convention(block) (AnyObject, PHAsset) -> NSArray = { _, asset in
            resourceReads += 1
            return ((asset as? FakeAsset)?.resources ?? []) as NSArray
        }
        original = method_setImplementation(method, imp_implementationWithBlock(fake))
    }

    override class func tearDown() {
        if let original, let method = class_getClassMethod(PHAssetResource.self, selector) {
            method_setImplementation(method, original)
        }
        super.tearDown()
    }

    private func asset(_ seconds: Double?, _ w: Int, _ h: Int,
                       _ resources: [(PHAssetResourceType, String)]) -> FakeAsset {
        let a = FakeAsset()
        a.date = seconds.map { Date(timeIntervalSince1970: $0) }
        a.width = w
        a.height = h
        a.resources = resources.map { kind, name in
            let r = FakeResource()
            r.kind = kind
            r.name = name
            return r
        }
        return a
    }

    func testTheKeyIsTheOriginalSwiftKeyForEveryVector() {
        let vectors: [(String, Double?, Int, Int, [(PHAssetResourceType, String)], String)] = [
            ("screenshot-fractional-ms", 1700000000.123456, 1170, 2532, [(.photo, "IMG_0001.PNG")],
             "v1:cd0fc261514e464d21f034cbb0d9f0a8132936225f3bd42aa8d1a500220b64e1"),
            ("heic-near-next-ms", 1700000000.9999, 4032, 3024, [(.photo, "IMG_4821.HEIC")],
             "v1:377261fc4330b23d0fcecd403f7b290bfffcbdbb8b2bb92444614a1de6f2bb1f"),
            ("no-date-no-resources", nil, 100, 100, [],
             "v1:97f733a4c961a07a70f2ccb65ad94b8da243a17bfa9be5fb8a491523bac66014"),
            ("non-ascii-prefers-photo", 1500000000.0, 1920, 1080,
             [(.fullSizePhoto, "edited.jpg"), (.photo, "Café crème — 日本語 ノート.jpeg")],
             "v1:90bbae8039da619d6169a78abf61091c09b0cb5024bf00bb23dcaae63d4b395e"),
            ("nfc-e-acute", 1600000000.5, 800, 600, [(.photo, "Caf\u{e9}.jpg")],
             "v1:decb8c84656a68890675ad2c5a3b7537fa0d256f8bde8c90517215f05eb3b334"),
            ("nfd-e-acute", 1600000000.5, 800, 600, [(.photo, "Cafe\u{301}.jpg")],
             "v1:d33ef2f6f56e1390e786201e46b65ce9d4ecc5b4da3d7ec004ab1bff825a1d44"),
            ("emoji", 1650000000.001, 3024, 4032, [(.photo, "📝 notes 🧾.png")],
             "v1:733b856f39a891b3ec984ddbfc3f411165a6ad0c7011403168cef1d1cda31389"),
            ("negative-fraction", -1.5, 1, 1, [(.photo, "old.jpg")],
             "v1:d895041930d6c5431bcc5157ba7d2b399b3b4674d16032fe4bcdb484459ccdae"),
            ("tiny-negative-truncates-to-zero", -0.0005, 2, 2, [(.photo, "epoch.jpg")],
             "v1:6e9da197b14a3f00f1ee7b4c2568cb935ef58d5b71f8b80d005a4487f83b740b"),
            ("fullsize-when-no-photo", 1690000000.25, 640, 480,
             [(.adjustmentData, "Adjustments.plist"), (.fullSizePhoto, "FullSizeRender.jpg")],
             "v1:8e05fa3cfaa64d5a0ad19983c9c96147cae2ac490388076f8bac199a5f3be416"),
            ("first-when-neither", 1690000000.25, 640, 480,
             [(.video, "clip.MOV"), (.alternatePhoto, "alt.jpg")],
             "v1:7fd55a9ca1e08d41ad1f703b6b4eeccc89e6bc36116c2cb714e77283b7ab50a7"),
            ("pipe-in-name", 1700000001.0, 10, 20, [(.photo, "a|b.jpg")],
             "v1:6d5d182fdfcae8ab1fdff64d8c93824482e79e2c6c7aa544f168a65eb5ae7159"),
            ("empty-name-is-not-unknown", 1700000002.0, 10, 20, [(.photo, "")],
             "v1:5af3cf2ffede13323fb0d5b0615a1c50c103e382a06377a08147c41fa3790f29"),
        ]
        for (label, seconds, w, h, resources, golden) in vectors {
            XCTAssertEqual(AssetIdentity.assetKey(for: asset(seconds, w, h, resources)), golden, label)
        }
    }

    func testDescribeCarriesTheKeyAndTheExactInputsItWasDerivedFrom() {
        let a = asset(1700000000.9999, 4032, 3024, [(.photo, "Café crème — 日本語 ノート.jpeg")])
        let d = CameraSweepChannel.describe(a)
        XCTAssertEqual(d["assetKey"] as? String, AssetIdentity.assetKey(for: a))
        XCTAssertEqual(d["creationSeconds"] as? Double, 1700000000.9999)
        XCTAssertEqual(d["pixelWidth"] as? Int, 4032)
        XCTAssertEqual(d["pixelHeight"] as? Int, 3024)
        XCTAssertEqual(d["originalFilename"] as? String, "Café crème — 日本語 ノート.jpeg")
        XCTAssertEqual(d["isScreenshot"] as? Bool, false)
        XCTAssertEqual(d["isRepresentative"] as? Bool, true)
        XCTAssertEqual(d["localIdentifier"] as? String, "fake/L0/001")

        let undated = CameraSweepChannel.describe(asset(nil, 1, 1, []))
        XCTAssertTrue(undated["creationSeconds"] is NSNull)
        XCTAssertTrue(undated["originalFilename"] is NSNull)
    }

    /// 5.40.0 (feature spec §4): a listing derives nothing — no resource
    /// lookup, no key — because the ledger skips most listed assets. `describe`
    /// is the listing plus the key and the name.
    func testAListingReadsNoResourceAndCarriesNoKey() {
        let a = asset(1700000000.5, 1170, 2532, [(.photo, "IMG_1.PNG")])
        Self.resourceReads = 0
        let l = CameraSweepChannel.listing(a)
        XCTAssertEqual(Self.resourceReads, 0)
        XCTAssertEqual(Set(l.keys), ["localIdentifier", "creationSeconds", "pixelWidth",
                                     "pixelHeight", "isScreenshot", "isRepresentative"])
        let d = CameraSweepChannel.describe(a)
        XCTAssertGreaterThan(Self.resourceReads, 0)
        XCTAssertEqual(Set(d.keys), Set(l.keys).union(["assetKey", "originalFilename"]))
        for (key, value) in l {
            XCTAssertEqual("\(d[key]!)", "\(value)", key)
        }
    }

    /// A change token that cannot be read is a walk of the whole library,
    /// answered before Photos is asked anything.
    func testAnUnreadableTokenIsAWalk() {
        XCTAssertNil(LibraryHistory.changes(since: "not base64 !"))
        XCTAssertNil(LibraryHistory.changes(since: Data("junk".utf8).base64EncodedString()))
    }

    /// Feature spec §1: partial access is refused, not silently tolerated.
    func testOnlyFullAccessRuns() {
        XCTAssertNil(CameraSweepChannel.refusal(for: .granted))
        XCTAssertEqual(CameraSweepChannel.refusal(for: .limited), "limited")
        XCTAssertEqual(CameraSweepChannel.refusal(for: .denied), "denied")
        XCTAssertEqual(CameraSweepChannel.wire(PhotoLibraryAccess.Access.granted), "granted")
        XCTAssertEqual(CameraSweepChannel.wire(PhotoLibraryAccess.Access.limited), "limited")
        XCTAssertEqual(CameraSweepChannel.wire(PhotoLibraryAccess.Access.denied), "denied")
    }

    func testVerdictWireNames() {
        XCTAssertEqual(CameraSweepChannel.wire(AssetPrefilter.Verdict.candidate), "candidate")
        XCTAssertEqual(CameraSweepChannel.wire(AssetPrefilter.Verdict.noText), "noText")
        XCTAssertEqual(CameraSweepChannel.wire(AssetPrefilter.Verdict.notLocallyAvailable),
                       "notLocallyAvailable")
    }

    /// The calibration the port must not move.
    func testCalibration() {
        XCTAssertEqual(AssetIdentity.schemeVersion, "v1")
        XCTAssertEqual(AssetPrefilter.minimumCharacters, 80)
        XCTAssertEqual(AssetPrefilter.version, 1)
    }
}
