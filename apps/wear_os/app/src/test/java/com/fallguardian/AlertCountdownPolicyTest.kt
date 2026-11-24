package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertCountdownPolicyTest {
    @Test
    fun activeIncidentCannotRestartCountdown() {
        assertFalse(shouldStartAlert(true, 1_000L, 2_000L))
    }

    @Test
    fun freshIncidentStartsCountdown() {
        assertTrue(shouldStartAlert(false, 1_000L, 2_000L))
        assertEquals(29, alertRemainingSeconds(1_000L, 2_000L))
    }

    @Test
    fun expiredOrFutureIncidentCannotStart() {
        assertFalse(shouldStartAlert(false, 1_000L, 31_000L))
        assertFalse(shouldStartAlert(false, 2_000L, 1_000L))
        assertEquals(0, alertRemainingSeconds(1_000L, 31_000L))
    }

    @Test
    fun remainingSecondsAfterElapsedTime() {
        assertEquals(30, alertRemainingSecondsAfter(0L))
        assertEquals(30, alertRemainingSecondsAfter(999L))
        assertEquals(1, alertRemainingSecondsAfter(29_999L))
        assertEquals(0, alertRemainingSecondsAfter(30_000L))
        assertEquals(0, alertRemainingSecondsAfter(-1L))
        assertEquals(0, alertRemainingSeconds(0L, 5_000L))
    }
}
