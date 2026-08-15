import Foundation
import Security
import UIKit

/// Delivers Apple Watch fall incidents to the API even when the Flutter engine
/// is not running. WatchConnectivity may wake the iPhone application without a
/// UI, so relying on a Dart timer would lose the server-owned grace period.
///
/// The relay intentionally stores only the incident metadata in UserDefaults.
/// The device bearer token remains in the Keychain and never crosses the
/// WatchConnectivity boundary.
final class NativeAppleWatchAlertRelay {
    static let shared = NativeAppleWatchAlertRelay()

    private static let deviceTokenKey = "backend_device_token"
    private let preferences = UserDefaults.standard
    private let secureStorageService = "com.fallguardian.secure-store"
    private let queue = DispatchQueue(label: "com.fallguardian.apple-watch-alert-relay")

    private let baseURLKey = "native_apple_watch_alert_relay_base_url"
    private let timestampKey = "native_apple_watch_alert_timestamp"
    private let clientAlertIDKey = "native_apple_watch_alert_client_id"
    private let submittedKey = "native_apple_watch_alert_submitted"
    private let cancelRequestedKey = "native_apple_watch_alert_cancel_requested"
    private let activeIncidentWindowMilliseconds: Int64 = 30_000
    private var isRelaying = false

    private init() {}

    /// Called after Flutter has bootstrapped authenticated API access. Production
    /// builds accept HTTPS only; debug builds may use a local HTTP backend.
    func configure(baseURL: String) -> Bool {
        guard let url = validatedBaseURL(baseURL) else { return false }
        preferences.set(url.absoluteString, forKey: baseURLKey)
        relayPendingIncident()
        return true
    }

    /// Persists first, then starts the network work. Returning a stable ID lets
    /// Flutter and this native path submit/cancel one idempotent backend alert.
    func enqueueFall(timestamp: Int64) -> String {
        let existingTimestamp = Int64(preferences.double(forKey: timestampKey))
        if let existingID = preferences.string(forKey: clientAlertIDKey),
           timestamp >= existingTimestamp,
           timestamp - existingTimestamp <= activeIncidentWindowMilliseconds {
            relayPendingIncident()
            return existingID
        }

        let clientAlertID = "apple-watch-\(timestamp)"
        preferences.set(Double(timestamp), forKey: timestampKey)
        preferences.set(clientAlertID, forKey: clientAlertIDKey)
        preferences.set(false, forKey: submittedKey)
        preferences.set(false, forKey: cancelRequestedKey)
        relayPendingIncident()
        return clientAlertID
    }

    /// A cancellation can arrive before the create request completes. Keeping it
    /// durable lets the relay submit first and then cancel the same backend record.
    func requestCancel() {
        guard preferences.string(forKey: clientAlertIDKey) != nil else { return }
        preferences.set(true, forKey: cancelRequestedKey)
        relayPendingIncident()
    }

    private func relayPendingIncident() {
        queue.async { [weak self] in
            guard let self, !self.isRelaying else { return }
            self.isRelaying = true

            Task {
                defer {
                    self.queue.async { self.isRelaying = false }
                }
                await self.sendPendingIncident()
            }
        }
    }

    private func sendPendingIncident() async {
        guard let incident = pendingIncident(),
              let baseURLString = preferences.string(forKey: baseURLKey),
              let baseURL = URL(string: baseURLString),
              let token = readSecureValue(forKey: Self.deviceTokenKey),
              !token.isEmpty else {
            NSLog("[AppleWatchAlertRelay] incident retained: relay is not configured or credentials are unavailable")
            return
        }

        let backgroundTask = beginBackgroundTask()
        defer { endBackgroundTask(backgroundTask) }

        var current = incident
        if !current.submitted {
            let created = await postJSON(
                url: baseURL.appendingPathComponent("api/v1/fall-alerts"),
                token: token,
                payload: createPayload(for: current)
            )
            guard created else {
                NSLog("[AppleWatchAlertRelay] create failed; incident retained for a later relay")
                return
            }
            preferences.set(true, forKey: submittedKey)
            current.submitted = true
        }

        guard current.cancelRequested || preferences.bool(forKey: cancelRequestedKey) else { return }
        let cancelled = await postJSON(
            url: baseURL.appendingPathComponent("api/v1/fall-alerts/\(current.clientAlertID)/cancel"),
            token: token,
            payload: nil
        )
        if cancelled {
            clearIncident(clientAlertID: current.clientAlertID)
        } else {
            NSLog("[AppleWatchAlertRelay] cancel failed; incident retained for a later relay")
        }
    }

    private func postJSON(url: URL, token: String, payload: [String: Any]?) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
            request.httpBody = data
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            NSLog("[AppleWatchAlertRelay] request failed: \(error)")
            return false
        }
    }

    private func createPayload(for incident: PendingIncident) -> [String: Any] {
        let date = Date(timeIntervalSince1970: TimeInterval(incident.timestamp) / 1000)
        return [
            "clientAlertId": incident.clientAlertID,
            "fallTimestamp": ISO8601DateFormatter().string(from: date),
            "locale": Locale.current.languageCode ?? "en",
            "latitude": NSNull(),
            "longitude": NSNull(),
            "revision": 1,
            "detectionSource": "apple_watch",
            "resolution": "unknown",
        ]
    }

    private func pendingIncident() -> PendingIncident? {
        let timestamp = Int64(preferences.double(forKey: timestampKey))
        guard timestamp > 0,
              let clientAlertID = preferences.string(forKey: clientAlertIDKey),
              !clientAlertID.isEmpty else { return nil }
        return PendingIncident(
            timestamp: timestamp,
            clientAlertID: clientAlertID,
            submitted: preferences.bool(forKey: submittedKey),
            cancelRequested: preferences.bool(forKey: cancelRequestedKey)
        )
    }

    private func clearIncident(clientAlertID: String) {
        guard preferences.string(forKey: clientAlertIDKey) == clientAlertID else { return }
        preferences.removeObject(forKey: timestampKey)
        preferences.removeObject(forKey: clientAlertIDKey)
        preferences.removeObject(forKey: submittedKey)
        preferences.removeObject(forKey: cancelRequestedKey)
    }

    private func validatedBaseURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host != nil else { return nil }
        #if DEBUG
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        #else
        guard url.scheme == "https" else { return nil }
        #endif
        return url
    }

    private func readSecureValue(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: secureStorageService,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        var task = UIBackgroundTaskIdentifier.invalid
        let begin = {
            task = UIApplication.shared.beginBackgroundTask(withName: "AppleWatchFallRelay") {}
        }
        if Thread.isMainThread {
            begin()
        } else {
            DispatchQueue.main.sync(execute: begin)
        }
        return task
    }

    private func endBackgroundTask(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

private struct PendingIncident {
    let timestamp: Int64
    let clientAlertID: String
    var submitted: Bool
    let cancelRequested: Bool
}
