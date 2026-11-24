package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

class NativeAlertRelayPolicyTest {
    private val uuid = "3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f"

    @Test
    fun `client alert id is deterministic for native and Flutter retries`() {
        assertEquals(
            "wear-os-1710000000123",
            NativeAlertRelayPolicy.clientAlertId(1710000000123)
        )
    }

    @Test
    fun `payload identifies Wear OS source and UTC timestamp`() {
        val payload = NativeAlertRelayPolicy.createPayload(
            clientAlertId = "wear-os-1710000000123",
            timestamp = 1710000000123,
            locale = "fr"
        )

        assertTrue(payload.contains("\"clientAlertId\":\"wear-os-1710000000123\""))
        assertTrue(payload.contains("\"fallTimestamp\":\"2024-03-09T16:00:00.123Z\""))
        assertTrue(payload.contains("\"locale\":\"fr\""))
        assertTrue(payload.contains("\"detectionSource\":\"wear_os\""))
        assertTrue(payload.contains("\"resolution\":\"unknown\""))
        assertFalse(payload.contains("cancelled"))
        assertFalse(payload.contains("deviceToken"))
    }

    @Test
    fun `phone originated cancelled payload records the cancellation`() {
        val payload = NativeAlertRelayPolicy.createPayload(
            clientAlertId = uuid,
            timestamp = 0,
            locale = "en",
            source = RelaySource.ASSISTED_PHONE,
            cancelled = true
        )

        assertTrue(payload.contains("\"cancelled\":true"))
        assertTrue(payload.contains("\"detectionSource\":\"assisted_phone\""))
    }

    @Test
    fun `payload constrains and escapes locale`() {
        val payload = NativeAlertRelayPolicy.createPayload(
            clientAlertId = "id\"quoted",
            timestamp = 0,
            locale = "fr\nFR-too-long"
        )

        assertTrue(payload.contains("\"clientAlertId\":\"id\\\"quoted\""))
        assertTrue(payload.contains("\"locale\":\"fr\\nFR-to\""))
    }

    @Test
    fun `only valid UUID incident ids are used as client alert ids`() {
        assertEquals(uuid, NativeAlertRelayPolicy.normalizedIncidentId(uuid))
        assertEquals(uuid, NativeAlertRelayPolicy.normalizedIncidentId(" ${uuid.uppercase()} "))
        assertNull(NativeAlertRelayPolicy.normalizedIncidentId(null))
        assertNull(NativeAlertRelayPolicy.normalizedIncidentId(""))
        assertNull(NativeAlertRelayPolicy.normalizedIncidentId("not-a-uuid"))
        assertNull(NativeAlertRelayPolicy.normalizedIncidentId("$uuid-extra"))
    }

    @Test
    fun `successful statuses succeed for every operation`() {
        RelayOperation.values().forEach {
            assertEquals(RelayHttpOutcome.SUCCESS, NativeAlertRelayPolicy.outcomeFor(it, 200))
            assertEquals(RelayHttpOutcome.SUCCESS, NativeAlertRelayPolicy.outcomeFor(it, 201))
        }
    }

    @Test
    fun `only 401 requires re-pairing, 403 is retried`() {
        RelayOperation.values().forEach {
            assertEquals(RelayHttpOutcome.REAUTH_REQUIRED, NativeAlertRelayPolicy.outcomeFor(it, 401))
            assertEquals(RelayHttpOutcome.RETRY, NativeAlertRelayPolicy.outcomeFor(it, 403))
        }
    }

    @Test
    fun `transient failures are retried`() {
        listOf(0, -1, 408, 429, 500, 502, 503).forEach {
            assertEquals(
                RelayHttpOutcome.RETRY,
                NativeAlertRelayPolicy.outcomeFor(RelayOperation.CREATE, it)
            )
        }
    }

    @Test
    fun `conflict is a duplicate success on create and too late on cancel`() {
        assertEquals(
            RelayHttpOutcome.ALREADY_DONE,
            NativeAlertRelayPolicy.outcomeFor(RelayOperation.CREATE, 409)
        )
        assertEquals(
            RelayHttpOutcome.TOO_LATE,
            NativeAlertRelayPolicy.outcomeFor(RelayOperation.CANCEL, 409)
        )
        assertEquals(
            RelayHttpOutcome.TOO_LATE,
            NativeAlertRelayPolicy.outcomeFor(RelayOperation.CREATE_CANCELLED, 409)
        )
    }

    @Test
    fun `not found is done for cancel but a permanent failure for create`() {
        assertEquals(
            RelayHttpOutcome.ALREADY_DONE,
            NativeAlertRelayPolicy.outcomeFor(RelayOperation.CANCEL, 404)
        )
        assertEquals(
            RelayHttpOutcome.REJECTED,
            NativeAlertRelayPolicy.outcomeFor(RelayOperation.CREATE, 404)
        )
    }

    @Test
    fun `validation errors are permanent failures, never retried forever`() {
        listOf(400, 405, 410, 413, 415, 422).forEach {
            assertEquals(
                RelayHttpOutcome.REJECTED,
                NativeAlertRelayPolicy.outcomeFor(RelayOperation.CREATE, it)
            )
        }
    }

    @Test
    fun `legacy 8 byte fall message has no incident id`() {
        val data = ByteBuffer.allocate(8).putLong(1710000000123).array()

        assertEquals(WatchFall(1710000000123, null), WatchPayloads.parseFall(data))
    }

    private fun fallMessage(timestamp: Long, suffix: String): ByteArray =
        ByteBuffer.allocate(8).putLong(timestamp).array() + suffix.toByteArray(Charsets.UTF_8)

    @Test
    fun `fall message carries the watch incident id after the timestamp`() {
        assertEquals(
            WatchFall(1710000000123, uuid),
            WatchPayloads.parseFall(fallMessage(1710000000123, uuid))
        )
    }

    @Test
    fun `fall message with invalid incident id falls back to derivation`() {
        assertEquals(WatchFall(5, null), WatchPayloads.parseFall(fallMessage(5, "nope")))
        assertNull(WatchPayloads.parseFall(ByteArray(3)))
    }

    @Test
    fun `cancel message targets are optional`() {
        assertEquals(WatchCancelTarget(null, null), WatchPayloads.parseCancel(ByteArray(0)))
        assertEquals(
            WatchCancelTarget(uuid, 1710000000123),
            WatchPayloads.parseCancel(
                """{"event":"alert_cancelled","incidentId":"$uuid","fallTimestamp":1710000000123}"""
                    .toByteArray()
            )
        )
        assertEquals(
            WatchCancelTarget(null, null),
            WatchPayloads.parseCancel("not json".toByteArray())
        )
    }
}
