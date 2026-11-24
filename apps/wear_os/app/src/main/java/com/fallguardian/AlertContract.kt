package com.fallguardian

import java.nio.ByteBuffer
import java.util.UUID

/**
 * Watch <-> phone Data Layer contract for one fall incident.
 *
 * Every confirmed fall gets an [ActiveAlert.incidentId] (lowercase random
 * UUID). Cancels carry that id plus the original fall timestamp so neither
 * side can close a newer incident with an old cancel.
 *
 * Backward compatibility with phone builds that predate incident ids:
 * - `/fall_event` message: the first 8 bytes stay the big-endian fall
 *   timestamp (old phones read only those); the incident id follows as UTF-8.
 * - `/fall_event` data item: keeps `timestamp` and `updatedAt`, adds
 *   `incidentId`.
 * - `/cancel_alert` message: JSON; old phones ignore the payload entirely.
 * - `/cancel_alert` data item: `timestamp` is now the fall timestamp (old
 *   phones ignore it), plus `incidentId`, `fallTimestamp`, `cancelledAt`.
 *
 * Pure Kotlin, no Android types, so the contract is unit-tested on the JVM.
 */
object AlertContract {
    const val FALL_PATH = "/fall_event"
    const val CANCEL_PATH = "/cancel_alert"

    const val KEY_TIMESTAMP = "timestamp"
    const val KEY_UPDATED_AT = "updatedAt"
    const val KEY_INCIDENT_ID = "incidentId"
    const val KEY_FALL_TIMESTAMP = "fallTimestamp"
    const val KEY_CANCELLED_AT = "cancelledAt"

    private val INCIDENT_ID_PATTERN =
        Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

    // Phone payloads are untrusted input: only an exact UUID-shaped value or a
    // plain non-negative integer is extracted; everything else is ignored.
    private val JSON_INCIDENT_ID =
        Regex("\"incidentId\"\\s*:\\s*\"([0-9A-Fa-f-]{36})\"")
    private val JSON_FALL_TIMESTAMP =
        Regex("\"fallTimestamp\"\\s*:\\s*(\\d{1,19})(?![\\d.eE])")

    fun newIncidentId(): String = UUID.randomUUID().toString().lowercase()

    fun isValidIncidentId(value: String?): Boolean =
        value != null && INCIDENT_ID_PATTERN.matches(value)

    /** 8-byte big-endian timestamp followed by the UTF-8 incident id. */
    fun fallMessagePayload(alert: ActiveAlert): ByteArray {
        val id = alert.incidentId.toByteArray(Charsets.UTF_8)
        return ByteBuffer.allocate(8 + id.size)
            .putLong(alert.fallTimestampMs)
            .put(id)
            .array()
    }

    fun fallDataFields(alert: ActiveAlert, updatedAtMs: Long): Map<String, Any> = linkedMapOf(
        KEY_TIMESTAMP to alert.fallTimestampMs,
        KEY_UPDATED_AT to updatedAtMs,
        KEY_INCIDENT_ID to alert.incidentId
    )

    fun cancelMessagePayload(alert: ActiveAlert): ByteArray =
        ("{\"event\":\"alert_cancelled\"," +
            "\"incidentId\":\"${alert.incidentId}\"," +
            "\"fallTimestamp\":${alert.fallTimestampMs}}")
            .toByteArray(Charsets.UTF_8)

    fun cancelDataFields(alert: ActiveAlert, cancelledAtMs: Long): Map<String, Any> = linkedMapOf(
        KEY_TIMESTAMP to alert.fallTimestampMs,
        KEY_UPDATED_AT to cancelledAtMs,
        KEY_INCIDENT_ID to alert.incidentId,
        KEY_FALL_TIMESTAMP to alert.fallTimestampMs,
        KEY_CANCELLED_AT to cancelledAtMs
    )

    /** Parses a phone `/cancel_alert` message payload (JSON or empty). */
    fun parsePhoneCancel(payload: ByteArray?): PhoneCancel {
        if (payload == null || payload.isEmpty() || payload.size > 4_096) {
            return PhoneCancel(null, null)
        }
        val text = String(payload, Charsets.UTF_8)
        val incidentId = JSON_INCIDENT_ID.find(text)?.groupValues?.get(1)?.lowercase()
            ?.takeIf { isValidIncidentId(it) }
        val fallTimestamp = JSON_FALL_TIMESTAMP.find(text)?.groupValues?.get(1)?.toLongOrNull()
        return PhoneCancel(incidentId, fallTimestamp)
    }

    /**
     * Decides whether a phone cancel may close [active].
     * - No active alert: nothing to close.
     * - Cancel names an incident: it must be the active one.
     * - Cancel names only a fall timestamp: it must be the active fall.
     * - Legacy cancel (neither): accepted while an alert is active.
     */
    fun shouldAcceptPhoneCancel(active: ActiveAlert?, cancel: PhoneCancel): Boolean {
        if (active == null) return false
        if (cancel.incidentId != null) return cancel.incidentId == active.incidentId
        if (cancel.fallTimestampMs != null) return cancel.fallTimestampMs == active.fallTimestampMs
        return true
    }
}

/**
 * One reading of the three clocks used by the alert.
 * - [wallMs]: System.currentTimeMillis(), shared with the phone, but can jump
 *   (user/network time changes).
 * - [elapsedMs]: SystemClock.elapsedRealtime(), monotonic since boot.
 * - [bootCount]: Settings.Global.BOOT_COUNT (null when unavailable); elapsed
 *   time is only comparable within the same boot.
 */
data class ClockReading(val wallMs: Long, val elapsedMs: Long, val bootCount: Int?)

/**
 * The active incident. [fallTimestampMs] (wall clock) is what the phone
 * receives; the countdown itself runs on the monotonic clock anchored at
 * [detectedElapsedMs], so a wall-clock jump cannot end or extend it. After a
 * reboot (different boot count) elapsed time is meaningless and the wall
 * clock is used instead.
 */
data class ActiveAlert(
    val incidentId: String,
    val fallTimestampMs: Long,
    val detectedElapsedMs: Long = -1L,
    val bootCount: Int? = null
) {
    val deadlineMs: Long get() = fallTimestampMs + ALERT_WINDOW_MS

    /** Milliseconds since the fall, measured monotonically when possible. */
    fun elapsedSinceFallMs(now: ClockReading): Long =
        if (bootCount != null && detectedElapsedMs >= 0 && now.bootCount == bootCount) {
            now.elapsedMs - detectedElapsedMs
        } else {
            now.wallMs - fallTimestampMs
        }

    fun isLive(now: ClockReading): Boolean =
        elapsedSinceFallMs(now) in 0 until ALERT_WINDOW_MS

    fun remainingSeconds(now: ClockReading): Int =
        alertRemainingSecondsAfter(elapsedSinceFallMs(now))

    companion object {
        /**
         * Builds the alert for a fall detected at wall time [fallTimestampMs]
         * (possibly slightly in the past), anchoring the monotonic clock at the
         * same instant.
         */
        fun detected(incidentId: String, fallTimestampMs: Long, now: ClockReading): ActiveAlert {
            val ageMs = (now.wallMs - fallTimestampMs).coerceAtLeast(0L)
            return ActiveAlert(incidentId, fallTimestampMs, now.elapsedMs - ageMs, now.bootCount)
        }
    }
}

data class PhoneCancel(val incidentId: String?, val fallTimestampMs: Long?)

/**
 * Minimal key-value port so the active alert survives process death.
 * Production uses SharedPreferences; tests use a map.
 */
interface AlertStateStorage {
    fun getString(key: String): String?
    fun getLong(key: String): Long?
    fun write(values: Map<String, Any>?)
}

/**
 * Persists the active incident (id, wall fall timestamp, wall deadline,
 * monotonic anchor and boot count). Restores it only while the 30-second
 * window is still running; otherwise clears it.
 */
class ActiveAlertStore(private val storage: AlertStateStorage) {
    fun save(alert: ActiveAlert) {
        storage.write(
            buildMap {
                put(KEY_ID, alert.incidentId)
                put(KEY_FALL_TS, alert.fallTimestampMs)
                put(KEY_DEADLINE, alert.deadlineMs)
                put(KEY_DETECTED_ELAPSED, alert.detectedElapsedMs)
                alert.bootCount?.let { put(KEY_BOOT_COUNT, it.toLong()) }
            }
        )
    }

    fun clear() = storage.write(null)

    fun restore(now: ClockReading): ActiveAlert? {
        val id = storage.getString(KEY_ID)
        val timestamp = storage.getLong(KEY_FALL_TS)
        val deadline = storage.getLong(KEY_DEADLINE)
        val alert = if (AlertContract.isValidIncidentId(id) && timestamp != null && timestamp > 0) {
            ActiveAlert(
                id!!,
                timestamp,
                storage.getLong(KEY_DETECTED_ELAPSED) ?: -1L,
                storage.getLong(KEY_BOOT_COUNT)?.toInt()
            )
        } else {
            null
        }
        val live = alert != null && deadline == alert.deadlineMs && alert.isLive(now)
        if (!live) {
            if (id != null || timestamp != null || deadline != null) clear()
            return null
        }
        return alert
    }

    companion object {
        const val KEY_ID = "active_incident_id"
        const val KEY_FALL_TS = "active_fall_timestamp"
        const val KEY_DEADLINE = "active_deadline"
        const val KEY_DETECTED_ELAPSED = "active_detected_elapsed"
        const val KEY_BOOT_COUNT = "active_boot_count"
    }
}
