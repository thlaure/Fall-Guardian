package com.fallguardian

/**
 * Pure rules behind the alert screen and alert haptics, kept out of Compose
 * and the service so they are unit-tested on the JVM.
 */
object AlertUiPolicy {
    /** Deliberate press-and-hold duration, matching watchOS (ContentView.swift). */
    const val HOLD_TO_CANCEL_MS = 1_500

    /**
     * Font scale ceiling for alert text. Text still follows the wearer's
     * accessibility font size up to this factor, but never grows so far that
     * the countdown or cancel target is pushed off a small round screen.
     */
    const val MAX_FONT_SCALE = 1.3f

    /** Returns the sp value to request so the rendered size is capped. */
    fun cappedSp(baseSp: Float, fontScale: Float, maxScale: Float = MAX_FONT_SCALE): Float {
        if (fontScale <= 0f || !fontScale.isFinite()) return baseSp
        val effective = fontScale.coerceAtMost(maxScale)
        return baseSp * effective / fontScale
    }

    /**
     * Value screen readers announce for the countdown (through a polite live
     * region). Announcing every second would be noise and block other speech,
     * so it changes every 10 s above 10 s, then every second for the last 5 s.
     */
    fun countdownAnnouncementSeconds(remaining: Int): Int = when {
        remaining <= 0 -> 0
        remaining <= 5 -> remaining
        remaining <= 10 -> 10
        else -> ((remaining + 9) / 10) * 10
    }

    /**
     * One-shot vibration waveform for the rest of the countdown, played by the
     * foreground service so the wearer feels the alert even when the screen is
     * off or only the notification is visible. One pulse per second: short and
     * moderate above 10 s, long and full-strength in the last 10 s.
     */
    fun alertVibrationPattern(remainingSeconds: Int): VibrationPattern {
        val seconds = remainingSeconds.coerceIn(0, 30)
        val timings = ArrayList<Long>(seconds * 2)
        val amplitudes = ArrayList<Int>(seconds * 2)
        for (left in seconds downTo 1) {
            val urgent = left <= 10
            val pulse = if (urgent) 150L else 40L
            timings += pulse
            amplitudes += if (urgent) 255 else 80
            timings += 1_000L - pulse
            amplitudes += 0
        }
        return VibrationPattern(timings.toLongArray(), amplitudes.toIntArray())
    }
}

class VibrationPattern(val timingsMs: LongArray, val amplitudes: IntArray) {
    val isEmpty: Boolean get() = timingsMs.isEmpty()
}

/**
 * How the accelerometer is subscribed. Chosen by [AccelerometerPlan.choose]
 * from what the hardware reports, so the decision is testable on the JVM.
 */
data class AccelerometerPlan(
    val useWakeUpSensor: Boolean,
    val samplingPeriodUs: Int,
    val maxReportLatencyUs: Int
) {
    companion object {
        // 25 Hz gives four samples for the default 160 ms low-acceleration
        // window. 50 Hz would double FIFO fill rate and therefore AP wake-ups
        // whenever the FIFO, not the latency, limits batching; without device
        // measurements that cost is not justified, so 25 Hz is kept.
        const val SAMPLING_PERIOD_US = 40_000

        // Non-wake-up fallback (previous behaviour): short batches while the
        // CPU is awake; samples are dropped by the hub once the AP sleeps.
        const val NON_WAKE_UP_LATENCY_US = 500_000

        // Wake-up sensor: the sensor hub buffers samples in its FIFO and wakes
        // the AP at most once per batch to deliver them. Detection needs 2 s of
        // post-impact stillness anyway, so 5 s adds at most ~5 s to alert
        // latency while keeping sleep wake-ups to <= 0.2 per second.
        const val WAKE_UP_LATENCY_US = 5_000_000

        // Only the FIFO space *reserved* for this sensor is guaranteed
        // (fifoReservedEventCount); fifoMaxEventCount is shared with other
        // sensors. Less than 2 s of reserved buffer would wake the AP too
        // often (or per sample with none), so the previous non-wake-up setup
        // is kept in that case.
        const val MIN_WAKE_UP_BUFFER_US = 2_000_000L

        fun choose(wakeUpAvailable: Boolean, wakeUpFifoReservedEvents: Int): AccelerometerPlan {
            val bufferUs = wakeUpFifoReservedEvents.toLong() * SAMPLING_PERIOD_US
            return if (wakeUpAvailable && bufferUs >= MIN_WAKE_UP_BUFFER_US) {
                // Never ask to batch longer than the guaranteed buffer.
                val latencyUs = minOf(WAKE_UP_LATENCY_US.toLong(), bufferUs).toInt()
                AccelerometerPlan(true, SAMPLING_PERIOD_US, latencyUs)
            } else {
                AccelerometerPlan(false, SAMPLING_PERIOD_US, NON_WAKE_UP_LATENCY_US)
            }
        }
    }
}
