package xp.NoteLetter.Flutter.camerasweep

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.BreakIterator
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * F-125 S5a: the camera-roll sweep's library bridge on Android — the same
 * channel, methods and wire shapes as iOS's `CameraSweepChannel.swift`, so the
 * Dart sweep (`lib/services/camera_sweep_bridge.dart` and everything above it)
 * runs unchanged. The rules are features/camera-roll-sweep.md's Android
 * paragraphs (5.26.0, ADR-180):
 *
 * - §1 **only full access runs**: every library method answers the error code
 *   `limited` or `denied` instead, as iOS's does;
 * - §2 the pre-filter is ML Kit's on-device recognizer, its model BUNDLED (the
 *   Play-services one downloads), on a decode ≤1024 px, at 80 characters; a
 *   row in a `Screenshots` directory is a candidate unread; a row whose file
 *   will not open is deferred, never "no text";
 * - §4 the key is [AssetIdentity]'s;
 * - §5 the upload bytes are a RENDERED JPEG, never the original file;
 * - §8 MediaStore records no bursts, so every image is representative.
 *
 * S5b added the uploads (`stageUpload` … `acknowledgeUploads`, [SweepUploader]).
 * The background pass is the step after; until it lands,
 * `CameraSweepBridge.isAvailable` keeps the Dart host off on Android.
 */
class CameraSweepChannel(private val context: Context) : EventChannel.StreamHandler {
    companion object {
        const val NAME = "xp.noteletter/camera_sweep"
        const val CHANGES = "xp.noteletter/camera_sweep/changes"
        const val PREFILTER_VERSION = 1
        const val MINIMUM_CHARACTERS = 80
        const val THUMBNAIL_EDGE = 1024
        const val REQUEST_CODE = 0x5EE9

        /** The wire word for an access state: full, partial or none (§1). */
        fun access(context: Context): String {
            fun granted(p: String) =
                context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
            return if (Build.VERSION.SDK_INT >= 33) {
                when {
                    granted(Manifest.permission.READ_MEDIA_IMAGES) -> "granted"
                    Build.VERSION.SDK_INT >= 34 &&
                        granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> "limited"
                    else -> "denied"
                }
            } else {
                if (granted(Manifest.permission.READ_EXTERNAL_STORAGE)) "granted" else "denied"
            }
        }

        /** The error code a library method answers instead of running. */
        fun refusal(access: String): String? = if (access == "granted") null else access

        /** Grapheme clusters, as Swift's `String.count` counts them. */
        fun characters(text: String): Int {
            val it = BreakIterator.getCharacterInstance()
            it.setText(text)
            var n = 0
            while (it.next() != BreakIterator.DONE) n++
            return n
        }
    }

    private var activity: Activity? = null
    private var pendingRequest: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var observer: ContentObserver? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler(::handle)
        EventChannel(messenger, CHANGES).setStreamHandler(this)
        EventChannel(messenger, SweepUploader.EVENTS).setStreamHandler(SweepUploader.events())
    }

    fun attach(activity: Activity?) {
        this.activity = activity
    }

    /** MainActivity's `onRequestPermissionsResult`, for [REQUEST_CODE]. */
    fun onPermissionsResult() {
        pendingRequest?.success(access(context))
        pendingRequest = null
    }

    private val images: Uri
        get() = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "constants" -> result.success(mapOf(
                "schemeVersion" to AssetIdentity.SCHEME_VERSION,
                "prefilterVersion" to PREFILTER_VERSION,
                "minimumCharacters" to MINIMUM_CHARACTERS,
            ))
            "access" -> result.success(access(context))
            "requestAccess" -> requestAccess(result)
            "openSettings" -> {
                // Both refusals carry this action (§1): this app's own page.
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", context.packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(runCatching { context.startActivity(intent) }.isSuccess)
            }
            // S5b: the uploads. They touch no photo, so they answer whatever
            // the library access — an upload handed off before access was
            // revoked still lands, and its result is still recorded.
            "stageUpload", "startUpload", "discardUpload", "uploadsInFlight",
            "finishedUploads", "acknowledgeUploads" -> {
                @Suppress("UNCHECKED_CAST")
                upload(call.method, (call.arguments as? Map<String, Any?>) ?: emptyMap(), result)
            }
            "fetchImages", "identify", "examine", "renderedJpeg", "thumbnail",
            "changeToken", "changesSince" -> {
                val a = access(context)
                refusal(a)?.let { return result.error(it, "photo library access is $a", null) }
                @Suppress("UNCHECKED_CAST")
                val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                when (call.method) {
                    "fetchImages" -> fetchImages(args, result)
                    "identify" -> identify(args, result)
                    "examine" -> examine(args, result)
                    "thumbnail" -> thumbnail(args, result)
                    "changeToken" -> io.execute {
                        val token = runCatching { LibraryHistory.token(context) }.getOrNull()
                        main.post { result.success(token) }
                    }
                    "changesSince" -> changesSince(args, result)
                    else -> renderedJpeg(args, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── S5b uploads ────────────────────────────────────────────────────────

    private fun upload(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        fun string(key: String): String? = (args[key] as? String)?.takeIf { it.isNotEmpty() }
            ?: run { result.error("badArgs", "$key is required", null); null }
        fun fail(e: Exception) = result.error("uploadFailed", e.message ?: e.javaClass.simpleName, null)
        when (method) {
            "stageUpload" -> {
                val path = string("path") ?: return
                try { result.success(SweepUploader.stage(context, path)) } catch (e: Exception) { fail(e) }
            }
            "startUpload" -> {
                val id = string("uploadId") ?: return
                val url = string("url") ?: return
                val mime = string("mimeType") ?: return
                val local = string("localIdentifier") ?: return
                val key = string("assetKey") ?: return
                try {
                    SweepUploader.start(context, id, url, mime, local, key)
                    result.success(null)
                } catch (e: Exception) { fail(e) }
            }
            "discardUpload" -> {
                val id = string("uploadId") ?: return
                SweepUploader.discard(context, id)
                result.success(null)
            }
            "uploadsInFlight" -> io.execute {
                val answer = runCatching { SweepUploader.inFlight(context) }
                main.post {
                    answer.fold({ result.success(it) },
                        { result.error("uploadFailed", it.message ?: it.javaClass.simpleName, null) })
                }
            }
            "finishedUploads" -> result.success(SweepUploader.finished(context))
            else -> {
                @Suppress("UNCHECKED_CAST")
                SweepUploader.acknowledge(context, (args["uploadIds"] as? List<String>) ?: emptyList())
                result.success(null)
            }
        }
    }

    // ── §1 access ──────────────────────────────────────────────────────────

    private fun requestAccess(result: MethodChannel.Result) {
        val a = activity
        if (a == null || pendingRequest != null) {
            result.success(access(context))
            return
        }
        val permissions = when {
            // Both, as Android 14 asks: a reader who picks "limited" is then
            // told so (§1), rather than read as "no access".
            Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        pendingRequest = result
        a.requestPermissions(permissions, REQUEST_CODE)
    }

    // ── §7 enumeration ─────────────────────────────────────────────────────

    private fun columns(): Array<String> = buildList {
        add(MediaStore.Images.Media._ID)
        add(MediaStore.Images.Media.DATE_TAKEN)
        add(MediaStore.Images.Media.WIDTH)
        add(MediaStore.Images.Media.HEIGHT)
        add(MediaStore.Images.Media.DISPLAY_NAME)
        add(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
        if (Build.VERSION.SDK_INT >= 29) add(MediaStore.Images.Media.RELATIVE_PATH)
    }.toTypedArray()

    /**
     * Still images, newest first, `since` inclusive and `until` exclusive, as
     * listings with no key (5.40.0). With `localIdentifiers`, only those rows
     * (a pass from a change token), in the same window and order.
     */
    private fun fetchImages(args: Map<String, Any?>, result: MethodChannel.Result) {
        val offset = (args["offset"] as? Number)?.toInt() ?: 0
        val limit = (args["limit"] as? Number)?.toInt() ?: 0
        if (offset < 0 || limit <= 0) {
            return result.error("badArgs", "offset must be >= 0 and limit > 0", null)
        }
        val since = (args["sinceMs"] as? Number)?.toLong()
        val until = (args["untilMs"] as? Number)?.toLong()
        val ids = (args["localIdentifiers"] as? List<*>)?.mapNotNull { (it as? String)?.toLongOrNull() }
        io.execute {
            val where = mutableListOf<String>()
            val params = mutableListOf<String>()
            since?.let { where += "${MediaStore.Images.Media.DATE_TAKEN} >= ?"; params += "$it" }
            until?.let { where += "${MediaStore.Images.Media.DATE_TAKEN} < ?"; params += "$it" }
            try {
                val answer = if (ids == null) {
                    pageOfLibrary(where, params, offset, limit)
                } else {
                    pageOfRows(ids, where, params, offset, limit)
                }
                main.post { result.success(answer) }
            } catch (e: Exception) {
                main.post { result.error("queryFailed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private val newestFirst =
        "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media._ID} DESC"

    private fun pageOfLibrary(where: List<String>, params: List<String>, offset: Int, limit: Int): Map<String, Any?> =
        // Pending and trashed rows are excluded by MediaStore by default.
        context.contentResolver.query(
            images, columns(),
            where.joinToString(" AND ").ifEmpty { null },
            params.toTypedArray().ifEmpty { null },
            newestFirst,
        ).use { c ->
            val total = c?.count ?: 0
            val assets = mutableListOf<Map<String, Any?>>()
            if (c != null && offset < total && c.moveToPosition(offset)) {
                do {
                    assets += listing(c)
                } while (assets.size < limit && c.moveToNext())
            }
            mapOf("total" to total, "assets" to assets)
        }

    /**
     * The named rows, read in chunks (a query's `?` arguments are bounded) and
     * put back in [newestFirst]'s order: DATE_TAKEN descending with an undated
     * row last, as SQLite sorts a NULL, then `_ID` descending.
     */
    private fun pageOfRows(
        ids: List<Long>, where: List<String>, params: List<String>, offset: Int, limit: Int,
    ): Map<String, Any?> {
        val rows = mutableListOf<Map<String, Any?>>()
        for (chunk in ids.distinct().chunked(500)) {
            val inIds = "${MediaStore.Images.Media._ID} IN (${chunk.joinToString(",") { "?" }})"
            context.contentResolver.query(
                images, columns(),
                (where + inIds).joinToString(" AND "),
                (params + chunk.map { "$it" }).toTypedArray(),
                null,
            )?.use { c -> while (c.moveToNext()) rows += listing(c) }
        }
        val sorted = rows.sortedWith(
            compareByDescending<Map<String, Any?>> { it["creationSeconds"] as Double? ?: Double.NEGATIVE_INFINITY }
                .thenByDescending { (it["localIdentifier"] as String).toLong() },
        )
        return mapOf("total" to sorted.size, "assets" to sorted.drop(offset).take(limit))
    }

    /** One row, as iOS's `listing`: what deciding whether to look at it needs. */
    private fun listing(c: android.database.Cursor): Map<String, Any?> {
        val r = RowMetadata(c)
        return mapOf(
            "localIdentifier" to "${r.id}",
            "creationSeconds" to r.taken?.let { it / 1000.0 },
            "pixelWidth" to r.width,
            "pixelHeight" to r.height,
            "isScreenshot" to AssetIdentity.isScreenshot(r.relative, r.bucket),
            "isRepresentative" to true,
        )
    }

    /** One row, as iOS's `describe`: the listing, the key and the name. */
    private fun describe(c: android.database.Cursor): Map<String, Any?> {
        val r = RowMetadata(c)
        return listing(c) + mapOf(
            "assetKey" to r.key,
            "originalFilename" to r.name,
        )
    }

    /** A row's columns, read once; metadata only, no pixel read. */
    private class RowMetadata(c: android.database.Cursor) {
        private fun str(c: android.database.Cursor, col: String) =
            c.getColumnIndex(col).takeIf { it >= 0 && !c.isNull(it) }?.let(c::getString)
        private fun long(c: android.database.Cursor, col: String) =
            c.getColumnIndex(col).takeIf { it >= 0 && !c.isNull(it) }?.let(c::getLong)

        val id = long(c, MediaStore.Images.Media._ID) ?: 0L
        val taken = long(c, MediaStore.Images.Media.DATE_TAKEN)
        val width = long(c, MediaStore.Images.Media.WIDTH)?.toInt() ?: 0
        val height = long(c, MediaStore.Images.Media.HEIGHT)?.toInt() ?: 0
        val name = str(c, MediaStore.Images.Media.DISPLAY_NAME)
        val relative = if (Build.VERSION.SDK_INT >= 29) str(c, MediaStore.Images.Media.RELATIVE_PATH) else null
        val bucket = str(c, MediaStore.Images.Media.BUCKET_DISPLAY_NAME)

        /** The INV-14 key: derived only when asked (5.40.0). */
        val key: String get() = AssetIdentity.assetKey(taken, width, height, name)
    }

    /** A candidate's key and name, with the rest of its listing (5.40.0). */
    private fun identify(args: Map<String, Any?>, result: MethodChannel.Result) {
        val id = (args["localIdentifier"] as? String)?.toLongOrNull()
            ?: return result.error("badArgs", "localIdentifier is required", null)
        io.execute {
            val found = runCatching {
                context.contentResolver.query(ContentUris.withAppendedId(images, id), columns(), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) describe(c) else null }
            }.getOrNull()
            main.post {
                if (found == null) result.error("notFound", "no asset $id", null) else result.success(found)
            }
        }
    }

    /** What changed since a token, or null when only a walk will do. */
    private fun changesSince(args: Map<String, Any?>, result: MethodChannel.Result) {
        val token = (args["token"] as? String)?.takeIf { it.isNotEmpty() }
            ?: return result.error("badArgs", "token is required", null)
        io.execute {
            val changes = runCatching { LibraryHistory.changes(context, token) }.getOrNull()
            main.post { result.success(changes) }
        }
    }

    // ── one row ────────────────────────────────────────────────────────────

    private class Row(val uri: Uri, val screenshot: Boolean, val orientation: Int, private val metadata: RowMetadata) {
        /** Only the rendered file's name needs it. */
        val key: String get() = metadata.key
    }

    private fun row(args: Map<String, Any?>, result: MethodChannel.Result): Row? {
        val id = (args["localIdentifier"] as? String)?.toLongOrNull()
        if (id == null) {
            result.error("badArgs", "localIdentifier is required", null)
            return null
        }
        val uri = ContentUris.withAppendedId(images, id)
        val cols = columns() + MediaStore.Images.Media.ORIENTATION
        val found = runCatching {
            context.contentResolver.query(uri, cols, null, null, null)?.use { c ->
                if (!c.moveToFirst()) return@use null
                val m = RowMetadata(c)
                val o = c.getColumnIndex(MediaStore.Images.Media.ORIENTATION)
                Row(uri, AssetIdentity.isScreenshot(m.relative, m.bucket),
                    if (o >= 0 && !c.isNull(o)) c.getInt(o) else 0, m)
            }
        }.getOrNull()
        if (found == null) result.error("notFound", "no asset $id", null)
        return found
    }

    /** The bitmap at most [edge] px on its long side, upright; null if undecodable. */
    private fun decode(uri: Uri, edge: Int?, orientation: Int): Bitmap? {
        val bitmap = if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { d, info, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val long = max(info.size.width, info.size.height)
                if (edge != null && long > edge) {
                    val s = edge.toDouble() / long
                    d.setTargetSize(max(1, (info.size.width * s).toInt()), max(1, (info.size.height * s).toInt()))
                }
            }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            val long = max(bounds.outWidth, bounds.outHeight)
            if (edge != null) while (long / (sample * 2) >= edge) sample *= 2
            val decoded = context.contentResolver.openInputStream(uri)!!.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            } ?: return null
            val dl = max(decoded.width, decoded.height)
            if (edge != null && dl > edge) {
                val s = edge.toDouble() / dl
                Bitmap.createScaledBitmap(decoded, max(1, (decoded.width * s).toInt()),
                    max(1, (decoded.height * s).toInt()), true)
            } else decoded
        } ?: return null
        // ImageDecoder applies EXIF rotation itself; BitmapFactory does not.
        if (Build.VERSION.SDK_INT >= 28 || orientation == 0) return bitmap
        val m = Matrix().apply { postRotate(orientation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    // ── §2 the pre-filter ──────────────────────────────────────────────────

    private fun examine(args: Map<String, Any?>, result: MethodChannel.Result) {
        val row = row(args, result) ?: return
        fun answer(verdict: String, chars: Int?, w: Int?, h: Int?) {
            main.post {
                result.success(mapOf("verdict" to verdict, "characters" to chars,
                    "thumbnailWidth" to w, "thumbnailHeight" to h, "prefilterVersion" to PREFILTER_VERSION))
            }
        }
        if (row.screenshot) return answer("candidate", null, null, null)
        io.execute {
            val bitmap = try {
                decode(row.uri, THUMBNAIL_EDGE, row.orientation)
            } catch (e: java.io.IOException) {
                // Undecodable bytes are "no text", as iOS's missing cgImage is;
                // a file that would not OPEN is deferred, never "no text".
                if (Build.VERSION.SDK_INT >= 28 && e is ImageDecoder.DecodeException) null
                else return@execute answer("notLocallyAvailable", null, null, null)
            } catch (e: SecurityException) {
                return@execute answer("notLocallyAvailable", null, null, null)
            } catch (e: Exception) {
                null
            }
            if (bitmap == null) return@execute answer("noText", null, null, null)
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    // Swift joins the observations with a space and counts
                    // characters; the lines here are its observations.
                    val joined = text.textBlocks.flatMap { it.lines }.joinToString(" ") { it.text }
                    val n = characters(joined)
                    answer(if (n >= MINIMUM_CHARACTERS) "candidate" else "noText", n, bitmap.width, bitmap.height)
                }
                .addOnFailureListener {
                    // Swift's recognizer failure reads as "" too.
                    answer("noText", 0, bitmap.width, bitmap.height)
                }
        }
    }

    // ── §5 the upload bytes ────────────────────────────────────────────────

    private fun renderedJpeg(args: Map<String, Any?>, result: MethodChannel.Result) {
        val row = row(args, result) ?: return
        io.execute {
            try {
                // A photo that will not open or decode renders nothing: null,
                // which the sweep records as deferred, as iOS's nil is.
                val bitmap = try {
                    decode(row.uri, null, row.orientation)
                } catch (e: java.io.IOException) {
                    null
                } catch (e: SecurityException) {
                    null
                }
                if (bitmap == null) {
                    main.post { result.success(null) }
                    return@execute
                }
                val dir = File(context.cacheDir, "camera-sweep").apply { mkdirs() }
                val file = File(dir, row.key.replace(':', '-') + ".jpg")
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                main.post { result.success(mapOf("path" to file.path, "bytes" to file.length().toInt())) }
            } catch (e: Exception) {
                main.post { result.error("writeFailed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    /** A review card's picture, as JPEG bytes; null when it cannot be drawn. */
    private fun thumbnail(args: Map<String, Any?>, result: MethodChannel.Result) {
        val row = row(args, result) ?: return
        val width = (args["width"] as? Number)?.toInt() ?: 216
        val height = (args["height"] as? Number)?.toInt() ?: 280
        io.execute {
            val bytes = runCatching {
                val bitmap = if (Build.VERSION.SDK_INT >= 29) {
                    context.contentResolver.loadThumbnail(row.uri, Size(width, height), null)
                } else {
                    decode(row.uri, max(width, height), row.orientation)
                } ?: return@runCatching null
                ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
            }.getOrNull()
            main.post { result.success(bytes) }
        }
    }

    // ── S3's change events ─────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val a = access(context)
        refusal(a)?.let { return events.error(it, "photo library access is $a", null) }
        if (observer == null) {
            observer = object : ContentObserver(main) {
                override fun onChange(selfChange: Boolean) {
                    sink?.success(null)
                }
            }.also { context.contentResolver.registerContentObserver(images, true, it) }
        }
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        observer?.let { context.contentResolver.unregisterContentObserver(it) }
        observer = null
        sink = null
    }
}
