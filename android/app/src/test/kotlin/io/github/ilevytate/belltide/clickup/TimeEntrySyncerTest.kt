package io.github.ilevytate.belltide.clickup

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TimeEntrySyncerTest {
    private fun entry(id: String, task: String = "t1") = PendingTimeEntry(
        id = id,
        teamId = "9001",
        taskId = task,
        taskName = "Task $task",
        description = "Stretch (Belltide)",
        startMs = 1_700_000_000_000,
        durationMs = 40_000,
    )

    private class FakeTransport(private val responses: MutableList<() -> HttpResponse>) : HttpTransport {
        val requests = mutableListOf<Triple<String, Map<String, String>, String>>()
        override fun post(url: String, headers: Map<String, String>, body: String): HttpResponse {
            requests += Triple(url, headers, body)
            return responses.removeAt(0)()
        }
    }

    private fun ok() = { HttpResponse(200, """{"data":{"id":"123"}}""") }

    @Test
    fun postsTheDocumentedTimeEntryRequest() {
        val transport = FakeTransport(mutableListOf(ok()))
        val store = MemorySyncStore().apply { add(entry("a")) }
        TimeEntrySyncer(store, TimeEntryUploader(transport), clock = { 42 }).flush("pk_123")

        val (url, headers, body) = transport.requests.single()
        assertEquals("https://api.clickup.com/api/v2/team/9001/time_entries", url)
        assertEquals("pk_123", headers["Authorization"])
        assertEquals("application/json", headers["Content-Type"])
        val json = JSONObject(body)
        assertEquals(1_700_000_000_000, json.getLong("start"))
        assertEquals(40_000, json.getLong("duration"))
        assertEquals("t1", json.getString("tid"))
        assertEquals(false, json.getBoolean("billable"))
        assertEquals("Stretch (Belltide)", json.getString("description"))

        assertTrue(store.entries().isEmpty())
        assertEquals(42, store.lastSyncedAt)
        assertNull(store.lastError)
    }

    @Test
    fun offlineKeepsEverythingAndStops() {
        val transport = FakeTransport(mutableListOf({ throw IOException("no route") }))
        val store = MemorySyncStore().apply { add(entry("a")); add(entry("b")) }
        val uploaded = TimeEntrySyncer(store, TimeEntryUploader(transport)).flush("pk")
        assertEquals(0, uploaded)
        assertEquals(1, transport.requests.size)
        assertEquals(listOf("a", "b"), store.entries().map { it.id })
        assertTrue(store.lastError!!.contains("Couldn't reach ClickUp"))
    }

    @Test
    fun rejectedEntryIsDroppedAndTheRestContinue() {
        val transport = FakeTransport(
            mutableListOf(
                { HttpResponse(404, """{"err":"Task not found","ECODE":"ITEM_013"}""") },
                ok(),
            ),
        )
        val store = MemorySyncStore().apply { add(entry("a", task = "gone")); add(entry("b")) }
        val uploaded = TimeEntrySyncer(store, TimeEntryUploader(transport)).flush("pk")
        assertEquals(1, uploaded)
        assertTrue(store.entries().isEmpty())
        assertEquals("Couldn't log time to \"Task gone\": Task not found", store.lastError)
    }

    @Test
    fun badTokenAndRateLimitAreRetriedLater() {
        for (code in listOf(401, 429, 503)) {
            val transport = FakeTransport(mutableListOf({ HttpResponse(code, "{}") }))
            val store = MemorySyncStore().apply { add(entry("a")) }
            TimeEntrySyncer(store, TimeEntryUploader(transport)).flush("pk")
            assertEquals("code $code", 1, store.entries().size)
        }
    }

    @Test
    fun withoutATokenNothingIsSent() {
        val transport = FakeTransport(mutableListOf())
        val store = MemorySyncStore().apply { add(entry("a")) }
        TimeEntrySyncer(store, TimeEntryUploader(transport)).flush(null)
        assertTrue(transport.requests.isEmpty())
        assertEquals(1, store.entries().size)
        assertTrue(store.lastError!!.contains("Connect ClickUp"))
    }

    @Test
    fun queueSurvivesJson() {
        val list = listOf(entry("a"), entry("b", task = "t2"))
        assertEquals(list, PendingTimeEntry.listFromJson(PendingTimeEntry.listToJson(list)))
        assertTrue(PendingTimeEntry.listFromJson("not json").isEmpty())
        assertTrue(PendingTimeEntry.listFromJson(null).isEmpty())
    }
}
