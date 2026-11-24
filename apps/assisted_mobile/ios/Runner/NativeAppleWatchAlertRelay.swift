import BackgroundTasks
import Foundation
import Network
import Security
import UIKit

// MARK: - Pure queue rules (unit-tested in RunnerTests)

/// One incident waiting for (or tracked after) backend delivery.
///
/// `aliases` holds other ids the same physical incident is known by (e.g. a
/// watch UUID that arrived after the incident was queued under its legacy
/// `apple-watch-<ts>` id). Optional so entries stored before it decode.
struct RelayQueueItem: Codable, Equatable {
    static let appleWatchSource = "apple_watch"
    static let assistedPhoneSource = "assisted_phone"

    let clientAlertID: String
    let timestamp: Int64
    let source: String
    var submitted: Bool
    var cancelRequested: Bool
    let enqueuedAt: Int64
    var aliases: [String]?

    func isKnownAs(_ id: String) -> Bool {
        clientAlertID == id || (aliases ?? []).contains(id)
    }
}

/// A targeted cancel that arrived before its fall was queued. Kept briefly
/// so the late fall is queued already cancelled instead of escalating.
struct CancelTombstone: Codable, Equatable {
    let incidentID: String?
    let fallTimestamp: Int64?
    let createdAt: Int64

    func matches(_ item: RelayQueueItem) -> Bool {
        if let incidentID, item.isKnownAs(incidentID) { return true }
        if let fallTimestamp, item.timestamp == fallTimestamp { return true }
        return false
    }
}

/// Terminal relay result Flutter imports into the local history screen.
struct RelayOutcome: Codable, Equatable {
    static let createRejected = "create_rejected"
    static let cancelTooLate = "cancel_too_late"
    static let cancelRejected = "cancel_rejected"
    static let cancelUnconfirmed = "cancel_unconfirmed"
    static let cancelledUnsent = "cancelled_unsent"
    static let dropped = "dropped"
    static let repairNotDelivered = "repair_not_delivered"
    /// Success: the backend accepted the incident (grace period running).
    static let created = "created"
    /// Success: the backend confirmed the cancellation (or never had it).
    static let cancelled = "cancelled"

    let clientAlertID: String
    let timestamp: Int64
    let outcome: String

    /// Stable key Flutter echoes back to acknowledge a persisted outcome.
    var key: String { "\(clientAlertID)|\(timestamp)|\(outcome)" }
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
    /// Device credentials were revoked/unknown (401): the user must re-pair.
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
    static let maxTombstones = 20
    static let legacyDedupWindowMilliseconds: Int64 = 30_000
    static let tombstoneTTLMilliseconds: Int64 = 2 * 60_000
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

    static func pruneTombstones(_ tombstones: [CancelTombstone], now: Int64) -> [CancelTombstone] {
        tombstones.filter { now - $0.createdAt >= 0 && now - $0.createdAt <= tombstoneTTLMilliseconds }
    }

    /// Adds an incident unless it duplicates a queued one (then a new id is
    /// remembered as an alias). A matching cancel tombstone queues it
    /// already cancelled. Returns the new queue, the clientAlertId to use,
    /// incidents dropped by the bound, and the remaining tombstones.
    static func enqueue(
        _ items: [RelayQueueItem],
        timestamp: Int64,
        requestedID: String?,
        source: String,
        now: Int64,
        tombstones: [CancelTombstone] = []
    ) -> (items: [RelayQueueItem], clientAlertID: String, dropped: [RelayQueueItem], tombstones: [CancelTombstone]) {
        var live = pruneTombstones(tombstones, now: now)
        if let index = items.firstIndex(where: {
            (requestedID.map($0.isKnownAs) ?? false) || ($0.source == source && $0.timestamp == timestamp)
        }) {
            var updated = items
            if let requestedID, !updated[index].isKnownAs(requestedID) {
                updated[index].aliases = (updated[index].aliases ?? []) + [requestedID]
            }
            return (updated, items[index].clientAlertID, [], live)
        }

        if requestedID == nil,
           let active = items
               .filter({ $0.source == source && !$0.cancelRequested })
               .max(by: { $0.timestamp < $1.timestamp }),
           timestamp >= active.timestamp,
           timestamp - active.timestamp <= legacyDedupWindowMilliseconds {
            return (items, active.clientAlertID, [], live)
        }

        let clientAlertID = requestedID ?? derivedClientAlertID(timestamp: timestamp, source: source)
        var newItem = RelayQueueItem(
            clientAlertID: clientAlertID,
            timestamp: timestamp,
            source: source,
            submitted: false,
            cancelRequested: false,
            enqueuedAt: now
        )
        if let tombstoneIndex = live.firstIndex(where: { $0.matches(newItem) }) {
            newItem.cancelRequested = true
            live.remove(at: tombstoneIndex)
        }
        var updated = items
        updated.append(newItem)

        var dropped: [RelayQueueItem] = []
        while updated.count > maxItems {
            if let index = indexOfOldest(updated, where: { $0.submitted && !$0.cancelRequested }) {
                updated.remove(at: index)
            } else if let index = indexOfOldest(updated, where: { _ in true }) {
                dropped.append(updated.remove(at: index))
            }
        }
        return (updated, clientAlertID, dropped, live)
    }

    /// With an incident id and/or fall timestamp only the matching incident is
    /// cancelled; if none is queued yet a short-lived tombstone is kept.
    /// Without either (legacy) the most recent open incident is cancelled, and
    /// never a tombstone: it could cancel an unrelated genuine fall.
    static func requestCancel(
        _ items: [RelayQueueItem],
        incidentID: String?,
        fallTimestamp: Int64?,
        now: Int64 = 0,
        tombstones: [CancelTombstone] = []
    ) -> (items: [RelayQueueItem], tombstones: [CancelTombstone]) {
        let live = pruneTombstones(tombstones, now: now)
        let id = incidentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = (id?.isEmpty ?? true) ? nil : id
        if normalizedID != nil || fallTimestamp != nil {
            var matched = false
            let updated = items.map { item -> RelayQueueItem in
                var copy = item
                let idMatches = normalizedID.map {
                    item.isKnownAs($0) || item.isKnownAs($0.lowercased())
                } ?? false
                if idMatches || item.timestamp == fallTimestamp {
                    copy.cancelRequested = true
                    matched = true
                }
                return copy
            }
            if matched { return (updated, live) }
            let tombstone = CancelTombstone(
                incidentID: normalizedID.map { normalizedIncidentID($0) ?? $0 },
                fallTimestamp: fallTimestamp,
                createdAt: now
            )
            return (items, Array((live + [tombstone]).suffix(maxTombstones)))
        }

        guard let latest = items
            .filter({ !$0.cancelRequested })
            .max(by: { $0.timestamp < $1.timestamp }) else { return (items, live) }
        return (items.map { item in
            var copy = item
            if item.clientAlertID == latest.clientAlertID { copy.cancelRequested = true }
            return copy
        }, live)
    }

    /// Returns kept items and outcomes for everything that expired: nothing
    /// leaves the queue silently except a submitted, uncancelled incident.
    static func prune(
        _ items: [RelayQueueItem],
        now: Int64
    ) -> (kept: [RelayQueueItem], outcomes: [RelayOutcome]) {
        var outcomes: [RelayOutcome] = []
        let kept = items.filter { item in
            let age = now - item.enqueuedAt
            if item.submitted && !item.cancelRequested && age > submittedRetentionMilliseconds {
                return false
            }
            if age > undeliveredRetentionMilliseconds {
                let outcome = item.submitted
                    ? RelayOutcome.cancelUnconfirmed
                    : (item.cancelRequested ? RelayOutcome.cancelledUnsent : RelayOutcome.dropped)
                outcomes.append(RelayOutcome(clientAlertID: item.clientAlertID, timestamp: item.timestamp, outcome: outcome))
                return false
            }
            return true
        }
        return (kept, outcomes)
    }

    /// Re-pairing registers a new, caregiver-less device: queued incidents
    /// are reported instead of being sent silently under it.
    static func discardForRepair(_ items: [RelayQueueItem]) -> [RelayOutcome] {
        items.compactMap { item in
            let outcome: String?
            switch (item.submitted, item.cancelRequested) {
            case (false, false): outcome = RelayOutcome.repairNotDelivered
            case (true, true): outcome = RelayOutcome.cancelUnconfirmed
            case (false, true): outcome = RelayOutcome.cancelledUnsent
            case (true, false): outcome = nil // the old backend owns it
            }
            return outcome.map {
                RelayOutcome(clientAlertID: item.clientAlertID, timestamp: item.timestamp, outcome: $0)
            }
        }
    }

    static func outcome(for operation: RelayOperation, status: Int) -> RelayHTTPOutcome {
        switch status {
        case 200...299:
            return .success
        // Only 401 means the token is unknown. 403 can be transient
        // (edge/WAF policy) and must never stop delivery: retry it.
        case 401:
            return .reauthRequired
        case ...0, 403, 408, 429, 500...:
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

/// One watch cancel waiting to be delivered to Flutter.
struct PendingCancelEntry: Codable, Equatable {
    let entryID: String
    let incidentID: String?
    let fallTimestamp: Int64?
}

/// Small persistent list of watch cancels not yet confirmed delivered to
/// Flutter. A list (not a single slot) so a legacy untargeted cancel can
/// never overwrite a targeted one; entries are removed only once Flutter's
/// handler succeeded.
enum PendingCancelList {
    static let maxEntries = 20

    static func add(_ entries: [PendingCancelEntry], _ entry: PendingCancelEntry) -> [PendingCancelEntry] {
        let duplicate = entries.contains {
            $0.incidentID == entry.incidentID && $0.fallTimestamp == entry.fallTimestamp
        }
        return duplicate ? entries : Array((entries + [entry]).suffix(maxEntries))
    }

    static func remove(_ entries: [PendingCancelEntry], entryID: String) -> [PendingCancelEntry] {
        entries.filter { $0.entryID != entryID }
    }

    /// Pre-list builds stored one flag plus an optional target.
    static func migrateLegacy(pending: Bool, incidentID: String?, fallTimestamp: Int64?) -> [PendingCancelEntry] {
        pending ? [PendingCancelEntry(entryID: "legacy", incidentID: incidentID, fallTimestamp: fallTimestamp)] : []
    }
}

/// Which incident the native wake-up notification currently shows.
struct DisplayedFallNotification: Codable, Equatable {
    let clientAlertID: String?
    let watchIncidentID: String?
    let timestamp: Int64
}

/// A delayed, targeted cancel for incident A must never remove the
/// notification of a newer incident B; only legacy untargeted cancels
/// dismiss unconditionally.
enum FallNotificationMatch {
    static func shouldDismiss(
        displayed: DisplayedFallNotification?,
        incidentID: String?,
        fallTimestamp: Int64?
    ) -> Bool {
        if incidentID == nil && fallTimestamp == nil { return true }
        // Unknown displayed incident: keep it rather than risk hiding a
        // different, still-active fall.
        guard let displayed else { return false }
        if let id = incidentID?.lowercased(),
           id == displayed.clientAlertID?.lowercased() || id == displayed.watchIncidentID {
            return true
        }
        if let fallTimestamp, fallTimestamp == displayed.timestamp { return true }
        return false
    }
}

/// Guards a UIKit background task so it is ended exactly once, whether by
/// the normal completion path or by the expiration handler.
final class BackgroundTaskToken {
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var ended = false

    func set(_ identifier: UIBackgroundTaskIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        if ended {
            // Expired before begin returned: end it right away.
            if identifier != .invalid { endTask(identifier) }
            return
        }
        self.identifier = identifier
    }

    /// Returns true only for the first call.
    @discardableResult
    func end(_ endTask: (UIBackgroundTaskIdentifier) -> Void = { UIApplication.shared.endBackgroundTask($0) }) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return false }
        ended = true
        if identifier != .invalid { endTask(identifier) }
        identifier = .invalid
        return true
    }

    private func endTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
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
    private let tombstonesKey = "native_apple_watch_alert_cancel_tombstones_v1"

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

    /// A cancellation can arrive before the create request completes, or even
    /// before the fall itself (targeted cancels then leave a short-lived
    /// tombstone so the late fall is queued already cancelled).
    func requestCancel(incidentID: String? = nil, fallTimestamp: Int64? = nil) {
        stateQueue.sync {
            let result = RelayQueueLogic.requestCancel(
                readQueue(),
                incidentID: incidentID,
                fallTimestamp: fallTimestamp,
                now: nowMilliseconds(),
                tombstones: readTombstones()
            )
            writeQueue(result.items)
            writeTombstones(result.tombstones)
        }
        relayPendingIncidents()
    }

    /// Terminal outcomes for Flutter's history. They stay stored until
    /// Flutter acknowledges them after persisting ([acknowledgeOutcomes]).
    func peekOutcomes() -> [[String: Any]] {
        stateQueue.sync {
            readOutcomes().map {
                [
                    "clientAlertId": $0.clientAlertID,
                    "timestamp": $0.timestamp,
                    "outcome": $0.outcome,
                    "key": $0.key,
                ]
            }
        }
    }

    func acknowledgeOutcomes(keys: [String]) {
        stateQueue.sync {
            let remaining = readOutcomes().filter { !keys.contains($0.key) }
            writeOutcomes(remaining)
        }
    }

    /// Called before the phone re-registers as a new device: queued incidents
    /// must not be sent under the new, caregiver-less registration. They are
    /// reported instead (history: caregivers may not have been reached).
    @discardableResult
    func discardForRepair() -> Int {
        stateQueue.sync {
            let items = readQueue()
            RelayQueueLogic.discardForRepair(items).forEach(recordOutcome)
            writeQueue([])
            writeTombstones([])
            return items.count
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
                now: nowMilliseconds(),
                tombstones: readTombstones()
            )
            writeQueue(result.items)
            writeTombstones(result.tombstones)
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
        writeOutcomes(Array((readOutcomes() + [outcome]).suffix(RelayQueueLogic.maxOutcomes)))
    }

    private func writeOutcomes(_ outcomes: [RelayOutcome]) {
        guard let data = try? JSONEncoder().encode(outcomes) else { return }
        preferences.set(data, forKey: outcomesKey)
    }

    private func readTombstones() -> [CancelTombstone] {
        guard let data = preferences.data(forKey: tombstonesKey) else { return [] }
        return (try? JSONDecoder().decode([CancelTombstone].self, from: data)) ?? []
    }

    private func writeTombstones(_ tombstones: [CancelTombstone]) {
        guard let data = try? JSONEncoder().encode(tombstones) else { return }
        preferences.set(data, forKey: tombstonesKey)
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
        let (kept, expiredOutcomes) = RelayQueueLogic.prune(readQueue(), now: nowMilliseconds())
        writeQueue(kept)
        expiredOutcomes.forEach(recordOutcome)
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
            backgroundTask.end()
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
                        self.complete(clientAlertID, outcome: RelayOutcome.cancelled)
                        completion(.done)
                    } else {
                        self.updateItem(clientAlertID) { $0.submitted = true }
                        // Lets Flutter upgrade a provisional "failed" history entry.
                        self.recordOutcome(RelayOutcome(
                            clientAlertID: clientAlertID,
                            timestamp: item.timestamp,
                            outcome: RelayOutcome.created
                        ))
                        // A cancel may have arrived meanwhile; handle it now.
                        self.relayItem(clientAlertID, baseURL: baseURL, token: token, completion: completion)
                    }
                case .tooLate:
                    self.complete(clientAlertID, outcome: RelayOutcome.cancelTooLate)
                    completion(.done)
                case .rejected:
                    NSLog("[AlertRelay] fall alert rejected permanently (HTTP \(status))")
                    self.complete(
                        clientAlertID,
                        outcome: item.cancelRequested ? RelayOutcome.cancelRejected : RelayOutcome.createRejected
                    )
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
                // Lets Flutter upgrade a provisional "cancellation pending" entry.
                self.complete(clientAlertID, outcome: RelayOutcome.cancelled)
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
            // 401 only (403 is retried). Never re-register silently: a new
            // device has no caregiver links.
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
    /// The returned token ends the task exactly once, whichever of the
    /// expiration handler or the normal completion runs first.
    private func beginBackgroundTask() -> BackgroundTaskToken {
        let token = BackgroundTaskToken()
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "FallAlertRelay") { [weak self] in
            // Out of time: state is on disk, a scheduled BGTask resumes it.
            self?.scheduleBackgroundTasks()
            token.end()
        }
        token.set(identifier)
        return token
    }
}
