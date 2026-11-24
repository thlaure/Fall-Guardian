package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives the relay orchestration with scripted HTTP status sequences. */
class RelayProcessorTest {
    private class MemoryStore(var items: MutableList<QueuedAlert>) : RelayQueueStore {
        val outcomes = mutableListOf<RelayOutcome>()

        override fun find(clientAlertId: String) = items.firstOrNull { it.clientAlertId == clientAlertId }

        override fun markSubmitted(clientAlertId: String) {
            items = NativeAlertQueue.markSubmitted(items, clientAlertId).toMutableList()
        }

        override fun complete(clientAlertId: String, outcome: RelayOutcomeKind?) {
            val item = find(clientAlertId) ?: return
            items.remove(item)
            outcome?.let { outcomes += RelayOutcome(item.clientAlertId, item.timestamp, it) }
        }

        override fun recordOutcome(clientAlertId: String, outcome: RelayOutcomeKind) {
            val item = find(clientAlertId) ?: return
            outcomes += RelayOutcome(item.clientAlertId, item.timestamp, outcome)
        }
    }

    private fun alert(id: String, submitted: Boolean = false, cancel: Boolean = false) =
        QueuedAlert(id, 1, RelaySource.WEAR_OS, submitted, cancel, 1)

    private fun run(
        store: MemoryStore,
        vararg statuses: Int,
        onPost: (String) -> Unit = {}
    ): Pair<RelayPassResult, List<String>> {
        val script = statuses.toMutableList()
        val calls = mutableListOf<String>()
        val processor = RelayProcessor(
            store,
            post = { path, body ->
                calls += if (body == null) path else "$path ${if (body.contains("\"cancelled\":true")) "cancelled" else "create"}"
                onPost(path)
                script.removeAt(0)
            },
            createPayload = { a, cancelled ->
                NativeAlertRelayPolicy.createPayload(a.clientAlertId, a.timestamp, "en", a.source, cancelled)
            }
        )
        return processor.relay(store.items.map { it.clientAlertId }) to calls
    }

    @Test
    fun `successful create keeps the incident as submitted`() {
        val store = MemoryStore(mutableListOf(alert("a")))

        val (result, calls) = run(store, 201)

        assertEquals(RelayPassResult.DONE, result)
        assertEquals(listOf("/api/v1/fall-alerts create"), calls)
        assertTrue(store.items.single().submitted)
        assertEquals(listOf(RelayOutcomeKind.CREATED), store.outcomes.map { it.kind })
    }

    @Test
    fun `cancel requested during create is sent right after`() {
        val store = MemoryStore(mutableListOf(alert("a")))

        val (result, calls) = run(store, 201, 200) { path ->
            if (path == RelayProcessor.CREATE_PATH) {
                store.items = NativeAlertQueue.requestCancel(store.items, "a", null).items.toMutableList()
            }
        }

        assertEquals(RelayPassResult.DONE, result)
        assertEquals(listOf("/api/v1/fall-alerts create", "/api/v1/fall-alerts/a/cancel"), calls)
        assertTrue(store.items.isEmpty())
        // Success outcomes let Flutter replace provisional history entries.
        assertEquals(
            listOf(RelayOutcomeKind.CREATED, RelayOutcomeKind.CANCELLED),
            store.outcomes.map { it.kind }
        )
    }

    @Test
    fun `unsent cancelled incident is recorded with one cancelled create`() {
        val store = MemoryStore(mutableListOf(alert("a", cancel = true)))

        val (_, calls) = run(store, 201)

        assertEquals(listOf("/api/v1/fall-alerts cancelled"), calls)
        assertTrue(store.items.isEmpty())
        assertEquals(RelayOutcomeKind.CANCELLED, store.outcomes.single().kind)
    }

    @Test
    fun `401 stops the pass for re-pairing and keeps everything queued`() {
        val store = MemoryStore(mutableListOf(alert("a"), alert("b")))

        val (result, calls) = run(store, 401)

        assertEquals(RelayPassResult.REAUTH_REQUIRED, result)
        assertEquals(1, calls.size)
        assertEquals(2, store.items.size)
    }

    @Test
    fun `403 and 5xx are retried, not treated as re-pairing`() {
        val store = MemoryStore(mutableListOf(alert("a"), alert("b")))

        val (result, calls) = run(store, 403, 503)

        assertEquals(RelayPassResult.RETRY, result)
        assertEquals(2, calls.size)
        assertEquals(2, store.items.size)
    }

    @Test
    fun `validation error removes the incident with a history outcome`() {
        val store = MemoryStore(mutableListOf(alert("a")))

        val (result, _) = run(store, 422)

        assertEquals(RelayPassResult.DONE, result)
        assertTrue(store.items.isEmpty())
        assertEquals(RelayOutcomeKind.CREATE_REJECTED, store.outcomes.single().kind)
    }

    @Test
    fun `cancel conflict is reported as too late, cancel not found is done`() {
        val tooLate = MemoryStore(mutableListOf(alert("a", submitted = true, cancel = true)))
        run(tooLate, 409)
        assertEquals(RelayOutcomeKind.CANCEL_TOO_LATE, tooLate.outcomes.single().kind)

        val gone = MemoryStore(mutableListOf(alert("a", submitted = true, cancel = true)))
        run(gone, 404)
        assertTrue(gone.items.isEmpty())
        assertEquals(RelayOutcomeKind.CANCELLED, gone.outcomes.single().kind)
    }

    @Test
    fun `duplicate create conflict counts as submitted`() {
        val store = MemoryStore(mutableListOf(alert("a")))

        run(store, 409)

        assertTrue(store.items.single().submitted)
        assertEquals(RelayOutcomeKind.CREATED, store.outcomes.single().kind)
    }
}
