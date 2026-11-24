import BackgroundTasks
import Foundation
import Network
import Security
import UIKit

// MARK: - Pure queue rules (unit-tested in RunnerTests)

/// One incident waiting for (or tracked after) backend delivery.
struct RelayQueueItem: Codable, Equatable {
    static let appleWatchSource = "apple_watch"
    static let assistedPhoneSource = "assisted_phone"

    let clientAlertID: String
    let timestamp: Int64
    let source: String
    var submitted: Bool
    var cancelRequested: Bool
    let enqueuedAt: Int64
}

/// Terminal relay result Flutter imports into the local history screen.
struct RelayOutcome: Codable, Equatable {
    static let createRejected = "create_rejected"
    static let cancelTooLate = "cancel_too_late"
    static let cancelRejected = "cancel_rejected"
    static let dropped = "dropped"

    let clientAlertID: String
    let timestamp: Int64
    let outcome: String
}

enum RelayOperation {
    case create
    case createCancelled
    case cancel
}

enum RelayHTTPOutcome: Equatable {
    case success
    /// Nothing left to do (duplicate create, or cancel target already gone).
    case alreadyDone
    /// Server grace period is over; caregivers are being notified.
    case tooLate
    /// Device credentials were revoked/unknown: the user must re-pair.
    case reauthRequired
    case retry
    /// Permanent client error; retrying can never succeed.
    case rejected
}

/// Same rules as Android's NativeAlertQueue/NativeAlertRelayPolicy so both
/// platforms deduplicate, bound, cancel and retry identically.
enum RelayQueueLogic {
    static let maxItems = 20
    static let maxOutcomes = 50
    static let legacyDedupWindowMilliseconds: Int64 = 30_000
    static let submittedRetentionMilliseconds: Int64 = 10 * 60_000
    static let undeliveredRetentionMilliseconds: Int64 = 24 * 60 * 60_000

    /// Backoff for in-process retries (seconds), capped at the last value.
    static let retryDelays: [TimeInterval] = [5, 15, 30, 60, 120, 300]

    private static let uuidPattern =
        "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    private static let safeIDPattern = "^[A-Za-z0-9._:-]{1,100}$"

    static func retryDelay(attempt: Int) -> TimeInterval {
        retryDelays[min(max(attempt, 0), retryDelays.count - 1)]
    }

    /// Watch incident ids are lowercase UUIDs (36 chars) which satisfy the API
    /// clientAlertId constraint (NotBlank, max 100). Anything else is ignored.
    static func normalizedIncidentID(_ raw: String?) -> String? {
        guard let candidate = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              candidate.range(of: uuidPattern, options: .regularExpression) != nil else {
            return nil
        }
        return candidate
    }

    static func isSafeClientAlertID(_ value: String) -> Bool {
        value.range(of: safeIDPattern, options: .regularExpression) != nil
    }

    static func derivedClientAlertID(timestamp: Int64, source: String) -> String {
        source == RelayQueueItem.assistedPhoneSource
            ? "assisted-phone-\(timestamp)"
            : "apple-watch-\(timestamp)"
    }

    static func migrateLegacy(
        timestamp: Int64,
        clientAlertID: String?,
        submitted: Bool,
        cancelRequested: Bool,
        now: Int64
    ) -> [RelayQueueItem] {
        guard timestamp > 0, let clientAlertID, isSafeClientAlertID(clientAlertID) else {
            return []
        }
        return [RelayQueueItem(
            clientAlertID: clientAlertID,
            timestamp: timestamp,
            source: RelayQueueItem.appleWatchSource,
            submitted: submitted,
            cancelRequested: cancelRequested,
            enqueuedAt: now
        )]
    }

    /// Adds an incident unless it duplicates a queued one. Returns the new
    /// queue, the clientAlertId to use, and incidents dropped by the bound.
    static func enqueue(
        _ items: [RelayQueueItem],
        timestamp: Int64,
        requestedID: String?,
        source: String,
        now: Int64
    ) -> (items: [RelayQueueItem], clientAlertID: String, dropped: [RelayQueueItem]) {
        if let duplicate = items.first(where: {
            ($0.clientAlertID == requestedID) || ($0.source == source && $0.timestamp == timestamp)
        }) {
            return (items, duplicate.clientAlertID, [])
        }

        if requestedID == nil,
           let active = items
               .filter({ $0.source == source && !$0.cancelRequested })
               .max(by: { $0.timestamp < $1.timestamp }),
           timestamp >= active.timestamp,
           timestamp - active.timestamp <= legacyDedupWindowMilliseconds {
            return (items, active.clientAlertID, [])
        }

        let clientAlertID = requestedID ?? derivedClientAlertID(timestamp: timestamp, source: source)
        var updated = items
        updated.append(RelayQueueItem(
            clientAlertID: clientAlertID,
            timestamp: timestamp,
            source: source,
            submitted: false,
            cancelRequested: false,
            enqueuedAt: now
        ))

        var dropped: [RelayQueueItem] = []
        while updated.count > maxItems {
            if let index = indexOfOldest(updated, where: { $0.submitted && !$0.cancelRequested }) {
                updated.remove(at: index)
            } else if let index = indexOfOldest(updated, where: { _ in true }) {
                dropped.append(updated.remove(at: index))
            }
        }
        return (updated, clientAlertID, dropped)
    }

    /// With an incident id and/or fall timestamp only the matching incident is
    /// cancelled; without either (legacy) the most recent open incident is.
    static func requestCancel(
        _ items: [RelayQueueItem],
        incidentID: String?,
        fallTimestamp: Int64?
    ) -> [RelayQueueItem] {
        let id = incidentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = (id?.isEmpty ?? true) ? nil : id
        if normalizedID != nil || fallTimestamp != nil {
            return items.map { item in
                var copy = item
                let idMatches = normalizedID.map {
                    item.clientAlertID == $0 || item.clientAlertID == $0.lowercased()
                } ?? false
                if idMatches || item.timestamp == fallTimestamp {
                    copy.cancelRequested = true
                }
                return copy
            }
        }

        guard let latest = items
            .filter({ !$0.cancelRequested })
            .max(by: { $0.timestamp < $1.timestamp }) else { return items }
        return items.map { item in
            var copy = item
            if item.clientAlertID == latest.clientAlertID { copy.cancelRequested = true }
            return copy
        }
    }

    /// Returns kept items and the undelivered ones that expired.
    static func prune(
        _ items: [RelayQueueItem],
        now: Int64
    ) -> (kept: [RelayQueueItem], expired: [RelayQueueItem]) {
        var expired: [RelayQueueItem] = []
        let kept = items.filter { item in
            let age = now - item.enqueuedAt
            if item.submitted && !item.cancelRequested && age > submittedRetentionMilliseconds {
                return false
            }
            if age > undeliveredRetentionMilliseconds {
                if !item.submitted && !item.cancelRequested { expired.append(item) }
                return false
            }
            return true
        }
        return (kept, expired)
    }

    static func outcome(for operation: RelayOperation, status: Int) -> RelayHTTPOutcome {
        switch status {
        case 200...299:
            return .success
        case 401, 403:
            return .reauthRequired
        case ...0, 408, 429, 500...:
            return .retry
        case 409:
            return operation == .create ? .alreadyDone : .tooLate
        case 404 where operation == .cancel:
            return .alreadyDone
        default:
            return .rejected
        }
    }

    private static func indexOfOldest(
        _ items: [RelayQueueItem],
        where predicate: (RelayQueueItem) -> Bool
    ) -> Int? {
        items.indices
            .filter { predicate(items[$0]) }
            .min(by: { items[$0].timestamp < items[$1].timestamp })
    }
}

// MARK: - Relay

/// Delivers fall incidents to the API even when the Flutter engine is not
/// running. WatchConnectivity may wake the iPhone application without a UI,
/// so relying on a Dart timer would lose the server-owned grace period.
///
/// Incidents live in a small bounded queue (UserDefaults, metadata only). The
/// device bearer token remains in the Keychain and never crosses the
/// WatchConnectivity boundary. Failed deliveries are retried:
///   • in-process with exponential backoff while the app runs,
///   • immediately when the network path becomes satisfied (NWPathMonitor),
///   • via BGTaskScheduler (app refresh + processing with network) when iOS
///     wakes the app in the background later.
final class NativeAppleWatchAlertRelay {
    static let shared = NativeAppleWatchAlertRelay()

    static let refreshTaskIdentifier = "com.fallguardian.alert-relay.refresh"
    static let processingTaskIdentifier = "com.fallguardian.alert-relay.processing"

    private static let deviceTokenKey = "backend_device_token"
    /// Shared with Dart (BackendApiService) through the Keychain store.
    private static let reauthRequiredKey = "backend_reauth_required"

    private let preferences = UserDefaults.standard
    private let secureStorageService = "com.fallguardian.secure-store"
    private let stateQueue = DispatchQueue(label: "com.fallguardian.apple-watch-alert-relay")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    private let baseURLKey = "native_apple_watch_alert_relay_base_url"
    private let queueKey = "native_apple_watch_alert_queue_v2"
    private let outcomesKey = "native_apple_watch_alert_outcomes_v1"

    // Legacy single-slot keys (pre-queue). Read once, migrated, then removed.
    private let legacyTimestampKey = "native_apple_watch_alert_timestamp"
    private let legacyClientAlertIDKey = "native_apple_watch_alert_client_id"
    private let legacySubmittedKey = "native_apple_watch_alert_submitted"
    private let legacyCancelRequestedKey = "native_apple_watch_alert_cancel_requested"

    private var isRelaying = false
    private var relayAgain = false
    private var retryAttempt = 0
    private var retryWorkItem: DispatchWorkItem?
    private var pathMonitor: NWPathMonitor?
    private var pendingCompletions: [(Bool) -> Void] = []

    private init() {}

    // MARK: Public API (all thread-safe)

    /// Must be called from application(_:didFinishLaunchingWithOptions:):
    /// BGTaskScheduler only accepts registrations before launch completes.
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task)
        }
        startPathMonitor()
        // Resume anything left over from a previous process.
        relayPendingIncidents()
    }

    /// Called after Flutter has bootstrapped authenticated API access. Production
    /// builds accept HTTPS only; debug builds may use a local HTTP backend.
    func configure(baseURL: String) -> Bool {
        guard let url = validatedBaseURL(baseURL) else { return false }
        preferences.set(url.absoluteString, forKey: baseURLKey)
        stateQueue.async { self.retryAttempt = 0 }
        relayPendingIncidents()
        return true
    }

    /// Persists first, then starts the network work. Returning a stable ID lets
    /// Flutter and this native path submit/cancel one idempotent backend alert.
    func enqueueFall(timestamp: Int64, incidentID: String? = nil) -> String {
        enqueue(
            timestamp: timestamp,
            requestedID: RelayQueueLogic.normalizedIncidentID(incidentID),
            source: RelayQueueItem.appleWatchSource
        )
    }

    /// Persists an incident first seen by Flutter so it is retried natively
    /// after process death. Idempotent per clientAlertId.
    func enqueuePhoneAlert(timestamp: Int64, clientAlertID: String) -> String? {
        let id = clientAlertID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RelayQueueLogic.isSafeClientAlertID(id) else { return nil }
        return enqueue(timestamp: timestamp, requestedID: id, source: RelayQueueItem.assistedPhoneSource)
    }

    /// A cancellation can arrive before the create request completes. Keeping it
    /// durable lets the relay submit first and then cancel the same backend record.
    func requestCancel(incidentID: String? = nil, fallTimestamp: Int64? = nil) {
        stateQueue.sync {
            let items = readQueue()
            guard !items.isEmpty else { return }
            writeQueue(RelayQueueLogic.requestCancel(items, incidentID: incidentID, fallTimestamp: fallTimestamp))
        }
        relayPendingIncidents()
    }

    /// Hands terminal outcomes to Flutter (history) and forgets them.
    func takeOutcomes() -> [[String: Any]] {
        stateQueue.sync {
            let outcomes = readOutcomes()
            preferences.removeObject(forKey: outcomesKey)
            return outcomes.map {
                ["clientAlertId": $0.clientAlertID, "timestamp": $0.timestamp, "outcome": $0.outcome]
            }
        }
    }

    // MARK: Queue storage (stateQueue only)

    private func enqueue(timestamp: Int64, requestedID: String?, source: String) -> String {
        let clientAlertID: String = stateQueue.sync {
            let result = RelayQueueLogic.enqueue(
                readQueue(),
                timestamp: timestamp,
                requestedID: requestedID,
                source: source,
                now: nowMilliseconds()
            )
            writeQueue(result.items)
            result.dropped.forEach {
                recordOutcome(RelayOutcome(clientAlertID: $0.clientAlertID, timestamp: $0.timestamp, outcome: RelayOutcome.dropped))
            }
            retryAttempt = 0
            return result.clientAlertID
        }
        relayPendingIncidents()
        return clientAlertID
    }

    private func readQueue() -> [RelayQueueItem] {
        if let data = preferences.data(forKey: queueKey) {
            return (try? JSONDecoder().decode([RelayQueueItem].self, from: data)) ?? []
        }
        // First read after upgrading from the single-slot relay: carry over a
        // possibly unsent incident, then drop the legacy keys.
        let migrated = RelayQueueLogic.migrateLegacy(
            timestamp: Int64(preferences.double(forKey: legacyTimestampKey)),
            clientAlertID: preferences.string(forKey: legacyClientAlertIDKey),
            submitted: preferences.bool(forKey: legacySubmittedKey),
            cancelRequested: preferences.bool(forKey: legacyCancelRequestedKey),
            now: nowMilliseconds()
        )
        writeQueue(migrated)
        [legacyTimestampKey, legacyClientAlertIDKey, legacySubmittedKey, legacyCancelRequestedKey]
            .forEach { preferences.removeObject(forKey: $0) }
        return migrated
    }

    private func writeQueue(_ items: [RelayQueueItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        preferences.set(data, forKey: queueKey)
    }

    private func readOutcomes() -> [RelayOutcome] {
        guard let data = preferences.data(forKey: outcomesKey) else { return [] }
        return (try? JSONDecoder().decode([RelayOutcome].self, from: data)) ?? []
    }

    private func recordOutcome(_ outcome: RelayOutcome) {
        let outcomes = Array((readOutcomes() + [outcome]).suffix(RelayQueueLogic.maxOutcomes))
        guard let data = try? JSONEncoder().encode(outcomes) else { return }
        preferences.set(data, forKey: outcomesKey)
    }

    private func updateItem(_ clientAlertID: String, _ change: (inout RelayQueueItem) -> Void) {
        var items = readQueue()
        guard let index = items.firstIndex(where: { $0.clientAlertID == clientAlertID }) else { return }
        change(&items[index])
        writeQueue(items)
    }

    private func complete(_ clientAlertID: String, outcome: String?) {
        var items = readQueue()
        guard let index = items.firstIndex(where: { $0.clientAlertID == clientAlertID }) else { return }
        let item = items.remove(at: index)
        writeQueue(items)
        if let outcome {
            recordOutcome(RelayOutcome(clientAlertID: item.clientAlertID, timestamp: item.timestamp, outcome: outcome))
        }
    }

    // MARK: Relay loop

    /// Starts one relay pass (or queues another pass after the current one).
    /// [completion] reports whether everything that could be sent was sent.
    private func relayPendingIncidents(completion: ((Bool) -> Void)? = nil) {
        stateQueue.async {
            if let completion { self.pendingCompletions.append(completion) }
            if self.isRelaying {
                self.relayAgain = true
                return
            }
            self.isRelaying = true
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
            self.runPass()
        }
    }

    private func runPass() {
        let (kept, expired) = RelayQueueLogic.prune(readQueue(), now: nowMilliseconds())
        writeQueue(kept)
        expired.forEach {
            recordOutcome(RelayOutcome(clientAlertID: $0.clientAlertID, timestamp: $0.timestamp, outcome: RelayOutcome.dropped))
        }
        guard !kept.isEmpty else {
            finishPass(result: .done)
            return
        }
        guard let baseURLString = preferences.string(forKey: baseURLKey),
              let baseURL = URL(string: baseURLString),
              let token = readSecureValue(forKey: Self.deviceTokenKey),
              !token.isEmpty else {
            NSLog("[AlertRelay] incidents retained: relay is not configured or credentials are unavailable")
            // Flutter calls configure() once ready, which restarts the relay.
            finishPass(result: .done)
            return
        }

        let backgroundTask = beginBackgroundTask()
        processItems(kept.map(\.clientAlertID), baseURL: baseURL, token: token, needsRetry: false) { result in
            self.finishPass(result: result)
            self.endBackgroundTask(backgroundTask)
        }
    }

    private enum PassResult { case done, retry, reauthRequired }

    private func processItems(
        _ ids: [String],
        baseURL: URL,
        token: String,
        needsRetry: Bool,
        completion: @escaping (PassResult) -> Void
    ) {
        guard let id = ids.first else {
            completion(needsRetry ? .retry : .done)
            return
        }
        relayItem(id, baseURL: baseURL, token: token) { result in
            switch result {
            case .reauthRequired:
                completion(.reauthRequired)
            case .retry, .done:
                self.processItems(
                    Array(ids.dropFirst()),
                    baseURL: baseURL,
                    token: token,
                    needsRetry: needsRetry || result == .retry,
                    completion: completion
                )
            }
        }
    }

    private func relayItem(
        _ clientAlertID: String,
        baseURL: URL,
        token: String,
        completion: @escaping (PassResult) -> Void
    ) {
        guard let item = readQueue().first(where: { $0.clientAlertID == clientAlertID }) else {
            completion(.done)
            return
        }

        if !item.submitted {
            let operation: RelayOperation = item.cancelRequested ? .createCancelled : .create
            post(
                url: baseURL.appendingPathComponent("api/v1/fall-alerts"),
                token: token,
                payload: createPayload(for: item, cancelled: item.cancelRequested)
            ) { status in
                switch RelayQueueLogic.outcome(for: operation, status: status) {
                case .success, .alreadyDone:
                    if operation == .createCancelled {
                        self.complete(clientAlertID, outcome: nil)
                        completion(.done)
                    } else {
                        self.updateItem(clientAlertID) { $0.submitted = true }
                        // A cancel may have arrived meanwhile; handle it now.
                        self.relayItem(clientAlertID, baseURL: baseURL, token: token, completion: completion)
                    }
                case .tooLate:
                    self.complete(clientAlertID, outcome: RelayOutcome.cancelTooLate)
                    completion(.done)
                case .rejected:
                    NSLog("[AlertRelay] fall alert rejected permanently (HTTP \(status))")
                    self.complete(clientAlertID, outcome: RelayOutcome.createRejected)
                    completion(.done)
                case .reauthRequired:
                    completion(.reauthRequired)
                case .retry:
                    completion(.retry)
                }
            }
            return
        }

        guard item.cancelRequested else {
            // Submitted: the backend owns the grace period. Keep the entry
            // until retention ends so a later cancel can still be relayed.
            completion(.done)
            return
        }

        post(
            url: baseURL.appendingPathComponent("api/v1/fall-alerts/\(clientAlertID)/cancel"),
            token: token,
            payload: nil
        ) { status in
            switch RelayQueueLogic.outcome(for: .cancel, status: status) {
            case .success, .alreadyDone:
                self.complete(clientAlertID, outcome: nil)
                completion(.done)
            case .tooLate:
                self.complete(clientAlertID, outcome: RelayOutcome.cancelTooLate)
                completion(.done)
            case .rejected:
                NSLog("[AlertRelay] cancellation rejected permanently (HTTP \(status))")
                self.complete(clientAlertID, outcome: RelayOutcome.cancelRejected)
                completion(.done)
            case .reauthRequired:
                completion(.reauthRequired)
            case .retry:
                completion(.retry)
            }
        }
    }

    /// Runs on stateQueue.
    private func finishPass(result: PassResult) {
        switch result {
        case .done:
            retryAttempt = 0
        case .reauthRequired:
            // Never re-register silently: a new device has no caregiver links.
            // Flag it for the Flutter UI and keep the incidents queued; the
            // relay resumes when Flutter reconfigures after re-pairing.
            NSLog("[AlertRelay] device credentials rejected; re-pairing required")
            writeSecureValue("true", forKey: Self.reauthRequiredKey)
            retryAttempt = 0
        case .retry:
            scheduleInProcessRetry()
            scheduleBackgroundTasks()
        }

        isRelaying = false
        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(result != .retry) }

        if relayAgain {
            relayAgain = false
            relayPendingIncidents()
        }
    }

    private func scheduleInProcessRetry() {
        let delay = RelayQueueLogic.retryDelay(attempt: retryAttempt)
        retryAttempt += 1
        let work = DispatchWorkItem { [weak self] in self?.relayPendingIncidents() }
        retryWorkItem = work
        stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Background wake-ups

    private func scheduleBackgroundTasks() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        let processing = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(refresh)
            try BGTaskScheduler.shared.submit(processing)
        } catch {
            NSLog("[AlertRelay] background task scheduling failed: \(error)")
        }
    }

    private func handleBackgroundTask(_ task: BGTask) {
        // setTaskCompleted must be called exactly once.
        let lock = NSLock()
        var completed = false
        let finish = { (success: Bool) in
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = { [weak self] in
            // Work in flight keeps its state on disk; the next pass resumes it.
            self?.scheduleBackgroundTasks()
            finish(false)
        }
        relayPendingIncidents { success in finish(success) }
    }

    private func startPathMonitor() {
        stateQueue.async {
            guard self.pathMonitor == nil else { return }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                self?.stateQueue.async {
                    guard let self, self.retryWorkItem != nil else { return }
                    // Connectivity is back: retry now instead of waiting out
                    // the backoff delay.
                    self.retryAttempt = 0
                    self.relayPendingIncidents()
                }
            }
            monitor.start(queue: DispatchQueue(label: "com.fallguardian.alert-relay.path"))
            self.pathMonitor = monitor
        }
    }

    // MARK: Networking

    private func post(
        url: URL,
        token: String,
        payload: [String: Any]?,
        completion: @escaping (Int) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                stateQueue.async { completion(400) }
                return
            }
            request.httpBody = data
        }

        session.dataTask(with: request) { [weak self] _, response, error in
            let status: Int
            if let error {
                NSLog("[AlertRelay] request failed: \(error.localizedDescription)")
                status = 0
            } else {
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            }
            self?.stateQueue.async { completion(status) }
        }.resume()
    }

    private func createPayload(for item: RelayQueueItem, cancelled: Bool) -> [String: Any] {
        let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var payload: [String: Any] = [
            "clientAlertId": item.clientAlertID,
            "fallTimestamp": formatter.string(from: date),
            "locale": String((Locale.current.languageCode ?? "en").prefix(8)),
            "latitude": NSNull(),
            "longitude": NSNull(),
            "revision": 1,
            "detectionSource": item.source,
            "resolution": "unknown",
        ]
        if cancelled { payload["cancelled"] = true }
        return payload
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

    // MARK: Keychain (same item attributes as AppDelegate's secure store)

    private func secureQuery(forKey key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: secureStorageService,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    private func readSecureValue(forKey key: String) -> String? {
        var query = secureQuery(forKey: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeSecureValue(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        SecItemDelete(secureQuery(forKey: key) as CFDictionary)
        var query = secureQuery(forKey: key)
        query[kSecValueData] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[AlertRelay] keychain write failed: \(status)")
        }
    }

    // MARK: Helpers

    private func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Asks iOS for extra execution time while requests are in flight.
    /// beginBackgroundTask/endBackgroundTask are documented as callable from
    /// any thread, so no main-thread hop (which could deadlock against a
    /// main-thread stateQueue.sync caller) is needed.
    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "FallAlertRelay") {
            // Out of time: state is on disk, a scheduled BGTask resumes it.
            self.scheduleBackgroundTasks()
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        return task
    }

    private func endBackgroundTask(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
    }
}
