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
    /// The wearer answered Apple's prompt: they fell but are OK.
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
    /// The wearer already said "I'm OK" to Apple: record locally, no alert.
    case recordDismissed
    /// Not a fall: nothing to do.
    case ignoreRejected
    /// Already processed (Apple can redeliver across launches).
    case ignoreDuplicate
}

enum SystemFallPolicy {
    /// Decision for one Apple fall event.
    ///
    /// `dismissed` is NOT forwarded to the phone: the current phone contract has
    /// no "resolved without alert" event, and sending `alert_cancelled` for an
    /// incident the phone never saw could cancel a different, real incident on
    /// phone builds that do not check incident identity. It is only recorded.
    /// Unknown future resolutions escalate: a missed fall is worse than a
    /// cancellable false alarm.
    static func decide(
        timestamp: Int64,
        resolution: SystemFallResolution,
        lastProcessedTimestamp: Int64
    ) -> SystemFallDecision {
        guard timestamp > lastProcessedTimestamp else { return .ignoreDuplicate }
        switch resolution {
        case .rejected: return .ignoreRejected
        case .dismissed: return .recordDismissed
        case .confirmed, .unresponsive, .unknown: return .escalate
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
