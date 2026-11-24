package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertUiPolicyTest {
    @Test fun `hold to cancel matches the watchOS 1_5 second hold`() {
        assertEquals(1_500, AlertUiPolicy.HOLD_TO_CANCEL_MS)
    }

    @Test fun `text follows font scale up to the cap`() {
        assertEquals(56f, AlertUiPolicy.cappedSp(56f, 1.0f), 0.001f)
        assertEquals(56f, AlertUiPolicy.cappedSp(56f, 0.85f), 0.001f)  // smaller fonts honoured
        assertEquals(56f, AlertUiPolicy.cappedSp(56f, 1.3f), 0.001f)
        // At 2x system scale the rendered size is 56 * 1.3, not 56 * 2.
        val requested = AlertUiPolicy.cappedSp(56f, 2.0f)
        assertEquals(56f * 1.3f, requested * 2.0f, 0.001f)
        assertEquals(11f, AlertUiPolicy.cappedSp(11f, 0f), 0.001f)
        assertEquals(11f, AlertUiPolicy.cappedSp(11f, Float.NaN), 0.001f)
    }

    @Test fun `countdown announcements change at milestones only`() {
        val announced = (30 downTo 0).map(AlertUiPolicy::countdownAnnouncementSeconds)
        assertEquals(listOf(30, 20, 10, 5, 4, 3, 2, 1, 0), announced.distinct())
        assertEquals(30, AlertUiPolicy.countdownAnnouncementSeconds(21))
        assertEquals(20, AlertUiPolicy.countdownAnnouncementSeconds(11))
        assertEquals(10, AlertUiPolicy.countdownAnnouncementSeconds(6))
        assertEquals(0, AlertUiPolicy.countdownAnnouncementSeconds(-3))
    }

    @Test fun `vibration pattern pulses once per remaining second and escalates`() {
        val pattern = AlertUiPolicy.alertVibrationPattern(12)
        assertEquals(24, pattern.timingsMs.size)
        assertEquals(pattern.timingsMs.size, pattern.amplitudes.size)
        assertEquals(12_000L, pattern.timingsMs.sum())
        // Seconds 12 and 11: short moderate pulses.
        assertEquals(40L, pattern.timingsMs[0]); assertEquals(80, pattern.amplitudes[0])
        assertEquals(0, pattern.amplitudes[1])
        // From 10 s left: long full-strength pulses.
        assertEquals(150L, pattern.timingsMs[4]); assertEquals(255, pattern.amplitudes[4])
        assertTrue(pattern.amplitudes.filterIndexed { i, _ -> i % 2 == 1 }.all { it == 0 })
    }

    @Test fun `vibration pattern is bounded to the countdown`() {
        assertTrue(AlertUiPolicy.alertVibrationPattern(0).isEmpty)
        assertTrue(AlertUiPolicy.alertVibrationPattern(-5).isEmpty)
        assertEquals(30_000L, AlertUiPolicy.alertVibrationPattern(99).timingsMs.sum())
        assertFalse(AlertUiPolicy.alertVibrationPattern(1).isEmpty)
    }
}

