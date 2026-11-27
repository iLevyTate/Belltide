package io.github.ilevytate.belltide.engine

/** One step of a timer, for example "Hold" for 10 seconds with the bell sound. */
data class StepConfig(
    val label: String,
    val durationMs: Long,
    val sound: String,
)

/** A ClickUp task a timer logs its running time to. */
data class TaskLink(
    val taskId: String,
    /** The ClickUp workspace (API "team") the task belongs to. */
    val teamId: String,
    val name: String,
)

/**
 * Everything the engine needs to run a timer. The Flutter side builds this from a
 * saved preset and sends it over the platform channel as JSON.
 *
 * A timer runs an optional lead-in, then its steps in order, repeated [rounds] times
 * ([rounds] == 0 repeats until stopped). Each step start is a "boundary" where that
 * step's sound plays; the last boundary of a finite timer plays [finishSound].
 */
data class TimerConfig(
    val id: String,
    val name: String,
    val kind: String,
    val steps: List<StepConfig>,
    val rounds: Int,
    val leadInMs: Long,
    val startChime: Boolean,
    val finishSound: String,
    /** When set, each stretch of running time is logged to this task. */
    val task: TaskLink? = null,
) {
    init {
        require(steps.isNotEmpty()) { "A timer needs at least one step" }
        require(steps.all { it.durationMs > 0 }) { "Step durations must be positive" }
        require(rounds >= 0) { "rounds must be >= 0" }
        require(leadInMs >= 0) { "leadInMs must be >= 0" }
    }

    val isInterval: Boolean get() = kind == KIND_INTERVAL

    companion object {
        const val KIND_INTERVAL = "interval"
        const val KIND_SEQUENCE = "sequence"
        const val SOUND_NONE = "none"
    }
}
