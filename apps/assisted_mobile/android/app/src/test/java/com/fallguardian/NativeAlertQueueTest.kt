package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAlertQueueTest {
    private val now = 1_710_000_000_000L
    private val uuidA = "3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f"
    private val uuidB = "7a1c2d3e-4f50-4617-8293-a4b5c6d7e8f9"

    private fun item(
        id: String,
        timestamp: Long,
        submitted: Boolean = false,
        cancelRequested: Boolean = false,
        source: RelaySource = RelaySource.WEAR_OS
    ) = QueuedAlert(id, timestamp, source, submitted, cancelRequested, timestamp)

    @Test
    fun `legacy single pending slot migrates into one queue item`() {
        val migrated = NativeAlertQueue.migrateLegacy(
            timestamp = now,
            clientAlertId = "wear-os-$now",
            submitted = false,
            cancelRequested = true,
            now = now + 5
        )

        assertEquals(
            listOf(QueuedAlert("wear-os-$now", now, RelaySource.WEAR_OS, false, true, now + 5)),
            migrated
        )
    }

    @Test
    fun `missing or unsafe legacy slot migrates to an empty queue`() {
        assertTrue(NativeAlertQueue.migrateLegacy(null, "wear-os-1", false, false, now).isEmpty())
        assertTrue(NativeAlertQueue.migrateLegacy(now, null, false, false, now).isEmpty())
        assertTrue(NativeAlertQueue.migrateLegacy(now, "bad|id", false, false, now).isEmpty())
    }

    @Test
    fun `queue survives an encode decode round trip`() {
        val items = listOf(
            item(uuidA, now, submitted = true),
            item("assisted-phone-1", now + 1, cancelRequested = true, source = RelaySource.ASSISTED_PHONE)
        )

        assertEquals(items, NativeAlertQueue.decode(NativeAlertQueue.encode(items)))
    }

    @Test
    fun `decode skips corrupted lines and unknown formats`() {
        val raw = "v2\n$uuidA|$now|wear_os|0|0|$now\ngarbage\nx|notanumber|wear_os|0|0|1\n$uuidB|1|alien|0|0|1"

        assertEquals(listOf(item(uuidA, now)), NativeAlertQueue.decode(raw))
        assertTrue(NativeAlertQueue.decode("v1\nwhatever").isEmpty())
        assertTrue(NativeAlertQueue.decode(null).isEmpty())
    }

    @Test
    fun `second distinct fall is queued instead of overwriting an unsent first`() {
        val first = NativeAlertQueue.enqueue(emptyList(), now, uuidA, RelaySource.WEAR_OS, now)
        val second = NativeAlertQueue.enqueue(first.items, now + 5_000, uuidB, RelaySource.WEAR_OS, now)

        assertEquals(uuidB, second.clientAlertId)
        assertEquals(listOf(uuidA, uuidB), second.items.map { it.clientAlertId })
        assertFalse(second.items.first().submitted)
    }

    @Test
    fun `duplicate transports of one incident are deduplicated by id or timestamp`() {
        val first = NativeAlertQueue.enqueue(emptyList(), now, uuidA, RelaySource.WEAR_OS, now)

        val sameId = NativeAlertQueue.enqueue(first.items, now, uuidA, RelaySource.WEAR_OS, now)
        val legacyTransportSameTimestamp =
            NativeAlertQueue.enqueue(first.items, now, null, RelaySource.WEAR_OS, now)

        assertEquals(uuidA, sameId.clientAlertId)
        assertEquals(1, sameId.items.size)
        assertEquals(uuidA, legacyTransportSameTimestamp.clientAlertId)
        assertEquals(1, legacyTransportSameTimestamp.items.size)
    }

    @Test
    fun `legacy watch retriggers within 30 s reuse the active incident`() {
        val first = NativeAlertQueue.enqueue(emptyList(), now, null, RelaySource.WEAR_OS, now)
        val retrigger = NativeAlertQueue.enqueue(first.items, now + 10_000, null, RelaySource.WEAR_OS, now)
        val later = NativeAlertQueue.enqueue(first.items, now + 31_000, null, RelaySource.WEAR_OS, now)

        assertEquals("wear-os-$now", first.clientAlertId)
        assertEquals("wear-os-$now", retrigger.clientAlertId)
        assertEquals("wear-os-${now + 31_000}", later.clientAlertId)
        assertEquals(2, later.items.size)
    }

    @Test
    fun `a new legacy fall after a cancel never reuses the cancelled incident`() {
        val cancelled = listOf(item("wear-os-$now", now, cancelRequested = true))

        val result = NativeAlertQueue.enqueue(cancelled, now + 5_000, null, RelaySource.WEAR_OS, now)

        assertEquals("wear-os-${now + 5_000}", result.clientAlertId)
    }

    @Test
    fun `queue is bounded and evicts already submitted incidents first`() {
        var items = (0 until NativeAlertQueue.MAX_ITEMS).map {
            item("wear-os-${now + it}", now + it, submitted = it == 5)
        }

        val result = NativeAlertQueue.enqueue(items, now + 100, uuidA, RelaySource.WEAR_OS, now)

        assertEquals(NativeAlertQueue.MAX_ITEMS, result.items.size)
        assertFalse(result.items.any { it.clientAlertId == "wear-os-${now + 5}" })
        assertTrue(result.dropped.isEmpty())

        items = result.items
        val overflow = NativeAlertQueue.enqueue(items, now + 200, uuidB, RelaySource.WEAR_OS, now)
        assertEquals(NativeAlertQueue.MAX_ITEMS, overflow.items.size)
        assertEquals(listOf("wear-os-$now"), overflow.dropped.map { it.clientAlertId })
    }

    @Test
    fun `cancel with incident id only targets the matching incident`() {
        val items = listOf(item(uuidA, now), item(uuidB, now + 1))

        val result = NativeAlertQueue.requestCancel(items, uuidA.uppercase(), null)

        assertTrue(result.first { it.clientAlertId == uuidA }.cancelRequested)
        assertFalse(result.first { it.clientAlertId == uuidB }.cancelRequested)
    }

    @Test
    fun `cancel with fall timestamp targets a legacy derived incident`() {
        val items = listOf(item("wear-os-$now", now), item(uuidB, now + 1))

        val result = NativeAlertQueue.requestCancel(items, uuidA, now)

        assertTrue(result.first { it.clientAlertId == "wear-os-$now" }.cancelRequested)
        assertFalse(result.first { it.clientAlertId == uuidB }.cancelRequested)
    }

    @Test
    fun `cancel with unknown target changes nothing`() {
        val items = listOf(item(uuidA, now))

        assertEquals(items, NativeAlertQueue.requestCancel(items, uuidB, now + 99))
    }

    @Test
    fun `legacy cancel without target cancels only the most recent open incident`() {
        val items = listOf(item(uuidA, now), item(uuidB, now + 1))

        val result = NativeAlertQueue.requestCancel(items, null, null)

        assertFalse(result.first { it.clientAlertId == uuidA }.cancelRequested)
        assertTrue(result.first { it.clientAlertId == uuidB }.cancelRequested)
    }

    @Test
    fun `prune forgets old submitted incidents and reports expired undelivered ones`() {
        val oldSubmitted = item(uuidA, now - NativeAlertQueue.SUBMITTED_RETENTION_MS - 1, submitted = true)
        val recentSubmitted = item(uuidB, now - 1_000, submitted = true)
        val expired = item("wear-os-1", now - NativeAlertQueue.UNDELIVERED_RETENTION_MS - 1)
        val pendingCancel = item("wear-os-2", now - NativeAlertQueue.SUBMITTED_RETENTION_MS - 1, submitted = true, cancelRequested = true)

        val (kept, dropped) = NativeAlertQueue.prune(
            listOf(oldSubmitted, recentSubmitted, expired, pendingCancel),
            now
        )

        assertEquals(listOf(recentSubmitted, pendingCancel), kept)
        assertEquals(listOf(expired), dropped)
    }

    @Test
    fun `outcomes round trip and stay bounded`() {
        val outcomes = (0 until NativeAlertQueue.MAX_OUTCOMES + 3).map {
            RelayOutcome("wear-os-$it", it.toLong(), RelayOutcomeKind.CREATE_REJECTED)
        }

        val decoded = NativeAlertQueue.decodeOutcomes(NativeAlertQueue.encodeOutcomes(outcomes))

        assertEquals(NativeAlertQueue.MAX_OUTCOMES, decoded.size)
        assertEquals("wear-os-3", decoded.first().clientAlertId)
        assertTrue(NativeAlertQueue.decodeOutcomes("bad|line").isEmpty())
    }

    @Test
    fun `phone ids must use a safe charset`() {
        assertTrue(NativeAlertQueue.isSafeClientAlertId(uuidA))
        assertFalse(NativeAlertQueue.isSafeClientAlertId("a|b"))
        assertFalse(NativeAlertQueue.isSafeClientAlertId(""))
        assertFalse(NativeAlertQueue.isSafeClientAlertId("x".repeat(101)))
        assertNull(RelaySource.fromWireName("unknown"))
    }
}
