package io.github.ilevytate.belltide.engine

import org.json.JSONArray
import org.json.JSONObject

/** JSON wire format shared with the Flutter side and the on-device persistence. */
object EngineJson {
    fun parseConfig(json: String): TimerConfig = parseConfig(JSONObject(json))

    fun parseConfig(o: JSONObject): TimerConfig {
        val steps = o.getJSONArray("steps")
        return TimerConfig(
            id = o.getString("id"),
            name = o.optString("name", ""),
            kind = o.optString("kind", TimerConfig.KIND_SEQUENCE),
            steps = (0 until steps.length()).map { i ->
                val s = steps.getJSONObject(i)
                StepConfig(
                    label = s.optString("label", ""),
                    durationMs = s.getLong("durationMs"),
                    sound = s.optString("sound", TimerConfig.SOUND_NONE),
                )
            },
            rounds = o.optInt("rounds", 0),
            leadInMs = o.optLong("leadInMs", 0),
            startChime = o.optBoolean("startChime", false),
            finishSound = o.optString("finishSound", TimerConfig.SOUND_NONE),
            task = o.optJSONObject("task")?.let { t ->
                TaskLink(
                    taskId = t.getString("id"),
                    teamId = t.getString("teamId"),
                    name = t.optString("name", ""),
                )
            },
        )
    }

    fun configToJson(c: TimerConfig): JSONObject = JSONObject()
        .put("id", c.id)
        .put("name", c.name)
        .put("kind", c.kind)
        .put("steps", JSONArray().also { arr ->
            c.steps.forEach { s ->
                arr.put(
                    JSONObject()
                        .put("label", s.label)
                        .put("durationMs", s.durationMs)
                        .put("sound", s.sound),
                )
            }
        })
        .put("rounds", c.rounds)
        .put("leadInMs", c.leadInMs)
        .put("startChime", c.startChime)
        .put("finishSound", c.finishSound)
        .also { o ->
            c.task?.let { t ->
                o.put("task", JSONObject().put("id", t.taskId).put("teamId", t.teamId).put("name", t.name))
            }
        }

    fun snapshotsToJson(snapshots: List<TimerSnapshot>, finished: List<String> = emptyList()): String {
        val timers = JSONArray()
        snapshots.forEach { s ->
            timers.put(
                JSONObject()
                    .put("id", s.id)
                    .put("name", s.name)
                    .put("kind", s.kind)
                    .put("status", if (s.paused) "paused" else "running")
                    .put("inLeadIn", s.inLeadIn)
                    .put("stepIndex", s.stepIndex)
                    .put("stepCount", s.stepCount)
                    .put("stepLabel", s.stepLabel)
                    .put("round", s.round)
                    .put("rounds", s.rounds)
                    .put("stepDurationMs", s.stepDurationMs)
                    .put("stepRemainingMs", s.stepRemainingMs)
                    .put("totalRemainingMs", s.totalRemainingMs)
                    .put("activeMs", s.activeMs),
            )
        }
        return JSONObject()
            .put("timers", timers)
            .put("finished", JSONArray(finished))
            .toString()
    }

    fun runningToJson(timers: List<RunningTimer>): String {
        val arr = JSONArray()
        timers.forEach { t ->
            arr.put(
                JSONObject()
                    .put("config", configToJson(t.config))
                    .put("anchorMs", t.anchorMs)
                    .put("pausedAtMs", t.pausedAtMs ?: JSONObject.NULL)
                    .put("segmentStartMs", t.segmentStartMs ?: JSONObject.NULL),
            )
        }
        return arr.toString()
    }

    fun parseRunning(json: String): List<RunningTimer> {
        val arr = JSONArray(json)
        return (0 until arr.length()).mapNotNull { i ->
            runCatching {
                val o = arr.getJSONObject(i)
                RunningTimer(
                    config = parseConfig(o.getJSONObject("config")),
                    anchorMs = o.getLong("anchorMs"),
                    pausedAtMs = if (o.isNull("pausedAtMs")) null else o.getLong("pausedAtMs"),
                    segmentStartMs = if (o.isNull("segmentStartMs")) null else o.getLong("segmentStartMs"),
                )
            }.getOrNull()
        }
    }
}
