// CompanionEnrollmentClient.swift
// Fall Guardian — watchOS
//
// Consumes the one-time companion-enrollment token relayed by the phone:
// validates it, exchanges it for watch-specific credentials via
// POST /api/v1/companion-enrollments/claim, stores them in Keychain, and
// confirms success back to the phone. See docs/COMPANION_ENROLLMENT.md.
//
// This is the watch's only network call today — the fall/cancel path still
// goes exclusively through WatchConnectivity to the phone relay. Direct
// incident submission using these stored credentials is a later increment
// (docs/COMPANION_ENROLLMENT.md §6, PR D).

import Foundation
import WatchConnectivity

final class CompanionEnrollmentClient {
    static let shared = CompanionEnrollmentClient()

    private let urlSession = URLSession(configuration: .ephemeral)

    private init() {}

    /// Entry point called by WatchSessionManager when a `companionEnrollment`
    /// message arrives, regardless of delivery path (sendMessage,
    /// transferUserInfo). Silently ignores anything that fails validation —
    /// per spec, the watch "accepts only an enrollment message coming from
    /// the associated app" and never surfaces a raw protocol error to the UI.
    func handleEnrollmentMessage(_ message: [String: Any]) {
        guard let validated = CompanionEnrollmentValidation.validate(
            message,
            expectedPlatform: "watchos"
        ) else {
            NSLog("[CompanionEnrollment] rejecting invalid or expired enrollment message")
            return
        }

        claim(token: validated.enrollmentToken)
    }

    private func claim(token: String) {
        var request = URLRequest(
            url: BackendConfiguration.baseURL.appendingPathComponent("api/v1/companion-enrollments/claim")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
        let body: [String: Any] = [
            "enrollmentToken": token,
            "platform": "watchos",
            "appVersion": appVersion,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 201,
                  let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceId = payload["deviceId"] as? String,
                  let deviceToken = payload["deviceToken"] as? String else {
                // Never log `token` or any response body — both may carry
                // durable secrets. The error/status alone is diagnosable.
                let status = (response as? HTTPURLResponse)?.statusCode
                NSLog("[CompanionEnrollment] claim failed: status=\(String(describing: status)) error=\(String(describing: error))")
                return
            }

            guard CompanionEnrollmentKeychainStore.save(
                deviceId: deviceId,
                deviceToken: deviceToken,
                schemaVersion: 1
            ) else {
                NSLog("[CompanionEnrollment] claim succeeded but Keychain write failed")
                return
            }

            NSLog("[CompanionEnrollment] enrolled successfully")
            self.confirmSuccessToPhone()
        }.resume()
    }

    /// Best-effort confirmation only — the phone does not yet gate any
    /// behavior on it, and the watch's own Keychain write is already the
    /// source of truth for whether enrollment succeeded.
    private func confirmSuccessToPhone() {
        guard WCSession.default.activationState == .activated else { return }

        let message: [String: Any] = [
            "type": "companionEnrollmentResult",
            "schemaVersion": 1,
            "status": "enrolled",
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }
}
