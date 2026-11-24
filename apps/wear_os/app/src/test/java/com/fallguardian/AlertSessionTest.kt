package com.fallguardian

import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertSessionTest {
    private class MapStorage : AlertStateStorage {
        val values = mutableMapOf<String, Any>()
        override fun getString(key: String) = values[key] as? String
        override fun getLong(key: String) = values[key] as? Long
        override fun write(values: Map<String, Any>?) {
            this.values.clear()
            values?.let { this.values.putAll(it) }
        }
    }

    private val ids = ArrayDeque(listOf(
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222"
    ))
    private val storage = MapStorage()
    private fun session(store: MapStorage = storage) =
        AlertSession(ActiveAlertStore(store)) { ids.removeFirst() }

    private val fallWall = 1_763_700_000_000L
    private fun at(offsetMs: Long, boot: Int? = 5) =
        ClockReading(fallWall + offsetMs, 100_000L + offsetMs, boot)

    private fun paths(effects: List<AlertEffect>) = effects.map {
        when (it) {
            is AlertEffect.SendMessage -> "send ${it.path}"
            is AlertEffect.PutDataItem -> "put ${it.path}"
            is AlertEffect.DeleteDataItem -> "delete ${it.path}"
            is AlertEffect.Present -> "present ${it.presentation}"
        }
    }

    @Test fun `fall deletes stale cancel before queuing the fall and persists first`() {
        val s = session()
        val effects = s.onFallDetected(fallWall, at(0))
        assertEquals(
            listOf("delete /cancel_alert", "send /fall_event", "put /fall_event", "present SHOW"),
            paths(effects)
        )
        val alert = s.active!!
        assertEquals("11111111-1111-4111-8111-111111111111", alert.incidentId)
        assertEquals(alert.incidentId, storage.values[ActiveAlertStore.KEY_ID])
        val put = effects[2] as AlertEffect.PutDataItem
        assertEquals(fallWall, put.fields["timestamp"])
        assertEquals(alert.incidentId, put.fields["incidentId"])
        val send = effects[1] as AlertEffect.SendMessage
        assertEquals(fallWall, ByteBuffer.wrap(send.payload).long)
    }

    @Test fun `repeated detection during an alert does not restart it`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        assertEquals(emptyList<AlertEffect>(), s.onFallDetected(fallWall + 3_000, at(3_000)))
        assertEquals("11111111-1111-4111-8111-111111111111", s.active!!.incidentId)
    }

    @Test fun `stale or future detections are ignored`() {
        val s = session()
        assertEquals(emptyList<AlertEffect>(), s.onFallDetected(fallWall, at(30_000)))
        assertEquals(emptyList<AlertEffect>(), s.onFallDetected(fallWall + 1, at(0)))
        assertNull(s.active)
    }

    @Test fun `watch cancel clears state then deletes the fall before queuing the cancel`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        val effects = s.onWatchCancel(at(4_000))
        assertEquals(
            listOf("present DISMISS_CONFIRMED", "send /cancel_alert", "delete /fall_event", "put /cancel_alert"),
            paths(effects)
        )
        assertTrue(storage.values.isEmpty())
        assertNull(s.active)
        val put = effects[3] as AlertEffect.PutDataItem
        assertEquals("11111111-1111-4111-8111-111111111111", put.fields["incidentId"])
        assertEquals(fallWall, put.fields["fallTimestamp"])
        assertEquals(fallWall + 4_000, put.fields["cancelledAt"])
        assertEquals(emptyList<AlertEffect>(), s.onWatchCancel(at(5_000)))
    }

    @Test fun `phone cancel for another incident is ignored, matching one dismisses`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        val other = PhoneCancel("22222222-2222-4222-8222-222222222222", null)
        assertEquals(emptyList<AlertEffect>(), s.onPhoneCancel(other))
        assertNotEquals(null, s.active)

        val mine = PhoneCancel("11111111-1111-4111-8111-111111111111", fallWall)
        assertEquals(listOf("present DISMISS"), paths(s.onPhoneCancel(mine)))
        assertNull(s.active)
        assertTrue(storage.values.isEmpty())
        // Legacy cancel with nothing active: ignored.
        assertEquals(emptyList<AlertEffect>(), s.onPhoneCancel(PhoneCancel(null, null)))
    }

    @Test fun `countdown ticks then expires and keeps the fall queued for the phone`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        assertEquals(30, s.remainingSeconds(at(0)))
        assertEquals(emptyList<AlertEffect>(), s.onTick(at(29_999)))
        assertEquals(1, s.remainingSeconds(at(29_999)))
        assertEquals(listOf("present DISMISS"), paths(s.onTick(at(30_000))))
        assertNull(s.active)
        assertEquals(0, s.remainingSeconds(at(30_000)))
        assertTrue(storage.values.isEmpty())
        assertEquals(emptyList<AlertEffect>(), s.onTick(at(31_000)))
    }

    @Test fun `wall clock moving backwards does not end the countdown`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        val jumpedBack = ClockReading(fallWall - 3_600_000L, 100_000L + 2_000L, 5)
        assertEquals(emptyList<AlertEffect>(), s.onTick(jumpedBack))
        assertEquals(28, s.remainingSeconds(jumpedBack))
    }

    @Test fun `restore after process death resends the same incident`() {
        session().onFallDetected(fallWall, at(0))
        // New process: fresh session over the same storage.
        val restarted = session()
        val effects = restarted.restore(at(10_000))
        assertEquals(
            listOf("delete /cancel_alert", "send /fall_event", "put /fall_event", "present SHOW"),
            paths(effects)
        )
        assertEquals("11111111-1111-4111-8111-111111111111", restarted.active!!.incidentId)
        val put = effects[2] as AlertEffect.PutDataItem
        assertEquals("11111111-1111-4111-8111-111111111111", put.fields["incidentId"])
        assertEquals(fallWall, put.fields["timestamp"])          // original fall time
        assertEquals(fallWall + 10_000, put.fields["updatedAt"]) // fresh change marker
        assertEquals(20, restarted.remainingSeconds(at(10_000)))
    }

    @Test fun `restore while alive only re-announces without resending`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        assertEquals(listOf("present SHOW"), paths(s.restore(at(2_000))))
    }

    @Test fun `nothing is restored or resent after a cancel or expiry`() {
        val s = session()
        s.onFallDetected(fallWall, at(0))
        s.onWatchCancel(at(1_000))
        assertEquals(emptyList<AlertEffect>(), session().restore(at(2_000)))

        val other = MapStorage()
        session(other).onFallDetected(fallWall, at(0))
        assertEquals(emptyList<AlertEffect>(), session(other).restore(at(30_000)))
        assertTrue(other.values.isEmpty())
    }

    @Test fun `restore after a reboot falls back to the wall clock`() {
        session().onFallDetected(fallWall, at(0, boot = 5))
        val afterReboot = ClockReading(fallWall + 12_000L, 3_000L, 6)
        val restarted = session()
        assertEquals("present SHOW", paths(restarted.restore(afterReboot)).last())
        assertEquals(18, restarted.remainingSeconds(afterReboot))
    }

    @Test fun `message effects compare by payload content`() {
        val a = AlertEffect.SendMessage("/p", byteArrayOf(1, 2))
        assertEquals(a, AlertEffect.SendMessage("/p", byteArrayOf(1, 2)))
        assertEquals(a.hashCode(), AlertEffect.SendMessage("/p", byteArrayOf(1, 2)).hashCode())
        assertNotEquals(a, AlertEffect.SendMessage("/p", byteArrayOf(1, 3)))
        assertTrue(!a.equals("/p"))
    }
}
