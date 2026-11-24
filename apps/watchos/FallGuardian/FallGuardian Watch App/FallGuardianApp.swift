import SwiftUI
import WatchKit
import CoreMotion
import UserNotifications

@main
struct FallGuardianApp: App {
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Configures services that must exist even when watchOS launches the app in the
/// background without creating the SwiftUI interface.
final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        let notificationService = WatchAlertNotificationService.shared
        notificationService.configure()
        if let active = notificationService.activeAlert() {
            WatchSessionManager.shared.restoreActiveFall(active.incident)
        }
        WatchSessionManager.shared.startSession()
        // Must be configured before SwiftUI exists: watchOS can launch this
        // extension directly in the background for an Apple fall event.
        SystemFallDetectionService.shared.configure()
        WatchSessionManager.shared.onAlertCancelled = {
            WatchAlertNotificationService.shared.clearAlert()
        }
    }
}

/// Presents the safety-critical watch alert when watchOS detects a fall while
/// the SwiftUI interface is closed. watchOS does not let third-party apps force
/// themselves into the foreground, so the system notification is the supported
/// surface that wakes the display, plays sound, and exposes a cancellation action.
final class WatchAlertNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchAlertNotificationService()

    /// An alert persisted across process launches: the incident plus the time
    /// the watch first presented it (drives the minimum display window).
    struct ActiveAlert: Equatable {
        let incident: WatchIncident
        let presentedAt: Int64
    }

    private let notificationIdentifier = "fall-guardian-active-fall"
    private let categoryIdentifier = "FALL_GUARDIAN_FALL_ALERT"
    private let openActionIdentifier = "FALL_GUARDIAN_OPEN_ALERT"
    private let activeFallTimestampKey = "active_watch_fall_timestamp"
    private let activeFallIncidentIdKey = "active_watch_fall_incident_id"
    private let activeFallPresentedAtKey = "active_watch_fall_presented_at"
    private var expiryWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // `.foreground` launches the app on its alert screen instead of
        // cancelling from a single tap: cancelling a safety alert always goes
        // through the deliberate 1.5 s hold in ContentView.
        let openAction = UNNotificationAction(
            identifier: openActionIdentifier,
            title: String(localized: "I'm OK — Open to cancel"),
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    /// Called only while the app is visible so watchOS can safely show its
    /// one-time notification permission sheet.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error {
                NSLog("[WatchAlert] notification authorization failed: \(error)")
            } else {
                NSLog("[WatchAlert] notification authorization granted=\(granted)")
            }
        }
    }

    func presentFallAlert(_ incident: WatchIncident) {
        let now = Self.nowMilliseconds()
        // Apple may deliver the event after its own check-in flow, so the
        // fall-time window can already be over: the alert is still shown for
        // the minimum display window (in the "notifying caregivers" state).
        guard WatchAlertDeadline.isDisplayable(
            timestamp: incident.timestamp,
            presentedAt: now,
            now: now
        ) else {
            clearAlert()
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(Double(incident.timestamp), forKey: activeFallTimestampKey)
        defaults.set(incident.id, forKey: activeFallIncidentIdKey)
        defaults.set(Double(now), forKey: activeFallPresentedAtKey)
        scheduleExpiry(ActiveAlert(incident: incident, presentedAt: now), now: now)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Fall detected")
        content.body = String(localized: "Open Fall Guardian and hold “I'm OK” to cancel the alert.")
        content.categoryIdentifier = categoryIdentifier
        content.sound = .default
        // Time-sensitive delivery lets the alert break through Focus. It needs
        // the com.apple.developer.usernotifications.time-sensitive entitlement.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[WatchAlert] failed to present notification: \(error)")
            }
        }
    }

    /// Lets ContentView restore the same incident when the wearer taps the
    /// notification and watchOS launches the app after background detection.
    func activeAlert(now: Int64 = WatchAlertNotificationService.nowMilliseconds()) -> ActiveAlert? {
        let defaults = UserDefaults.standard
        let timestamp = Int64(defaults.double(forKey: activeFallTimestampKey))
        let storedPresentedAt = Int64(defaults.double(forKey: activeFallPresentedAtKey))
        // Alerts persisted by an older build have no presentation time.
        let presentedAt = storedPresentedAt > 0 ? storedPresentedAt : timestamp
        guard WatchAlertDeadline.isDisplayable(
            timestamp: timestamp,
            presentedAt: presentedAt,
            now: now
        ) else {
            clearAlert()
            return nil
        }

        let incidentId: String
        if let storedId = defaults.string(forKey: activeFallIncidentIdKey), !storedId.isEmpty {
            incidentId = storedId
        } else {
            // Upgrade path: an alert stored before incident ids existed.
            incidentId = WatchIncident.make(timestamp: timestamp).id
            defaults.set(incidentId, forKey: activeFallIncidentIdKey)
        }

        let alert = ActiveAlert(
            incident: WatchIncident(id: incidentId, timestamp: timestamp),
            presentedAt: presentedAt
        )
        scheduleExpiry(alert, now: now)
        return alert
    }

    func clearAlert() {
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: activeFallTimestampKey)
        defaults.removeObject(forKey: activeFallIncidentIdKey)
        defaults.removeObject(forKey: activeFallPresentedAtKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [notificationIdentifier]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Both the notification tap and the "Open to cancel" action launch the
    /// app; ContentViewModel restores the alert from `activeAlert()`. Nothing
    /// is cancelled here.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func scheduleExpiry(_ alert: ActiveAlert, now: Int64) {
        expiryWorkItem?.cancel()
        let remainingMs = WatchAlertDeadline.displayEnd(
            timestamp: alert.incident.timestamp,
            presentedAt: alert.presentedAt
        ) - now
        guard remainingMs > 0 else {
            clearAlert()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.clearAlert()
        }
        expiryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(remainingMs)),
            execute: workItem
        )
    }
}

/// Owns Apple's system Fall Detection API.
///
/// Unlike raw accelerometer streaming, CMFallDetectionManager can wake or launch
/// the Watch app after a fall while its interface is closed. Apple supports only
/// one manager instance, hence this process-wide singleton.
final class SystemFallDetectionService: NSObject, CMFallDetectionDelegate {
    static let shared = SystemFallDetectionService()

    private let lastProcessedEventKey = "last_processed_system_fall_timestamp"
    private var manager: CMFallDetectionManager?

    var onFallDetected: ((WatchIncident) -> Void)?
    var onAuthorizationChanged: ((CMAuthorizationStatus) -> Void)?

    var isAvailable: Bool {
        CMFallDetectionManager.isAvailable
    }

    var authorizationStatus: CMAuthorizationStatus {
        manager?.authorizationStatus ?? .notDetermined
    }

    var usesSystemDetection: Bool {
        isAvailable && authorizationStatus == .authorized
    }

    private override init() {
        super.init()
    }

    /// Creates the single manager and attaches its delegate as early as possible.
    func configure() {
        guard manager == nil, CMFallDetectionManager.isAvailable else { return }
        let manager = CMFallDetectionManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Must be called from visible UI so watchOS can present the permission sheet.
    func requestAuthorizationIfNeeded() {
        configure()
        guard let manager else {
            onAuthorizationChanged?(.restricted)
            return
        }

        guard manager.authorizationStatus == .notDetermined else {
            onAuthorizationChanged?(manager.authorizationStatus)
            return
        }

        manager.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.onAuthorizationChanged?(status)
            }
        }
    }

    func fallDetectionManager(
        _ fallDetectionManager: CMFallDetectionManager,
        didDetect event: CMFallDetectionEvent,
        completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let timestamp = Int64(event.date.timeIntervalSince1970 * 1000)
        processDetectedFall(
            timestamp: timestamp,
            resolution: Self.resolution(from: event.resolution)
        )
    }

    /// Maps Apple's resolution onto the testable policy enum.
    private static func resolution(
        from resolution: CMFallDetectionEvent.UserResolution
    ) -> SystemFallResolution {
        switch resolution {
        case .confirmed: return .confirmed
        case .dismissed: return .dismissed
        case .rejected: return .rejected
        case .unresponsive: return .unresponsive
        @unknown default: return .unknown
        }
    }

    /// Sends a system-detection-style event through the same WatchConnectivity
    /// path in debug builds. This tests our relay, not Apple's sensor model.
    #if DEBUG || TESTING
    func simulateFallForTesting() {
        processDetectedFall(
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            resolution: .unresponsive
        )
    }
    #endif

    private func processDetectedFall(
        timestamp: Int64,
        resolution: SystemFallResolution
    ) {
        let defaults = UserDefaults.standard
        let lastTimestamp = Int64(defaults.double(forKey: lastProcessedEventKey))
        let decision = SystemFallPolicy.decide(
            timestamp: timestamp,
            resolution: resolution,
            lastProcessedTimestamp: lastTimestamp
        )
        NSLog("[SystemFall] resolution=\(resolution) decision=\(decision)")

        // Apple may redeliver the same event across process launches.
        guard decision != .ignoreDuplicate else { return }
        defaults.set(Double(timestamp), forKey: lastProcessedEventKey)

        // Only `rejected` stops here; `dismissed` escalates (see SystemFallPolicy).
        guard decision == .escalate else { return }

        // Identity generated once, at detection, and shared with the phone.
        let incident = WatchIncident.make(timestamp: timestamp)

        // Queue phone delivery before touching UI: background launches may never
        // construct ContentView, but the incident must still leave the Watch.
        WatchAlertNotificationService.shared.presentFallAlert(incident)
        WatchSessionManager.shared.sendFallEvent(incident)
        DispatchQueue.main.async { [weak self] in
            self?.onFallDetected?(incident)
        }
    }

    func fallDetectionManagerDidChangeAuthorization(
        _ fallDetectionManager: CMFallDetectionManager
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onAuthorizationChanged?(fallDetectionManager.authorizationStatus)
        }
    }
}
