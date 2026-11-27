package io.github.ilevytate.belltide.clickup

import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject

/** A stretch of running time waiting to be logged to a ClickUp task. */
data class PendingTimeEntry(
    /** Local id, so an entry can be removed after it uploads. */
    val id: String,
    val teamId: String,
    val taskId: String,
    val taskName: String,
    val description: String,
    /** Wall-clock start, in Unix milliseconds. */
    val startMs: Long,
    val durationMs: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("teamId", teamId)
        .put("taskId", taskId)
        .put("taskName", taskName)
        .put("description", description)
        .put("startMs", startMs)
        .put("durationMs", durationMs)

    /** Body for ClickUp's "Create a time entry" endpoint. */
    fun requestBody(): String = JSONObject()
        .put("description", description)
        .put("start", startMs)
        .put("duration", durationMs)
        .put("billable", false)
        .put("tid", taskId)
        .toString()

    companion object {
        fun fromJson(o: JSONObject) = PendingTimeEntry(
            id = o.getString("id"),
            teamId = o.getString("teamId"),
            taskId = o.getString("taskId"),
            taskName = o.optString("taskName", ""),
            description = o.optString("description", ""),
            startMs = o.getLong("startMs"),
            durationMs = o.getLong("durationMs"),
        )

        fun listToJson(entries: List<PendingTimeEntry>): String =
            JSONArray().also { arr -> entries.forEach { arr.put(it.toJson()) } }.toString()

        fun listFromJson(json: String?): List<PendingTimeEntry> {
            if (json.isNullOrBlank()) return emptyList()
            val arr = runCatching { JSONArray(json) }.getOrNull() ?: return emptyList()
            return (0 until arr.length()).mapNotNull { i ->
                runCatching { fromJson(arr.getJSONObject(i)) }.getOrNull()
            }
        }
    }
}

/** Where the queue and sync status live. Synchronized so the uploader thread can share it. */
interface SyncStore {
    fun entries(): List<PendingTimeEntry>
    fun add(entry: PendingTimeEntry)
    fun remove(id: String)
    fun clear()
    var lastError: String?
    var lastSyncedAt: Long
}

class MemorySyncStore : SyncStore {
    private val list = mutableListOf<PendingTimeEntry>()
    @Synchronized override fun entries() = list.toList()
    @Synchronized override fun add(entry: PendingTimeEntry) { list += entry }
    @Synchronized override fun remove(id: String) { list.removeAll { it.id == id } }
    @Synchronized override fun clear() { list.clear() }
    override var lastError: String? = null
    override var lastSyncedAt: Long = 0
}

data class HttpResponse(val code: Int, val body: String)

/** Minimal HTTP seam so the uploader can be tested without a network. */
fun interface HttpTransport {
    @Throws(IOException::class)
    fun post(url: String, headers: Map<String, String>, body: String): HttpResponse
}

/** What happened when one entry was sent. */
sealed interface UploadOutcome {
    data object Uploaded : UploadOutcome

    /** Worth trying again later: offline, rate limited, server trouble, bad token. */
    data class Retry(val reason: String) : UploadOutcome

    /** ClickUp refused this entry (for example the task was deleted); drop it. */
    data class Rejected(val reason: String) : UploadOutcome
}

class TimeEntryUploader(
    private val transport: HttpTransport,
    private val baseUrl: String = "https://api.clickup.com/api",
) {
    fun upload(entry: PendingTimeEntry, token: String): UploadOutcome {
        val response = try {
            transport.post(
                "$baseUrl/v2/team/${entry.teamId}/time_entries",
                mapOf("Authorization" to token, "Content-Type" to "application/json"),
                entry.requestBody(),
            )
        } catch (e: IOException) {
            return UploadOutcome.Retry("Couldn't reach ClickUp. Time will be logged when you're back online.")
        }
        val message = errorMessage(response.body)
        return when (response.code) {
            in 200..299 -> UploadOutcome.Uploaded
            401 -> UploadOutcome.Retry("ClickUp didn't accept the API token. Reconnect ClickUp in Settings.")
            429 -> UploadOutcome.Retry("ClickUp's rate limit was reached. Time will be logged shortly.")
            in 500..599 -> UploadOutcome.Retry("ClickUp had a problem (HTTP ${response.code}). Will retry.")
            else -> UploadOutcome.Rejected(message ?: "HTTP ${response.code}")
        }
    }

    private fun errorMessage(body: String): String? =
        runCatching { JSONObject(body).optString("err").takeIf { it.isNotBlank() } }.getOrNull()
}

/**
 * Sends queued entries in order. Stops at the first entry that should be retried, so
 * entries stay in time order and a flaky connection isn't hammered.
 */
class TimeEntrySyncer(
    private val store: SyncStore,
    private val uploader: TimeEntryUploader,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    /** Returns the number of entries uploaded. */
    fun flush(token: String?): Int {
        val entries = store.entries()
        if (entries.isEmpty()) return 0
        if (token.isNullOrBlank()) {
            store.lastError = "Connect ClickUp in Settings to log ${entries.size} saved time " +
                if (entries.size == 1) "entry." else "entries."
            return 0
        }
        var uploaded = 0
        var error: String? = null
        for (entry in entries) {
            when (val outcome = uploader.upload(entry, token)) {
                UploadOutcome.Uploaded -> {
                    store.remove(entry.id)
                    uploaded++
                }
                is UploadOutcome.Rejected -> {
                    store.remove(entry.id)
                    error = "Couldn't log time to \"${entry.taskName}\": ${outcome.reason}"
                }
                is UploadOutcome.Retry -> {
                    error = outcome.reason
                    break
                }
            }
        }
        if (uploaded > 0) store.lastSyncedAt = clock()
        store.lastError = error
        return uploaded
    }
}
