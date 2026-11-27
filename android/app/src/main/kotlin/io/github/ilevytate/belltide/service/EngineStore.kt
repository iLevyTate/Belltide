package io.github.ilevytate.belltide.service

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.edit
import io.github.ilevytate.belltide.engine.EngineJson
import io.github.ilevytate.belltide.engine.RunningTimer

/** Audio and haptic settings the service applies to every chime. */
data class EngineSettings(
    /** "alarm" plays on the alarm volume (and the speaker); "media" follows media volume. */
    val audioStream: String = STREAM_ALARM,
    val vibrate: Boolean = false,
) {
    companion object {
        const val STREAM_ALARM = "alarm"
        const val STREAM_MEDIA = "media"
    }
}

/**
 * Persists running timers and engine settings in SharedPreferences so the service can
 * pick up where it left off if Android kills and restarts it. Timer times are on the
 * elapsedRealtime clock, which resets on reboot, so state from an earlier boot is dropped.
 */
class EngineStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveTimers(timers: List<RunningTimer>) {
        prefs.edit {
            if (timers.isEmpty()) {
                remove(KEY_TIMERS)
            } else {
                putString(KEY_TIMERS, EngineJson.runningToJson(timers))
                putInt(KEY_BOOT_COUNT, bootCount())
                putLong(KEY_SAVED_AT, SystemClock.elapsedRealtime())
            }
        }
    }

    fun loadTimers(): List<RunningTimer> {
        val json = prefs.getString(KEY_TIMERS, null) ?: return emptyList()
        val sameBoot = prefs.getInt(KEY_BOOT_COUNT, -1) == bootCount() &&
            prefs.getLong(KEY_SAVED_AT, Long.MAX_VALUE) <= SystemClock.elapsedRealtime()
        if (!sameBoot) {
            prefs.edit { remove(KEY_TIMERS) }
            return emptyList()
        }
        return runCatching { EngineJson.parseRunning(json) }.getOrDefault(emptyList())
    }

    fun hasTimers(): Boolean = loadTimers().isNotEmpty()

    fun removeTimer(id: String) {
        saveTimers(loadTimers().filter { it.config.id != id })
    }

    var settings: EngineSettings
        get() = EngineSettings(
            audioStream = prefs.getString(KEY_STREAM, EngineSettings.STREAM_ALARM)
                ?: EngineSettings.STREAM_ALARM,
            vibrate = prefs.getBoolean(KEY_VIBRATE, false),
        )
        set(value) {
            prefs.edit {
                putString(KEY_STREAM, value.audioStream)
                putBoolean(KEY_VIBRATE, value.vibrate)
            }
        }

    private fun bootCount(): Int =
        Settings.Global.getInt(appContext.contentResolver, Settings.Global.BOOT_COUNT, -1)

    private companion object {
        const val PREFS = "belltide_engine"
        const val KEY_TIMERS = "running_timers"
        const val KEY_BOOT_COUNT = "boot_count"
        const val KEY_SAVED_AT = "saved_at_elapsed"
        const val KEY_STREAM = "audio_stream"
        const val KEY_VIBRATE = "vibrate"
    }
}
