// Foundation is Apple's base library: strings, dates, files, networking primitives.
// We need it for FileManager (IPC flag files) and Date (timestamps).
import Foundation

// WatchConnectivity is Apple's official framework for iPhone ↔ Apple Watch
// communication. It provides WCSession — a singleton that manages the Bluetooth/
// Wi-Fi link between the paired devices. All messages between the phone app and
// the watchOS app flow through WCSession.
import WatchConnectivity

// Flutter is needed here to reference FlutterMethodChannel, the named pipe
// we use to forward watch events to the Dart side of the phone app.
import Flutter
import UIKit
import UserNotifications  // For showing a native fall alert when Flutter is not yet ready

// MARK: - WatchSessionManager
//
// Role in the system
// ──────────────────
// This class is the bridge between two separate worlds:
//
//   [Apple Watch / watchOS app]
//           ↕  WCSession (Bluetooth / Wi-Fi)
//   [WatchSessionManager — this file]
//           ↕  FlutterMethodChannel "fall_guardian/watch"
//   [Flutter / Dart phone app]
//
// When the watch detects a fall it sends a WCSession message. WatchSessionManager
// receives it and calls channel.invokeMethod("onFallDetected", ...) so that Flutter
// can show the alert screen.
//
// When the user cancels the alert on the phone, Flutter calls
// channel.invokeMethod("sendCancelAlert") → AppDelegate routes it here →
// we send the cancellation back to the watch via WCSession.
//
// Why NSObject?
// WCSessionDelegate is an Objective-C protocol. In Swift, a class must inherit
// from NSObject (the root Objective-C class) to conform to Objective-C protocols.
// Without it the compiler would refuse to compile.

/// Receives messages from the watchOS app via WCSession
/// and forwards fall events to Flutter via MethodChannel.
class WatchSessionManager: NSObject, WCSessionDelegate {
    private static let simulatorFallEventNotification = "com.fallguardian.fallEvent"

    // MARK: - Properties

    // The channel used to call methods on the Dart/Flutter side.
    // Optional because the manager is created early (before Flutter initialises)
    // and the channel is injected later via setChannel(_:).
    private var channel: FlutterMethodChannel?

    // UserDefaults key for the fall timestamp stored during a background wakeup.
    // When the iOS app is woken by WCSession before the Flutter engine starts,
    // the timestamp is saved here and drained once Flutter is ready.
    private static let pendingFallTimestampKey = "pendingFallTimestamp"
    private static let pendingAlertCancelledKey = "pendingAlertCancelled"

    // Identifier for the native wake-up notification shown when Flutter is not
    // ready. Cancelled by drainPendingFallEvent() once Flutter takes over.
    static let fallWakeupNotifId = "fall_guardian_wakeup"

    // This flag tracks whether the current alert has been cancelled by the phone.
    // The Apple Watch periodically polls the phone ("query_cancel_status") to know
    // whether it should stop its own countdown. We answer that poll using this flag.
    // It starts as false (no alert, nothing cancelled) and flips to:
    //   true  → when sendCancelAlert() is called (user tapped "I'm OK" on phone)
    //   false → when resetCancelContext() is called (a new fall event begins)
    /// Set to true when the phone alert is cancelled so the watch poll gets the right answer.
    private var alertCancelledFlag = false

    // MARK: - Simulator IPC: background (Task handles)
    //
    // What is Swift Concurrency / Task?
    // Swift's async/await system lets you write asynchronous code that looks like
    // synchronous code. A `Task` is a unit of concurrent work — similar to a thread,
    // but managed by Swift's runtime (much lighter weight). You can cancel a Task
    // to stop it from running any more iterations.
    //
    // We store the Task handles so we can cancel the background loops when they are
    // no longer needed (e.g. when a cancel arrives, stop watching for more cancels).

    // Handle for the loop that watches for fall events written by the watchOS simulator.
    private var watchCancelPollTask: Task<Void, Never>?

    // Handle for the loop that watches for cancel signals written by the watchOS simulator.
    private var fallEventPollTask: Task<Void, Never>?

    // MARK: - Simulator IPC: fall event polling
    //
    // Context — why does this exist?
    // ─────────────────────────────
    // WCSession is Apple's official watch↔phone channel. On real devices it works
    // over Bluetooth/Wi-Fi. In the Xcode simulator, WCSession is partially emulated
    // but the watch→phone direction is completely broken when the watchOS app is
    // launched via `xcrun simctl` (the command-line tool we use in the Makefile).
    //
    // Workaround — shared /tmp files (IPC = Inter-Process Communication):
    // Both the iOS simulator process and the watchOS simulator process run on the
    // same Mac, so they share the Mac's /tmp directory. We exploit this:
    //   • watchOS sim writes  /tmp/com.fallguardian.fallEvent  (contains timestamp)
    //   • iOS sim polls that file every 500 ms
    //   • When found: read timestamp, delete file, forward event to Flutter
    //
    // The #if targetEnvironment(simulator) compiler directive ensures this code is
    // compiled only for simulator builds. On a real iPhone it is stripped out
    // entirely — zero impact on production behaviour.

    /// Continuously polls for a fall event written by the watchOS simulator.
    /// WCSession watch→phone sendMessage is broken in the simulator; the watch writes
    /// /tmp/com.fallguardian.fallEvent with the ms-since-epoch timestamp instead.
    func startPollingForFallEvent() {
        // Cancel any previous polling loop before starting a new one.
        // This prevents duplicate loops if startPollingForFallEvent is called again.
        fallEventPollTask?.cancel()

        // Everything inside this block is ONLY compiled for simulator targets.
        // On a real device the compiler skips it completely.
        #if targetEnvironment(simulator)
        fallEventPollTask = Task {
            // Infinite loop — keeps running until the Task is cancelled.
            while !Task.isCancelled {

                // Wait 500 ms (500,000,000 nanoseconds) before each check.
                // try? discards any error (Task.sleep throws CancellationError if
                // the task is cancelled mid-sleep, which we handle with the guard below).
                try? await Task.sleep(nanoseconds: 500_000_000)

                // If the task was cancelled while sleeping, exit cleanly.
                guard !Task.isCancelled else { return }

                let path = "/tmp/com.fallguardian.fallEvent"

                // If the file doesn't exist yet, keep looping.
                guard FileManager.default.fileExists(atPath: path) else { continue }

                // Read the file content (the timestamp written by the watchOS sim).
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

                // Delete the file immediately so we don't process the same event twice.
                try? FileManager.default.removeItem(atPath: path)

                // Parse the timestamp string into an Int (milliseconds since epoch).
                // If parsing fails (empty/corrupt file), fall back to "now".
                let timestamp = Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? Int(Date().timeIntervalSince1970 * 1000)

                NSLog("[WCSession][Phone] fallEvent poll: flag file found → timestamp=\(timestamp)")

                // A new fall clears any leftover cancel state from a previous alert.
                resetCancelContext()

                // Show the native notification immediately, before Flutter is involved.
                // This bypasses flutter_local_notifications (which has unreliable
                // foreground delivery on iOS 26 / UIScene lifecycle) and posts
                // directly to UNUserNotificationCenter — the same path that works
                // reliably for the killed-app case.
                showFallNotificationIfNeeded(timestamp: timestamp)

                // Forward the fall event to Flutter — this triggers FallAlertScreen.
                forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])

                // Now start watching for a cancel signal from the watch,
                // in case the user taps "I'm OK" on the watch first.
                startPollingForWatchCancel()
            }
        }
        #endif
    }

    // MARK: - Simulator IPC: watch→phone cancel polling
    //
    // Mirror of the phone→watch cancel file, but in the opposite direction.
    // Once a fall event has been forwarded to Flutter, either the phone user
    // or the watch user can cancel. If the watch cancels first, it writes:
    //   /tmp/com.fallguardian.cancelFromWatch
    // This loop polls for that file every 1 s and forwards onAlertCancelled to Flutter.

    /// Start polling for a cancel signal written by the watchOS simulator.
    /// Called as soon as a fall event is forwarded to Flutter.
    func startPollingForWatchCancel() {
        // Cancel the previous watch-cancel loop if one is already running.
        watchCancelPollTask?.cancel()

        #if targetEnvironment(simulator)
        watchCancelPollTask = Task {
            while !Task.isCancelled {

                // Poll every 1 second (less aggressive than the fall-event poll
                // because cancel latency of ~1 s is acceptable).
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                let path = "/tmp/com.fallguardian.cancelFromWatch"
                guard FileManager.default.fileExists(atPath: path) else { continue }

                // Delete the file to avoid processing the same cancel twice.
                try? FileManager.default.removeItem(atPath: path)
                NSLog("[WCSession][Phone] watchCancel poll: flag file found → forwarding onAlertCancelled")

                // Tell Flutter the alert was cancelled — Flutter will dismiss
                // the FallAlertScreen and stop the SMS countdown.
                forwardToFlutter("onAlertCancelled", arguments: nil)

                // Exit the loop: there is nothing more to watch for.
                return
            }
        }
        #endif
    }

    /// Stop the watch-cancel polling loop.
    ///
    /// Called in two situations:
    ///   1. The phone itself cancels (sendCancelAlert) — no point watching for watch cancel.
    ///   2. A new fall begins (resetCancelContext) — clean slate before restarting.
    func stopPollingForWatchCancel() {
        watchCancelPollTask?.cancel()
        watchCancelPollTask = nil
    }

    // MARK: - Initialisation

    /// Early-startup initialiser — no Flutter channel yet.
    ///
    /// Use this in application(_:didFinishLaunchingWithOptions:) so WCSession is
    /// active before the Flutter engine starts. Call setChannel(_:) followed by
    /// drainPendingFallEvent() once didInitializeImplicitFlutterEngine fires.
    override init() {
        super.init()
    }

    /// Convenience initialiser for when Flutter is already available.
    init(channel: FlutterMethodChannel) {
        super.init()
        self.channel = channel
    }

    /// Inject the Flutter MethodChannel once the engine has initialised.
    ///
    /// Always follow this call with drainPendingFallEvent() to forward any fall
    /// event that arrived before Flutter was ready (background wakeup scenario).
    func setChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }

    /// Forward any fall event that arrived before Flutter was ready.
    ///
    /// When iOS is woken in the background by a WCSession `transferUserInfo`
    /// delivery (e.g. from a killed state), `didInitializeImplicitFlutterEngine`
    /// does not fire — the Flutter engine is not started for background-only
    /// wakeups. Instead, the fall timestamp is stored in UserDefaults and a
    /// native notification is shown. Once the user opens the app and Flutter
    /// initialises, this method reads that timestamp, forwards it to Flutter via
    /// the channel, and cancels the native wake-up notification so that Flutter's
    /// FallAlertScreen takes over.
    func drainPendingFallEvent() {
        let key = WatchSessionManager.pendingFallTimestampKey
        guard let timestamp = UserDefaults.standard.object(forKey: key) as? Int else { return }
        UserDefaults.standard.removeObject(forKey: key)
        // Cancel the native wake-up notification — FallAlertScreen takes over.
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [WatchSessionManager.fallWakeupNotifId])
        NSLog("[WCSession][Phone] drainPendingFallEvent: forwarding timestamp=\(timestamp) to Flutter")
        resetCancelContext()
        forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])
        startPollingForWatchCancel()
    }

    /// Forward any watch-originated cancel that arrived before Flutter was ready.
    ///
    /// This prevents a stale native fall notification from lingering if the watch
    /// user cancels while the phone app is backgrounded or killed.
    func drainPendingAlertCancel() {
        let key = WatchSessionManager.pendingAlertCancelledKey
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [WatchSessionManager.fallWakeupNotifId])
        forwardToFlutter("onAlertCancelled", arguments: nil)
    }

    // MARK: - Session Lifecycle

    /// Activate the WCSession link between iPhone and Apple Watch.
    ///
    /// WCSession workflow:
    ///   1. Check that WCSession is available on this device (it is not available
    ///      on iPads, for example — they cannot pair with an Apple Watch).
    ///   2. Set self as the delegate so we receive incoming messages.
    ///   3. Call activate() to start the Bluetooth/Wi-Fi handshake.
    ///   4. Start the simulator fall-event polling loop (no-op on real devices).
    func startSession() {
        // isSupported() returns false on devices that cannot pair with a watch (iPad).
        guard WCSession.isSupported() else { return }

        // WCSession.default is a singleton — there is exactly one session per app.
        WCSession.default.delegate = self
        WCSession.default.activate()

        // Start the simulator IPC fall-event poller. On real devices this is a no-op
        // because #if targetEnvironment(simulator) strips the body out at compile time.
        startPollingForFallEvent()

        // Register a Darwin notification observer so that a backgrounded/suspended iOS
        // app is woken immediately when the watchOS sim posts notify_post().
        // The poll loop alone cannot fire while the process is frozen; this Darwin
        // notification is delivered by the OS kernel even to suspended processes.
        // Stripped from real-device builds by the compiler directive.
        #if targetEnvironment(simulator)
        registerDarwinFallEventObserver()
        #endif
    }

    // MARK: - Simulator: Darwin notification for backgrounded-app wakeup

    #if targetEnvironment(simulator)
    /// Register for a Darwin (kernel-level) notification posted by the watchOS simulator
    /// when it writes the fall-event flag file.
    ///
    /// Darwin notifications are delivered even to suspended processes, unlike Swift
    /// Tasks which are frozen when the app is backgrounded. This bridges the gap:
    ///   1. watchOS sim writes /tmp/com.fallguardian.fallEvent
    ///   2. watchOS sim calls notify_post("com.fallguardian.fallEvent")
    ///   3. iOS sim is woken → this handler fires → reads the file → shows notification
    ///
    /// Complements rather than replaces the poll loop: whichever path finds the file
    /// first deletes it, so both can coexist without double-processing.
    private func registerDarwinFallEventObserver() {
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, name, _, _ in
                guard let observer else { return }
                guard let notificationName = name?.rawValue as String? else { return }
                guard notificationName == WatchSessionManager.simulatorFallEventNotification else { return }

                let manager = Unmanaged<WatchSessionManager>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                manager.handleSimulatorFallEventFlag()
            },
            WatchSessionManager.simulatorFallEventNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleSimulatorFallEventFlag() {
        let path = "/tmp/com.fallguardian.fallEvent"
        guard FileManager.default.fileExists(atPath: path) else { return }

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(atPath: path)

        let timestamp = Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? Int(Date().timeIntervalSince1970 * 1000)

        NSLog("[WCSession][Phone] Darwin wake: fallEvent timestamp=\(timestamp)")

        resetCancelContext()
        showFallNotificationIfNeeded(timestamp: timestamp)
        forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])
        startPollingForWatchCancel()
    }
    #endif

    // MARK: - WCSessionDelegate
    //
    // WCSessionDelegate is a protocol (interface) that WCSession calls back on when
    // connection state changes or messages arrive. We must implement its required
    // methods here.

    /// Called when the WCSession activation process completes (success or failure).
    ///
    /// activationState will be .activated if everything went well. Once activated,
    /// sendMessage / transferUserInfo / updateApplicationContext are available.
    /// We do not need to do anything here beyond noting the session is ready.
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Session activated — ready to receive messages
    }

    /// Called when the user's Apple Watch becomes inactive (e.g. watch is removed
    /// or a new watch is being paired). Required by the protocol; no action needed.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Called after the watch fully deactivates (e.g. switching to a new watch).
    /// We re-activate immediately so the session stays live with the new watch.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // re-activate on Apple Watch switch
    }

    // MARK: - Receiving Messages from the Watch

    /// Called when the watchOS app sends data via `transferUserInfo()`.
    ///
    /// `transferUserInfo()` is used when the watch is not immediately reachable
    /// (e.g. the phone app is backgrounded or Bluetooth is momentarily lost).
    /// WCSession queues the data and delivers it here when the phone app becomes
    /// reachable again. The payload format is identical to sendMessage(), so we
    /// reuse the same parsing logic by delegating to session(_:didReceiveMessage:).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    /// Called when the watchOS app sends a real-time message via `sendMessage()`
    /// WITHOUT a reply handler (fire-and-forget style).
    ///
    /// Message format (dictionary):
    ///   { "event": "fall_detected", "timestamp": <Int ms since epoch> }
    ///   { "event": "alert_cancelled" }
    ///
    /// This method runs on a background thread provided by WCSession.
    /// We must dispatch to the main thread before touching Flutter (see forwardToFlutter).
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        switch message["event"] as? String {

        // The watch detected a fall and is starting its 30-second countdown.
        case "fall_detected":
            // Reset cancel state so a leftover cancellation from a previous alert
            // does not immediately dismiss the new one.
            resetCancelContext()  // new fall resets cancel state + applicationContext

            // Extract the timestamp (milliseconds since epoch) that the watch wrote
            // at the moment of detection. Both the watch and the phone use this same
            // value as the countdown origin, keeping the timers in sync even if there
            // is a small delay delivering the message.
            let timestamp = message["timestamp"] as? Int ??
                Int(Date().timeIntervalSince1970 * 1000)

            // Show the native UNNotification immediately, before involving Flutter.
            // This is reliable across all app states (foreground, background, killed)
            // and sidesteps flutter_local_notifications' UIScene delegate issues on iOS 26.
            showFallNotificationIfNeeded(timestamp: timestamp)

            // Tell Flutter a fall was detected. Flutter will show FallAlertScreen.
            forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])

            // Start the simulator cancel-poll loop in case the user cancels on the watch.
            startPollingForWatchCancel()  // watch→phone IPC fallback for simulator

        // The user cancelled the alert on the watch side.
        case "alert_cancelled":
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [WatchSessionManager.fallWakeupNotifId])
            // Tell Flutter to dismiss the alert screen.
            forwardToFlutter("onAlertCancelled", arguments: nil)

        default:
            break
        }
    }

    /// Called when the watchOS app sends a message WITH a reply handler.
    ///
    /// The watch uses this variant when it needs an answer. Specifically, the watchOS
    /// app periodically polls the phone with "query_cancel_status" to know whether
    /// the phone user cancelled the alert. This lets the watch stop its own countdown
    /// even if the cancel message from the phone failed to arrive via WCSession.
    ///
    /// We MUST call replyHandler() — if we don't, WCSession throws an error on the
    /// watch side and the message is considered lost.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        switch message["event"] as? String {

        // The watch is asking: "did the phone user cancel the alert?"
        case "query_cancel_status":
            NSLog("[WCSession][Phone] query_cancel_status → cancelled=\(alertCancelledFlag)")
            // Reply immediately with the current flag value.
            // The watch checks this answer and stops its countdown if cancelled=true.
            replyHandler(["cancelled": alertCancelledFlag])

        default:
            // For any other message type that happens to include a reply handler,
            // process it as a normal fire-and-forget message and acknowledge receipt.
            self.session(session, didReceiveMessage: message)
            replyHandler(["status": "received"])
        }
    }

    // MARK: - Sending Messages to the Watch

    /// Send a cancel-alert signal to the paired Apple Watch.
    ///
    /// Called by AppDelegate when Flutter invokes "sendCancelAlert" on the channel
    /// (i.e. the user tapped "I'm OK" on the phone's FallAlertScreen).
    ///
    /// What this does:
    ///   1. Marks alertCancelledFlag = true so watch polls answered immediately.
    ///   2. Stops watching for a watch-side cancel (it's already cancelled).
    ///   3. Simulator IPC: writes /tmp/com.fallguardian.cancelAlert for the watchOS sim.
    ///   4. Sends the cancellation to the real watch via three delivery paths (see below).
    func sendCancelAlert() {
        // Step 1 — Update the in-memory flag immediately.
        // If the watch sends a "query_cancel_status" before the WCSession message
        // arrives, we still return the correct answer.
        alertCancelledFlag = true

        // Step 2 — No need to keep watching for a watch-initiated cancel.
        stopPollingForWatchCancel()  // phone handled the cancel; stop watch poll

        // Step 3 — Simulator IPC: write a flag file that the watchOS sim process
        // will find on its next poll (every 2 s on the watchOS side).
        // Both simulators are macOS processes sharing the same /tmp directory.
        // This path is ONLY compiled into simulator builds.
        #if targetEnvironment(simulator)
        try? "cancelled".write(
            toFile: "/tmp/com.fallguardian.cancelAlert",
            atomically: true, encoding: .utf8
        )
        #endif

        // Step 4 — Send cancellation to the real watch via WCSession.
        // Guard: WCSession must be activated before we can send anything.
        guard WCSession.default.activationState == .activated else {
            NSLog("[WCSession][Phone] sendCancelAlert: not activated")
            return
        }
        NSLog("[WCSession][Phone] sendCancelAlert: isReachable=\(WCSession.default.isReachable)")

        let message: [String: Any] = ["event": "alert_cancelled"]

        // Three delivery paths, ordered most → least real-time:
        //
        // 4a. sendMessage — delivered immediately if the watch app is in the foreground
        //     and reachable over Bluetooth/Wi-Fi. This is the fastest path.
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)

        // 4b. transferUserInfo — queued in WCSession's background transfer system.
        //     Delivered even if the watch app is suspended, as soon as it wakes.
        //     Acts as a belt-and-suspenders fallback if sendMessage drops the packet.
        WCSession.default.transferUserInfo(message)

        // 4c. updateApplicationContext — persists a dictionary that the watch app
        //     reads when it next launches. This ensures the cancel survives an
        //     app restart on either device. Only the latest context is kept
        //     (unlike transferUserInfo which queues all calls).
        try? WCSession.default.updateApplicationContext(["alertCancelled": true])
    }

    /// Reset all cancel state when a NEW fall event begins.
    ///
    /// Without this, a cancellation from a previous alert could immediately
    /// dismiss the new alert's countdown — a dangerous bug in a safety app.
    ///
    /// What this does:
    ///   1. Resets alertCancelledFlag to false (no active cancellation).
    ///   2. Stops any ongoing watch-cancel poll loop.
    ///   3. Pushes alertCancelled: false to the watch's applicationContext so
    ///      the watch also sees the clean state on its next context check.
    ///   4. Simulator IPC: removes all three flag files so stale state
    ///      from a previous test run cannot affect the new alert.
    func resetCancelContext() {
        alertCancelledFlag = false
        stopPollingForWatchCancel()

        // Update the persistent application context so the watch side also resets.
        // The watch reads this when it launches or when it calls
        // WCSession.default.receivedApplicationContext.
        try? WCSession.default.updateApplicationContext(["alertCancelled": false])

        // Simulator-only cleanup: remove all IPC flag files.
        // This prevents a previous test's leftover files from triggering events
        // in the next test run within the same simulator session.
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.cancelAlert")
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.cancelFromWatch")
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.fallEvent")
        #endif
    }

    /// Send updated fall-detection thresholds to the paired Apple Watch.
    ///
    /// Called by AppDelegate when Flutter invokes "sendThresholds" on the channel
    /// (i.e. the user changed sensitivity settings in the Settings screen).
    ///
    /// Threshold keys (must match watchOS UserDefaults keys exactly):
    ///   thresh_freefall, thresh_impact, thresh_tilt, thresh_freefall_ms
    ///
    /// Delivery strategy:
    ///   • Watch is reachable → sendMessage (immediate)
    ///   • Watch not reachable → transferUserInfo (background queue)
    ///
    /// Unlike the cancel signal, we do NOT use updateApplicationContext here because
    /// applicationContext only keeps the LAST value, and we want every threshold
    /// update to be delivered reliably.
    func sendThresholds(_ thresholds: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = ["event": "set_thresholds", "thresholds": thresholds]
        if WCSession.default.isReachable {
            // Watch app is in the foreground and Bluetooth is live — send immediately.
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            // Watch is not reachable right now (watch app backgrounded, watch asleep,
            // or Bluetooth temporarily unavailable). transferUserInfo queues the data
            // and delivers it when the watch wakes up.
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - Private Helpers

    /// Forward a method call to Flutter on the main thread.
    ///
    /// If the Flutter channel is not yet ready (background wakeup before the
    /// engine initialises), fall events are persisted to UserDefaults and a
    /// native UNNotification is shown to wake the user. The channel becomes
    /// available once AppDelegate.didInitializeImplicitFlutterEngine fires and
    /// calls setChannel(_:) + drainPendingFallEvent().
    ///
    /// [weak self] prevents a retain cycle. If WatchSessionManager is somehow
    /// deallocated while the dispatch is queued, the closure silently does nothing
    /// instead of crashing.
    private func forwardToFlutter(_ method: String, arguments: Any?) {
        guard let channel = channel else {
            // Flutter engine not yet ready (background wakeup before engine initialises).
            // The notification was already shown by the caller (session/poll loop) before
            // forwardToFlutter was invoked. Just persist the timestamp so
            // drainPendingFallEvent() can forward it to Flutter once the engine starts.
            if method == "onFallDetected",
               let args = arguments as? [String: Any],
               let timestamp = args["timestamp"] as? Int {
                NSLog("[WCSession][Phone] forwardToFlutter: no channel — storing timestamp=\(timestamp) for drain")
                UserDefaults.standard.set(timestamp, forKey: WatchSessionManager.pendingFallTimestampKey)
            } else if method == "onAlertCancelled" {
                NSLog("[WCSession][Phone] forwardToFlutter: no channel — storing pending cancel for drain")
                UserDefaults.standard.set(true, forKey: WatchSessionManager.pendingAlertCancelledKey)
                UNUserNotificationCenter.current()
                    .removeDeliveredNotifications(withIdentifiers: [WatchSessionManager.fallWakeupNotifId])
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(method, arguments: arguments)
        }
    }

    /// Post a native UNNotification for a fall event.
    ///
    /// Called directly from the WCSession receive path and the simulator IPC poll
    /// loop — before Flutter is involved — so the notification fires reliably in
    /// every app state (foreground, background, killed) regardless of whether
    /// flutter_local_notifications has initialised or is set as the notification
    /// center delegate.
    ///
    /// The `timeSensitive` interruption level (iOS 15+) bypasses Focus modes,
    /// which is appropriate for a safety-critical fall alert.
    private func showFallNotification(timestamp: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Fall Detected"
        content.body = "Open app to cancel — SMS sends in 30 seconds"
        content.sound = .default
        if #available(iOS 15.0, *) {
            // timeSensitive bypasses Focus modes without requiring the Critical
            // Alerts entitlement (which needs Apple approval).
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = ["fall_timestamp": timestamp]

        let request = UNNotificationRequest(
            identifier: WatchSessionManager.fallWakeupNotifId,
            content: content,
            trigger: nil  // nil = deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[WCSession][Phone] showBackgroundFallNotification failed: \(error)")
            }
        }
    }

    /// Only show the native banner when the app is not already active.
    ///
    /// In the foreground, Flutter immediately pushes FallAlertScreen and a second
    /// iOS banner creates noisy duplicate alert UI.
    private func showFallNotificationIfNeeded(timestamp: Int) {
        if UIApplication.shared.applicationState == .active {
            NSLog("[WCSession][Phone] suppressing native fall notification while foregrounded")
            return
        }
        showFallNotification(timestamp: timestamp)
    }
}
