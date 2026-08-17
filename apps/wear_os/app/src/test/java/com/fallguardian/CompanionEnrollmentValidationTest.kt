package com.fallguardian

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CompanionEnrollmentValidationTest {
    private val now = Instant.ofEpochSecond(1_000_000)
    private val future = now.plusSeconds(300).toString()
    private val past = now.minusSeconds(1).toString()
    private val token = "a".repeat(64)

    private fun validMessage(overrides: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        val message: Map<String, Any?> = mapOf(
            "type" to "companionEnrollment",
            "schemaVersion" to 1,
            "platform" to "wearos",
            "enrollmentToken" to token,
            "expiresAt" to future
        )
        return message + overrides
    }

    @Test
    fun `well-formed unexpired message for the requested platform validates`() {
        val result = CompanionEnrollmentValidation.validate(validMessage(), "wearos", now)
        assertEquals(token, result?.enrollmentToken)
    }

    @Test
    fun `wrong envelope type is rejected`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("type" to "somethingElse")), "wearos", now
            )
        )
    }

    @Test
    fun `wrong platform is rejected without needing the network call to reject it`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("platform" to "watchos")), "wearos", now
            )
        )
    }

    @Test
    fun `unknown schema version is rejected`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("schemaVersion" to 2)), "wearos", now
            )
        )
    }

    @Test
    fun `missing or blank token is rejected`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("enrollmentToken" to "")), "wearos", now
            )
        )
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("enrollmentToken" to null)), "wearos", now
            )
        )
    }

    @Test
    fun `malformed expiry timestamp is rejected`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("expiresAt" to "not-a-date")), "wearos", now
            )
        )
    }

    @Test
    fun `already-expired token is rejected client-side before any network call`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("expiresAt" to past)), "wearos", now
            )
        )
    }

    @Test
    fun `boundary - token expiring exactly now is treated as expired`() {
        assertNull(
            CompanionEnrollmentValidation.validate(
                validMessage(mapOf("expiresAt" to now.toString())), "wearos", now
            )
        )
    }
}
