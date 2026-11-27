package io.github.ilevytate.belltide.engine

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineJsonTest {
    /** Reads a fixture shared with the Dart tests (test/fixtures at the repo root). */
    private fun fixture(name: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test/fixtures/$name")
            if (candidate.isFile) return candidate.readText()
            dir = dir.parentFile
        }
        error("Fixture $name not found")
    }

    @Test
    fun parsesTheSharedConfigFixture() {
        val config = EngineJson.parseConfig(fixture("engine_config.json"))
        assertEquals(
            TimerConfig(
                id = "stretch-holds",
                name = "Stretch holds",
                kind = TimerConfig.KIND_SEQUENCE,
                steps = listOf(
                    StepConfig("Hold", 10_000, "bell"),
                    StepConfig("Rest", 30_000, "wood"),
                ),
                rounds = 10,
                leadInMs = 5_000,
                startChime = true,
                finishSound = "rise",
            ),
            config,
        )
    }

    @Test
    fun snapshotMatchesTheSharedStateFixture() {
        val engine = TimerEngine()
        engine.start(EngineJson.parseConfig(fixture("engine_config.json")), 0)
        val actual = JSONObject(EngineJson.snapshotsToJson(engine.snapshots(17_000)))
        val expected = JSONObject(fixture("engine_state.json"))
        assertEquals(plain(expected), plain(actual))
    }

    /** Converts JSON to plain maps and lists, with every number as a Long. */
    private fun plain(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { plain(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { plain(value.get(it)) }
        is Number -> value.toLong()
        else -> value
    }
    @Test
    fun configRoundTrips() {
        val config = holdRest(rounds = 4, leadInMs = 3_000)
        val parsed = EngineJson.parseConfig(EngineJson.configToJson(config).toString())
        assertEquals(config, parsed)
    }

    @Test
    fun parsesTheFlutterWireFormat() {
        // Mirrors TimerPreset.toEngineJson() on the Dart side.
        val json = """
            {"id":"p1","name":"Work and rest","kind":"sequence",
             "steps":[{"label":"Work","durationMs":3000000,"sound":"bell"},
                      {"label":"Break","durationMs":600000,"sound":"double"}],
             "rounds":0,"leadInMs":0,"startChime":true,"finishSound":"rise"}
        """.trimIndent()
        val c = EngineJson.parseConfig(json)
        assertEquals("p1", c.id)
        assertEquals(2, c.steps.size)
        assertEquals(600_000, c.steps[1].durationMs)
        assertEquals(0, c.rounds)
        assertTrue(c.startChime)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsEmptySteps() {
        EngineJson.parseConfig("""{"id":"x","steps":[]}""")
    }

    @Test
    fun runningTimersRoundTrip() {
        val timers = listOf(
            RunningTimer(holdRest(), anchorMs = 123, pausedAtMs = 456),
            RunningTimer(interval(), anchorMs = 789),
        )
        val parsed = EngineJson.parseRunning(EngineJson.runningToJson(timers))
        assertEquals(2, parsed.size)
        assertEquals(456L, parsed[0].pausedAtMs)
        assertNull(parsed[1].pausedAtMs)
        assertEquals(789, parsed[1].anchorMs)
        assertEquals(interval(), parsed[1].config)
    }

    @Test
    fun snapshotJsonHasStatusAndFinished() {
        val engine = TimerEngine()
        engine.start(holdRest(), 0)
        engine.pause("stretch", 1_000)
        val o = JSONObject(EngineJson.snapshotsToJson(engine.snapshots(2_000), listOf("old")))
        val t = o.getJSONArray("timers").getJSONObject(0)
        assertEquals("paused", t.getString("status"))
        assertEquals(9_000, t.getLong("stepRemainingMs"))
        assertEquals("old", o.getJSONArray("finished").getString(0))
    }
}
