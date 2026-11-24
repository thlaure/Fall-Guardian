package com.fallguardian

import android.app.job.JobParameters
import android.app.job.JobService
import android.util.Log
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Sends every queued incident without requiring a Flutter Activity.
 *
 * JobScheduler retries (exponential backoff) after process death or network
 * loss. The per-incident create/cancel flow and the HTTP status policy live
 * in the pure [RelayProcessor] so they are unit-tested on the JVM; this
 * service only provides Android storage, credentials and HTTP.
 */
class NativeAlertRelayJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        executor.execute {
            val retry = try {
                relayPendingAlerts()
            } catch (error: Exception) {
                Log.e(TAG, "Native fall relay failed", error)
                true
            }
            jobFinished(params, retry)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true

    /** Returns true when JobScheduler should retry later with backoff. */
    private fun relayPendingAlerts(): Boolean {
        val queued = NativeAlertRelay.pending(this)
        if (queued.isEmpty()) return false
        // Missing configuration/credentials: keep everything queued. Flutter
        // re-schedules via configureNativeAlertRelay once it is available.
        val baseUrl = NativeAlertRelay.baseUrl(this) ?: return true
        val deviceToken =
            AndroidSecureStore(this).read(NativeAlertRelay.DEVICE_TOKEN_KEY)
                ?.takeIf { it.isNotBlank() }
                ?: return true

        val context = this
        val processor = RelayProcessor(
            store = object : RelayQueueStore {
                override fun find(clientAlertId: String) =
                    NativeAlertRelay.find(context, clientAlertId)

                override fun markSubmitted(clientAlertId: String) =
                    NativeAlertRelay.markSubmitted(context, clientAlertId)

                override fun complete(clientAlertId: String, outcome: RelayOutcomeKind?) =
                    NativeAlertRelay.complete(context, clientAlertId, outcome)

                override fun recordOutcome(clientAlertId: String, outcome: RelayOutcomeKind) =
                    NativeAlertRelay.recordOutcome(context, clientAlertId, outcome)
            },
            post = { path, body -> postJson("$baseUrl$path", deviceToken, body) },
            createPayload = NativeAlertRelay::createPayload
        )

        return when (processor.relay(queued.map { it.clientAlertId })) {
            RelayPassResult.DONE -> false
            RelayPassResult.RETRY -> true
            RelayPassResult.REAUTH_REQUIRED -> {
                // 401 only. Never re-register silently: a new device has no
                // caregiver links. Flag the state for the UI, keep incidents
                // queued, and stop until the user re-pairs.
                Log.w(TAG, "Device credentials rejected; re-pairing required")
                NativeAlertRelay.markReauthRequired(this)
                false
            }
        }
    }

    /** Returns the HTTP status, or 0 when the request never got a response. */
    private fun postJson(url: String, token: String, body: String?): Int {
        val connection = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (error: IOException) {
            Log.w(TAG, "Relay connection failed", error)
            return 0
        }
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use {
                    it.write(body.toByteArray(Charsets.UTF_8))
                }
            }
            val status = connection.responseCode
            // Consume and close the response so HTTP connections are reusable.
            val stream =
                if (status >= 400) connection.errorStream else connection.inputStream
            stream?.use { it.readBytes() }
            status
        } catch (error: IOException) {
            Log.w(TAG, "Relay request failed", error)
            0
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val TAG = "NativeAlertRelay"
        val executor = Executors.newSingleThreadExecutor()
    }
}
