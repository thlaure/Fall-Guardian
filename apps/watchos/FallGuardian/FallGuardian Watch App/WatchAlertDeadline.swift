// WatchAlertDeadline.swift
// Fall Guardian — watchOS
//
// Pure, platform-independent alert logic: deadlines, incident identity,
// WatchConnectivity payloads, Apple resolution policy, cancel matching, and
// the alert screen state machine.
//
// Everything here depends only on Foundation so it is unit tested on the Mac
// host by `swift test` (see ../../Package.swift) with a coverage gate. The
// framework-facing wrappers (WCSession, CMFallDetectionManager, SwiftUI,
// UserNotifications) stay thin and delegate decisions to these types.
//
// The types live in this single existing file on purpose: the production
// watch build is also compiled by apps/assisted_mobile/ios/Runner.xcodeproj,
// which lists the watch source files explicitly. Adding a new Swift file here
// would not be compiled there until that project is updated too.

import Foundation

// MARK: - Deadline

/// The shared 30-second grace window. The API owns the real escalation
/// deadline; the watch uses the same origin only to render its countdown.
enum WatchAlertDeadline {
    static let windowMilliseconds: Int64 = 30_000

    /// Minimum time the watch keeps the alert (and its hold-to-cancel control)
    /// on screen after presenting it. Apple can deliver a fall event after its
    /// own check-in flow, when the fall-time window is already over; the wearer
    /// must still get a chance to say "I'm OK".
    static let minimumDisplayMilliseconds: Int64 = 30_000

    static func isActive(timestamp: Int64, now: Int64) -> Bool {
        guard timestamp > 0, now >= timestamp else { return false }
        return now - timestamp < windowMilliseconds
    }

    static func remainingMilliseconds(timestamp: Int64, now: Int64) -> Int64 {
        guard isActive(timestamp: timestamp, now: now) else { return 0 }
        return windowMilliseconds - (now - timestamp)
    }

    /// Absolute time (ms since epoch) after which the watch hides the alert:
    /// the later of the fall-time grace deadline and the minimum display time.
    static func displayEnd(timestamp: Int64, presentedAt: Int64) -> Int64 {
        max(timestamp + windowMilliseconds, presentedAt + minimumDisplayMilliseconds)
    }

    /// Whether an alert presented at `presentedAt` must still be visible.
    static func isDisplayable(timestamp: Int64, presentedAt: Int64, now: Int64) -> Bool {
        guard timestamp > 0, presentedAt > 0 else { return false }
        return now < displayEnd(timestamp: timestamp, presentedAt: presentedAt)
    }
}

// MARK: - Incident identity

/// One fall incident. `id` is a lowercase UUID generated on the watch at
/// detection time and shared with the phone so cancels target exactly one
/// incident (millisecond timestamps alone can collide or be re-used).
struct WatchIncident: Equatable {
    let id: String
    let timestamp: Int64

    init(id: String, timestamp: Int64) {
        self.id = id.lowercased()
        self.timestamp = timestamp
    }

    static func make(timestamp: Int64, uuid: UUID = UUID()) -> WatchIncident {
        WatchIncident(id: uuid.uuidString.lowercased(), timestamp: timestamp)
    }
}

// MARK: - Persisted incident identity

/// Minimal key-value storage so identity resolution is testable without
/// UserDefaults. UserDefaults conforms as-is.
protocol WatchKeyValueStore: AnyObject {
    func string(forKey defaultName: String) -> String?
    func double(forKey defaultName: String) -> Double
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: WatchKeyValueStore {}

/// UserDefaults keys for the two places an in-flight incident is persisted:
/// the active alert (notification path) and the pending phone delivery.
enum WatchIncidentStorageKey {
    static let activeTimestamp = "active_watch_fall_timestamp"
    static let activeIncidentId = "active_watch_fall_incident_id"
    static let pendingTimestamp = "pending_watch_fall_timestamp"
    static let pendingIncidentId = "pending_watch_fall_incident_id"
    static let pendingCancelTimestamp = "pending_watch_cancel_timestamp"
    static let pendingCancelIncidentId = "pending_watch_cancel_incident_id"
}

/// A watch cancel waiting for WatchConnectivity. Persisted so a cancel made
/// right after a cold launch (before WCSession activates) is not lost.
enum WatchPendingCancel {
    static func save(_ incident: WatchIncident, store: WatchKeyValueStore) {
        store.set(Double(incident.timestamp), forKey: WatchIncidentStorageKey.pendingCancelTimestamp)
        store.set(incident.id, forKey: WatchIncidentStorageKey.pendingCancelIncidentId)
    }

    static func load(store: WatchKeyValueStore) -> WatchIncident? {
        let timestamp = Int64(store.double(forKey: WatchIncidentStorageKey.pendingCancelTimestamp))
        guard timestamp > 0,
              let id = store.string(forKey: WatchIncidentStorageKey.pendingCancelIncidentId),
              !id.isEmpty else { return nil }
        return WatchIncident(id: id, timestamp: timestamp)
    }

    /// Clears only the cancel that was delivered, so a newer pending cancel
    /// saved meanwhile survives.
    static func clear(_ delivered: WatchIncident, store: WatchKeyValueStore) {
        guard load(store: store) == delivered else { return }
        store.set(nil, forKey: WatchIncidentStorageKey.pendingCancelTimestamp)
        store.set(nil, forKey: WatchIncidentStorageKey.pendingCancelIncidentId)
    }
}

enum WatchIncidentIdentity {
    private static let slots = [
        (timestamp: WatchIncidentStorageKey.activeTimestamp, id: WatchIncidentStorageKey.activeIncidentId),
        (timestamp: WatchIncidentStorageKey.pendingTimestamp, id: WatchIncidentStorageKey.pendingIncidentId),
    ]

    /// Stable id for a persisted incident. Reuses an id already stored for the
    /// same timestamp by either path; otherwise (incident stored by a build
    /// that predates incident ids) generates ONE id and writes it to every
    /// slot holding that timestamp, so the notification path, the pending
    /// phone delivery, and therefore the phone all agree.
    static func resolve(
        timestamp: Int64,
        store: WatchKeyValueStore,
        generate: () -> String = { UUID().uuidString.lowercased() }
    ) -> String {
        let matching = slots.filter { Int64(store.double(forKey: $0.timestamp)) == timestamp }
        let existing = matching
            .compactMap { store.string(forKey: $0.id) }
            .first { !$0.isEmpty }
        let id = (existing ?? generate()).lowercased()
        for slot in matching where store.string(forKey: slot.id) != id {
            store.set(id, forKey: slot.id)
        }
        return id
    }
}

// MARK: - WatchConnectivity contract

/// Dictionary keys exchanged with the assisted iPhone app. Only ADD keys:
/// older phone builds read `event`, `timestamp`, `fallTimestamp`, and
/// `alertCancelled` and ignore everything else.
enum WatchMessageKey {
    static let event = "event"
    static let timestamp = "timestamp"
    static let fallTimestamp = "fallTimestamp"
    static let incidentId = "incidentId"
    static let alertCancelled = "alertCancelled"
    static let thresholds = "thresholds"
}

enum WatchMessageEvent {
    static let fallDetected = "fall_detected"
    static let alertCancelled = "alert_cancelled"
    static let setThresholds = "set_thresholds"
}

enum WatchPayloads {
    /// watch → phone fall event. `timestamp` stays the countdown origin used by
    /// every phone version; `incidentId` is additive.
    static func fallDetected(_ incident: WatchIncident) -> [String: Any] {
        [
            WatchMessageKey.event: WatchMessageEvent.fallDetected,
            WatchMessageKey.timestamp: incident.timestamp,
            WatchMessageKey.incidentId: incident.id,
        ]
    }

    /// watch → phone cancel. Identifies the incident so a newer phone can ignore
    /// a late cancel aimed at a previous fall. Older phones read only `event`.
    static func alertCancelled(_ incident: WatchIncident?) -> [String: Any] {
        var message: [String: Any] = [WatchMessageKey.event: WatchMessageEvent.alertCancelled]
        if let incident {
            message[WatchMessageKey.fallTimestamp] = incident.timestamp
            message[WatchMessageKey.incidentId] = incident.id
        }
        return message
    }

    /// Reads an integer timestamp whatever numeric type WatchConnectivity or a
    /// test used to box it. Returns nil for missing or non-numeric values.
    static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        // Int64(exactly:) returns nil for NaN, infinity, and out-of-range
        // values instead of trapping on hostile input.
        case let value as Double: return Int64(exactly: value.rounded(.towardZero))
        default: return nil
        }
    }
}

/// Decides whether a phone → watch cancel applies to the alert on screen.
enum WatchCancelMatcher {
    /// - With `incidentId`: accepted only when it equals the active incident.
    /// - Without (older phone): accepted only when `fallTimestamp` equals the
    ///   active incident timestamp — the pre-existing behaviour.
    static func accepts(_ message: [String: Any], active: WatchIncident?) -> Bool {
        guard let active else { return false }
        if let incidentId = message[WatchMessageKey.incidentId] as? String, !incidentId.isEmpty {
            return incidentId.lowercased() == active.id
        }
        return WatchPayloads.int64(message[WatchMessageKey.fallTimestamp]) == active.timestamp
    }

    /// The durable application context additionally needs `alertCancelled == true`
    /// because the phone also publishes `alertCancelled: false` for new incidents.
    static func acceptsApplicationContext(_ context: [String: Any], active: WatchIncident?) -> Bool {
        guard context[WatchMessageKey.alertCancelled] as? Bool == true else { return false }
        return accepts(context, active: active)
    }
}

// MARK: - Apple fall resolution policy

/// Mirror of `CMFallDetectionEvent.UserResolution` (CoreMotion's type is not
/// available on the macOS test host).
enum SystemFallResolution: Equatable {
    /// The wearer told watchOS they fell and need help.
    case confirmed
    /// The wearer dismissed Apple's alert, immediately or after its haptics
    /// and chimes. This does NOT mean "I'm OK": a disoriented person can
    /// swipe the prompt away.
    case dismissed
    /// The wearer told watchOS they did not fall.
    case rejected
    /// The wearer did not answer Apple's prompt.
    case unresponsive
    /// A resolution added by a future watchOS version.
    case unknown
}

enum SystemFallDecision: Equatable {
    /// Start the Fall Guardian alert and relay the event to the phone.
    case escalate
    /// Not a fall: nothing to do.
    case ignoreRejected
    /// Already processed (Apple can redeliver across launches).
    case ignoreDuplicate
}

enum SystemFallPolicy {
    /// Decision for one Apple fall event.
    ///
    /// Only `rejected` (the wearer told watchOS they did not fall) is ignored.
    /// `dismissed` escalates: Apple uses it whenever its alert was dismissed,
    /// which a disoriented person can do; the 30-second hold-to-cancel covers
    /// the genuine "I'm fine" case. Unknown future resolutions escalate too:
    /// a missed fall is worse than a cancellable false alarm.
    static func decide(
        timestamp: Int64,
        resolution: SystemFallResolution,
        lastProcessedTimestamp: Int64
    ) -> SystemFallDecision {
        guard timestamp > lastProcessedTimestamp else { return .ignoreDuplicate }
        switch resolution {
        case .rejected: return .ignoreRejected
        case .confirmed, .dismissed, .unresponsive, .unknown: return .escalate
        }
    }
}

// MARK: - Alert screen state machine

/// What the alert screen shows.
enum WatchAlertPhase: Equatable {
    /// Seconds left in the grace window, always >= 1.
    case countdown(seconds: Int)
    /// Grace window over (or the event arrived late): the phone/API is
    /// escalating. Cancel stays available.
    case notifyingCaregivers
}

/// How a wearer's cancel relates to the grace window.
enum WatchCancelOutcome: Equatable {
    /// Cancelled within the window: the API should not escalate.
    case beforeDeadline
    /// Cancelled after the window: the cancel is still relayed, but
    /// caregivers may already have been notified. The UI must say so.
    case afterDeadline
}

enum WatchAlertHapticCue: Equatable {
    case tick
    case urgent
}

/// Pure state machine behind ContentViewModel.
struct WatchAlertState: Equatable {
    private(set) var incident: WatchIncident?
    private(set) var presentedAt: Int64 = 0

    var isActive: Bool { incident != nil }

    /// Starts an alert. Returns false when one is already active or the
    /// incident is too old to show (e.g. restored long after the fact).
    mutating func start(_ incident: WatchIncident, presentedAt: Int64, now: Int64) -> Bool {
        guard self.incident == nil,
              WatchAlertDeadline.isDisplayable(
                  timestamp: incident.timestamp,
                  presentedAt: presentedAt,
                  now: now
              ) else { return false }
        self.incident = incident
        self.presentedAt = presentedAt
        return true
    }

    /// Current phase, or nil when no alert should be displayed.
    func phase(now: Int64) -> WatchAlertPhase? {
        guard let incident,
              WatchAlertDeadline.isDisplayable(
                  timestamp: incident.timestamp,
                  presentedAt: presentedAt,
                  now: now
              ) else { return nil }
        let remainingMs = WatchAlertDeadline.remainingMilliseconds(
            timestamp: incident.timestamp,
            now: now
        )
        guard remainingMs > 0 else { return .notifyingCaregivers }
        // Round up so the screen never shows 0 while time remains.
        return .countdown(seconds: Int((remainingMs + 999) / 1000))
    }

    /// Whether cancelling now beats the grace deadline; nil without an alert.
    func cancelOutcome(now: Int64) -> WatchCancelOutcome? {
        guard let incident else { return nil }
        return WatchAlertDeadline.isActive(timestamp: incident.timestamp, now: now)
            ? .beforeDeadline
            : .afterDeadline
    }

    /// Ends the alert and returns the incident that was active, if any.
    @discardableResult
    mutating func finish() -> WatchIncident? {
        let finished = incident
        incident = nil
        presentedAt = 0
        return finished
    }

    /// Haptic to play when the phase changes. Ticks during the countdown, a
    /// stronger cue for the last 10 seconds and when escalation starts.
    static func hapticCue(from previous: WatchAlertPhase?, to current: WatchAlertPhase?) -> WatchAlertHapticCue? {
        guard let current, current != previous else { return nil }
        switch current {
        case .countdown(let seconds): return seconds <= 10 ? .urgent : .tick
        case .notifyingCaregivers: return .urgent
        }
    }

    /// VoiceOver announces milestones instead of every second.
    static func shouldAnnounce(_ phase: WatchAlertPhase?, previous: WatchAlertPhase?) -> Bool {
        guard let phase, phase != previous else { return false }
        switch phase {
        case .countdown(let seconds): return [30, 20, 10, 5].contains(seconds)
        case .notifyingCaregivers: return true
        }
    }
}
