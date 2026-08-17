package com.fallguardian

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.Wearable
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import org.json.JSONObject

/**
 * Consumes the one-time companion-enrollment token relayed by the phone:
 * validates it, exchanges it for watch-specific credentials via
 * POST /api/v1/companion-enrollments/claim, stores them via
 * CompanionEnrollmentSecureStore, and confirms success back to the phone.
 * See docs/COMPANION_ENROLLMENT.md.
 *
 * This is the watch's only direct network call today — the fall/cancel path
 * still goes exclusively through the Wearable Data Layer to the phone relay.
 * Direct incident submission using these stored credentials is a later
 * increment (docs/COMPANION_ENROLLMENT.md §6, PR E).
 */
object CompanionEnrollmentClient {
    private const val TAG = "CompanionEnrollment"
    private const val EXPECTED_PLATFORM = "wearos"

    /**
     * Entry point called by PhoneMessageListenerService when a
     * `/companion_enrollment` message arrives. Runs on the caller's thread —
     * WearableListenerService callbacks already execute off the main thread,
     * so this may block on the network call directly, matching
     * NativeAlertRelayJobService's synchronous HttpURLConnection pattern.
     */
    fun handleEnrollmentMessage(context: Context, payload: ByteArray) {
        val json = try {
            JSONObject(String(payload, Charsets.UTF_8))
        } catch (error: Exception) {
            Log.e(TAG, "Rejecting malformed enrollment payload", error)
            return
        }

        val message = json.keys().asSequence().associateWith { key -> json.get(key) }
        val validated = CompanionEnrollmentValidation.validate(
            message,
            expectedPlatform = EXPECTED_PLATFORM,
            now = Instant.now()
        )
        if (validated == null) {
            Log.w(TAG, "Rejecting invalid or expired enrollment message")
            return
        }

        claim(context, validated.enrollmentToken)
    }

    private fun claim(context: Context, token: String) {
        val status: Int
        val responseBody: String?
        val connection = URL("${BuildConfig.BACKEND_BASE_URL}/api/v1/companion-enrollments/claim")
            .openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")

            val body = JSONObject()
                .put("enrollmentToken", token)
                .put("platform", EXPECTED_PLATFORM)
                .put("appVersion", BuildConfig.VERSION_NAME)
                .toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            responseBody = stream?.use { it.readBytes().toString(Charsets.UTF_8) }
        } catch (error: Exception) {
            // Never log `token` or the response body — both may carry durable
            // secrets. The exception type/message alone is diagnosable.
            Log.e(TAG, "Claim request failed", error)
            return
        } finally {
            connection.disconnect()
        }

        if (status != HttpURLConnection.HTTP_CREATED || responseBody == null) {
            Log.e(TAG, "Claim failed: status=$status")
            return
        }

        val deviceId: String
        val deviceToken: String
        try {
            val response = JSONObject(responseBody)
            deviceId = response.getString("deviceId")
            deviceToken = response.getString("deviceToken")
        } catch (error: Exception) {
            Log.e(TAG, "Claim succeeded but response was unparseable", error)
            return
        }

        try {
            CompanionEnrollmentSecureStore(context).save(deviceId, deviceToken, schemaVersion = 1)
        } catch (error: Exception) {
            // A Keystore failure here must not crash this WearableListenerService
            // callback, and must not be followed by a success confirmation —
            // the credentials were not actually persisted.
            Log.e(TAG, "Claim succeeded but storing credentials failed", error)
            return
        }

        Log.i(TAG, "Enrolled successfully")
        confirmSuccessToPhone(context)
    }

    /**
     * Best-effort confirmation only — the phone does not yet gate any
     * behavior on it, and the watch's own secure-store write is already the
     * source of truth for whether enrollment succeeded.
     */
    private fun confirmSuccessToPhone(context: Context) {
        val payload = JSONObject()
            .put("type", "companionEnrollmentResult")
            .put("schemaVersion", 1)
            .put("status", "enrolled")
            .toString()
            .toByteArray(Charsets.UTF_8)

        Wearable.getNodeClient(context).connectedNodes
            .addOnSuccessListener { nodes ->
                nodes.forEach { node ->
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, "/companion_enrollment_result", payload)
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Failed to confirm enrollment to phone", e)
                        }
                }
            }
            .addOnFailureListener { e -> Log.e(TAG, "Failed to get connected nodes for confirmation", e) }
    }
}
