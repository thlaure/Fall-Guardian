package com.fallguardian

import java.time.Instant

/**
 * Where an incident queued in the native relay was detected. The wire name is
 * the API `detectionSource` value; the prefix keeps the legacy deterministic
 * clientAlertId derivation (`wear-os-<timestamp>`) used before watches sent an
 * incidentId.
 */
internal enum class RelaySource(val wireName: String, private val idPrefix: String) {
    WEAR_OS("wear_os", "wear-os-"),
    ASSISTED_PHONE("assisted_phone", "assisted-phone-");

    fun derivedClientAlertId(timestamp: Long): String = "$idPrefix$timestamp"

    companion object {
        fun fromWireName(value: String): RelaySource? =
            values().firstOrNull { it.wireName == value }
    }
}

/** One incident waiting for (or tracked after) backend delivery. */
internal data class QueuedAlert(
    val clientAlertId: String,
    val timestamp: Long,
    val source: RelaySource,
    val submitted: Boolean,
    val cancelRequested: Boolean,
    val enqueuedAt: Long
)

/** Terminal relay results Flutter imports into the local history screen. */
internal enum class RelayOutcomeKind(val wireName: String) {
    /** API rejected the incident permanently (400/422/...): never delivered. */
    CREATE_REJECTED("create_rejected"),
    /** Cancellation arrived after the server grace period: caregivers notified. */
    CANCEL_TOO_LATE("cancel_too_late"),
    /** Cancellation was rejected permanently; treat as possibly dispatched. */
    CANCEL_REJECTED("cancel_rejected"),
    /** Queue overflow or expiry removed an incident that was never delivered. */
    DROPPED("dropped");

    companion object {
        fun fromWireName(value: String): RelayOutcomeKind? =
            values().firstOrNull { it.wireName == value }
    }
}

internal data class RelayOutcome(
    val clientAlertId: String,
    val timestamp: Long,
    val kind: RelayOutcomeKind
)

internal data class EnqueueResult(
    val items: List<QueuedAlert>,
    val clientAlertId: String,
    val dropped: List<QueuedAlert>
)

/**
 * Pure, Android-free queue rules so JVM unit tests can prove migration,
 * deduplication, bounding and cancel matching without instrumentation.
 *
 * Storage format (SharedPreferences string): a `v2` header line followed by one
 * `clientAlertId|timestamp|source|submitted|cancelRequested|enqueuedAt` line
 * per incident. clientAlertIds are restricted to a safe charset, so `|` and
 * newlines can never appear inside a field.
 */
internal object NativeAlertQueue {
    const val MAX_ITEMS = 20
    const val MAX_OUTCOMES = 50
    const val LEGACY_DEDUP_WINDOW_MS = 30_000L
    /** Submitted, never-cancelled incidents are forgotten after the server
     * grace period is long over; nothing more can be done for them. */
    const val SUBMITTED_RETENTION_MS = 10 * 60_000L
    /** Undelivered incidents older than this are reported as dropped. */
    const val UNDELIVERED_RETENTION_MS = 24 * 60 * 60_000L

    private const val HEADER = "v2"
    private val SAFE_ID = Regex("^[A-Za-z0-9._:-]{1,100}$")

    fun isSafeClientAlertId(value: String): Boolean = SAFE_ID.matches(value)

    fun encode(items: List<QueuedAlert>): String = buildString {
        append(HEADER)
        items.forEach { item ->
            append('\n')
            append(item.clientAlertId).append('|')
            append(item.timestamp).append('|')
            append(item.source.wireName).append('|')
            append(if (item.submitted) '1' else '0').append('|')
            append(if (item.cancelRequested) '1' else '0').append('|')
            append(item.enqueuedAt)
        }
    }

    fun decode(raw: String?): List<QueuedAlert> {
        if (raw.isNullOrBlank()) return emptyList()
        val lines = raw.split('\n')
        if (lines.first() != HEADER) return emptyList()
        return lines.drop(1).mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 6) return@mapNotNull null
            val id = fields[0]
            val timestamp = fields[1].toLongOrNull()
            val source = RelaySource.fromWireName(fields[2])
            val enqueuedAt = fields[5].toLongOrNull()
            if (!isSafeClientAlertId(id) || timestamp == null || source == null ||
                enqueuedAt == null
            ) {
                return@mapNotNull null
            }
            QueuedAlert(
                clientAlertId = id,
                timestamp = timestamp,
                source = source,
                submitted = fields[3] == "1",
                cancelRequested = fields[4] == "1",
                enqueuedAt = enqueuedAt
            )
        }
    }

    /**
     * Converts the pre-queue single pending slot (always a Wear OS incident)
     * into a queue item so an unsent incident survives the app update.
     */
    fun migrateLegacy(
        timestamp: Long?,
        clientAlertId: String?,
        submitted: Boolean,
        cancelRequested: Boolean,
        now: Long
    ): List<QueuedAlert> {
        if (timestamp == null || clientAlertId.isNullOrBlank() ||
            !isSafeClientAlertId(clientAlertId)
        ) {
            return emptyList()
        }
        return listOf(
            QueuedAlert(
                clientAlertId = clientAlertId,
                timestamp = timestamp,
                source = RelaySource.WEAR_OS,
                submitted = submitted,
                cancelRequested = cancelRequested,
                enqueuedAt = now
            )
        )
    }

    /**
     * Adds an incident unless it is a duplicate transport of one already
     * queued. [requestedId] is the watch incidentId (already validated) or the
     * Flutter-generated id; when absent the legacy derivation and its 30 s
     * re-trigger window apply.
     */
    fun enqueue(
        items: List<QueuedAlert>,
        timestamp: Long,
        requestedId: String?,
        source: RelaySource,
        now: Long
    ): EnqueueResult {
        val duplicate = items.firstOrNull { item ->
            (requestedId != null && item.clientAlertId == requestedId) ||
                (item.source == source && item.timestamp == timestamp)
        }
        if (duplicate != null) {
            return EnqueueResult(items, duplicate.clientAlertId, emptyList())
        }

        if (requestedId == null) {
            // Legacy watches re-send the same physical fall as several
            // sensor triggers; only an uncancelled incident may absorb them.
            val active = items
                .filter { it.source == source && !it.cancelRequested }
                .maxByOrNull { it.timestamp }
            if (active != null && timestamp - active.timestamp in 0..LEGACY_DEDUP_WINDOW_MS) {
                return EnqueueResult(items, active.clientAlertId, emptyList())
            }
        }

        val clientAlertId = requestedId ?: source.derivedClientAlertId(timestamp)
        val added = items + QueuedAlert(
            clientAlertId = clientAlertId,
            timestamp = timestamp,
            source = source,
            submitted = false,
            cancelRequested = false,
            enqueuedAt = now
        )
        val (bounded, dropped) = bound(added)
        return EnqueueResult(bounded, clientAlertId, dropped)
    }

    /**
     * Marks the cancellation target. With an incidentId and/or fall timestamp
     * only the matching incident is cancelled; without either (legacy watch
     * or phone) the most recent uncancelled incident is.
     */
    fun requestCancel(
        items: List<QueuedAlert>,
        incidentId: String?,
        fallTimestamp: Long?
    ): List<QueuedAlert> {
        val normalizedId = incidentId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedId != null || fallTimestamp != null) {
            return items.map { item ->
                val matches = (normalizedId != null &&
                    (item.clientAlertId == normalizedId ||
                        item.clientAlertId == normalizedId.lowercase())) ||
                    (fallTimestamp != null && item.timestamp == fallTimestamp)
                if (matches) item.copy(cancelRequested = true) else item
            }
        }

        val latest = items.filter { !it.cancelRequested }.maxByOrNull { it.timestamp }
            ?: return items
        return items.map {
            if (it.clientAlertId == latest.clientAlertId) it.copy(cancelRequested = true) else it
        }
    }

    fun markSubmitted(items: List<QueuedAlert>, clientAlertId: String): List<QueuedAlert> =
        items.map { if (it.clientAlertId == clientAlertId) it.copy(submitted = true) else it }

    fun remove(items: List<QueuedAlert>, clientAlertId: String): List<QueuedAlert> =
        items.filterNot { it.clientAlertId == clientAlertId }

    /** Returns the kept items and the undelivered ones that expired. */
    fun prune(items: List<QueuedAlert>, now: Long): Pair<List<QueuedAlert>, List<QueuedAlert>> {
        val expired = mutableListOf<QueuedAlert>()
        val kept = items.filter { item ->
            val age = now - item.enqueuedAt
            when {
                item.submitted && !item.cancelRequested && age > SUBMITTED_RETENTION_MS -> false
                age > UNDELIVERED_RETENTION_MS -> {
                    if (!item.submitted && !item.cancelRequested) expired += item
                    false
                }
                else -> true
            }
        }
        return kept to expired
    }

    /**
     * Keeps at most [MAX_ITEMS]. Already-submitted, uncancelled incidents are
     * evicted first (the backend already owns them); otherwise the oldest goes
     * and is reported so history shows it was never delivered.
     */
    private fun bound(items: List<QueuedAlert>): Pair<List<QueuedAlert>, List<QueuedAlert>> {
        var current = items
        val dropped = mutableListOf<QueuedAlert>()
        while (current.size > MAX_ITEMS) {
            val victim = current
                .filter { it.submitted && !it.cancelRequested }
                .minByOrNull { it.timestamp }
                ?: current.minBy { it.timestamp }.also { dropped += it }
            current = current - victim
        }
        return current to dropped
    }

    fun encodeOutcomes(outcomes: List<RelayOutcome>): String =
        outcomes.takeLast(MAX_OUTCOMES).joinToString("\n") {
            "${it.clientAlertId}|${it.timestamp}|${it.kind.wireName}"
        }

    fun decodeOutcomes(raw: String?): List<RelayOutcome> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split('\n').mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 3) return@mapNotNull null
            val timestamp = fields[1].toLongOrNull() ?: return@mapNotNull null
            val kind = RelayOutcomeKind.fromWireName(fields[2]) ?: return@mapNotNull null
            if (!isSafeClientAlertId(fields[0])) return@mapNotNull null
            RelayOutcome(fields[0], timestamp, kind)
        }
    }
}

internal enum class RelayOperation { CREATE, CREATE_CANCELLED, CANCEL }

internal enum class RelayHttpOutcome {
    SUCCESS,
    /** Nothing left to do (duplicate create, or cancel target already gone). */
    ALREADY_DONE,
    /** Server grace period is over; caregivers are being notified. */
    TOO_LATE,
    /** Device credentials were revoked/unknown: the user must re-pair. */
    REAUTH_REQUIRED,
    RETRY,
    /** Permanent client error; retrying can never succeed. */
    REJECTED
}

/**
 * Pure formatting and HTTP status policy kept independent from Android
 * services so JVM tests can verify idempotency, payloads and retry rules.
 */
internal object NativeAlertRelayPolicy {
    private val UUID = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    )

    /** Legacy derivation kept for watches that do not send an incidentId. */
    fun clientAlertId(timestamp: Long): String =
        RelaySource.WEAR_OS.derivedClientAlertId(timestamp)

    /**
     * Watch-generated incident ids are lowercase UUIDs (36 chars), which fit
     * the API clientAlertId constraint (NotBlank, max 100). Anything else is
     * ignored and the caller falls back to the legacy derivation.
     */
    fun normalizedIncidentId(raw: String?): String? {
        val candidate = raw?.trim()?.lowercase() ?: return null
        return candidate.takeIf { UUID.matches(it) }
    }

    fun outcomeFor(operation: RelayOperation, status: Int): RelayHttpOutcome = when {
        status in 200..299 -> RelayHttpOutcome.SUCCESS
        status == 401 || status == 403 -> RelayHttpOutcome.REAUTH_REQUIRED
        status <= 0 || status == 408 || status == 429 || status >= 500 -> RelayHttpOutcome.RETRY
        status == 409 -> if (operation == RelayOperation.CREATE) {
            RelayHttpOutcome.ALREADY_DONE
        } else {
            RelayHttpOutcome.TOO_LATE
        }
        status == 404 && operation == RelayOperation.CANCEL -> RelayHttpOutcome.ALREADY_DONE
        else -> RelayHttpOutcome.REJECTED
    }

    fun createPayload(
        clientAlertId: String,
        timestamp: Long,
        locale: String,
        source: RelaySource = RelaySource.WEAR_OS,
        cancelled: Boolean = false
    ): String {
        val safeLocale = locale.take(8).ifBlank { "en" }
        return buildString {
            append('{')
            append("\"clientAlertId\":\"").append(jsonEscape(clientAlertId)).append("\",")
            append("\"fallTimestamp\":\"").append(Instant.ofEpochMilli(timestamp)).append("\",")
            append("\"locale\":\"").append(jsonEscape(safeLocale)).append("\",")
            append("\"latitude\":null,\"longitude\":null,")
            if (cancelled) append("\"cancelled\":true,")
            append("\"revision\":1,")
            append("\"detectionSource\":\"").append(source.wireName).append("\",")
            append("\"resolution\":\"unknown\"")
            append('}')
        }
    }

    private fun jsonEscape(value: String): String = buildString {
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (character.code < 0x20) {
                        append("\\u%04x".format(character.code))
                    } else {
                        append(character)
                    }
                }
            }
        }
    }
}
