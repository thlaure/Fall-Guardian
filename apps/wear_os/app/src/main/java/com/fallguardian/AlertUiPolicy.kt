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

