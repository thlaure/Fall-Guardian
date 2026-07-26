package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAlertRelayPolicyTest {
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
        assertFalse(payload.contains("deviceToken"))
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
}
