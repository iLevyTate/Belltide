package io.github.ilevytate.belltide.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.github.ilevytate.belltide.clickup.ClickUpSync
import io.github.ilevytate.belltide.engine.EngineEffect
import io.github.ilevytate.belltide.engine.EngineJson
import io.github.ilevytate.belltide.engine.TimerEngine

/**
 * Foreground service that owns the timer engine.
 *
 * Reliability with the screen off comes from three things: the service runs in the
 * foreground (so Android keeps the process and honours its wake lock in Doze), a
 * partial wake lock is held while any timer is actively running (so the CPU stays
 * awake for the next chime), and all timing is computed from
 * SystemClock.elapsedRealtime, so a late wake-up never shifts later chimes.
 *
 * Running timers are persisted on every state change. If Android kills the service,
 * it is restarted (START_STICKY) or restored the next time the app opens, and the
 * timers continue on their original schedule.
 */
class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = Runnable { onTick() }
    private val engine = TimerEngine()
    private lateinit var store: EngineStore
    private lateinit var notifications: TimerNotifications
    private lateinit var wakeLock: PowerManager.WakeLock
    private var lastStartId = 0

    /** When the pending tick was due, for logging how late wake-ups are. */
    private var tickDueAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        store = EngineStore(this)
        notifications = TimerNotifications(this)
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Belltide:timers")
            .apply { setReferenceCounted(false) }
        // Timers recovered from an earlier run continue silently from where they are now.
        logSegments(engine.restore(store.loadTimers(), now()))
        EngineHub.snapshotProvider = { EngineJson.snapshotsToJson(engine.snapshots(now())) }
        // Retry time entries that couldn't be sent earlier.
        ClickUpSync.get(this).flush()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        // Satisfies the startForegroundService contract before doing anything else.
        if (!enterForeground()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val now = now()
        val id = intent?.getStringExtra(EXTRA_TIMER_ID)
        val effects = mutableListOf<EngineEffect>()
        when (intent?.action) {
            ACTION_START -> intent.getStringExtra(EXTRA_CONFIG)?.let { json ->
                runCatching { EngineJson.parseConfig(json) }
                    .onSuccess { effects += engine.start(it, now) }
                    .onFailure { Log.w(TAG, "Ignoring invalid timer config", it) }
            }
            ACTION_PAUSE -> id?.let { effects += engine.pause(it, now) }
            ACTION_RESUME -> id?.let { effects += engine.resume(it, now) }
            ACTION_SKIP -> id?.let { effects += engine.skip(it, now) }
            ACTION_STOP -> id?.let { effects += engine.stop(it, now) }
            ACTION_PAUSE_ALL -> effects += engine.pauseAll(now)
            ACTION_RESUME_ALL -> effects += engine.resumeAll(now)
            ACTION_STOP_ALL -> effects += engine.stopAll(now)
            else -> Unit // ACTION_RESTORE or a sticky restart: state was loaded in onCreate.
        }
        sync(effects, persist = true)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        releaseWakeLock()
        EngineHub.snapshotProvider = null
        EngineHub.publish(EngineHub.EMPTY_STATE)
        super.onDestroy()
    }

    private fun onTick() {
        val now = now()
        // `adb logcat -s BelltideTimerService` shows timing while the screen is off.
        Log.d(TAG, "tick ${now - tickDueAt} ms after due")
        val effects = engine.tick(now)
        if (effects.isEmpty()) {
            // Woke a little early; wait for the boundary.
            schedule()
            return
        }
        sync(effects, persist = effects.any { it is EngineEffect.Finished })
    }

    /** Queues finished stretches of running time for timers linked to a ClickUp task. */
    private fun logSegments(effects: List<EngineEffect>) {
        val segments = effects.filterIsInstance<EngineEffect.SegmentEnded>()
        if (segments.isEmpty()) return
        val clickUp = ClickUpSync.get(this)
        // Engine times are elapsedRealtime; ClickUp wants wall-clock milliseconds.
        val wallOffset = System.currentTimeMillis() - now()
        segments.forEach { s ->
            clickUp.recordSegment(s.config, s.startMs + wallOffset, s.endMs - s.startMs)
        }
    }

    /** Plays chimes, then pushes the new state to storage, the UI and the notification. */
    private fun sync(effects: List<EngineEffect>, persist: Boolean) {
        val player = ChimePlayer.get(this)
        effects.filterIsInstance<EngineEffect.Play>()
            .map { it.sound }
            .distinct()
            .forEach(player::playChime)
        logSegments(effects)

        if (persist || effects.any { it is EngineEffect.SegmentEnded }) store.saveTimers(engine.all)
        val now = now()
        val snapshots = engine.snapshots(now)
        val finished = effects.filterIsInstance<EngineEffect.Finished>().map { it.timerId }
        EngineHub.publish(EngineJson.snapshotsToJson(snapshots, finished))

        if (engine.isEmpty) {
            shutDown()
            return
        }
        notifications.update(snapshots)
        schedule()
    }

    private fun schedule() {
        handler.removeCallbacks(tickRunnable)
        val next = engine.nextWakeAt()
        if (next == null) {
            // Everything is paused: no chimes are due, so let the CPU sleep.
            releaseWakeLock()
            return
        }
        val delay = (next - now()).coerceAtLeast(0)
        tickDueAt = next
        wakeLock.acquire(delay + WAKE_LOCK_MARGIN_MS)
        handler.postDelayed(tickRunnable, delay)
    }

    private fun enterForeground(): Boolean = try {
        val notification = notifications.build(engine.snapshots(now()))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this, TimerNotifications.NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(TimerNotifications.NOTIFICATION_ID, notification)
        }
        true
    } catch (e: Exception) {
        // Android 12+ refuses foreground starts from the background in some cases
        // (for example a sticky restart). State stays persisted and is restored the
        // next time the app opens.
        Log.w(TAG, "Could not enter the foreground", e)
        false
    }

    private fun shutDown() {
        handler.removeCallbacks(tickRunnable)
        releaseWakeLock()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf(lastStartId)
    }

    private fun releaseWakeLock() {
        if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release()
    }

    private fun now(): Long = SystemClock.elapsedRealtime()

    companion object {
        private const val TAG = "BelltideTimerService"
        private const val WAKE_LOCK_MARGIN_MS = 60_000L

        private const val PREFIX = "io.github.ilevytate.belltide.action."
        const val ACTION_START = PREFIX + "START"
        const val ACTION_PAUSE = PREFIX + "PAUSE"
        const val ACTION_RESUME = PREFIX + "RESUME"
        const val ACTION_SKIP = PREFIX + "SKIP"
        const val ACTION_STOP = PREFIX + "STOP"
        const val ACTION_PAUSE_ALL = PREFIX + "PAUSE_ALL"
        const val ACTION_RESUME_ALL = PREFIX + "RESUME_ALL"
        const val ACTION_STOP_ALL = PREFIX + "STOP_ALL"
        const val ACTION_RESTORE = PREFIX + "RESTORE"

        const val EXTRA_CONFIG = "config"
        const val EXTRA_TIMER_ID = "timerId"

        /** True while the service exists in this process. Main thread only. */
        @Volatile
        var running = false
            private set

        fun start(context: Context, configJson: String) {
            val intent = Intent(context, TimerService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_CONFIG, configJson)
            ContextCompat.startForegroundService(context, intent)
        }

        /** Sends a control action from the UI. Call while the app is in the foreground. */
        fun send(context: Context, action: String, timerId: String? = null) {
            val intent = Intent(context, TimerService::class.java).setAction(action)
            if (timerId != null) intent.putExtra(EXTRA_TIMER_ID, timerId)
            when {
                running -> context.startService(intent)
                // Timers were persisted by a service that is gone: restore, then apply.
                EngineStore(context).hasTimers() -> ContextCompat.startForegroundService(context, intent)
            }
        }

        /** Brings back timers that were running when the process died. */
        fun restoreIfNeeded(context: Context) {
            if (running || !EngineStore(context).hasTimers()) return
            val intent = Intent(context, TimerService::class.java).setAction(ACTION_RESTORE)
            ContextCompat.startForegroundService(context, intent)
        }
    }
}
