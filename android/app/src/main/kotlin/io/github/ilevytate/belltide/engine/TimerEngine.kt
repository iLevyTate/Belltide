package io.github.ilevytate.belltide.engine

/** A timer that is running or paused. Times are on the engine's monotonic clock. */
class RunningTimer(
    val config: TimerConfig,
    /** Clock time at which the timer's active time was zero. Shifts on resume and skip. */
    var anchorMs: Long,
    /** Clock time when the timer was paused, or null while it runs. */
    var pausedAtMs: Long? = null,
    /** Index of the next boundary whose sound has not been handled yet. */
    var nextBoundary: Long = 0,
    /** Clock time when the current stretch of running time began; null while paused. */
    var segmentStartMs: Long? = null,
) {
    val timeline = Timeline(config)
    val paused: Boolean get() = pausedAtMs != null
    fun activeMs(now: Long): Long = (pausedAtMs ?: now) - anchorMs
}

sealed interface EngineEffect {
    val timerId: String

    /** A timer reached a new step (or finished); its displayed state changed. */
    data class Advanced(override val timerId: String) : EngineEffect

    /** Play a chime now. */
    data class Play(override val timerId: String, val sound: String) : EngineEffect

    /** A finite timer ran all its rounds and was removed. */
    data class Finished(override val timerId: String, val name: String) : EngineEffect

    /**
     * A stretch of running time ended (pause, stop, finish or restart). Times are on
     * the engine clock. Used to log time to a linked ClickUp task.
     */
    data class SegmentEnded(
        override val timerId: String,
        val config: TimerConfig,
        val startMs: Long,
        val endMs: Long,
    ) : EngineEffect
}

/** What the UI and the notification show for one timer. */
data class TimerSnapshot(
    val id: String,
    val name: String,
    val kind: String,
    val paused: Boolean,
    val inLeadIn: Boolean,
    val stepIndex: Int,
    val stepCount: Int,
    val stepLabel: String,
    /** One-based round number. */
    val round: Long,
    /** 0 when the timer repeats until stopped. */
    val rounds: Int,
    val stepDurationMs: Long,
    val stepRemainingMs: Long,
    /** -1 when the timer repeats until stopped. */
    val totalRemainingMs: Long,
    val activeMs: Long,
    /** Name of the linked ClickUp task, if any. */
    val taskName: String? = null,
)

/**
 * Runs any number of timers side by side. The engine never reads a clock itself:
 * every call takes `now` from a monotonic clock (SystemClock.elapsedRealtime on
 * Android), which keeps it deterministic and testable.
 *
 * The caller asks [nextWakeAt] when to call [tick] next. A tick that arrives late
 * plays only the most recent chime for each timer rather than a burst of missed
 * ones, and skips it entirely if it is more than [maxLatenessMs] late.
 */
class TimerEngine(
    private val toleranceMs: Long = 15,
    private val maxLatenessMs: Long = 5_000,
) {
    private val timers = LinkedHashMap<String, RunningTimer>()

    val isEmpty: Boolean get() = timers.isEmpty()
    val hasActive: Boolean get() = timers.values.any { !it.paused }
    val all: List<RunningTimer> get() = timers.values.toList()

    operator fun get(id: String): RunningTimer? = timers[id]

    /** Starts [config], replacing any running instance with the same id. */
    fun start(config: TimerConfig, now: Long): List<EngineEffect> {
        val previous = timers.remove(config.id)
        val ended = previous?.let { endSegment(it, now) } ?: emptyList()
        timers[config.id] = RunningTimer(config, anchorMs = now, segmentStartMs = now)
        return ended + tick(now) + EngineEffect.Advanced(config.id)
    }

    /** Closes the timer's current stretch of running time, if it has one. */
    private fun endSegment(timer: RunningTimer, endMs: Long): List<EngineEffect> {
        val start = timer.segmentStartMs ?: return emptyList()
        timer.segmentStartMs = null
        if (endMs <= start) return emptyList()
        return listOf(EngineEffect.SegmentEnded(timer.config.id, timer.config, start, endMs))
    }

    /** Adds timers recovered after a restart without replaying chimes they missed. */
    fun restore(restored: List<RunningTimer>, now: Long): List<EngineEffect> {
        val effects = mutableListOf<EngineEffect>()
        for (timer in restored) {
            val k = timer.timeline.lastBoundaryAt(timer.activeMs(now))
            val finish = timer.timeline.finishBoundary
            if (finish != null && k >= finish) {
                val end = (timer.anchorMs + timer.timeline.boundaryTime(finish)).coerceAtMost(now)
                effects += endSegment(timer, end)
                effects += EngineEffect.Finished(timer.config.id, timer.config.name)
                continue
            }
            // Older saved state had no segment; count from now so no time is lost.
            if (!timer.paused && timer.segmentStartMs == null) timer.segmentStartMs = now
            timer.nextBoundary = k + 1
            timers[timer.config.id] = timer
        }
        return effects
    }

    fun pause(id: String, now: Long): List<EngineEffect> {
        val timer = timers[id] ?: return emptyList()
        if (timer.paused) return emptyList()
        timer.pausedAtMs = now
        return endSegment(timer, now) + EngineEffect.Advanced(id)
    }

    fun resume(id: String, now: Long): List<EngineEffect> {
        val timer = timers[id] ?: return emptyList()
        val pausedAt = timer.pausedAtMs ?: return emptyList()
        timer.anchorMs += now - pausedAt
        timer.pausedAtMs = null
        timer.segmentStartMs = now
        return listOf(EngineEffect.Advanced(id))
    }

    fun pauseAll(now: Long): List<EngineEffect> = timers.keys.toList().flatMap { pause(it, now) }

    fun resumeAll(now: Long): List<EngineEffect> = timers.keys.toList().flatMap { resume(it, now) }

    fun stop(id: String, now: Long): List<EngineEffect> {
        val timer = timers.remove(id) ?: return emptyList()
        return endSegment(timer, now) + EngineEffect.Advanced(id)
    }

    fun stopAll(now: Long): List<EngineEffect> = timers.keys.toList().flatMap { stop(it, now) }

    /** Jumps to the start of the next step. While paused the jump is silent. */
    fun skip(id: String, now: Long): List<EngineEffect> {
        val timer = timers[id] ?: return emptyList()
        val active = timer.activeMs(now)
        val target = maxOf(timer.timeline.lastBoundaryAt(active + toleranceMs) + 1, timer.nextBoundary)
        timer.anchorMs -= timer.timeline.boundaryTime(target) - active
        if (!timer.paused) return tick(now) + EngineEffect.Advanced(id)

        val finish = timer.timeline.finishBoundary
        if (finish != null && target >= finish) {
            timers.remove(id)
            return endSegment(timer, now) + EngineEffect.Finished(id, timer.config.name)
        }
        timer.nextBoundary = target + 1
        return listOf(EngineEffect.Advanced(id))
    }

    /** Handles every boundary reached by [now]. */
    fun tick(now: Long): List<EngineEffect> {
        val effects = mutableListOf<EngineEffect>()
        val iterator = timers.values.iterator()
        while (iterator.hasNext()) {
            val timer = iterator.next()
            if (timer.paused) continue
            val active = timer.activeMs(now)
            val k = timer.timeline.lastBoundaryAt(active + toleranceMs)
            if (k < timer.nextBoundary) continue

            val id = timer.config.id
            val lateness = active - timer.timeline.boundaryTime(k)
            if (lateness <= maxLatenessMs) {
                timer.timeline.soundForBoundary(k)?.let { effects += EngineEffect.Play(id, it) }
            }
            timer.nextBoundary = k + 1
            effects += EngineEffect.Advanced(id)

            val finish = timer.timeline.finishBoundary
            if (finish != null && k >= finish) {
                iterator.remove()
                // Log up to the scheduled end, not a late wake-up.
                val end = (timer.anchorMs + timer.timeline.boundaryTime(finish)).coerceAtMost(now)
                effects += endSegment(timer, end)
                effects += EngineEffect.Finished(id, timer.config.name)
            }
        }
        return effects
    }

    /** Clock time of the next boundary across all running timers, or null if none. */
    fun nextWakeAt(): Long? = timers.values
        .filter { !it.paused }
        .minOfOrNull { it.anchorMs + it.timeline.boundaryTime(it.nextBoundary) }

    fun snapshots(now: Long): List<TimerSnapshot> = timers.values.map { snapshotOf(it, now) }

    private fun snapshotOf(timer: RunningTimer, now: Long): TimerSnapshot {
        val config = timer.config
        val active = timer.activeMs(now)
        val pos = timer.timeline.positionAt(active)
        val step = config.steps[pos.stepIndex]
        val total = timer.timeline.totalMs
        return TimerSnapshot(
            id = config.id,
            name = config.name,
            kind = config.kind,
            paused = timer.paused,
            inLeadIn = pos.inLeadIn,
            stepIndex = pos.stepIndex,
            stepCount = config.steps.size,
            stepLabel = if (pos.inLeadIn) "" else step.label,
            round = pos.round + 1,
            rounds = config.rounds,
            stepDurationMs = pos.endMs - pos.startMs,
            stepRemainingMs = (pos.endMs - active).coerceAtLeast(0),
            totalRemainingMs = total?.let { (it - active).coerceAtLeast(0) } ?: -1,
            activeMs = active,
            taskName = config.task?.name,
        )
    }
}
