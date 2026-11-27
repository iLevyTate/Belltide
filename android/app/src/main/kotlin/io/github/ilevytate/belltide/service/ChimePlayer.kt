package io.github.ilevytate.belltide.service

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.github.ilevytate.belltide.R

/**
 * Plays chimes with a SoundPool, which keeps the short sounds decoded in memory so they
 * start with low latency. One instance per process, used from the main thread only.
 */
class ChimePlayer private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val store = EngineStore(appContext)
    private var pool: SoundPool? = null
    private var poolStream: String? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val pending = mutableSetOf<Int>()

    /** Plays [sound] for a timer, with vibration if the user turned it on. */
    fun playChime(sound: String) {
        val settings = store.settings
        play(sound, settings.audioStream)
        if (settings.vibrate) vibrate(settings.audioStream)
    }

    /** Plays [sound] once so the user can hear it while choosing. */
    fun preview(sound: String) {
        play(sound, store.settings.audioStream)
    }

    /** Rebuilds the sound pool if the audio stream setting changed. */
    fun onSettingsChanged() {
        if (poolStream != null && poolStream != store.settings.audioStream) release()
    }

    fun release() {
        pool?.release()
        pool = null
        poolStream = null
        soundIds.clear()
        loaded.clear()
        pending.clear()
    }

    private fun play(sound: String, stream: String) {
        val p = ensurePool(stream)
        val id = soundIds[sound] ?: return
        if (id in loaded) {
            p.play(id, 1f, 1f, 1, 0, 1f)
        } else {
            // Sounds load asynchronously; a chime requested in the first moments
            // after the pool is created plays as soon as it is ready.
            pending += id
        }
    }

    private fun ensurePool(stream: String): SoundPool {
        pool?.let { if (poolStream == stream) return it }
        release()
        val attributes = AudioAttributes.Builder()
            .setUsage(
                if (stream == EngineSettings.STREAM_MEDIA) AudioAttributes.USAGE_MEDIA
                else AudioAttributes.USAGE_ALARM,
            )
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val p = SoundPool.Builder().setMaxStreams(6).setAudioAttributes(attributes).build()
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            if (status != 0) return@setOnLoadCompleteListener
            loaded += sampleId
            if (pending.remove(sampleId)) sp.play(sampleId, 1f, 1f, 1, 0, 1f)
        }
        for ((name, res) in SOUNDS) soundIds[name] = p.load(appContext, res, 1)
        pool = p
        poolStream = stream
        return p
    }

    private fun vibrate(stream: String) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Vibrator::class.java)
        } ?: return
        if (!vibrator.hasVibrator()) return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 180, 120, 180), -1)
        val alarm = stream != EngineSettings.STREAM_MEDIA
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val usage = if (alarm) VibrationAttributes.USAGE_ALARM else VibrationAttributes.USAGE_MEDIA
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(usage))
        } else {
            val usage = if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_MEDIA
            @Suppress("DEPRECATION")
            vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(usage).build())
        }
    }

    companion object {
        /** Sound ids shared with the Flutter side (lib/src/model/chime_sound.dart). */
        val SOUNDS: Map<String, Int> = mapOf(
            "bell" to R.raw.chime_bell,
            "bowl" to R.raw.chime_bowl,
            "chime" to R.raw.chime_chime,
            "double" to R.raw.chime_double,
            "wood" to R.raw.chime_wood,
            "gong" to R.raw.chime_gong,
            "rise" to R.raw.chime_rise,
            "beep" to R.raw.chime_beep,
        )

        @Volatile
        private var instance: ChimePlayer? = null

        fun get(context: Context): ChimePlayer =
            instance ?: synchronized(this) {
                instance ?: ChimePlayer(context).also { instance = it }
            }
    }
}
