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
        timers.remove(config.id)
        timers[config.id] = RunningTimer(config, anchorMs = now)
        return tick(now) + EngineEffect.Advanced(config.id)
    }

    /** Adds timers recovered after a restart without replaying chimes they missed. */
    fun restore(restored: List<RunningTimer>, now: Long): List<EngineEffect> {
        val effects = mutableListOf<EngineEffect>()
        for (timer in restored) {
            val k = timer.timeline.lastBoundaryAt(timer.activeMs(now))
            val finish = timer.timeline.finishBoundary
            if (finish != null && k >= finish) {
                effects += EngineEffect.Finished(timer.config.id, timer.config.name)
                continue
            }
            timer.nextBoundary = k + 1
            timers[timer.config.id] = timer
        }
        return effects
    }

    fun pause(id: String, now: Long): Boolean {
        val timer = timers[id] ?: return false
        if (timer.paused) return false
        timer.pausedAtMs = now
        return true
    }

    fun resume(id: String, now: Long): Boolean {
        val timer = timers[id] ?: return false
        val pausedAt = timer.pausedAtMs ?: return false
        timer.anchorMs += now - pausedAt
        timer.pausedAtMs = null
        return true
    }

    fun pauseAll(now: Long): Boolean = timers.keys.toList().map { pause(it, now) }.any { it }

    fun resumeAll(now: Long): Boolean = timers.keys.toList().map { resume(it, now) }.any { it }

    fun stop(id: String): Boolean = timers.remove(id) != null

    fun stopAll(): Boolean {
        val had = timers.isNotEmpty()
        timers.clear()
        return had
    }

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
            return listOf(EngineEffect.Finished(id, timer.config.name))
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
        )
    }
}
