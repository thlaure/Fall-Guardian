package com.fallguardian

import java.nio.ByteBuffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertContractTest {
    private val id = "3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b"
    private val alert = ActiveAlert(id, 1_763_700_000_123L)

    @Test fun `incident ids are lowercase random uuids`() {
        val first = AlertContract.newIncidentId()
        val second = AlertContract.newIncidentId()
        assertTrue(AlertContract.isValidIncidentId(first))
        assertEquals(first.lowercase(), first)
        assertNotEquals(first, second)
        assertFalse(AlertContract.isValidIncidentId(first.uppercase()))
        assertFalse(AlertContract.isValidIncidentId("not-a-uuid"))
        assertFalse(AlertContract.isValidIncidentId(null))
    }

    @Test fun `fall message keeps the legacy 8 byte timestamp prefix`() {
        val payload = AlertContract.fallMessagePayload(alert)
        // Phone builds without incident ids read exactly ByteBuffer.wrap(data).long.
        assertEquals(alert.fallTimestampMs, ByteBuffer.wrap(payload).long)
        assertEquals(8 + 36, payload.size)
        assertEquals(id, String(payload, 8, payload.size - 8, Charsets.UTF_8))
    }

    @Test fun `fall data item keeps legacy keys and adds incidentId`() {
        val fields = AlertContract.fallDataFields(alert, updatedAtMs = 1_763_700_000_500L)
        assertEquals(
            mapOf(
                "timestamp" to alert.fallTimestampMs,
                "updatedAt" to 1_763_700_000_500L,
                "incidentId" to id
            ),
            fields
        )
    }

    @Test fun `cancel payloads identify the incident and original fall time`() {
        val message = String(AlertContract.cancelMessagePayload(alert), Charsets.UTF_8)
        assertEquals(
            "{\"event\":\"alert_cancelled\",\"incidentId\":\"$id\",\"fallTimestamp\":${alert.fallTimestampMs}}",
            message
        )
        val fields = AlertContract.cancelDataFields(alert, cancelledAtMs = 1_763_700_009_000L)
        assertEquals(alert.fallTimestampMs, fields["timestamp"])   // fall time, not cancel time
        assertEquals(alert.fallTimestampMs, fields["fallTimestamp"])
        assertEquals(id, fields["incidentId"])
        assertEquals(1_763_700_009_000L, fields["cancelledAt"])
        assertEquals(1_763_700_009_000L, fields["updatedAt"])
    }

    @Test fun `watch cancel payload round trips through the phone cancel parser`() {
        val parsed = AlertContract.parsePhoneCancel(AlertContract.cancelMessagePayload(alert))
        assertEquals(PhoneCancel(id, alert.fallTimestampMs), parsed)
    }

    @Test fun `legacy and malformed phone cancels carry no identifiers`() {
        val legacy = "{\"event\":\"alert_cancelled\"}".toByteArray()
        assertEquals(PhoneCancel(null, null), AlertContract.parsePhoneCancel(legacy))
        assertEquals(PhoneCancel(null, null), AlertContract.parsePhoneCancel(ByteArray(0)))
        assertEquals(PhoneCancel(null, null), AlertContract.parsePhoneCancel(null))
        assertEquals(PhoneCancel(null, null), AlertContract.parsePhoneCancel(byteArrayOf(-1, -2, 0)))
        assertEquals(
            PhoneCancel(null, null),
            AlertContract.parsePhoneCancel("{\"incidentId\":\"zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz\",\"fallTimestamp\":1.5e3}".toByteArray())
        )
        assertEquals(
            PhoneCancel(null, null),
            AlertContract.parsePhoneCancel(("{\"incidentId\":\"$id\"" + " ".repeat(5_000) + "}").toByteArray())
        )
    }

    @Test fun `phone cancel parser accepts whitespace and uppercase ids`() {
        val json = "{ \"fallTimestamp\" : 42 , \"incidentId\" : \"${id.uppercase()}\" }"
        assertEquals(PhoneCancel(id, 42L), AlertContract.parsePhoneCancel(json.toByteArray()))
    }

    @Test fun `phone cancel closes only the matching active incident`() {
        val other = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        val accept = AlertContract::shouldAcceptPhoneCancel
        assertTrue(accept(alert, PhoneCancel(id, null)))
        assertTrue(accept(alert, PhoneCancel(id, 1L)))  // id wins over timestamp
        assertFalse(accept(alert, PhoneCancel(other, alert.fallTimestampMs)))
        assertTrue(accept(alert, PhoneCancel(null, alert.fallTimestampMs)))
        assertFalse(accept(alert, PhoneCancel(null, alert.fallTimestampMs - 1)))
        // Legacy phone build: no identifiers, accepted only while an alert is active.
        assertTrue(accept(alert, PhoneCancel(null, null)))
        assertFalse(accept(null, PhoneCancel(null, null)))
        assertFalse(accept(null, PhoneCancel(id, alert.fallTimestampMs)))
    }

    @Test fun `active alert is live only inside its 30 second window`() {
        assertEquals(alert.fallTimestampMs + 30_000L, alert.deadlineMs)
        assertFalse(alert.isLive(alert.fallTimestampMs - 1))
        assertTrue(alert.isLive(alert.fallTimestampMs))
        assertTrue(alert.isLive(alert.deadlineMs - 1))
        assertFalse(alert.isLive(alert.deadlineMs))
    }

    @Test fun `paths stay compatible with the phone manifest filters`() {
        assertEquals("/fall_event", AlertContract.FALL_PATH)
        assertEquals("/cancel_alert", AlertContract.CANCEL_PATH)
        assertArrayEquals(
            ByteBuffer.allocate(8).putLong(5L).array(),
            AlertContract.fallMessagePayload(ActiveAlert(id, 5L)).copyOf(8)
        )
    }
}

class ActiveAlertStoreTest {
    private class MapStorage : AlertStateStorage {
        val values = mutableMapOf<String, Any>()
        var writes = 0
        override fun getString(key: String) = values[key] as? String
        override fun getLong(key: String) = values[key] as? Long
        override fun write(values: Map<String, Any>?) {
            writes++
            this.values.clear()
            values?.let { this.values.putAll(it) }
        }
    }

    private val id = "3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b"
    private val alert = ActiveAlert(id, 1_000_000L)

    @Test fun `persists id fall timestamp and deadline`() {
        val storage = MapStorage()
        ActiveAlertStore(storage).save(alert)
        assertEquals(
            mapOf(
                ActiveAlertStore.KEY_ID to id,
                ActiveAlertStore.KEY_FALL_TS to 1_000_000L,
                ActiveAlertStore.KEY_DEADLINE to 1_030_000L
            ),
            storage.values
        )
    }

    @Test fun `restores an alert still inside its window after process restart`() {
        val storage = MapStorage()
        ActiveAlertStore(storage).save(alert)
        assertEquals(alert, ActiveAlertStore(storage).restore(nowMs = 1_029_999L))
    }

    @Test fun `expired alert is cleared instead of restored`() {
        val storage = MapStorage()
        ActiveAlertStore(storage).save(alert)
        assertNull(ActiveAlertStore(storage).restore(nowMs = 1_030_000L))
        assertTrue(storage.values.isEmpty())
    }

    @Test fun `alert from the future (clock change) is cleared`() {
        val storage = MapStorage()
        ActiveAlertStore(storage).save(alert)
        assertNull(ActiveAlertStore(storage).restore(nowMs = 999_999L))
        assertTrue(storage.values.isEmpty())
    }

    @Test fun `corrupt or partial state is cleared`() {
        val storage = MapStorage()
        storage.values.putAll(mapOf(ActiveAlertStore.KEY_ID to "bogus", ActiveAlertStore.KEY_FALL_TS to 1_000_000L))
        assertNull(ActiveAlertStore(storage).restore(1_000_001L))
        assertTrue(storage.values.isEmpty())

        storage.values.putAll(mapOf(
            ActiveAlertStore.KEY_ID to id,
            ActiveAlertStore.KEY_FALL_TS to 1_000_000L,
            ActiveAlertStore.KEY_DEADLINE to 9_999_999L   // tampered deadline
        ))
        assertNull(ActiveAlertStore(storage).restore(1_000_001L))
        assertTrue(storage.values.isEmpty())
    }

    @Test fun `empty storage restores nothing without writing`() {
        val storage = MapStorage()
        assertNull(ActiveAlertStore(storage).restore(1_000L))
        assertEquals(0, storage.writes)
    }

    @Test fun `clear removes the persisted alert`() {
        val storage = MapStorage()
        val store = ActiveAlertStore(storage)
        store.save(alert)
        store.clear()
        assertTrue(storage.values.isEmpty())
        assertNull(store.restore(1_000_001L))
    }
}
