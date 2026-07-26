package com.fallguardian

import android.app.job.JobParameters
import android.app.job.JobService
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Sends the pending Wear OS incident without requiring a Flutter Activity.
 *
 * JobScheduler retries after process death or network loss. The incident is
 * submitted first, then cancellation is sent if the wearer already cancelled
 * while the phone process was unavailable.
 */
class NativeAlertRelayJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        executor.execute {
            val retry = try {
                relayPendingAlert()
            } catch (error: Exception) {
                Log.e(TAG, "Native fall relay failed", error)
                true
            }
            jobFinished(params, retry)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true

    private fun relayPendingAlert(): Boolean {
        var alert = NativeAlertRelay.read(this) ?: return false
        val baseUrl = NativeAlertRelay.baseUrl(this) ?: return true
        val deviceToken =
            AndroidSecureStore(this).read(NativeAlertRelay.DEVICE_TOKEN_KEY)
                ?.takeIf { it.isNotBlank() }
                ?: return true

        if (!alert.submitted) {
            val createStatus = postJson(
                "$baseUrl/api/v1/fall-alerts",
                deviceToken,
                NativeAlertRelay.createPayload(alert)
            )
            if (createStatus !in 200..299) {
                return shouldRetry(createStatus)
            }
            NativeAlertRelay.markSubmitted(this, alert.clientAlertId)
            alert = NativeAlertRelay.read(this) ?: return false
        }

        if (!alert.cancelRequested) {
            // Keep the submitted state until the cancellation deadline. A later
            // watch-side cancel can reschedule this job without Flutter.
            return false
        }

        val cancelStatus = postJson(
            "$baseUrl/api/v1/fall-alerts/${alert.clientAlertId}/cancel",
            deviceToken,
            null
        )
        if (cancelStatus in 200..299) {
            NativeAlertRelay.clear(this, alert.clientAlertId)
            return false
        }
        return shouldRetry(cancelStatus)
    }

    private fun postJson(url: String, token: String, body: String?): Int {
        val connection = URL(url).openConnection() as HttpURLConnection
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
        } finally {
            connection.disconnect()
        }
    }

    private fun shouldRetry(status: Int): Boolean =
        status == HttpURLConnection.HTTP_UNAUTHORIZED ||
            status == HttpURLConnection.HTTP_FORBIDDEN ||
            status == HttpURLConnection.HTTP_CLIENT_TIMEOUT ||
            status == 429 ||
            status >= 500

    private companion object {
        const val TAG = "NativeAlertRelay"
        val executor = Executors.newSingleThreadExecutor()
    }
}
