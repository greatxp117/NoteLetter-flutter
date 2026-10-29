package xp.NoteLetter.Flutter.camerasweep

import android.content.Context
import android.os.Build
import android.provider.MediaStore
import org.json.JSONObject

/**
 * The library's change history on Android (5.40.0, ADR-195;
 * features/camera-roll-sweep.md §7), iOS's `LibraryHistory` over MediaStore:
 * after a walk that finished, a pass reads only the rows added or modified
 * since it.
 *
 * The token is each external volume's generation (`getGeneration`) beside
 * that volume's version (`getVersion`). A changed version means MediaStore
 * rebuilt the volume and its generations restarted, so only a walk will do,
 * and so does a volume the token never saw (a card put in since). Before
 * Android 11 MediaStore keeps no generations: both calls answer null, and
 * every pass walks the library.
 */
object LibraryHistory {
    /** The current token: `{volume: {"version": …, "generation": …}}`. */
    fun token(context: Context): String? {
        if (Build.VERSION.SDK_INT < 30) return null
        return encode(MediaStore.getExternalVolumeNames(context).associateWith {
            MediaStore.getVersion(context, it) to MediaStore.getGeneration(context, it)
        })
    }

    /** Added or modified rows since [wire], and the token to keep next; null when only a walk will do. */
    fun changes(context: Context, wire: String): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < 30) return null
        // Read BEFORE the changes: a row landing between the two is read again
        // by the next pass, never missed.
        val next = token(context) ?: return null
        val versions = MediaStore.getExternalVolumeNames(context).associateWith { MediaStore.getVersion(context, it) }
        val from = generationsToRead(wire, versions) ?: return null
        val ids = linkedSetOf<String>()
        for ((volume, generation) in from) {
            context.contentResolver.query(
                MediaStore.Images.Media.getContentUri(volume),
                arrayOf(MediaStore.Images.Media._ID),
                "${MediaStore.MediaColumns.GENERATION_ADDED} > ? OR ${MediaStore.MediaColumns.GENERATION_MODIFIED} > ?",
                arrayOf("$generation", "$generation"),
                null,
            )?.use { c -> while (c.moveToNext()) ids += "${c.getLong(0)}" }
        }
        return mapOf("token" to next, "localIdentifiers" to ids.toList())
    }

    fun encode(volumes: Map<String, Pair<String, Long>>): String = JSONObject().apply {
        for ((volume, vg) in volumes) {
            put(volume, JSONObject().put("version", vg.first).put("generation", vg.second))
        }
    }.toString()

    /**
     * The generation to read each current volume from, or null when the token
     * cannot answer: unreadable, a volume it never saw, or a volume whose
     * version changed. A volume that went away needs nothing.
     */
    fun generationsToRead(wire: String, versionsNow: Map<String, String>): Map<String, Long>? {
        val then = runCatching { JSONObject(wire) }.getOrNull() ?: return null
        return versionsNow.mapValues { (volume, version) ->
            val was = then.optJSONObject(volume) ?: return null
            if (was.optString("version", "") != version) return null
            if (!was.has("generation")) return null
            was.optLong("generation", -1L).takeIf { it >= 0 } ?: return null
        }
    }
}
