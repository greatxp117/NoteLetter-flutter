package xp.NoteLetter.Flutter.camerasweep

import java.security.MessageDigest

/**
 * The INV-14 asset key on Android (F-125 S5a; features/camera-roll-sweep.md
 * §4, ADR-180): iOS's `v1` material, read from MediaStore — never `_ID`, which
 * a reinstall or a restore re-mints.
 *
 *   sha256("v1|<DATE_TAKEN ms>|<WIDTH>x<HEIGHT>|<DISPLAY_NAME>")
 *
 * The absent cases are `AssetIdentity.swift`'s exactly — a missing date is
 * Swift's `Date.distantPast` in milliseconds, a missing name is `unknown`, an
 * empty name stays empty — and nothing is Unicode-normalised, so the 13 iOS
 * vectors hold byte for byte (AssetIdentityTest).
 */
object AssetIdentity {
    const val SCHEME_VERSION = "v1"

    /** `Date.distantPast.timeIntervalSince1970 * 1000`, as Swift truncates it. */
    const val DISTANT_PAST_MS = -62135769600000L

    fun material(dateTakenMs: Long?, width: Int, height: Int, displayName: String?): String =
        "$SCHEME_VERSION|${dateTakenMs ?: DISTANT_PAST_MS}|${width}x$height|${displayName ?: "unknown"}"

    fun assetKey(dateTakenMs: Long?, width: Int, height: Int, displayName: String?): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(material(dateTakenMs, width, height, displayName).toByteArray(Charsets.UTF_8))
        return "$SCHEME_VERSION:" + digest.joinToString("") { "%02x".format(it) }
    }

    /**
     * A screenshot: a row in a `Screenshots` directory (§2) — where every
     * system screenshot tool writes, as MediaStore has no screenshot flag.
     * [relativePath] is API 29+'s `RELATIVE_PATH` (`Pictures/Screenshots/`,
     * `DCIM/Screenshots/`); [bucket] is the older `BUCKET_DISPLAY_NAME`.
     */
    fun isScreenshot(relativePath: String?, bucket: String?): Boolean {
        if (relativePath != null) {
            return relativePath.split('/').any { it.equals("Screenshots", ignoreCase = true) }
        }
        return bucket.equals("Screenshots", ignoreCase = true)
    }
}
