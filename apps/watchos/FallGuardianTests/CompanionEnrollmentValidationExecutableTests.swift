import Foundation

@main
enum CompanionEnrollmentValidationExecutableTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future = ISO8601DateFormatter().string(from: now.addingTimeInterval(300))
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-1))

        func validMessage(overrides: [String: Any] = [:]) -> [String: Any] {
            var message: [String: Any] = [
                "type": "companionEnrollment",
                "schemaVersion": 1,
                "platform": "watchos",
                "enrollmentToken": String(repeating: "a", count: 64),
                "expiresAt": future,
            ]
            for (key, value) in overrides {
                message[key] = value
            }
            return message
        }

        // A well-formed, unexpired message for the requested platform validates.
        let valid = CompanionEnrollmentValidation.validate(
            validMessage(), expectedPlatform: "watchos", now: now
        )
        assert(valid != nil)
        assert(valid?.enrollmentToken == String(repeating: "a", count: 64))

        // Wrong envelope type is rejected (e.g. an unrelated message reusing keys).
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["type": "somethingElse"]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        // Wrong platform is rejected without needing the network call to reject it.
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["platform": "wearos"]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        // Unknown schema version is rejected rather than guessed at.
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["schemaVersion": 2]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        // Missing or empty token is rejected.
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["enrollmentToken": ""]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )
        var missingToken = validMessage()
        missingToken.removeValue(forKey: "enrollmentToken")
        assert(
            CompanionEnrollmentValidation.validate(missingToken, expectedPlatform: "watchos", now: now) == nil
        )

        // Malformed expiry timestamp is rejected.
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["expiresAt": "not-a-date"]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        // Already-expired token is rejected client-side, before any network call.
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["expiresAt": past]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        // Boundary: a token expiring exactly now is treated as expired, not valid.
        let exactlyNow = ISO8601DateFormatter().string(from: now)
        assert(
            CompanionEnrollmentValidation.validate(
                validMessage(overrides: ["expiresAt": exactlyNow]),
                expectedPlatform: "watchos", now: now
            ) == nil
        )

        print("CompanionEnrollmentValidation tests passed")
    }
}
