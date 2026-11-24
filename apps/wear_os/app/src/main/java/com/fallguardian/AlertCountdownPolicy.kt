package com.fallguardian

const val ALERT_WINDOW_MS = 30_000L

fun shouldStartAlert(alertActive: Boolean, timestamp: Long, now: Long): Boolean =
    !alertActive && timestamp > 0 && now >= timestamp && now - timestamp < ALERT_WINDOW_MS

fun alertRemainingSeconds(timestamp: Long, now: Long): Int {
    if (timestamp <= 0) return 0
    return alertRemainingSecondsAfter(now - timestamp)
}

/** Seconds left in the 30 s window after [elapsedMs]; 0 when outside it. */
fun alertRemainingSecondsAfter(elapsedMs: Long): Int {
    if (elapsedMs < 0) return 0
    val elapsedSeconds = elapsedMs / 1_000L
    return (30L - elapsedSeconds).coerceIn(0L, 30L).toInt()
}
