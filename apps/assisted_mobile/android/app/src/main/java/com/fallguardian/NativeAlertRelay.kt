package com.fallguardian

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.PersistableBundle
import java.util.Locale

/**
 * Durable phone-side relay for fall incidents (Wear OS and phone-originated).
 *
 * WearableListenerService may be launched while no Flutter engine exists.
 * Persisting each incident in a small bounded queue before scheduling a
 * network-constrained JobService guarantees that process death, temporary
 * network loss or a second fall cannot silently discard a backend
 * registration or a later cancellation.
 */
internal object NativeAlertRelay {
    const val DEVICE_TOKEN_KEY = "backend_device_token"

    /** Shared with Dart (BackendApiService) through AndroidSecureStore. */
    const val REAUTH_REQUIRED_KEY = "backend_reauth_required"

    private const val JOB_ID = 0x4647
    private const val BASE_URL_KEY = "native_alert_relay_base_url"
    private const val QUEUE_KEY = "native_alert_queue_v2"
    private const val OUTCOMES_KEY = "native_alert_outcomes_v1"
    private const val TOMBSTONES_KEY = "native_alert_cancel_tombstones_v1"

    // Legacy single-slot keys (pre-queue). Read once, migrated, then removed.
    private const val LEGACY_TIMESTAMP_KEY = "native_alert_timestamp"
    private const val LEGACY_CLIENT_ALERT_ID_KEY = "native_alert_client_id"
    private const val LEGACY_SUBMITTED_KEY = "native_alert_submitted"
    private const val LEGACY_CANCEL_REQUESTED_KEY = "native_alert_cancel_requested"

    @Synchronized
    fun configure(context: Context, baseUrl: String): Boolean {
        if (!isAllowedBaseUrl(context, baseUrl)) return false
        prefs(context).edit().putString(BASE_URL_KEY, baseUrl.trimEnd('/')).apply()
        if (readQueue(context).isNotEmpty()) schedule(context)
        return true
    }

    /** Persists a watch incident. Returns the clientAlertId Flutter must reuse. */
    @Synchronized
    fun enqueueFall(context: Context, timestamp: Long, incidentId: String? = null): String =
        enqueue(
            context,
            timestamp,
            NativeAlertRelayPolicy.normalizedIncidentId(incidentId),
            RelaySource.WEAR_OS
        )

    /**
     * Persists an incident first seen by Flutter (phone-originated or a
     * transport without native enqueue) so the JobService retries it after
     * process death. Idempotent per clientAlertId.
     */
    @Synchronized
    fun enqueuePhoneAlert(context: Context, timestamp: Long, clientAlertId: String): String? {
        val id = clientAlertId.trim()
        if (!NativeAlertQueue.isSafeClientAlertId(id)) return null
        return enqueue(context, timestamp, id, RelaySource.ASSISTED_PHONE)
    }

    private fun enqueue(
        context: Context,
        timestamp: Long,
        requestedId: String?,
        source: RelaySource
    ): String {
        val result = NativeAlertQueue.enqueue(
            readQueue(context),
            timestamp,
            requestedId,
            source,
            System.currentTimeMillis(),
            readTombstones(context)
        )
        writeQueue(context, result.items)
        writeTombstones(context, result.tombstones)
        result.dropped.forEach {
            recordOutcome(context, RelayOutcome(it.clientAlertId, it.timestamp, RelayOutcomeKind.DROPPED))
        }
        schedule(context)
        return result.clientAlertId
    }

    /**
     * Cancels the matching incident. A targeted cancel that arrives before its
     * fall is kept as a short-lived tombstone so the fall is queued cancelled.
     */
    @Synchronized
    fun requestCancel(context: Context, incidentId: String? = null, fallTimestamp: Long? = null) {
        val result = NativeAlertQueue.requestCancel(
            readQueue(context),
            incidentId,
            fallTimestamp,
            System.currentTimeMillis(),
            readTombstones(context)
        )
        writeQueue(context, result.items)
        writeTombstones(context, result.tombstones)
        if (result.items.isNotEmpty()) schedule(context)
    }

    /** Snapshot of the queue after pruning expired items (never silently). */
    @Synchronized
    fun pending(context: Context): List<QueuedAlert> {
        val current = readQueue(context)
        val (kept, outcomes) = NativeAlertQueue.prune(current, System.currentTimeMillis())
        if (kept.size != current.size) {
            writeQueue(context, kept)
            outcomes.forEach { recordOutcome(context, it) }
        }
        return kept
    }

    /**
     * Called before the phone re-registers as a new device: queued incidents
     * must not be sent under the new, caregiver-less registration. They are
     * reported instead (history: caregivers may not have been reached).
     */
    @Synchronized
    fun discardForRepair(context: Context): Int {
        val items = readQueue(context)
        val outcomes = NativeAlertQueue.discardForRepair(items)
        outcomes.forEach { recordOutcome(context, it) }
        writeQueue(context, emptyList())
        writeTombstones(context, emptyList())
        return items.size
    }

    @Synchronized
    fun find(context: Context, clientAlertId: String): QueuedAlert? =
        readQueue(context).firstOrNull { it.clientAlertId == clientAlertId }

    @Synchronized
    fun markSubmitted(context: Context, clientAlertId: String) {
        writeQueue(context, NativeAlertQueue.markSubmitted(readQueue(context), clientAlertId))
    }

    @Synchronized
    fun complete(context: Context, clientAlertId: String, outcome: RelayOutcomeKind? = null) {
        val items = readQueue(context)
        val item = items.firstOrNull { it.clientAlertId == clientAlertId } ?: return
        writeQueue(context, NativeAlertQueue.remove(items, clientAlertId))
        if (outcome != null) recordOutcome(context, RelayOutcome(item.clientAlertId, item.timestamp, outcome))
    }

    @Synchronized
    fun recordOutcome(context: Context, clientAlertId: String, kind: RelayOutcomeKind) {
        val item = readQueue(context).firstOrNull { it.clientAlertId == clientAlertId } ?: return
        recordOutcome(context, RelayOutcome(item.clientAlertId, item.timestamp, kind))
    }

    /**
     * Terminal outcomes for Flutter's history. They stay stored until Flutter
     * acknowledges them ([acknowledgeOutcomes]) after persisting, so a crash
     * between the two steps never loses one.
     */
    @Synchronized
    fun peekOutcomes(context: Context): List<RelayOutcome> =
        NativeAlertQueue.decodeOutcomes(prefs(context).getString(OUTCOMES_KEY, null))

    @Synchronized
    fun acknowledgeOutcomes(context: Context, keys: Collection<String>) {
        val remaining = NativeAlertQueue.acknowledge(peekOutcomes(context), keys)
        prefs(context).edit()
            .putString(OUTCOMES_KEY, NativeAlertQueue.encodeOutcomes(remaining))
            .commit()
    }

    fun markReauthRequired(context: Context) {
        AndroidSecureStore(context).write(REAUTH_REQUIRED_KEY, "true")
    }

    fun baseUrl(context: Context): String? =
        prefs(context).getString(BASE_URL_KEY, null)?.takeIf { it.isNotBlank() }

    fun createPayload(alert: QueuedAlert, cancelled: Boolean): String =
        NativeAlertRelayPolicy.createPayload(
            clientAlertId = alert.clientAlertId,
            timestamp = alert.timestamp,
            locale = Locale.getDefault().language,
            source = alert.source,
            cancelled = cancelled
        )

    private fun recordOutcome(context: Context, outcome: RelayOutcome) {
        val existing = NativeAlertQueue.decodeOutcomes(prefs(context).getString(OUTCOMES_KEY, null))
        prefs(context).edit()
            .putString(OUTCOMES_KEY, NativeAlertQueue.encodeOutcomes(existing + outcome))
            .commit()
    }

    private fun readTombstones(context: Context): List<CancelTombstone> =
        NativeAlertQueue.decodeTombstones(prefs(context).getString(TOMBSTONES_KEY, null))

    private fun writeTombstones(context: Context, tombstones: List<CancelTombstone>) {
        prefs(context).edit()
            .putString(TOMBSTONES_KEY, NativeAlertQueue.encodeTombstones(tombstones))
            .commit()
    }

    private fun readQueue(context: Context): List<QueuedAlert> {
        val values = prefs(context)
        val raw = values.getString(QUEUE_KEY, null)
        if (raw != null) return NativeAlertQueue.decode(raw)

        // First read after upgrading from the single-slot relay: carry over a
        // possibly unsent incident, then drop the legacy keys.
        val legacyTimestamp = values.getLong(LEGACY_TIMESTAMP_KEY, Long.MIN_VALUE)
            .takeIf { it != Long.MIN_VALUE }
        val migrated = NativeAlertQueue.migrateLegacy(
            timestamp = legacyTimestamp,
            clientAlertId = values.getString(LEGACY_CLIENT_ALERT_ID_KEY, null),
            submitted = values.getBoolean(LEGACY_SUBMITTED_KEY, false),
            cancelRequested = values.getBoolean(LEGACY_CANCEL_REQUESTED_KEY, false),
            now = System.currentTimeMillis()
        )
        values.edit()
            .putString(QUEUE_KEY, NativeAlertQueue.encode(migrated))
            .remove(LEGACY_TIMESTAMP_KEY)
            .remove(LEGACY_CLIENT_ALERT_ID_KEY)
            .remove(LEGACY_SUBMITTED_KEY)
            .remove(LEGACY_CANCEL_REQUESTED_KEY)
            .commit()
        return migrated
    }

    private fun writeQueue(context: Context, items: List<QueuedAlert>) {
        // commit() (synchronous) so the incident is on disk before the caller
        // reports it to Flutter or the process is allowed to die.
        prefs(context).edit().putString(QUEUE_KEY, NativeAlertQueue.encode(items)).commit()
    }

    private fun schedule(context: Context) {
        val extras = PersistableBundle().apply {
            putString("reason", "fall_alert_relay")
        }
        val job = JobInfo.Builder(
            JOB_ID,
            ComponentName(context, NativeAlertRelayJobService::class.java)
        )
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setBackoffCriteria(10_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            .setPersisted(true)
            .setExtras(extras)
            .build()
        context.getSystemService(JobScheduler::class.java)?.schedule(job)
    }

    private fun isAllowedBaseUrl(context: Context, raw: String): Boolean {
        val uri = Uri.parse(raw)
        if (uri.host.isNullOrBlank()) return false
        if (uri.scheme == "https") return true
        val debuggable =
            context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return debuggable && uri.scheme == "http"
    }

    private fun prefs(context: Context) = context.applicationContext
        .getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
}
