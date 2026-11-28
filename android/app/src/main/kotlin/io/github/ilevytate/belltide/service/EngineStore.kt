package io.github.ilevytate.belltide.service

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.edit
import io.github.ilevytate.belltide.engine.EngineJson
import io.github.ilevytate.belltide.engine.RunningTimer

/** Audio and haptic settings the service applies to every chime. */
data class EngineSettings(
    /**
     * "alarm" follows the alarm volume on the phone speaker and the media volume
     * through headphones; "media" always follows the media volume.
     */
    val audioStream: String = STREAM_ALARM,
    val vibrate: Boolean = false,
    /** In-app chime volume from 0 to 1, applied on top of the stream's own volume. */
    val level: Float = 1f,
    /** Briefly lower other apps' audio while a chime plays. */
    val duckOthers: Boolean = true,
    /** On vibrate or silent, buzz instead of playing the sound. */
    val vibrateWhenSilenced: Boolean = false,
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
            level = prefs.getFloat(KEY_LEVEL, 1f),
            duckOthers = prefs.getBoolean(KEY_DUCK, true),
            vibrateWhenSilenced = prefs.getBoolean(KEY_VIBRATE_WHEN_SILENCED, false),
        )
        set(value) {
            prefs.edit {
                putString(KEY_STREAM, value.audioStream)
                putBoolean(KEY_VIBRATE, value.vibrate)
                putFloat(KEY_LEVEL, value.level)
                putBoolean(KEY_DUCK, value.duckOthers)
                putBoolean(KEY_VIBRATE_WHEN_SILENCED, value.vibrateWhenSilenced)
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
        const val KEY_LEVEL = "chime_level"
        const val KEY_DUCK = "duck_others"
        const val KEY_VIBRATE_WHEN_SILENCED = "vibrate_when_silenced"
    }
}
