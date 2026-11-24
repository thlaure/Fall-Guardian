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

/**
 * One incident waiting for (or tracked after) backend delivery.
 *
 * [aliases] holds other ids the same physical incident is known by — e.g. a
 * watch UUID that arrived on a second transport after the incident had
 * already been queued under its legacy `wear-os-<ts>` id. Cancels naming any
 * alias target this incident.
 */
internal data class QueuedAlert(
    val clientAlertId: String,
    val timestamp: Long,
    val source: RelaySource,
    val submitted: Boolean,
    val cancelRequested: Boolean,
    val enqueuedAt: Long,
    val aliases: List<String> = emptyList()
) {
    fun isKnownAs(id: String): Boolean = clientAlertId == id || id in aliases
}

/**
 * A targeted cancel that arrived before its fall was queued (transports can
 * deliver the cancel first). Kept briefly so the late fall is queued already
 * cancelled instead of escalating.
 */
internal data class CancelTombstone(
    val incidentId: String?,
    val fallTimestamp: Long?,
    val createdAt: Long
) {
    fun matches(alert: QueuedAlert): Boolean =
        (incidentId != null && alert.isKnownAs(incidentId)) ||
            (fallTimestamp != null && alert.timestamp == fallTimestamp)
}

/** Terminal relay results Flutter imports into the local history screen. */
internal enum class RelayOutcomeKind(val wireName: String) {
    /** API rejected the incident permanently (400/422/...): never delivered. */
    CREATE_REJECTED("create_rejected"),
    /** Cancellation arrived after the server grace period: caregivers notified. */
    CANCEL_TOO_LATE("cancel_too_late"),
    /** Cancellation was rejected permanently; treat as possibly dispatched. */
    CANCEL_REJECTED("cancel_rejected"),
    /** Submitted, cancel requested, but the cancel never got confirmed. */
    CANCEL_UNCONFIRMED("cancel_unconfirmed"),
    /** Cancelled before it was ever sent; nothing reached the backend. */
    CANCELLED_UNSENT("cancelled_unsent"),
    /** Queue overflow or expiry removed an incident that was never delivered. */
    DROPPED("dropped"),
    /** Discarded when the phone was re-paired: caregivers may not have been reached. */
    REPAIR_NOT_DELIVERED("repair_not_delivered"),
    /** Success: the backend accepted the incident (grace period running). */
    CREATED("created"),
    /** Success: the backend confirmed the incident is cancelled (or never existed). */
    CANCELLED("cancelled");

    companion object {
        fun fromWireName(value: String): RelayOutcomeKind? =
            values().firstOrNull { it.wireName == value }
    }
}

internal data class RelayOutcome(
    val clientAlertId: String,
    val timestamp: Long,
    val kind: RelayOutcomeKind
) {
    /** Stable key Flutter echoes back to acknowledge a persisted outcome. */
    val key: String get() = "$clientAlertId|$timestamp|${kind.wireName}"
}

internal data class EnqueueResult(
    val items: List<QueuedAlert>,
    val clientAlertId: String,
    val dropped: List<QueuedAlert>,
    val tombstones: List<CancelTombstone> = emptyList()
)

internal data class CancelResult(
    val items: List<QueuedAlert>,
    val tombstones: List<CancelTombstone>
)

/**
 * Pure, Android-free queue rules so JVM unit tests can prove migration,
 * deduplication, bounding and cancel matching without instrumentation.
 *
 * Storage format (SharedPreferences string): a `v2` header line followed by one
 * `clientAlertId|timestamp|source|submitted|cancelRequested|enqueuedAt[|aliases]`
 * line per incident (aliases comma-separated, optional for older entries).
 * Ids are restricted to a safe charset, so `|`, `,` and newlines can never
 * appear inside a field.
 */
internal object NativeAlertQueue {
    const val MAX_ITEMS = 20
    const val MAX_OUTCOMES = 50
    const val MAX_TOMBSTONES = 20
    const val LEGACY_DEDUP_WINDOW_MS = 30_000L
    const val TOMBSTONE_TTL_MS = 2 * 60_000L
    /** Submitted, never-cancelled incidents are forgotten after the server
     * grace period is long over; nothing more can be done for them. */
    const val SUBMITTED_RETENTION_MS = 10 * 60_000L
    /** Anything still queued after this is reported and removed. */
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
            append(item.enqueuedAt).append('|')
            append(item.aliases.joinToString(","))
        }
    }

    fun decode(raw: String?): List<QueuedAlert> {
        if (raw.isNullOrBlank()) return emptyList()
        val lines = raw.split('\n')
        if (lines.first() != HEADER) return emptyList()
        return lines.drop(1).mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 6 && fields.size != 7) return@mapNotNull null
            val id = fields[0]
            val timestamp = fields[1].toLongOrNull()
            val source = RelaySource.fromWireName(fields[2])
            val enqueuedAt = fields[5].toLongOrNull()
            if (!isSafeClientAlertId(id) || timestamp == null || source == null ||
                enqueuedAt == null
            ) {
                return@mapNotNull null
            }
            val aliases = fields.getOrNull(6)
                ?.split(',')
                ?.filter { it.isNotEmpty() && isSafeClientAlertId(it) }
                .orEmpty()
            QueuedAlert(
                clientAlertId = id,
                timestamp = timestamp,
                source = source,
                submitted = fields[3] == "1",
                cancelRequested = fields[4] == "1",
                enqueuedAt = enqueuedAt,
                aliases = aliases
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
     * re-trigger window apply. A matching cancel tombstone queues the
     * incident already cancelled.
     */
    fun enqueue(
        items: List<QueuedAlert>,
        timestamp: Long,
        requestedId: String?,
        source: RelaySource,
        now: Long,
        tombstones: List<CancelTombstone> = emptyList()
    ): EnqueueResult {
        val live = pruneTombstones(tombstones, now)
        val duplicate = items.firstOrNull { item ->
            (requestedId != null && item.isKnownAs(requestedId)) ||
                (item.source == source && item.timestamp == timestamp)
        }
        if (duplicate != null) {
            // Same physical incident under a new id (e.g. legacy transport
            // first, UUID transport second): remember the alias.
            val updated = if (requestedId != null && !duplicate.isKnownAs(requestedId)) {
                items.map {
                    if (it.clientAlertId == duplicate.clientAlertId) {
                        it.copy(aliases = it.aliases + requestedId)
                    } else {
                        it
                    }
                }
            } else {
                items
            }
            return EnqueueResult(updated, duplicate.clientAlertId, emptyList(), live)
        }

        if (requestedId == null) {
            // Legacy watches re-send the same physical fall as several
            // sensor triggers; only an uncancelled incident may absorb them.
            val active = items
                .filter { it.source == source && !it.cancelRequested }
                .maxByOrNull { it.timestamp }
            if (active != null && timestamp - active.timestamp in 0..LEGACY_DEDUP_WINDOW_MS) {
                return EnqueueResult(items, active.clientAlertId, emptyList(), live)
            }
        }

        val clientAlertId = requestedId ?: source.derivedClientAlertId(timestamp)
        var newItem = QueuedAlert(
            clientAlertId = clientAlertId,
            timestamp = timestamp,
            source = source,
            submitted = false,
            cancelRequested = false,
            enqueuedAt = now
        )
        val tombstone = live.firstOrNull { it.matches(newItem) }
        if (tombstone != null) newItem = newItem.copy(cancelRequested = true)
        val (bounded, dropped) = bound(items + newItem)
        return EnqueueResult(bounded, clientAlertId, dropped, live - setOfNotNull(tombstone))
    }

    /**
     * Marks the cancellation target. With an incidentId and/or fall timestamp
     * only the matching incident is cancelled; if none is queued yet a short
     * lived tombstone is kept so the late-arriving fall is queued cancelled.
     * Without either (legacy watch or phone) the most recent uncancelled
     * incident is cancelled; an untargeted cancel never creates a tombstone,
     * because it could otherwise cancel an unrelated genuine fall.
     */
    fun requestCancel(
        items: List<QueuedAlert>,
        incidentId: String?,
        fallTimestamp: Long?,
        now: Long = 0L,
        tombstones: List<CancelTombstone> = emptyList()
    ): CancelResult {
        val live = pruneTombstones(tombstones, now)
        val normalizedId = incidentId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedId != null || fallTimestamp != null) {
            var matched = false
            val updated = items.map { item ->
                val matches = (normalizedId != null &&
                    (item.isKnownAs(normalizedId) || item.isKnownAs(normalizedId.lowercase()))) ||
                    (fallTimestamp != null && item.timestamp == fallTimestamp)
                if (matches) {
                    matched = true
                    item.copy(cancelRequested = true)
                } else {
                    item
                }
            }
            if (matched) return CancelResult(updated, live)
            val tombstone = CancelTombstone(
                incidentId = normalizedId?.let {
                    NativeAlertRelayPolicy.normalizedIncidentId(it) ?: it
                },
                fallTimestamp = fallTimestamp,
                createdAt = now
            )
            return CancelResult(items, (live + tombstone).takeLast(MAX_TOMBSTONES))
        }

        val latest = items.filter { !it.cancelRequested }.maxByOrNull { it.timestamp }
            ?: return CancelResult(items, live)
        return CancelResult(
            items.map {
                if (it.clientAlertId == latest.clientAlertId) it.copy(cancelRequested = true) else it
            },
            live
        )
    }

    fun pruneTombstones(tombstones: List<CancelTombstone>, now: Long): List<CancelTombstone> =
        tombstones.filter { now - it.createdAt in 0..TOMBSTONE_TTL_MS }

    fun markSubmitted(items: List<QueuedAlert>, clientAlertId: String): List<QueuedAlert> =
        items.map { if (it.clientAlertId == clientAlertId) it.copy(submitted = true) else it }

    fun remove(items: List<QueuedAlert>, clientAlertId: String): List<QueuedAlert> =
        items.filterNot { it.clientAlertId == clientAlertId }

    /**
     * Returns the kept items and outcomes for everything that left the queue
     * without a terminal answer — nothing is ever removed silently except a
     * submitted, uncancelled incident (the backend owns it).
     */
    fun prune(items: List<QueuedAlert>, now: Long): Pair<List<QueuedAlert>, List<RelayOutcome>> {
        val outcomes = mutableListOf<RelayOutcome>()
        val kept = items.filter { item ->
            val age = now - item.enqueuedAt
            when {
                item.submitted && !item.cancelRequested && age > SUBMITTED_RETENTION_MS -> false
                age > UNDELIVERED_RETENTION_MS -> {
                    outcomes += RelayOutcome(item.clientAlertId, item.timestamp, expiryOutcome(item))
                    false
                }
                else -> true
            }
        }
        return kept to outcomes
    }

    private fun expiryOutcome(item: QueuedAlert): RelayOutcomeKind = when {
        item.submitted -> RelayOutcomeKind.CANCEL_UNCONFIRMED
        item.cancelRequested -> RelayOutcomeKind.CANCELLED_UNSENT
        else -> RelayOutcomeKind.DROPPED
    }

    /**
     * Re-pairing registers a new device with no caregiver links. Queued
     * incidents must not be sent silently under it; they are reported
     * instead so history shows caregivers may not have been reached.
     */
    fun discardForRepair(items: List<QueuedAlert>): List<RelayOutcome> = items.mapNotNull { item ->
        val kind = when {
            !item.submitted && !item.cancelRequested -> RelayOutcomeKind.REPAIR_NOT_DELIVERED
            item.submitted && item.cancelRequested -> RelayOutcomeKind.CANCEL_UNCONFIRMED
            !item.submitted && item.cancelRequested -> RelayOutcomeKind.CANCELLED_UNSENT
            else -> null // submitted and not cancelled: the old backend owns it
        }
        kind?.let { RelayOutcome(item.clientAlertId, item.timestamp, it) }
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

    /** Removes the outcomes Flutter confirmed it persisted. */
    fun acknowledge(outcomes: List<RelayOutcome>, keys: Collection<String>): List<RelayOutcome> =
        outcomes.filterNot { it.key in keys }

    fun encodeTombstones(tombstones: List<CancelTombstone>): String =
        tombstones.joinToString("\n") {
            "${it.incidentId.orEmpty()}|${it.fallTimestamp?.toString().orEmpty()}|${it.createdAt}"
        }

    fun decodeTombstones(raw: String?): List<CancelTombstone> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split('\n').mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 3) return@mapNotNull null
            val id = fields[0].takeIf { it.isNotEmpty() && isSafeClientAlertId(it) }
            val ts = fields[1].toLongOrNull()
            val createdAt = fields[2].toLongOrNull() ?: return@mapNotNull null
            if (id == null && ts == null) return@mapNotNull null
            CancelTombstone(id, ts, createdAt)
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
        // Only 401 means the backend no longer knows this device's token.
        // 403 can be transient (e.g. edge/WAF policy) and must never stop
        // delivery, so it is retried with backoff like other transient errors.
        status == 401 -> RelayHttpOutcome.REAUTH_REQUIRED
        status <= 0 || status == 403 || status == 408 || status == 429 || status >= 500 ->
            RelayHttpOutcome.RETRY
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
