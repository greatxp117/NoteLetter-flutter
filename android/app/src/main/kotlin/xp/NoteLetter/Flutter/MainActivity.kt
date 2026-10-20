package xp.NoteLetter.Flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import xp.NoteLetter.Flutter.camerasweep.CameraSweepChannel
import xp.NoteLetter.Flutter.camerasweep.SweepBackground

/**
 * The Android share target (F-123): SEND and SEND_MULTIPLE, filtered in
 * AndroidManifest.xml, handed to Dart over `xp.noteletter/share`.
 *
 * Deliberately not a plugin. The share-intent plugins copy every shared file
 * into the cache AS the intent arrives — before anything can refuse it — and
 * drop the reason a read failed, which is the one sentence the share screen
 * owes the reader ("It couldn't be read — …", ported from iOS). Here a share
 * is DESCRIBED first (name, size, type: no bytes read), Dart refuses what the
 * closed upload set would refuse, and only an accepted file is copied, on
 * request, with its failure said in the system's own words.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** The share not yet taken by Dart. Held, because a cold start delivers it
     *  before the Dart side is listening. */
    private var pending: Map<String, Any?>? = null

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var copies = 0

    /** The camera-roll sweep's library bridge (F-125 S5a). */
    private var cameraSweep: CameraSweepChannel? = null

    /** Its background pass's channel on this engine (F-125 S5c). */
    private var sweepBackground: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The LAUNCH intent only: a re-creation (a rotation, a process restored)
        // carries the same intent, and must not offer the same share twice.
        if (savedInstanceState == null) {
            pending = describe(intent)
            // Copies from a process that ended; nothing can still be reading them.
            io.execute { shareDir().deleteRecursively() }
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val share = describe(intent) ?: return
        pending = share
        channel?.invokeMethod("arrived", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cameraSweep = CameraSweepChannel(applicationContext).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
            it.attach(this)
        }
        sweepBackground = SweepBackground.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(pending)
                        pending = null
                    }
                    "copy" -> copy(call.argument<String>("uri"), call.argument<String>("name"), result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CameraSweepChannel.REQUEST_CODE) cameraSweep?.onPermissionsResult()
    }

    override fun onDestroy() {
        cameraSweep?.attach(null)
        SweepBackground.detach(sweepBackground)
        super.onDestroy()
    }

    /** What was shared, without reading a byte of it. Null for any other intent. */
    private fun describe(intent: Intent?): Map<String, Any?>? {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return null
        val uris: List<Uri> = if (action == Intent.ACTION_SEND) {
            listOfNotNull(stream(intent))
        } else {
            streams(intent)
        }
        return mapOf(
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "items" to uris.map { item(it) },
        )
    }

    /** One stream's name, size and type — or why they could not be read. */
    private fun item(uri: Uri): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>("uri" to uri.toString())
        try {
            out["mime"] = contentResolver.getType(uri)
            if (uri.scheme == "file") {
                val f = File(uri.path ?: "")
                out["name"] = f.name
                out["size"] = f.length()
            } else {
                contentResolver.query(
                    uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null,
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val s = c.getColumnIndex(OpenableColumns.SIZE)
                        if (n >= 0 && !c.isNull(n)) out["name"] = c.getString(n)
                        if (s >= 0 && !c.isNull(s)) out["size"] = c.getLong(s)
                    }
                }
            }
            if (out["name"] == null) out["name"] = uri.lastPathSegment
        } catch (e: Exception) {
            out["error"] = reason(e)
        }
        return out
    }

    /** One accepted stream copied into the cache under its own name, off the
     *  main thread — a recording can be gigabytes. */
    private fun copy(uri: String?, name: String?, result: MethodChannel.Result) {
        if (uri == null) {
            result.error("unreadable", "no stream was named", null)
            return
        }
        val slot = copies++
        io.execute {
            try {
                val dir = File(shareDir(), "$slot").apply { mkdirs() }
                val safe = (name ?: "shared").replace('/', '_').ifBlank { "shared" }
                val target = File(dir, safe)
                val input = contentResolver.openInputStream(Uri.parse(uri))
                    ?: throw java.io.FileNotFoundException("the app that shared it gave nothing to read")
                input.use { i -> target.outputStream().use { o -> i.copyTo(o) } }
                main.post { result.success(mapOf("path" to target.path, "size" to target.length())) }
            } catch (e: Exception) {
                main.post { result.error("unreadable", reason(e), null) }
            }
        }
    }

    private fun shareDir() = File(cacheDir, "share")

    private fun reason(e: Exception) = e.localizedMessage ?: e.javaClass.simpleName

    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun streams(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }) ?: emptyList()

    companion object {
        const val CHANNEL = "xp.noteletter/share"
    }
}
