package com.fallguardian

/** One watch cancel waiting to be delivered to Flutter. */
internal data class PendingCancel(
    val entryId: String,
    val incidentId: String?,
    val fallTimestamp: Long?
)

/**
 * Small persistent list of watch cancels not yet confirmed delivered to
 * Flutter. A list (not a single slot) so two cancels — or a targeted and a
 * legacy untargeted one — never overwrite each other; each entry is removed
 * only after Flutter's method handler returned successfully.
 *
 * Format: one `entryId|incidentId|fallTimestamp` line per entry (empty field
 * = absent). Pure Kotlin for JVM tests.
 */
internal object PendingCancels {
    const val MAX_ENTRIES = 20
    private val SAFE = Regex("^[A-Za-z0-9._:-]{1,100}$")

    fun add(entries: List<PendingCancel>, cancel: PendingCancel): List<PendingCancel> {
        // The same target queued twice (duplicate transports) is delivered once.
        val duplicate = entries.any {
            it.incidentId == cancel.incidentId && it.fallTimestamp == cancel.fallTimestamp
        }
        return if (duplicate) entries else (entries + cancel).takeLast(MAX_ENTRIES)
    }

    fun remove(entries: List<PendingCancel>, entryId: String): List<PendingCancel> =
        entries.filterNot { it.entryId == entryId }

    /**
     * Pre-list builds stored a single boolean flag plus optional target.
     * Converts it into one entry so an undelivered cancel survives the update.
     */
    fun migrateLegacy(
        pending: Boolean,
        incidentId: String?,
        fallTimestamp: Long?
    ): List<PendingCancel> =
        if (pending) listOf(PendingCancel("legacy", incidentId, fallTimestamp)) else emptyList()

    fun encode(entries: List<PendingCancel>): String = entries.joinToString("\n") {
        "${it.entryId}|${it.incidentId.orEmpty()}|${it.fallTimestamp?.toString().orEmpty()}"
    }

    fun decode(raw: String?): List<PendingCancel> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split('\n').mapNotNull { line ->
            val fields = line.split('|')
            if (fields.size != 3 || !SAFE.matches(fields[0])) return@mapNotNull null
            val incidentId = fields[1].takeIf { it.isNotEmpty() && SAFE.matches(it) }
            val fallTimestamp = fields[2].takeIf { it.isNotEmpty() }?.toLongOrNull()
            PendingCancel(fields[0], incidentId, fallTimestamp)
        }
    }
}
