package io.github.ilevytate.belltide.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TimerEngineTest {
    private val t0 = 1_000_000L

    /** Drives the engine the way the service does: tick at every requested wake-up. */
    private fun runUntil(engine: TimerEngine, end: Long): List<Pair<Long, String>> {
        val played = mutableListOf<Pair<Long, String>>()
        while (true) {
            val next = engine.nextWakeAt() ?: break
            if (next > end) break
            engine.tick(next).sounds().forEach { played += (next - t0) to it }
        }
        return played
    }

    @Test
    fun startWithStartChimePlaysImmediately() {
        val engine = TimerEngine()
        val effects = engine.start(holdRest(startChime = true), t0)
        assertEquals(listOf("bell"), effects.sounds())
        assertEquals(t0 + 10_000, engine.nextWakeAt())
    }

    @Test
    fun intervalChimesAtEachInterval() {
        val engine = TimerEngine()
        assertTrue(engine.start(interval(everyMs = 300_000), t0).sounds().isEmpty())
        val played = runUntil(engine, t0 + 1_000_000)
        assertEquals(listOf(300_000L, 600_000L, 900_000L), played.map { it.first })
        assertTrue(played.all { it.second == "bowl" })
    }

    @Test
    fun finiteIntervalStopsAfterItsChimes() {
        val engine = TimerEngine()
        engine.start(interval(everyMs = 60_000, rounds = 3), t0)
        val played = runUntil(engine, t0 + 1_000_000)
        assertEquals(listOf(60_000L, 120_000L, 180_000L), played.map { it.first })
        assertTrue(engine.isEmpty)
    }

    @Test
    fun sequenceRunsAllRoundsThenFinishes() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 2, leadInMs = 5_000), t0)
        val played = runUntil(engine, t0 + 1_000_000)
        assertEquals(
            listOf(
                5_000L to "bell", 15_000L to "wood",
                45_000L to "bell", 55_000L to "wood",
                85_000L to "gong",
            ),
            played,
        )
        assertTrue(engine.isEmpty)
        assertNull(engine.nextWakeAt())
    }

    @Test
    fun finishEmitsFinishedEffect() {
        val engine = TimerEngine()
        engine.start(interval(everyMs = 1_000, rounds = 1, id = "a"), t0)
        val effects = engine.tick(t0 + 1_000)
        assertEquals(listOf("a"), effects.finished())
    }

    @Test
    fun pauseFreezesAndResumeShiftsSchedule() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 1), t0)
        assertTrue(engine.pause("stretch", t0 + 4_000))
        assertNull(engine.nextWakeAt())
        assertFalse(engine.hasActive)
        // Remaining time does not change while paused.
        assertEquals(6_000, engine.snapshots(t0 + 60_000).single().stepRemainingMs)

        assertTrue(engine.resume("stretch", t0 + 64_000))
        assertEquals(t0 + 70_000, engine.nextWakeAt())
        assertEquals(listOf("wood"), engine.tick(t0 + 70_000).sounds())
    }

    @Test
    fun lateTickPlaysOnlyTheLatestChime() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 10, startChime = false), t0)
        // The device stalled through several boundaries; only the current step chimes.
        val effects = engine.tick(t0 + 51_000)
        assertEquals(listOf("wood"), effects.sounds())
        assertEquals(t0 + 80_000, engine.nextWakeAt())
    }

    @Test
    fun veryLateTickIsSilentButKeepsSchedule() {
        val engine = TimerEngine(maxLatenessMs = 5_000)
        engine.start(holdRest(rounds = 10, startChime = false), t0)
        val effects = engine.tick(t0 + 22_000)
        assertTrue(effects.sounds().isEmpty())
        assertEquals(t0 + 40_000, engine.nextWakeAt())
    }

    @Test
    fun slightlyEarlyTickWithinToleranceCounts() {
        val engine = TimerEngine(toleranceMs = 15)
        engine.start(holdRest(startChime = false), t0)
        assertEquals(listOf("wood"), engine.tick(t0 + 9_990).sounds())
    }

    @Test
    fun earlyTickOutsideToleranceWaits() {
        val engine = TimerEngine(toleranceMs = 15)
        engine.start(holdRest(startChime = false), t0)
        assertTrue(engine.tick(t0 + 9_900).isEmpty())
        assertEquals(t0 + 10_000, engine.nextWakeAt())
    }

    @Test
    fun skipJumpsToNextStepAndChimes() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 2, startChime = false), t0)
        val effects = engine.skip("stretch", t0 + 3_000)
        assertEquals(listOf("wood"), effects.sounds())
        val snap = engine.snapshots(t0 + 3_000).single()
        assertEquals(1, snap.stepIndex)
        assertEquals(30_000, snap.stepRemainingMs)
        assertEquals(t0 + 33_000, engine.nextWakeAt())
    }

    @Test
    fun skipOutOfLeadInStartsFirstStep() {
        val engine = TimerEngine()
        engine.start(holdRest(leadInMs = 5_000), t0)
        assertEquals(listOf("bell"), engine.skip("stretch", t0 + 1_000).sounds())
        assertEquals(0, engine.snapshots(t0 + 1_000).single().stepIndex)
        assertFalse(engine.snapshots(t0 + 1_000).single().inLeadIn)
    }

    @Test
    fun skipOnLastStepFinishes() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 1), t0)
        engine.skip("stretch", t0 + 1_000) // to Rest
        val effects = engine.skip("stretch", t0 + 2_000) // past the end
        assertEquals(listOf("gong"), effects.sounds())
        assertEquals(listOf("stretch"), effects.finished())
        assertTrue(engine.isEmpty)
    }

    @Test
    fun skipWhilePausedIsSilentAndDoesNotReplayOnResume() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 2, startChime = false), t0)
        engine.pause("stretch", t0 + 2_000)
        assertTrue(engine.skip("stretch", t0 + 3_000).sounds().isEmpty())
        assertEquals(1, engine.snapshots(t0 + 3_000).single().stepIndex)
        engine.resume("stretch", t0 + 10_000)
        assertTrue(engine.tick(t0 + 10_000).sounds().isEmpty())
        assertEquals(t0 + 40_000, engine.nextWakeAt())
    }

    @Test
    fun timersRunSideBySide() {
        val engine = TimerEngine()
        engine.start(interval(everyMs = 20_000, id = "a"), t0)
        engine.start(holdRest(rounds = 0, startChime = false, id = "b"), t0)
        val played = runUntil(engine, t0 + 40_000)
        assertEquals(
            listOf(10_000L to "wood", 20_000L to "bowl", 40_000L to "bowl", 40_000L to "bell"),
            played,
        )
        assertEquals(2, engine.snapshots(t0).size)
    }

    @Test
    fun startingAgainRestartsTheSameTimer() {
        val engine = TimerEngine()
        engine.start(holdRest(), t0)
        engine.start(holdRest(), t0 + 7_000)
        val snap = engine.snapshots(t0 + 7_000).single()
        assertEquals(0, snap.activeMs)
    }

    @Test
    fun stopRemovesTimer() {
        val engine = TimerEngine()
        engine.start(holdRest(), t0)
        assertTrue(engine.stop("stretch"))
        assertTrue(engine.isEmpty)
        assertFalse(engine.stop("stretch"))
    }

    @Test
    fun restoreCatchesUpSilently() {
        val engine = TimerEngine()
        val restored = RunningTimer(holdRest(rounds = 5), anchorMs = t0)
        val effects = engine.restore(listOf(restored), t0 + 52_000)
        assertTrue(effects.isEmpty())
        assertTrue(engine.tick(t0 + 52_000).sounds().isEmpty())
        assertEquals(t0 + 80_000, engine.nextWakeAt())
    }

    @Test
    fun restoreDropsTimersThatEndedMeanwhile() {
        val engine = TimerEngine()
        val restored = RunningTimer(holdRest(rounds = 1), anchorMs = t0)
        val effects = engine.restore(listOf(restored), t0 + 600_000)
        assertEquals(listOf("stretch"), effects.finished())
        assertTrue(engine.isEmpty)
    }

    @Test
    fun restoreKeepsPausedTimersPaused() {
        val engine = TimerEngine()
        val restored = RunningTimer(holdRest(rounds = 1), anchorMs = t0, pausedAtMs = t0 + 4_000)
        engine.restore(listOf(restored), t0 + 600_000)
        val snap = engine.snapshots(t0 + 600_000).single()
        assertTrue(snap.paused)
        assertEquals(6_000, snap.stepRemainingMs)
    }

    @Test
    fun snapshotReportsRoundsAndRemaining() {
        val engine = TimerEngine()
        engine.start(holdRest(rounds = 3, leadInMs = 5_000), t0)
        val lead = engine.snapshots(t0 + 1_000).single()
        assertTrue(lead.inLeadIn)
        assertEquals(4_000, lead.stepRemainingMs)
        assertEquals(124_000, lead.totalRemainingMs)

        val s = engine.snapshots(t0 + 57_000).single()
        assertEquals("Rest", s.stepLabel)
        assertEquals(2, s.round)
        assertEquals(3, s.rounds)
        assertEquals(28_000, s.stepRemainingMs)
        assertEquals(68_000, s.totalRemainingMs)
    }

    @Test
    fun infiniteSnapshotHasNoTotal() {
        val engine = TimerEngine()
        engine.start(interval(), t0)
        assertEquals(-1, engine.snapshots(t0 + 1).single().totalRemainingMs)
    }
}
