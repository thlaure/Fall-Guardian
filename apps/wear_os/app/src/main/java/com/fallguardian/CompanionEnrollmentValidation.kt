package com.fallguardian

import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Pure validation for an inbound `/companion_enrollment` Data Layer message,
 * kept free of Android/Wearable/org.json APIs so it runs in plain JUnit tests
 * (see CompanionEnrollmentValidationTest.kt) the same way FallAlgorithm is
 * tested — `org.json.JSONObject` throws "not mocked" under the JVM unit-test
 * classpath, so this takes a plain Map instead; CompanionEnrollmentClient
 * converts the parsed JSONObject to a Map before calling in.
 *
 * Per docs/COMPANION_ENROLLMENT.md §3 ("Watch" responsibilities): "verify
 * platform and expiration before the network call" — this is that check, run
 * before CompanionEnrollmentClient ever touches the network.
 */
data class ValidatedEnrollment(val enrollmentToken: String, val expiresAt: Instant)

object CompanionEnrollmentValidation {
    fun validate(message: Map<String, Any?>, expectedPlatform: String, now: Instant): ValidatedEnrollment? {
        if (message["type"] != "companionEnrollment") return null
        if ((message["schemaVersion"] as? Number)?.toInt() != 1) return null
        if (message["platform"] != expectedPlatform) return null

        val token = message["enrollmentToken"] as? String
        if (token.isNullOrBlank()) return null

        val expiresAtRaw = message["expiresAt"] as? String
        if (expiresAtRaw.isNullOrBlank()) return null

        val expiresAt = try {
            Instant.parse(expiresAtRaw)
        } catch (_: DateTimeParseException) {
            return null
        }

        if (!expiresAt.isAfter(now)) return null

        return ValidatedEnrollment(token, expiresAt)
    }
}
