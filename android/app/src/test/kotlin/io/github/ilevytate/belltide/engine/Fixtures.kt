package io.github.ilevytate.belltide.engine

fun holdRest(
    rounds: Int = 3,
    leadInMs: Long = 0,
    startChime: Boolean = true,
    id: String = "stretch",
) = TimerConfig(
    id = id,
    name = "Stretch",
    kind = TimerConfig.KIND_SEQUENCE,
    steps = listOf(
        StepConfig("Hold", 10_000, "bell"),
        StepConfig("Rest", 30_000, "wood"),
    ),
    rounds = rounds,
    leadInMs = leadInMs,
    startChime = startChime,
    finishSound = "gong",
)

fun interval(
    everyMs: Long = 300_000,
    rounds: Int = 0,
    id: String = "mindful",
) = TimerConfig(
    id = id,
    name = "Mindful bell",
    kind = TimerConfig.KIND_INTERVAL,
    steps = listOf(StepConfig("Interval", everyMs, "bowl")),
    rounds = rounds,
    leadInMs = 0,
    startChime = false,
    finishSound = "bowl",
)

fun List<EngineEffect>.sounds(): List<String> =
    filterIsInstance<EngineEffect.Play>().map { it.sound }

fun List<EngineEffect>.finished(): List<String> =
    filterIsInstance<EngineEffect.Finished>().map { it.timerId }
