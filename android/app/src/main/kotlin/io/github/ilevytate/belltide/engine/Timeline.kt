package io.github.ilevytate.belltide.engine

/** Where a timer is at a given amount of active (unpaused) time. */
data class Position(
    /** True while the lead-in ("get ready") countdown runs. */
    val inLeadIn: Boolean,
    /** True once every round of a finite timer has run. */
    val finished: Boolean,
    /** Index into [TimerConfig.steps]; 0 during the lead-in. */
    val stepIndex: Int,
    /** Zero-based round number. */
    val round: Long,
    /** Active time at which the current step (or lead-in) started. */
    val startMs: Long,
    /** Active time at which the current step (or lead-in) ends. */
    val endMs: Long,
    /** Number of step boundaries already reached (boundary 0 is the first step's start). */
    val boundariesPassed: Long,
)

/**
 * Pure timing math for a single timer. All times are milliseconds of active time
 * since the timer started, so pausing is handled by the caller.
 *
 * Boundary k (k >= 0) is the start of step k % n in round k / n, where n is the
 * number of steps. For a finite timer, boundary rounds * n is the finish.
 */
class Timeline(private val config: TimerConfig) {
    private val n = config.steps.size
    private val offsets: LongArray = LongArray(n + 1).also { acc ->
        for (i in 0 until n) acc[i + 1] = acc[i] + config.steps[i].durationMs
    }
    val cycleMs: Long = offsets[n]

    /** The finishing boundary index, or null when the timer repeats until stopped. */
    val finishBoundary: Long? = if (config.rounds > 0) config.rounds.toLong() * n else null

    /** Total running time including the lead-in, or null when it repeats until stopped. */
    val totalMs: Long? = finishBoundary?.let { boundaryTime(it) }

    fun boundaryTime(k: Long): Long {
        require(k >= 0)
        return config.leadInMs + (k / n) * cycleMs + offsets[(k % n).toInt()]
    }

    /** Index of the last boundary at or before [activeMs], or -1 during the lead-in. */
    fun lastBoundaryAt(activeMs: Long): Long {
        if (activeMs < config.leadInMs) return -1
        val t = activeMs - config.leadInMs
        val round = t / cycleMs
        val inCycle = t % cycleMs
        var step = 0
        while (step + 1 < n && offsets[step + 1] <= inCycle) step++
        val k = round * n + step
        return finishBoundary?.let { minOf(k, it) } ?: k
    }

    fun positionAt(activeMs: Long): Position {
        val k = lastBoundaryAt(activeMs)
        if (k < 0) {
            return Position(
                inLeadIn = true, finished = false, stepIndex = 0, round = 0,
                startMs = 0, endMs = config.leadInMs, boundariesPassed = 0,
            )
        }
        val finish = finishBoundary
        if (finish != null && k >= finish) {
            val end = boundaryTime(finish)
            return Position(
                inLeadIn = false, finished = true, stepIndex = n - 1,
                round = config.rounds.toLong() - 1, startMs = end, endMs = end,
                boundariesPassed = finish + 1,
            )
        }
        return Position(
            inLeadIn = false, finished = false, stepIndex = (k % n).toInt(), round = k / n,
            startMs = boundaryTime(k), endMs = boundaryTime(k + 1), boundariesPassed = k + 1,
        )
    }

    /** The sound to play when boundary [k] is reached, or null for silence. */
    fun soundForBoundary(k: Long): String? {
        val sound = when {
            finishBoundary != null && k >= finishBoundary -> config.finishSound
            k == 0L && !config.startChime -> null
            else -> config.steps[(k % n).toInt()].sound
        }
        return sound?.takeUnless { it == TimerConfig.SOUND_NONE || it.isBlank() }
    }
}
