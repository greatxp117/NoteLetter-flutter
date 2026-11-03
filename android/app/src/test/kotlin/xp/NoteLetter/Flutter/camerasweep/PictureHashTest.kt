package xp.NoteLetter.Flutter.camerasweep

import java.io.File
import java.util.Base64
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 5.50.0 (ADR-202, INV-37): the camera roll's picture hash ([PictureHash])
 * against `spec/picture-hash.json` — the same vectors the backend's
 * `dhash_from_rgb` and iOS's `PictureHash.swift` are held to, so the phone's
 * hash of its thumbnail and the server's hash of the upload are one
 * function. Read from the contracts checkout beside this repo, never copied.
 */
class PictureHashTest {
    private data class Vector(val name: String, val width: Int, val height: Int, val rgb: ByteArray, val dhash: String)

    /** Gradle runs a module's unit tests from the module (android/app). */
    private fun vectors(): List<Vector> {
        val spec = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "NoteLetter-contracts/spec/picture-hash.json") }
            .first { it.isFile }
        val json = JSONObject(spec.readText())
        assertEquals("a new signature version is a re-signing, not a test edit", 1, json.getInt("version"))
        val all = json.getJSONArray("vectors")
        return (0 until all.length()).map {
            val v = all.getJSONObject(it)
            Vector(v.getString("name"), v.getInt("width"), v.getInt("height"),
                Base64.getDecoder().decode(v.getString("rgb")), v.getString("dhash"))
        }
    }

    @Test
    fun everyVectorInTheSpec() {
        val all = vectors()
        assertEquals("the spec's vectors, all of them", 8, all.size)
        for (v in all) {
            assertEquals(v.name, v.width * v.height * 3, v.rgb.size)
            assertEquals(v.name, v.dhash, PictureHash.dhash(v.rgb, v.width, v.height))
        }
    }

    /** The bitmap path (`getPixels`' ARGB) is the same function. */
    @Test
    fun theBitmapLayoutIsTheSameFunction() {
        for (v in vectors()) {
            val argb = IntArray(v.width * v.height) { i ->
                val r = v.rgb[i * 3].toInt() and 0xFF
                val g = v.rgb[i * 3 + 1].toInt() and 0xFF
                val b = v.rgb[i * 3 + 2].toInt() and 0xFF
                // An alpha the hash must not read.
                (0x5A shl 24) or (r shl 16) or (g shl 8) or b
            }
            assertEquals(v.name, v.dhash, PictureHash.dhash(argb, v.width, v.height))
        }
    }

    @Test
    fun underNineByEightHasNoHash() {
        assertNull(PictureHash.dhash(ByteArray(8 * 8 * 3), 8, 8))
        assertNull(PictureHash.dhash(ByteArray(9 * 7 * 3), 9, 7))
        assertNull("a buffer shorter than its size", PictureHash.dhash(ByteArray(10), 9, 8))
        assertNull(PictureHash.dhash(IntArray(8 * 8), 8, 8))
    }
}
