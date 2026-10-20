package xp.NoteLetter.Flutter.camerasweep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Android key against iOS's 13 vectors (ios/RunnerTests/
 * CameraSweepBridgeTests.swift, the retired Swift app's key). Each vector's
 * name is the one iOS's resource rule picked, and its milliseconds are
 * Swift's `Int(seconds * 1000)` — Kotlin's `toLong()` truncates the same way.
 */
class AssetIdentityTest {
    private fun ms(seconds: Double?): Long? = seconds?.let { (it * 1000).toLong() }

    @Test
    fun theKeyIsTheSwiftKeyForEveryVector() {
        val vectors = listOf(
            Triple(Triple(1700000000.123456, 1170 to 2532, "IMG_0001.PNG"),
                "v1:cd0fc261514e464d21f034cbb0d9f0a8132936225f3bd42aa8d1a500220b64e1", "screenshot-fractional-ms"),
            Triple(Triple(1700000000.9999, 4032 to 3024, "IMG_4821.HEIC"),
                "v1:377261fc4330b23d0fcecd403f7b290bfffcbdbb8b2bb92444614a1de6f2bb1f", "heic-near-next-ms"),
            Triple(Triple(null, 100 to 100, null),
                "v1:97f733a4c961a07a70f2ccb65ad94b8da243a17bfa9be5fb8a491523bac66014", "no-date-no-resources"),
            Triple(Triple(1500000000.0, 1920 to 1080, "Café crème — 日本語 ノート.jpeg"),
                "v1:90bbae8039da619d6169a78abf61091c09b0cb5024bf00bb23dcaae63d4b395e", "non-ascii-prefers-photo"),
            Triple(Triple(1600000000.5, 800 to 600, "Café.jpg"),
                "v1:decb8c84656a68890675ad2c5a3b7537fa0d256f8bde8c90517215f05eb3b334", "nfc-e-acute"),
            Triple(Triple(1600000000.5, 800 to 600, "Café.jpg"),
                "v1:d33ef2f6f56e1390e786201e46b65ce9d4ecc5b4da3d7ec004ab1bff825a1d44", "nfd-e-acute"),
            Triple(Triple(1650000000.001, 3024 to 4032, "📝 notes 🧾.png"),
                "v1:733b856f39a891b3ec984ddbfc3f411165a6ad0c7011403168cef1d1cda31389", "emoji"),
            Triple(Triple(-1.5, 1 to 1, "old.jpg"),
                "v1:d895041930d6c5431bcc5157ba7d2b399b3b4674d16032fe4bcdb484459ccdae", "negative-fraction"),
            Triple(Triple(-0.0005, 2 to 2, "epoch.jpg"),
                "v1:6e9da197b14a3f00f1ee7b4c2568cb935ef58d5b71f8b80d005a4487f83b740b", "tiny-negative-truncates-to-zero"),
            Triple(Triple(1690000000.25, 640 to 480, "FullSizeRender.jpg"),
                "v1:8e05fa3cfaa64d5a0ad19983c9c96147cae2ac490388076f8bac199a5f3be416", "fullsize-when-no-photo"),
            Triple(Triple(1690000000.25, 640 to 480, "clip.MOV"),
                "v1:7fd55a9ca1e08d41ad1f703b6b4eeccc89e6bc36116c2cb714e77283b7ab50a7", "first-when-neither"),
            Triple(Triple(1700000001.0, 10 to 20, "a|b.jpg"),
                "v1:6d5d182fdfcae8ab1fdff64d8c93824482e79e2c6c7aa544f168a65eb5ae7159", "pipe-in-name"),
            Triple(Triple(1700000002.0, 10 to 20, ""),
                "v1:5af3cf2ffede13323fb0d5b0615a1c50c103e382a06377a08147c41fa3790f29", "empty-name-is-not-unknown"),
        )
        for ((input, golden, label) in vectors) {
            val (seconds, size, name) = input
            assertEquals(label, golden, AssetIdentity.assetKey(ms(seconds), size.first, size.second, name))
        }
    }

    @Test
    fun aScreenshotIsARowInAScreenshotsDirectory() {
        assertTrue(AssetIdentity.isScreenshot("Pictures/Screenshots/", null))
        assertTrue(AssetIdentity.isScreenshot("DCIM/Screenshots/", "Screenshots"))
        assertTrue(AssetIdentity.isScreenshot("DCIM/screenshots/", null))
        assertFalse(AssetIdentity.isScreenshot("DCIM/Camera/", "Camera"))
        assertFalse(AssetIdentity.isScreenshot("Pictures/MyScreenshotsApp/", null))
        // Only API 28 and below has no RELATIVE_PATH.
        assertTrue(AssetIdentity.isScreenshot(null, "Screenshots"))
        assertFalse(AssetIdentity.isScreenshot(null, "Camera"))
        assertFalse(AssetIdentity.isScreenshot(null, null))
    }
}
