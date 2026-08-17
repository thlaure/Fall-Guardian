// CompanionEnrollmentValidation.swift
// Fall Guardian — watchOS
//
// Pure validation for an inbound companionEnrollment WatchConnectivity
// message, kept free of WatchConnectivity/Security/Foundation-networking
// imports so it compiles and runs standalone via `swiftc` for deterministic
// tests (see FallGuardianTests/CompanionEnrollmentValidationExecutableTests.swift
// and `make test`), the same pattern used by FallAlgorithm.swift.
//
// Per docs/COMPANION_ENROLLMENT.md §3 ("Watch" responsibilities): "verify
// platform and expiration before the network call" — this is that check,
// run before CompanionEnrollmentClient ever touches the network.

import Foundation

enum CompanionEnrollmentValidation {
    struct ValidatedEnrollment {
        let enrollmentToken: String
        let expiresAt: Date
    }

    /// Returns the validated token and expiry, or `nil` if the message is
    /// malformed, addressed to a different platform, or already expired.
    static func validate(
        _ message: [String: Any],
        expectedPlatform: String,
        now: Date = Date()
    ) -> ValidatedEnrollment? {
        guard message["type"] as? String == "companionEnrollment",
              message["schemaVersion"] as? Int == 1,
              message["platform"] as? String == expectedPlatform,
              let token = message["enrollmentToken"] as? String,
              !token.isEmpty,
              let expiresAtString = message["expiresAt"] as? String,
              let expiresAt = ISO8601DateFormatter().date(from: expiresAtString) else {
            return nil
        }

        guard expiresAt > now else { return nil }

        return ValidatedEnrollment(enrollmentToken: token, expiresAt: expiresAt)
    }
}
