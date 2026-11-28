package io.github.ilevytate.belltide.service

import android.media.AudioDeviceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChimeMixTest {
    @Test
    fun gainFollowsASquareCurveAndStaysInRange() {
        assertEquals(1f, ChimeMix.gainFor(1f), 0f)
        assertEquals(0.25f, ChimeMix.gainFor(0.5f), 1e-6f)
        assertEquals(0f, ChimeMix.gainFor(0f), 0f)
        assertEquals(1f, ChimeMix.gainFor(3f), 0f)
        assertEquals(0f, ChimeMix.gainFor(-1f), 0f)
        assertEquals(1f, ChimeMix.gainFor(Float.NaN), 0f)
    }

    @Test
    fun duckingCoversTheLoudPartOfAChimeWithinLimits() {
        assertEquals(2_100, ChimeMix.duckMs(3_000))
        assertEquals(400, ChimeMix.duckMs(200))
        assertEquals(3_000, ChimeMix.duckMs(6_500))
    }

    @Test
    fun chimePlaysAtFullVolumeAndLowersOtherAudioByDefault() {
        val output = ChimeMix.forChime(EngineSettings(), ringerSilenced = false)
        assertEquals(1f, output.gain, 0f)
        assertFalse(output.vibrate)
        assertTrue(output.duck)
    }

    @Test
    fun chimeStillPlaysWhenThePhoneIsOnVibrate() {
        val output = ChimeMix.forChime(EngineSettings(level = 0.5f), ringerSilenced = true)
        assertEquals(0.25f, output.gain, 1e-6f)
        assertFalse(output.vibrate)
        assertTrue(output.duck)
    }

    @Test
    fun vibrateSettingBuzzesAlongWithTheSound() {
        val output = ChimeMix.forChime(EngineSettings(vibrate = true), ringerSilenced = true)
        assertEquals(1f, output.gain, 0f)
        assertTrue(output.vibrate)
    }

    @Test
    fun vibrateWhenSilencedReplacesTheSoundWithABuzz() {
        val settings = EngineSettings(vibrateWhenSilenced = true)
        val silenced = ChimeMix.forChime(settings, ringerSilenced = true)
        assertEquals(0f, silenced.gain, 0f)
        assertTrue(silenced.vibrate)
        assertFalse(silenced.duck)

        val ringing = ChimeMix.forChime(settings, ringerSilenced = false)
        assertEquals(1f, ringing.gain, 0f)
        assertFalse(ringing.vibrate)
    }

    @Test
    fun mutedChimeNeitherPlaysNorLowersOtherAudio() {
        val output = ChimeMix.forChime(EngineSettings(level = 0f, vibrate = true), ringerSilenced = false)
        assertEquals(0f, output.gain, 0f)
        assertTrue(output.vibrate)
        assertFalse(output.duck)
    }

    @Test
    fun duckingCanBeTurnedOff() {
        assertFalse(ChimeMix.forChime(EngineSettings(duckOthers = false), ringerSilenced = false).duck)
        assertFalse(ChimeMix.forPreview(EngineSettings(duckOthers = false)).duck)
    }

    @Test
    fun previewIsHeardEvenWhenChimesWouldOnlyBuzz() {
        val output = ChimeMix.forPreview(EngineSettings(level = 0.8f, vibrate = true, vibrateWhenSilenced = true))
        assertEquals(0.64f, output.gain, 1e-6f)
        assertFalse(output.vibrate)
        assertTrue(output.duck)
    }

    @Test
    fun headphonesAndBluetoothCountAsExternalOutputs() {
        assertFalse(ChimeMix.isExternal(emptyList()))
        assertFalse(
            ChimeMix.isExternal(
                listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE),
            ),
        )
        assertTrue(ChimeMix.isExternal(listOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)))
        assertTrue(
            ChimeMix.isExternal(
                listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_WIRED_HEADPHONES),
            ),
        )
        assertTrue(ChimeMix.isExternal(listOf(AudioDeviceInfo.TYPE_BLE_HEADSET)))
        // A call's Bluetooth link is not where media plays.
        assertFalse(ChimeMix.isExternal(listOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)))
    }

    @Test
    fun alarmChimesPlayAsMediaThroughHeadphones() {
        val alarm = EngineSettings.STREAM_ALARM
        val media = EngineSettings.STREAM_MEDIA
        assertEquals(alarm, ChimeMix.streamFor(alarm, externalOutput = false))
        assertEquals(media, ChimeMix.streamFor(alarm, externalOutput = true))
        assertEquals(media, ChimeMix.streamFor(media, externalOutput = false))
        assertEquals(media, ChimeMix.streamFor(media, externalOutput = true))
    }

    @Test
    fun everyChimeHasALength() {
        assertEquals(18, CHIME_CATALOG.size)
        assertTrue(CHIME_CATALOG.values.all { it.durationMs in 100..7_500 })
    }
}
