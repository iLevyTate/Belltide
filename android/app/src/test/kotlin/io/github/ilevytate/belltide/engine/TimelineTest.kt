package io.github.ilevytate.belltide.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TimelineTest {
    @Test
    fun boundaryTimesFollowStepsAndRounds() {
        val t = Timeline(holdRest(rounds = 3, leadInMs = 5_000))
        assertEquals(40_000, t.cycleMs)
        assertEquals(5_000, t.boundaryTime(0))
        assertEquals(15_000, t.boundaryTime(1))
        assertEquals(45_000, t.boundaryTime(2))
        assertEquals(55_000, t.boundaryTime(3))
        assertEquals(6L, t.finishBoundary)
        assertEquals(125_000L, t.totalMs)
    }

    @Test
    fun lastBoundaryAtTracksTheCurrentStep() {
        val t = Timeline(holdRest(rounds = 3, leadInMs = 5_000))
        assertEquals(-1, t.lastBoundaryAt(0))
        assertEquals(-1, t.lastBoundaryAt(4_999))
        assertEquals(0, t.lastBoundaryAt(5_000))
        assertEquals(0, t.lastBoundaryAt(14_999))
        assertEquals(1, t.lastBoundaryAt(15_000))
        assertEquals(2, t.lastBoundaryAt(45_000))
        assertEquals(6, t.lastBoundaryAt(125_000))
        // Past the end it stays at the finish boundary.
        assertEquals(6, t.lastBoundaryAt(10_000_000))
    }

    @Test
    fun positionDuringLeadIn() {
        val p = Timeline(holdRest(leadInMs = 5_000)).positionAt(2_000)
        assertTrue(p.inLeadIn)
        assertFalse(p.finished)
        assertEquals(0, p.startMs)
        assertEquals(5_000, p.endMs)
    }

    @Test
    fun positionInSecondRoundRestStep() {
        val p = Timeline(holdRest(rounds = 3)).positionAt(52_000)
        assertFalse(p.inLeadIn)
        assertEquals(1, p.stepIndex)
        assertEquals(1, p.round)
        assertEquals(50_000, p.startMs)
        assertEquals(80_000, p.endMs)
    }

    @Test
    fun positionAfterTheEndIsFinished() {
        val p = Timeline(holdRest(rounds = 2)).positionAt(80_000)
        assertTrue(p.finished)
        assertEquals(80_000, p.endMs)
    }

    @Test
    fun infiniteTimerNeverFinishes() {
        val t = Timeline(interval(everyMs = 60_000))
        assertNull(t.finishBoundary)
        assertNull(t.totalMs)
        assertEquals(1_000, t.lastBoundaryAt(60_000_000 + 5))
        assertFalse(t.positionAt(Long.MAX_VALUE / 4).finished)
    }

    @Test
    fun soundsForBoundaries() {
        val t = Timeline(holdRest(rounds = 2, startChime = false))
        assertNull(t.soundForBoundary(0))
        assertEquals("wood", t.soundForBoundary(1))
        assertEquals("bell", t.soundForBoundary(2))
        assertEquals("wood", t.soundForBoundary(3))
        assertEquals("gong", t.soundForBoundary(4))
    }

    @Test
    fun startChimePlaysFirstStepSound() {
        assertEquals("bell", Timeline(holdRest(startChime = true)).soundForBoundary(0))
    }

    @Test
    fun noneSoundIsSilent() {
        val config = holdRest().copy(
            steps = listOf(StepConfig("Hold", 1_000, TimerConfig.SOUND_NONE), StepConfig("Rest", 1_000, "wood")),
        )
        assertNull(Timeline(config).soundForBoundary(2))
    }
}
