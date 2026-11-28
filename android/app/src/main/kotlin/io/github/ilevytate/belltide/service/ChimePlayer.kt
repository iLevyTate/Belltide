package io.github.ilevytate.belltide.service

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Plays chimes with a SoundPool, which keeps the short sounds decoded in memory so they
 * start with low latency. One instance per process, used from the main thread only.
 *
 * SoundPool never takes audio focus, so a chime mixes with whatever else is playing
 * (music, a video) instead of stopping it. To stay audible over that, the player can
 * ask other apps to lower their volume for the length of the chime ("ducking").
 *
 * A chime follows the alarm or the media volume, as the user chose, except through
 * headphones or an external speaker, where it always plays as media
 * (see [ChimeMix.streamFor]).
 */
class ChimePlayer private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val store = EngineStore(appContext)
    private val audio = appContext.getSystemService(AudioManager::class.java)
    private val handler = Handler(Looper.getMainLooper())

    private var pool: SoundPool? = null
    private var poolStream: String? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()

    /** Sounds asked for before they finished loading, with the play they are owed. */
    private val pending = mutableMapOf<Int, PendingPlay>()

    /** The stream of the sound the user is trying out, so the next one can replace it. */
    private var previewStream = 0

    private var focusRequest: AudioFocusRequest? = null
    private var focusUntil = 0L
    private val abandonFocus = Runnable { releaseFocus() }

    /** Plays [sound] for a timer, with vibration if the settings ask for it. */
    fun playChime(sound: String) {
        val settings = store.settings
        val output = ChimeMix.forChime(settings, ringerSilenced())
        play(sound, streamNow(audio, settings), output, preview = false)
        if (output.vibrate) vibrate()
    }

    /** Plays [sound] once so the user can hear it while choosing. */
    fun preview(sound: String) {
        val settings = store.settings
        play(sound, streamNow(audio, settings), ChimeMix.forPreview(settings), preview = true)
    }

    /** Loads [sounds] ahead of time so a timer's chimes start without a delay. */
    fun prepare(sounds: Collection<String>) {
        if (sounds.none { it in CHIME_CATALOG }) return
        val p = ensurePool(streamNow(audio, store.settings))
        sounds.forEach { soundId(p, it) }
    }

    /** Applies changed settings: a new stream needs a new pool, and ducking can be turned off. */
    fun onSettingsChanged() {
        val settings = store.settings
        if (poolStream != null && poolStream != streamNow(audio, settings)) release()
        if (!settings.duckOthers) releaseFocus()
    }

    fun release() {
        releaseFocus()
        pool?.release()
        pool = null
        poolStream = null
        soundIds.clear()
        loaded.clear()
        pending.clear()
        previewStream = 0
    }

    private fun play(sound: String, stream: String, output: ChimeOutput, preview: Boolean) {
        val info = CHIME_CATALOG[sound] ?: return
        if (output.gain <= 0f) return
        val p = ensurePool(stream)
        val id = soundId(p, sound) ?: return
        if (preview) {
            // The sound being tried out replaces the one before it.
            if (previewStream != 0) p.stop(previewStream)
            pending.values.removeAll { it.preview }
        }
        if (output.duck && streamAudible(stream)) holdFocus(stream, ChimeMix.duckMs(info.durationMs))
        if (id in loaded) {
            start(p, id, output.gain, preview)
        } else {
            // Sounds load asynchronously; one requested before it is ready plays
            // as soon as it is.
            pending[id] = PendingPlay(output.gain, preview)
        }
    }

    private fun start(p: SoundPool, id: Int, gain: Float, preview: Boolean) {
        val streamId = p.play(id, gain, gain, 1, 0, 1f)
        if (preview) previewStream = streamId
    }

    private fun soundId(p: SoundPool, sound: String): Int? {
        val info = CHIME_CATALOG[sound] ?: return null
        return soundIds.getOrPut(sound) { p.load(appContext, info.resId, 1) }
    }

    private fun ensurePool(stream: String): SoundPool {
        pool?.let { if (poolStream == stream) return it }
        release()
        val p = SoundPool.Builder()
            .setMaxStreams(MAX_STREAMS)
            .setAudioAttributes(attributesFor(stream))
            .build()
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            // SoundPool calls back on the thread that built it: the main thread.
            if (sp !== pool) return@setOnLoadCompleteListener
            if (status != 0) {
                Log.w(TAG, "Could not load sound $sampleId (status $status)")
                pending.remove(sampleId)
                return@setOnLoadCompleteListener
            }
            loaded += sampleId
            pending.remove(sampleId)?.let { start(sp, sampleId, it.gain, it.preview) }
        }
        pool = p
        poolStream = stream
        return p
    }

    /**
     * Asks other apps to lower their audio for [durationMs]. Chimes that overlap share
     * one request, which is given back when the last of them is over. If Android
     * refuses (during a call, for example) the chime simply plays over the other audio.
     */
    private fun holdFocus(stream: String, durationMs: Long) {
        if (focusRequest == null) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributesFor(stream))
                .build()
            val granted = runCatching { audio.requestAudioFocus(request) }
                .getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
            if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "Other audio was not lowered (focus result $granted)")
                return
            }
            focusRequest = request
            focusUntil = 0L
        }
        val until = SystemClock.uptimeMillis() + durationMs
        if (until > focusUntil) {
            focusUntil = until
            handler.removeCallbacks(abandonFocus)
            handler.postAtTime(abandonFocus, until)
        }
    }

    private fun releaseFocus() {
        handler.removeCallbacks(abandonFocus)
        focusRequest?.let { runCatching { audio.abandonAudioFocusRequest(it) } }
        focusRequest = null
        focusUntil = 0L
    }

    /** False when the chime's own volume is at zero: no reason to quieten anything else. */
    private fun streamAudible(stream: String): Boolean = audio.getStreamVolume(streamType(stream)) > 0

    /** True when the phone is on vibrate or silent. */
    private fun ringerSilenced(): Boolean = audio.ringerMode != AudioManager.RINGER_MODE_NORMAL

    private fun vibrate() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Vibrator::class.java)
        } ?: return
        if (!vibrator.hasVibrator()) return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 180, 120, 180), -1)
        // Always an alarm vibration, whichever volume the sound uses: Android drops
        // media vibrations from an app that is not on screen, and a chime has to
        // buzz with the screen off.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
            )
        }
    }

    private class PendingPlay(val gain: Float, val preview: Boolean)

    companion object {
        private const val TAG = "BelltideChimePlayer"
        private const val MAX_STREAMS = 6

        /** The AudioManager stream whose volume a chime follows. */
        fun streamType(stream: String): Int =
            if (stream == EngineSettings.STREAM_MEDIA) AudioManager.STREAM_MUSIC
            else AudioManager.STREAM_ALARM

        /** The volume a chime would play on right now: [EngineSettings.audioStream] or media. */
        fun streamNow(audio: AudioManager, settings: EngineSettings): String =
            ChimeMix.streamFor(settings.audioStream, externalOutput(audio))

        /** True while headphones or an external speaker carry the phone's media audio. */
        fun externalOutput(audio: AudioManager): Boolean = runCatching {
            val outputs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Where media is going now, which is not always the last thing plugged in.
                audio.getAudioDevicesForAttributes(attributesFor(EngineSettings.STREAM_MEDIA))
            } else {
                audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).asList()
            }
            ChimeMix.isExternal(outputs.map { it.type })
        }.getOrDefault(false)

        /**
         * Alarm and media audio both keep playing when the phone is on vibrate or
         * silent; only the ring and notification volumes are muted by the ringer.
         */
        private fun attributesFor(stream: String): AudioAttributes = AudioAttributes.Builder()
            .setUsage(
                if (stream == EngineSettings.STREAM_MEDIA) AudioAttributes.USAGE_MEDIA
                else AudioAttributes.USAGE_ALARM,
            )
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        @Volatile
        private var instance: ChimePlayer? = null

        fun get(context: Context): ChimePlayer =
            instance ?: synchronized(this) {
                instance ?: ChimePlayer(context).also { instance = it }
            }
    }
}
