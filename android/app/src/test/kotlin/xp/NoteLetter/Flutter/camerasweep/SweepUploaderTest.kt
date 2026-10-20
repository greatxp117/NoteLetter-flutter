package xp.NoteLetter.Flutter.camerasweep

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The result an upload writes down, against what `SweepUploadResult.fromWire`
 * (lib/services/sweep_uploader.dart) requires: every key present, `error`
 * present even when null, and `ok` only for a 2xx with no transport error —
 * the one bit that moves a photo to `ingested` (features §5 rule 1).
 */
class SweepUploaderTest {
    private fun r(code: Int, error: String?) =
        SweepUploader.result("U1", "42", "v1:abc", 1.0, code, error, appState = 2)

    @Test
    fun onlyA2xxWithNoErrorLanded() {
        assertTrue(r(200, null).getBoolean("ok"))
        assertTrue(r(204, null).getBoolean("ok"))
        assertFalse(r(403, null).getBoolean("ok"))
        assertFalse(r(0, "timeout").getBoolean("ok"))
        assertFalse(r(200, "reset after the body").getBoolean("ok"))
    }

    @Test
    fun theShapeIsTheOneDartReads() {
        val o = r(0, null)
        for (k in listOf("uploadId", "localIdentifier", "assetKey", "ok", "statusCode", "error",
                "finishedAtMs", "appState")) {
            assertTrue(k, o.has(k))
        }
        assertEquals(JSONObject.NULL, o.get("error"))
        assertEquals("timeout", r(0, "timeout").getString("error"))
        assertEquals(2, o.getInt("appState"))
        assertEquals("42", o.getString("localIdentifier"))
    }
}
