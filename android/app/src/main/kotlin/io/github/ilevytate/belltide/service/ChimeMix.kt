package io.github.ilevytate.belltide.service

import android.media.AudioDeviceInfo

/** What one chime does: how loud it plays and whether the phone buzzes. */
data class ChimeOutput(
    /** SoundPool volume from 0 to 1. At 0 the sound is not played at all. */
    val gain: Float,
    val vibrate: Boolean,
    /** Ask other apps to lower their audio while the chime plays. */
    val duck: Boolean,
)

/** Turns the user's settings and the phone's ringer state into a [ChimeOutput]. */
object ChimeMix {
    private const val MIN_DUCK_MS = 400L
    private const val MAX_DUCK_MS = 3_000L

    /** Outputs other than the phone's own speaker: headphones, Bluetooth, a dock, a TV. */
    private val EXTERNAL_OUTPUTS = setOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_AUX_LINE,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_BLE_BROADCAST,
        AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        AudioDeviceInfo.TYPE_DOCK,
        AudioDeviceInfo.TYPE_HDMI,
    )

    /** True when one of [outputTypes] (AudioDeviceInfo types) is not the phone's own speaker. */
    fun isExternal(outputTypes: Collection<Int>): Boolean = outputTypes.any { it in EXTERNAL_OUTPUTS }

    /**
     * The volume a chime really plays on. Android sends alarm audio to the phone
     * speaker as well as to connected headphones, and sets the level of both from
     * the speaker's volume: over Bluetooth that can leave a chime close to silent
     * and mute the music under it. So while headphones or an external speaker carry
     * the phone's audio, a chime travels with the media instead of as an alarm.
     */
    fun streamFor(chosen: String, externalOutput: Boolean): String =
        if (externalOutput || chosen == EngineSettings.STREAM_MEDIA) EngineSettings.STREAM_MEDIA
        else EngineSettings.STREAM_ALARM

    /**
     * SoundPool volume for the in-app chime volume. Hearing is roughly logarithmic,
     * so the slider is squared: half way sounds about half as loud (-12 dB), where a
     * straight line would still sound nearly full.
     */
    fun gainFor(level: Float): Float {
        val clamped = if (level.isNaN()) 1f else level.coerceIn(0f, 1f)
        return clamped * clamped
    }

    /**
     * How long other audio stays lowered for a chime of [durationMs]. A chime is
     * loudest at the strike and its tail is quiet, so other audio comes back before
     * the tail ends, and never stays down longer than a few seconds.
     */
    fun duckMs(durationMs: Long): Long = (durationMs * 7 / 10).coerceIn(MIN_DUCK_MS, MAX_DUCK_MS)

    /** A chime from a running timer. [ringerSilenced] is true on vibrate or silent. */
    fun forChime(settings: EngineSettings, ringerSilenced: Boolean): ChimeOutput {
        if (ringerSilenced && settings.vibrateWhenSilenced) {
            return ChimeOutput(gain = 0f, vibrate = true, duck = false)
        }
        val gain = gainFor(settings.level)
        return ChimeOutput(gain, settings.vibrate, duck = settings.duckOthers && gain > 0f)
    }

    /** A sound the user is trying out: always audible at the chosen volume, never a buzz. */
    fun forPreview(settings: EngineSettings): ChimeOutput {
        val gain = gainFor(settings.level)
        return ChimeOutput(gain, vibrate = false, duck = settings.duckOthers && gain > 0f)
    }
}
