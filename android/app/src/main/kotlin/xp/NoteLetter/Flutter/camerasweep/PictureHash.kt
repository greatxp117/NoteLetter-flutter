package xp.NoteLetter.Flutter.camerasweep

/**
 * 5.50.0 (ADR-202, INV-37): the picture hash, computed by the camera roll
 * from the pre-filter's own decode so the server can recognise a photo the
 * library already holds BEFORE it is read and sent
 * (`spec/features/picture-dedupe.md` §The picture hash). Three
 * implementations compute it — the backend (`functions/picture_signature.py`
 * `dhash_from_rgb`), iOS's `PictureHash.swift` and this — and all three are
 * tested against `spec/picture-hash.json` (here: `PictureHashTest`).
 *
 * Pure Kotlin over pixels already upright, so the JVM test reads the very
 * code the bridge runs; [CameraSweepChannel] hands it a decoded `Bitmap`'s
 * `getPixels`.
 */
object PictureHash {
    /**
     * A cell must lead its right neighbour by MORE than this many levels for
     * its bit to be 1 (ADR-202 §Calibration). Changing it is a `v` bump.
     */
    const val MARGIN = 1L

    /** Integer luma, `(R·299 + G·587 + B·114) / 1000`. */
    fun luma(r: Int, g: Int, b: Int): Int = (r * 299 + g * 587 + b * 114) / 1000

    /** Packed RGB, row-major — the shape `spec/picture-hash.json` holds. */
    fun dhash(rgb: ByteArray, width: Int, height: Int): String? {
        if (width < 9 || height < 8 || rgb.size < width * height * 3) return null
        return hash(width, height) { i ->
            luma(rgb[i * 3].toInt() and 0xFF, rgb[i * 3 + 1].toInt() and 0xFF, rgb[i * 3 + 2].toInt() and 0xFF)
        }
    }

    /** `Bitmap.getPixels`' packed ARGB, row-major; alpha is not read. */
    fun dhash(argb: IntArray, width: Int, height: Int): String? {
        if (width < 9 || height < 8 || argb.size < width * height) return null
        return hash(width, height) { i ->
            val p = argb[i]
            luma((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
        }
    }

    /**
     * Pixel (x, y) of a W×H picture is in cell `(x·9 / W, y·8 / H)`; bit
     * `r·8 + c` is 1 when `sum_l·count_r − sum_r·count_l >
     * MARGIN·count_l·count_r`, compared exactly in integers; row-major, most
     * significant first, 16 lowercase hex digits. [lumaAt] takes `y·W + x`.
     */
    private inline fun hash(width: Int, height: Int, lumaAt: (Int) -> Int): String {
        val sums = LongArray(72)
        val counts = LongArray(72)
        val column = IntArray(width) { it * 9 / width }
        for (y in 0 until height) {
            val row = (y * 8 / height) * 9
            val base = y * width
            for (x in 0 until width) {
                val cell = row + column[x]
                sums[cell] += lumaAt(base + x).toLong()
                counts[cell]++
            }
        }
        var value = 0L
        for (r in 0 until 8) {
            for (c in 0 until 8) {
                val a = r * 9 + c
                val b = a + 1
                val brighter = sums[a] * counts[b] - sums[b] * counts[a] > MARGIN * counts[a] * counts[b]
                value = (value shl 1) or (if (brighter) 1L else 0L)
            }
        }
        // Unsigned, and never localised (a locale's own digits are not hex).
        return java.lang.Long.toHexString(value).padStart(16, '0')
    }
}
