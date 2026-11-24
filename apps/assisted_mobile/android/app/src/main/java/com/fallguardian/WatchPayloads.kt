package com.fallguardian

import java.nio.ByteBuffer

internal data class WatchFall(val timestamp: Long, val incidentId: String?)

internal data class WatchCancelTarget(val incidentId: String?, val fallTimestamp: Long?)

/**
 * Parses Wear OS MessageClient payloads (untrusted input).
 *
 * Contract, backward compatible:
 * - `/fall_event`: 8-byte big-endian epoch-millis timestamp, optionally
 *   followed by the UTF-8 watch `incidentId` (lowercase UUID) in bytes 8..end.
 * - `/cancel_alert`: legacy empty payload (cancel the current incident), or a
 *   UTF-8 JSON object `{"incidentId": "<uuid>", "fallTimestamp": <ms>}`.
 *
 * Only flat scalar fields are needed, so a strict field extractor is used
 * instead of org.json to keep this JVM-testable.
 */
internal object WatchPayloads {
    private const val MAX_JSON_BYTES = 1024

    fun parseFall(data: ByteArray): WatchFall? {
        if (data.size < Long.SIZE_BYTES) return null
        val timestamp = ByteBuffer.wrap(data, 0, Long.SIZE_BYTES).long
        val incidentId = if (data.size > Long.SIZE_BYTES && data.size <= MAX_JSON_BYTES) {
            NativeAlertRelayPolicy.normalizedIncidentId(
                String(data, Long.SIZE_BYTES, data.size - Long.SIZE_BYTES, Charsets.UTF_8)
            )
        } else {
            null
        }
        return WatchFall(timestamp, incidentId)
    }

    fun parseCancel(data: ByteArray): WatchCancelTarget {
        val json = decodeJson(data) ?: return WatchCancelTarget(null, null)
        return WatchCancelTarget(
            NativeAlertRelayPolicy.normalizedIncidentId(stringField(json, "incidentId")),
            longField(json, "fallTimestamp")
        )
    }

    private fun decodeJson(data: ByteArray): String? {
        if (data.isEmpty() || data.size > MAX_JSON_BYTES) return null
        val text = String(data, Charsets.UTF_8).trim()
        return text.takeIf { it.startsWith("{") && it.endsWith("}") }
    }

    private fun stringField(json: String, name: String): String? =
        Regex("\"${Regex.escape(name)}\"\\s*:\\s*\"([^\"\\\\]{0,100})\"")
            .find(json)?.groupValues?.get(1)

    private fun longField(json: String, name: String): Long? =
        Regex("\"${Regex.escape(name)}\"\\s*:\\s*(-?\\d{1,19})(?![\\d.])")
            .find(json)?.groupValues?.get(1)?.toLongOrNull()
}

/** Which incident the native wake-up notification currently shows. */
internal data class DisplayedFallNotification(
    val clientAlertId: String,
    val watchIncidentId: String?,
    val timestamp: Long
)

/**
 * Decides whether a watch cancel may remove the fall notification. A
 * delayed, targeted cancel for incident A must never remove the notification
 * of a newer incident B; only legacy untargeted cancels dismiss
 * unconditionally. Pure Kotlin for JVM tests.
 */
internal object FallNotificationPolicy {
    private val SAFE = Regex("^[A-Za-z0-9._:-]{1,100}$")

    fun shouldDismiss(
        displayed: DisplayedFallNotification?,
        incidentId: String?,
        fallTimestamp: Long?
    ): Boolean {
        if (incidentId == null && fallTimestamp == null) return true
        // Unknown displayed incident: keep it rather than risk hiding a
        // different, still-active fall.
        if (displayed == null) return false
        val id = incidentId?.lowercase()
        return (id != null &&
            (id == displayed.clientAlertId.lowercase() || id == displayed.watchIncidentId)) ||
            (fallTimestamp != null && fallTimestamp == displayed.timestamp)
    }

    fun encode(displayed: DisplayedFallNotification): String =
        "${displayed.clientAlertId}|${displayed.watchIncidentId.orEmpty()}|${displayed.timestamp}"

    fun decode(raw: String?): DisplayedFallNotification? {
        val fields = raw?.split('|') ?: return null
        if (fields.size != 3 || !SAFE.matches(fields[0])) return null
        val timestamp = fields[2].toLongOrNull() ?: return null
        return DisplayedFallNotification(
            fields[0],
            fields[1].takeIf { it.isNotEmpty() && SAFE.matches(it) },
            timestamp
        )
    }
}
