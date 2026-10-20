package xp.NoteLetter.Flutter.camerasweep

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * F-125 S5c: the camera-roll sweep's background pass on Android — iOS's
 * `SweepBackgroundTask` (a `BGProcessingTask`) transposed onto WorkManager,
 * on the same channel (`lib/services/sweep_background.dart`):
 *
 * - `setScheduled(on)` asks for periodic work, or withdraws it, under iOS's
 *   own conditions: network, external power, the first run an hour out;
 * - `attach` says a host is listening on this engine.
 *
 * When the work runs, the pass is the HOST's own (`CameraSweepHost
 * .backgroundRun`), as on iOS: one ledger, one tray, one service. With the app
 * alive, the app's engine runs it. With the app gone, the job starts an engine
 * on `sweepBackgroundMain` (lib/main.dart), which builds the host and nothing
 * else, and stops it when the pass ends. The job finishes when the pass ENDS
 * (features §5 rule 4); when the system takes the time back, the host is told
 * `expire` and given a moment to stop at a safe point.
 */
object SweepBackground {
    const val CHANNEL = "xp.noteletter/camera_sweep/background"
    const val WORK = "xp.NoteLetter.Flutter.camerasweep.refresh"

    private val main by lazy { Handler(Looper.getMainLooper()) }

    /** The channel of the engine whose host attached last. Main thread only. */
    internal var attached: MethodChannel? = null
        private set
    private val waiting = mutableListOf<(MethodChannel) -> Unit>()

    fun register(context: Context, messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    attached = channel
                    val ready = waiting.toList()
                    waiting.clear()
                    ready.forEach { it(channel) }
                    result.success(null)
                }
                "setScheduled" -> result.success(schedule(context, call.argument<Boolean>("on") == true))
                else -> result.notImplemented()
            }
        }
        return channel
    }

    /** This engine is going away; its host can answer nothing more. */
    fun detach(channel: MethodChannel?) {
        if (channel != null && attached === channel) attached = null
    }

    /** Main thread: [use] gets the attached channel now, or once one attaches. */
    internal fun whenAttached(use: (MethodChannel) -> Unit) {
        attached?.let(use) ?: waiting.add(use)
    }

    internal fun forget(use: (MethodChannel) -> Unit) {
        waiting.remove(use)
    }

    fun schedule(context: Context, on: Boolean): Map<String, Any?> = try {
        val work = WorkManager.getInstance(context)
        if (on) {
            val request = PeriodicWorkRequestBuilder<SweepBackgroundWorker>(1, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .setRequiresCharging(true)
                    .build())
                .setInitialDelay(1, TimeUnit.HOURS)
                .build()
            // KEEP: asking again while scheduled leaves the next run where it is.
            work.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
            mapOf("scheduled" to true, "error" to null)
        } else {
            work.cancelUniqueWork(WORK)
            mapOf("scheduled" to false, "error" to null)
        }
    } catch (e: Exception) {
        mapOf("scheduled" to false, "error" to (e.message ?: e.javaClass.simpleName))
    }

    internal fun post(block: () -> Unit) {
        main.post(block)
    }
}

class SweepBackgroundWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private var engine: FlutterEngine? = null
    private var engineChannel: MethodChannel? = null

    override suspend fun doWork(): Result {
        try {
            val channel = withTimeout(ATTACH_TIMEOUT_MS) { channel() }
            val answer = run(channel)
            android.util.Log.i("NoteLetter", "camera sweep background pass: $answer")
            return Result.success()
        } catch (e: TimeoutCancellationException) {
            // No host attached in time (signed out, a boot that failed): the
            // next period tries again.
            android.util.Log.w("NoteLetter", "camera sweep background: no host attached")
            return Result.success()
        } catch (e: CancellationException) {
            // The system took the time back: stop at the next safe point.
            withContext(NonCancellable + Dispatchers.Main) {
                SweepBackground.attached?.invokeMethod("expire", null)
                delay(EXPIRE_GRACE_MS)
            }
            throw e
        } catch (e: Exception) {
            android.util.Log.e("NoteLetter", "camera sweep background pass failed", e)
            return Result.success() // the next period tries again; no retry storm
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                SweepBackground.detach(engineChannel)
                engine?.destroy()
                engine = null
            }
        }
    }

    /** The app's engine if its host is attached; otherwise one started for the pass. */
    private suspend fun channel(): MethodChannel = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { cont ->
            val use: (MethodChannel) -> Unit = { if (cont.isActive) cont.resume(it) }
            cont.invokeOnCancellation { SweepBackground.post { SweepBackground.forget(use) } }
            SweepBackground.whenAttached(use)
            if (SweepBackground.attached == null && engine == null) startEngine()
        }
    }

    private fun startEngine() {
        val context = applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        val e = FlutterEngine(context)
        val messenger = e.dartExecutor.binaryMessenger
        CameraSweepChannel(context).register(messenger)
        engineChannel = SweepBackground.register(context, messenger)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "sweepBackgroundMain"))
        engine = e
    }

    /** One pass, answered when it ENDS. */
    private suspend fun run(channel: MethodChannel): Any? = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { cont ->
            channel.invokeMethod("run", null, object : MethodChannel.Result {
                override fun success(result: Any?) { if (cont.isActive) cont.resume(result) }
                override fun error(code: String, message: String?, details: Any?) {
                    if (cont.isActive) cont.resume("error $code: $message")
                }
                override fun notImplemented() { if (cont.isActive) cont.resume("not implemented") }
            })
        }
    }

    companion object {
        /** How long a started engine has to boot and attach its host. */
        const val ATTACH_TIMEOUT_MS = 60_000L

        /** iOS's: the moment a stopped pass gets to reach a safe point. */
        const val EXPIRE_GRACE_MS = 2_000L
    }
}
