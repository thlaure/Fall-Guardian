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

class AccelerometerPlanTest {
    @Test fun `uses wake-up accelerometer with long FIFO batches when the hub can buffer`() {
        val plan = AccelerometerPlan.choose(wakeUpAvailable = true, wakeUpFifoReservedEvents = 3_000)
        assertEquals(AccelerometerPlan(true, 40_000, 5_000_000), plan)
    }

    @Test fun `reserved FIFO of exactly two seconds is accepted with a matching batch`() {
        // 50 * 40 ms = 2 s: batch no longer than the guaranteed buffer.
        assertEquals(AccelerometerPlan(true, 40_000, 2_000_000), AccelerometerPlan.choose(true, 50))
        assertFalse(AccelerometerPlan.choose(true, 49).useWakeUpSensor)
        // 100 events = 4 s reserved: 4 s batch, below the 5 s cap.
        assertEquals(4_000_000, AccelerometerPlan.choose(true, 100).maxReportLatencyUs)
    }

    @Test fun `falls back to previous non-wake-up behaviour`() {
        val previous = AccelerometerPlan(false, 40_000, 500_000)
        assertEquals(previous, AccelerometerPlan.choose(wakeUpAvailable = false, wakeUpFifoReservedEvents = 3_000))
        // No reserved FIFO (the shared max FIFO is not guaranteed): a wake-up
        // sensor could wake the CPU for every sample.
        assertEquals(previous, AccelerometerPlan.choose(wakeUpAvailable = true, wakeUpFifoReservedEvents = 0))
    }

    @Test fun `sampling stays at 25 Hz so the 160 ms window has four samples`() {
        val plan = AccelerometerPlan.choose(true, 3_000)
        assertEquals(4, 160_000 / plan.samplingPeriodUs)
    }
}
