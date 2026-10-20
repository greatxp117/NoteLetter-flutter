package xp.NoteLetter.Flutter.camerasweep

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * F-125 S5b: the sweep's uploads on Android — iOS's `CameraSweepUploader`
 * (a background `URLSession`) transposed onto WorkManager, answering the same
 * methods on the same channel (`lib/services/sweep_uploader.dart`). The order
 * is the one that keeps the server consistent (features/camera-roll-sweep.md
 * §5's background rules):
 *
 *  1. [stage] MOVES the rendered JPEG into `filesDir` — which the system never
 *     purges, unlike the cache — BEFORE any capture session is opened, so the
 *     step between a session and its upload cannot fail on the disk;
 *  2. the caller opens the session;
 *  3. [start] hands the upload to WorkManager, which runs it whether or not
 *     the app is still alive, and re-runs it if the system stops it.
 *
 * A result is WRITTEN DOWN (SharedPreferences, synchronously) before anyone is
 * told, and stays until the Dart side acknowledges it: an upload that lands
 * while the app is dead reaches the ledger at the next launch (§5 rule 1).
 * What an upload is FOR rides in its work tags, which WorkManager keeps across
 * process death, so [inFlight] can answer for uploads an earlier launch
 * started (§5 rule 3).
 */
object SweepUploader {
    const val EVENTS = "xp.noteletter/camera_sweep/uploads"
    private const val TAG = "camera-sweep-upload"
    private const val PREFS = "camera_sweep_uploads"
    private const val FINISHED = "nl.sweep.uploads.finished"
    private val lock = Any()
    private val main by lazy { Handler(Looper.getMainLooper()) }

    /** The Dart side's listener, when the app is alive and listening. */
    val events = UploadEvents()

    class UploadEvents : EventChannel.StreamHandler {
        var sink: EventChannel.EventSink? = null
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
        }

        override fun onCancel(arguments: Any?) {
            sink = null
        }
    }

    private fun staging(context: Context) = File(context.filesDir, "camera-sweep-uploads")

    private fun staged(context: Context, uploadId: String) = File(staging(context), "$uploadId.jpg")

    fun stage(context: Context, renderedPath: String): Map<String, Any> {
        val dir = staging(context).apply { mkdirs() }
        val uploadId = UUID.randomUUID().toString().uppercase()
        val target = File(dir, "$uploadId.jpg")
        val source = File(renderedPath)
        if (!source.renameTo(target)) {
            // Different filesystems: copy, then remove the original.
            source.copyTo(target, overwrite = true)
            source.delete()
        }
        return mapOf("uploadId" to uploadId, "bytes" to target.length().toInt())
    }

    fun discard(context: Context, uploadId: String) {
        staged(context, uploadId).delete()
    }

    fun start(context: Context, uploadId: String, url: String, mimeType: String,
              localIdentifier: String, assetKey: String) {
        val parsed = runCatching { URL(url) }.getOrNull()
        require(parsed != null && (parsed.protocol == "https" || parsed.protocol == "http")) {
            "Invalid upload URL"
        }
        require(staged(context, uploadId).exists()) {
            "The photo to upload is no longer on this phone."
        }
        val request = OneTimeWorkRequestBuilder<SweepUploadWorker>()
            .setInputData(workDataOf(
                "uploadId" to uploadId, "url" to url, "mimeType" to mimeType,
                "localIdentifier" to localIdentifier, "assetKey" to assetKey,
                "startedAtMs" to System.currentTimeMillis().toDouble(),
            ))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .addTag(TAG)
            .addTag("uploadId:$uploadId")
            .addTag("local:$localIdentifier")
            .addTag("key:$assetKey")
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(uploadId, ExistingWorkPolicy.KEEP, request)
    }

    /** Uploads WorkManager still holds, by what they are for. Blocking. */
    fun inFlight(context: Context): List<Map<String, Any>> =
        runBlocking { WorkManager.getInstance(context).getWorkInfosByTagFlow(TAG).first() }
            .filter { !it.state.isFinished }
            .mapNotNull { info ->
                fun tag(prefix: String) = info.tags.firstOrNull { it.startsWith(prefix) }?.removePrefix(prefix)
                val id = tag("uploadId:") ?: return@mapNotNull null
                mapOf("uploadId" to id, "localIdentifier" to (tag("local:") ?: ""),
                    "assetKey" to (tag("key:") ?: ""))
            }

    fun finished(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        stored(context).map { s -> JSONObject(s).let { o -> o.keys().asSequence().associateWith { k -> o.opt(k).takeIf { it != JSONObject.NULL } } } }
    }

    fun acknowledge(context: Context, uploadIds: Collection<String>) = synchronized(lock) {
        val kept = stored(context).filter { JSONObject(it).optString("uploadId") !in uploadIds }
        save(context, kept)
    }

    /** Written down, then told — never the other way round. */
    fun record(context: Context, result: JSONObject) {
        synchronized(lock) { save(context, stored(context) + result.toString()) }
        main.post { events.sink?.success("finished") }
    }

    private fun stored(context: Context): List<String> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(FINISHED, null)
            ?: return emptyList()
        val a = JSONArray(raw)
        return (0 until a.length()).map { a.getString(it) }
    }

    private fun save(context: Context, all: List<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(FINISHED, JSONArray(all).toString()).commit()
    }

    /** iOS's `applicationState` raw value: 0 in front, 2 in the background. */
    fun appState(): Int {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return if (info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) 0 else 2
    }

    /** A result as iOS's `CameraSweepUploader.result` shapes it. */
    fun result(uploadId: String, localIdentifier: String, assetKey: String, startedAtMs: Double,
               statusCode: Int, error: String?, appState: Int = appState()): JSONObject = JSONObject()
        .put("uploadId", uploadId).put("localIdentifier", localIdentifier)
        .put("assetKey", assetKey).put("startedAtMs", startedAtMs)
        .put("ok", error == null && statusCode in 200..299)
        .put("statusCode", statusCode)
        .put("error", error ?: JSONObject.NULL)
        .put("finishedAtMs", System.currentTimeMillis().toDouble())
        .put("appState", appState)

    internal fun stagedFile(context: Context, uploadId: String) = staged(context, uploadId)
}

/**
 * One upload: the bare signed PUT (INV-08 — no Authorization header, the
 * declared Content-Type), its outcome recorded whatever it is. A failure is a
 * RESULT, never a WorkManager retry: the Dart side re-requests the session
 * and PUTs again to the URL a `duplicate` answer carries (§5, §6), which a
 * blind retry against an expired link could not do.
 */
class SweepUploadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val d = inputData
        val uploadId = d.getString("uploadId") ?: return@withContext Result.failure()
        val local = d.getString("localIdentifier") ?: ""
        val key = d.getString("assetKey") ?: ""
        val started = d.getDouble("startedAtMs", 0.0)
        val file = SweepUploader.stagedFile(applicationContext, uploadId)
        var code = 0
        var error: String? = null
        try {
            if (!file.exists()) throw IllegalStateException("The photo to upload is no longer on this phone.")
            val conn = URL(d.getString("url")).openConnection() as HttpURLConnection
            try {
                conn.requestMethod = "PUT"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", d.getString("mimeType"))
                conn.setFixedLengthStreamingMode(file.length())
                conn.outputStream.use { out -> file.inputStream().use { it.copyTo(out) } }
                code = conn.responseCode
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            if (isStopped) throw e // the system took the time back: WorkManager runs it again
            error = e.localizedMessage ?: e.javaClass.simpleName
        }
        file.delete()
        SweepUploader.record(applicationContext,
            SweepUploader.result(uploadId, local, key, started, code, error))
        Result.success()
    }
}
