package com.fallguardian

import android.app.job.JobParameters
import android.app.job.JobService
import android.net.Uri
import android.util.Log
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Sends every queued incident without requiring a Flutter Activity.
 *
 * JobScheduler retries (exponential backoff) after process death or network
 * loss. Each incident is submitted first, then cancelled if the wearer already
 * cancelled while the phone process was unavailable. HTTP statuses map to an
 * explicit policy ([NativeAlertRelayPolicy.outcomeFor]) so permanent errors
 * never leave an incident stuck forever and revoked credentials never loop.
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

        var retry = false
        for (snapshot in queued) {
            when (relay(snapshot.clientAlertId, baseUrl, deviceToken)) {
                ItemResult.DONE -> Unit
                ItemResult.RETRY -> retry = true
                ItemResult.REAUTH_REQUIRED -> {
                    // Never re-register silently: a new device has no caregiver
                    // links. Flag the state for the UI, keep incidents queued,
                    // and stop retrying until the user re-pairs.
                    Log.w(TAG, "Device credentials rejected; re-pairing required")
                    NativeAlertRelay.markReauthRequired(this)
                    return false
                }
            }
        }
        return retry
    }

    private fun relay(clientAlertId: String, baseUrl: String, token: String): ItemResult {
        var alert = NativeAlertRelay.find(this, clientAlertId) ?: return ItemResult.DONE

        if (!alert.submitted) {
            val operation = if (alert.cancelRequested) {
                RelayOperation.CREATE_CANCELLED
            } else {
                RelayOperation.CREATE
            }
            val status = postJson(
                "$baseUrl/api/v1/fall-alerts",
                token,
                NativeAlertRelay.createPayload(alert, cancelled = alert.cancelRequested)
            )
            when (NativeAlertRelayPolicy.outcomeFor(operation, status)) {
                RelayHttpOutcome.SUCCESS, RelayHttpOutcome.ALREADY_DONE -> {
                    if (operation == RelayOperation.CREATE_CANCELLED) {
                        NativeAlertRelay.complete(this, clientAlertId)
                        return ItemResult.DONE
                    }
                    NativeAlertRelay.markSubmitted(this, clientAlertId)
                }
                RelayHttpOutcome.TOO_LATE -> {
                    NativeAlertRelay.complete(this, clientAlertId, RelayOutcomeKind.CANCEL_TOO_LATE)
                    return ItemResult.DONE
                }
                RelayHttpOutcome.REJECTED -> {
                    Log.e(TAG, "Fall alert rejected permanently (HTTP $status)")
                    NativeAlertRelay.complete(this, clientAlertId, RelayOutcomeKind.CREATE_REJECTED)
                    return ItemResult.DONE
                }
                RelayHttpOutcome.REAUTH_REQUIRED -> return ItemResult.REAUTH_REQUIRED
                RelayHttpOutcome.RETRY -> return ItemResult.RETRY
            }
            alert = NativeAlertRelay.find(this, clientAlertId) ?: return ItemResult.DONE
        }

        if (!alert.cancelRequested) {
            // Keep the submitted state until the retention window ends. A later
            // watch/phone cancel can reschedule this job without Flutter.
            return ItemResult.DONE
        }

        val status = postJson(
            "$baseUrl/api/v1/fall-alerts/${Uri.encode(clientAlertId)}/cancel",
            token,
            null
        )
        return when (NativeAlertRelayPolicy.outcomeFor(RelayOperation.CANCEL, status)) {
            RelayHttpOutcome.SUCCESS, RelayHttpOutcome.ALREADY_DONE -> {
                NativeAlertRelay.complete(this, clientAlertId)
                ItemResult.DONE
            }
            RelayHttpOutcome.TOO_LATE -> {
                NativeAlertRelay.complete(this, clientAlertId, RelayOutcomeKind.CANCEL_TOO_LATE)
                ItemResult.DONE
            }
            RelayHttpOutcome.REJECTED -> {
                Log.e(TAG, "Fall alert cancellation rejected permanently (HTTP $status)")
                NativeAlertRelay.complete(this, clientAlertId, RelayOutcomeKind.CANCEL_REJECTED)
                ItemResult.DONE
            }
            RelayHttpOutcome.REAUTH_REQUIRED -> ItemResult.REAUTH_REQUIRED
            RelayHttpOutcome.RETRY -> ItemResult.RETRY
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

    private enum class ItemResult { DONE, RETRY, REAUTH_REQUIRED }

    private companion object {
        const val TAG = "NativeAlertRelay"
        val executor = Executors.newSingleThreadExecutor()
    }
}
