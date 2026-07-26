package com.fallguardian

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.PersistableBundle
import java.time.Instant
import java.util.Locale

internal data class NativePendingAlert(
    val timestamp: Long,
    val clientAlertId: String,
    val submitted: Boolean,
    val cancelRequested: Boolean
)

/**
 * Durable phone-side relay for Wear OS incidents.
 *
 * WearableListenerService may be launched while no Flutter engine exists.
 * Persisting the incident before scheduling a network-constrained JobService
 * guarantees that process death or temporary network loss cannot silently
 * discard the backend registration or a later cancellation.
 */
internal object NativeAlertRelay {
    const val DEVICE_TOKEN_KEY = "backend_device_token"

    private const val JOB_ID = 0x4647
    private const val BASE_URL_KEY = "native_alert_relay_base_url"
    private const val TIMESTAMP_KEY = "native_alert_timestamp"
    private const val CLIENT_ALERT_ID_KEY = "native_alert_client_id"
    private const val SUBMITTED_KEY = "native_alert_submitted"
    private const val CANCEL_REQUESTED_KEY = "native_alert_cancel_requested"
    private const val ACTIVE_INCIDENT_WINDOW_MS = 30_000L

    @Synchronized
    fun configure(context: Context, baseUrl: String): Boolean {
        if (!isAllowedBaseUrl(context, baseUrl)) return false
        prefs(context).edit().putString(BASE_URL_KEY, baseUrl.trimEnd('/')).apply()
        if (read(context) != null) schedule(context)
        return true
    }

    @Synchronized
    fun enqueueFall(context: Context, timestamp: Long): String {
        val existing = read(context)
        if (existing != null &&
            timestamp - existing.timestamp in 0..ACTIVE_INCIDENT_WINDOW_MS
        ) {
            schedule(context)
            return existing.clientAlertId
        }

        val clientAlertId = NativeAlertRelayPolicy.clientAlertId(timestamp)
        prefs(context).edit()
            .putLong(TIMESTAMP_KEY, timestamp)
            .putString(CLIENT_ALERT_ID_KEY, clientAlertId)
            .putBoolean(SUBMITTED_KEY, false)
            .putBoolean(CANCEL_REQUESTED_KEY, false)
            .apply()
        schedule(context)
        return clientAlertId
    }

    @Synchronized
    fun requestCancel(context: Context) {
        if (read(context) == null) return
        prefs(context).edit().putBoolean(CANCEL_REQUESTED_KEY, true).apply()
        schedule(context)
    }

    @Synchronized
    fun read(context: Context): NativePendingAlert? {
        val values = prefs(context)
        val timestamp = values.getLong(TIMESTAMP_KEY, Long.MIN_VALUE)
        val clientAlertId = values.getString(CLIENT_ALERT_ID_KEY, null)
        if (timestamp == Long.MIN_VALUE || clientAlertId.isNullOrBlank()) return null
        return NativePendingAlert(
            timestamp = timestamp,
            clientAlertId = clientAlertId,
            submitted = values.getBoolean(SUBMITTED_KEY, false),
            cancelRequested = values.getBoolean(CANCEL_REQUESTED_KEY, false)
        )
    }

    @Synchronized
    fun markSubmitted(context: Context, clientAlertId: String) {
        val current = read(context) ?: return
        if (current.clientAlertId != clientAlertId) return
        prefs(context).edit().putBoolean(SUBMITTED_KEY, true).apply()
    }

    @Synchronized
    fun clear(context: Context, clientAlertId: String) {
        val current = read(context) ?: return
        if (current.clientAlertId != clientAlertId) return
        prefs(context).edit()
            .remove(TIMESTAMP_KEY)
            .remove(CLIENT_ALERT_ID_KEY)
            .remove(SUBMITTED_KEY)
            .remove(CANCEL_REQUESTED_KEY)
            .apply()
    }

    fun baseUrl(context: Context): String? =
        prefs(context).getString(BASE_URL_KEY, null)?.takeIf { it.isNotBlank() }

    fun createPayload(alert: NativePendingAlert): String =
        NativeAlertRelayPolicy.createPayload(
            clientAlertId = alert.clientAlertId,
            timestamp = alert.timestamp,
            locale = Locale.getDefault().language
        )

    private fun schedule(context: Context) {
        val extras = PersistableBundle().apply {
            putString("reason", "wear_os_fall")
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

/**
 * Pure formatting policy kept independent from Android services so JVM tests
 * can verify idempotency and the backend payload without device instrumentation.
 */
internal object NativeAlertRelayPolicy {
    fun clientAlertId(timestamp: Long): String = "wear-os-$timestamp"

    fun createPayload(
        clientAlertId: String,
        timestamp: Long,
        locale: String
    ): String {
        val safeLocale = locale.take(8).ifBlank { "en" }
        return buildString {
            append('{')
            append("\"clientAlertId\":\"").append(jsonEscape(clientAlertId)).append("\",")
            append("\"fallTimestamp\":\"").append(Instant.ofEpochMilli(timestamp)).append("\",")
            append("\"locale\":\"").append(jsonEscape(safeLocale)).append("\",")
            append("\"latitude\":null,\"longitude\":null,")
            append("\"revision\":1,")
            append("\"detectionSource\":\"wear_os\",")
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
