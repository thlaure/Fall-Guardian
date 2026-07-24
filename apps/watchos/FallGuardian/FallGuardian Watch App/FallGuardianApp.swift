import SwiftUI
import WatchKit
import CoreMotion

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
        WatchSessionManager.shared.startSession()
        SystemFallDetectionService.shared.configure()
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

    var onFallDetected: ((Int64) -> Void)?
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
        let defaults = UserDefaults.standard
        let lastTimestamp = Int64(defaults.double(forKey: lastProcessedEventKey))

        // Apple may redeliver the same event across process launches.
        guard timestamp > lastTimestamp else { return }
        defaults.set(Double(timestamp), forKey: lastProcessedEventKey)

        // "Rejected" explicitly means the wearer told watchOS they did not fall.
        guard event.resolution != .rejected else { return }

        // Queue phone delivery before touching UI: background launches may never
        // construct ContentView, but the incident must still leave the Watch.
        WatchSessionManager.shared.sendFallEvent(timestamp: timestamp)
        DispatchQueue.main.async { [weak self] in
            self?.onFallDetected?(timestamp)
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
