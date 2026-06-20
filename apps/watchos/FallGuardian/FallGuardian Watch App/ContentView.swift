// ContentView.swift
// Fall Guardian — watchOS
//
// This file is the entire watchOS user interface.  Apple Watch apps can only
// display one "scene" at a time (there are no navigation stacks or tabs in
// typical watch apps), so this single file renders both possible states:
//
//   IDLE      — shield icon + "Monitoring active" text (normal state)
//   ALERT     — large countdown number with red background (fall detected)
//
// Architecture pattern used here: MVVM (Model-View-ViewModel)
//   - `ContentView`      is the VIEW      — pure SwiftUI, no business logic.
//   - `ContentViewModel` is the VIEWMODEL — holds state and coordinates actions.
//   - FallDetectionManager / WatchSessionManager are the MODEL layer.
//
// How data flows end-to-end when a fall happens:
//   1. CMMotionManager samples accelerometer → FallDetectionManager.process()
//   2. FallAlgorithm.processSample() returns true
//   3. FallDetectionManager calls onFallDetected(timestamp)
//   4. ContentViewModel.alertDidFire(timestamp:) sets isAlertActive = true
//   5. SwiftUI re-renders ContentView, showing alertView
//   6. WatchSessionManager.sendFallEvent() notifies the iPhone
//
// How data flows when the alert is cancelled:
//   Watch side:   tap → ContentView.onTapGesture → viewModel.cancelAlert()
//   Phone side:   WatchSessionManager.onAlertCancelled → viewModel.cancelAlert(notifyPhone: false)

import SwiftUI      // Apple's declarative UI framework for all Apple platforms.
                    // Views are Swift structs that describe WHAT to show; SwiftUI
                    // decides HOW and WHEN to redraw them.
import Observation  // Provides the @Observable macro used on ContentViewModel.
                    // Replaces the older @ObservedObject/@Published pattern on iOS 17+.
import WatchKit     // WKInterfaceDevice.current().play() — haptic feedback API.

// MARK: - ContentView (the SwiftUI view)

/// The root view of the watchOS app.
///
/// SwiftUI views are value types (structs).  Every time a property they depend on
/// changes, SwiftUI calls `body` again to compute a fresh description of the UI
/// and applies only the necessary visual changes.  No manual `reloadData()` calls.
struct ContentView: View {

    // @State stores the ViewModel on the heap and keeps it alive for the lifetime
    // of this view.  @Observable (on ContentViewModel) makes SwiftUI automatically
    // re-render any view that reads a property when that property changes.
    @State private var viewModel = ContentViewModel()

    /// The main body of the view.  SwiftUI reads this whenever state changes.
    var body: some View {
        // `Group` is a transparent container — it lets us branch between two
        // completely different layouts without wrapping them in a VStack or ZStack.
        Group {
            if viewModel.isAlertActive {
                alertView   // Big red countdown — fall is in progress.
            } else {
                idleView    // Shield icon — monitoring quietly.
            }
        }
        // A single tap anywhere on the watch screen cancels the alert.
        // `onTapGesture` is added to the Group so it covers both sub-views.
        .onTapGesture {
            if viewModel.isAlertActive {
                viewModel.cancelAlert()  // User acknowledged — stop the countdown.
            }
        }
        // Called once when the view first appears on screen.
        // We start the fall detection pipeline here rather than in init() because
        // watchOS may keep the view object alive in memory while suspending the app;
        // onAppear fires reliably when the face is actually visible.
        .onAppear {
            viewModel.startIfNeeded()
        }
        // Fires every time remainingSeconds changes (every 0.5 s during an alert).
        // We use it to play haptic feedback — physical vibrations on the watch band
        // that alert the user even if they are not looking at the screen.
        .onChange(of: viewModel.remainingSeconds) { _, newValue in
            guard viewModel.isAlertActive, newValue > 0 else { return }
            // `.notification` is a stronger buzz used under 10 s (urgent!).
            // `.click` is a subtle tap used during the normal countdown.
            WKInterfaceDevice.current().play(newValue <= 10 ? .notification : .click)
        }
    }

    // MARK: - Alert view (fall detected, countdown active)

    /// Full-screen red layout shown during the 30-second alert window.
    ///
    /// Design choices:
    ///   - Very large countdown number (56 pt bold) — readable at a glance.
    ///   - Dark red background with an animated red flash under 10 s — urgency cue.
    ///   - Instruction text is dim (60% opacity) so it doesn't compete with the number.
    ///   - `ignoresSafeArea()` extends the background to the screen edges and
    ///     under the digital crown area on round Apple Watch faces.
    private var alertView: some View {
        ZStack {  // ZStack layers views from back to front (like CSS z-index).

            // Base background: near-black with a slight red tint.
            Color(red: 0.1, green: 0, blue: 0).ignoresSafeArea()

            // Animated red flash overlay — only shown when 10 or fewer seconds remain.
            // `.repeatForever(autoreverses: true)` pulses the opacity in and out
            // continuously without any manual timer.
            if viewModel.remainingSeconds <= 10 {
                Color.red.opacity(0.3).ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                               value: viewModel.remainingSeconds)
            }

            // Foreground content: number + instruction.
            VStack(spacing: 6) {
                // The main countdown digit.  Updates every 0.5 s via ContentViewModel.
                Text("\(viewModel.remainingSeconds)")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)

                // Helper text.  Small because screen real estate is precious on a watch.
                Text("Tap anywhere to cancel")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        // `containerBackground` sets the ambient color used by watchOS for the
        // "page curl" transition and the navigation background on watchOS 10+.
        .containerBackground(.red.opacity(0.1), for: .navigation)
    }

    // MARK: - Idle view (no active alert, monitoring silently)

    /// Compact status view shown when no fall is in progress.
    ///
    /// Displays the app icon and a "Monitoring active" label to reassure the user
    /// that detection is running.  A debug-only button is included so developers
    /// can trigger a simulated fall without physically dropping the device.
    private var idleView: some View {
        VStack(spacing: 8) {

            // Circular icon — layered using ZStack (teal circle behind shield icon).
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.247, blue: 0.235))  // Dark teal
                    .frame(width: 52, height: 52)
                Image(systemName: "shield.fill")  // SF Symbols icon — built into the OS.
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 0.898, green: 0.412, blue: 0.290))  // Warm orange
            }

            Text("Fall Guardian")
                .font(.headline)
                .foregroundColor(.white)

            Text("Monitoring active")
                .font(.caption)
                .foregroundColor(Color(red: 0.820, green: 0.878, blue: 0.843))  // Light mint

            // DEBUG only — stripped from App Store / release builds.
            // `#if DEBUG` is evaluated at compile time, not runtime, so the button
            // code does not exist in production binaries.
            #if DEBUG
            Button("Simulate Fall (debug)") {
                viewModel.simulateFall()
            }
            .font(.system(size: 11))
            .foregroundColor(Color(red: 0.898, green: 0.412, blue: 0.290))
            #endif
        }
        .containerBackground(.black, for: .navigation)
    }
}

// MARK: - ContentViewModel (the business logic layer)

/// Holds all state and coordinates actions between the UI and the underlying services.
///
/// `@Observable` (from the Observation framework, iOS/watchOS 17+) is a macro that
/// automatically instruments every stored property so SwiftUI knows exactly which
/// views need to be re-drawn when a property changes.  It replaces the older
/// `ObservableObject` + `@Published` pattern with zero boilerplate.
///
/// Threading note: `isAlertActive` and `remainingSeconds` are read by the SwiftUI
/// render thread.  Every write to them must happen on the main thread.  Code below
/// uses `DispatchQueue.main.async` and `await MainActor.run { }` to enforce this.
@Observable
class ContentViewModel {

    // MARK: - Published state (read by ContentView)

    /// Whether the 30-second emergency countdown is currently running.
    /// ContentView switches between idleView and alertView based on this flag.
    var isAlertActive: Bool = false

    /// Seconds remaining in the current alert countdown.
    /// Starts at 30 (or less if there was network latency) and counts down to 0.
    var remainingSeconds: Int = 30

    // MARK: - Private state

    /// The background task that drives the countdown timer.
    /// Stored so we can cancel it if the alert is dismissed before it expires.
    /// `Task<Void, Never>` means: runs asynchronously, never throws an error.
    private var alertExpireTask: Task<Void, Never>?

    /// The millisecond-since-epoch timestamp captured when the fall was detected.
    /// This is the shared reference point used by BOTH the watch and the phone to
    /// compute `remainingSeconds = 30 - (now - fallTimestamp) / 1000`.
    /// Using the same origin timestamp keeps both countdowns in sync even if there
    /// is a small delay between when the watch detects the fall and when the phone
    /// receives the notification.
    private var fallTimestamp: Int64 = 0

    /// Cancel the countdown task when the ViewModel is deallocated.
    /// Without this, a dismissed alert could leave a background Task running
    /// and writing to deallocated memory.
    deinit {
        alertExpireTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Called by ContentView.onAppear — starts detection if not already running
    /// and registers the callbacks that wire the services to the UI.
    ///
    /// Why not start in init()?  watchOS may create the ViewModel eagerly during
    /// app warm-up.  `startIfNeeded()` guards against double-starting and only
    /// runs the side-effecting setup once the view is actually on screen.
    func startIfNeeded() {
        // Start the accelerometer pipeline if it isn't running yet.
        if !FallDetectionManager.shared.isRunning {
            FallDetectionManager.shared.start()
        }

        // Wire the fall-detected callback.  Using `[weak self]` breaks the
        // reference cycle: FallDetectionManager holds the closure, closure
        // holds self, self holds the reference to FallDetectionManager.
        // Without `weak`, none of these objects would ever be released.
        FallDetectionManager.shared.onFallDetected = { [weak self] timestamp in
            // The callback may arrive on any thread — dispatch to main for UI safety.
            DispatchQueue.main.async { self?.alertDidFire(timestamp: timestamp) }
        }

        // Wire the cancel callback from the phone.
        // `notifyPhone: false` prevents the ping-pong loop: the phone already
        // knows it cancelled — we only need to update the watch UI.
        WatchSessionManager.shared.onAlertCancelled = { [weak self] in
            self?.cancelAlert(notifyPhone: false)
        }

        // In DEBUG + simulator builds, also start polling for test-script triggers.
        #if DEBUG && targetEnvironment(simulator)
        startDebugTriggerPolling()
        #endif
    }

    // MARK: - Debug / simulator test helpers

    #if DEBUG && targetEnvironment(simulator)
    /// Polls a pair of /tmp flag files written by the automated E2E test script
    /// (`scripts/test_ios_watchos.sh`).  This lets the CI script simulate a fall
    /// or a cancel without any UI interaction — no XCUITest framework needed.
    ///
    /// Polled files:
    ///   /tmp/com.fallguardian.debugSimulateFall  → triggers simulateFall()
    ///   /tmp/com.fallguardian.debugCancelWatch   → triggers cancelAlert()
    ///
    /// The loop runs every 500 ms.  Files are deleted after reading so each trigger
    /// fires exactly once.
    ///
    /// `MainActor.run { }` is the async/await equivalent of `DispatchQueue.main.async`.
    /// It ensures the state mutations happen on the main thread even though the
    /// surrounding Task runs on a background thread.
    private func startDebugTriggerPolling() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s
                let fm = FileManager.default
                let fallPath   = "/tmp/com.fallguardian.debugSimulateFall"
                let cancelPath = "/tmp/com.fallguardian.debugCancelWatch"
                if fm.fileExists(atPath: fallPath) {
                    try? fm.removeItem(atPath: fallPath)
                    NSLog("[Debug] debugSimulateFall trigger received")
                    await MainActor.run { self.simulateFall() }
                } else if fm.fileExists(atPath: cancelPath) {
                    try? fm.removeItem(atPath: cancelPath)
                    NSLog("[Debug] debugCancelWatch trigger received")
                    await MainActor.run { self.cancelAlert() }
                }
            }
        }
    }
    #endif

    // MARK: - Actions

    /// Manually triggers a fall event as if the algorithm had detected one.
    ///
    /// Used by:
    ///   1. The debug button in idleView (developer testing on device/simulator).
    ///   2. startDebugTriggerPolling() (automated E2E tests).
    ///
    /// We generate our own timestamp, fire the alert locally, AND send the event
    /// to the phone so the full alert flow (watch countdown + phone notification)
    /// is exercised end-to-end.
    func simulateFall() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)  // ms since epoch
        alertDidFire(timestamp: timestamp)                          // Update this device's UI.
        WatchSessionManager.shared.sendFallEvent(timestamp: timestamp)  // Notify the phone.
    }

    /// Cancels the active alert, stops the countdown, and optionally notifies the phone.
    ///
    /// - Parameter notifyPhone: Pass `false` when the cancel originated from the phone
    ///   to avoid sending a cancel back (which would create an infinite loop).
    ///   Default is `true` (user tapped the watch → phone should dismiss its alert too).
    func cancelAlert(notifyPhone: Bool = true) {
        alertExpireTask?.cancel()                // Stop the 0.5 s countdown loop.
        WatchSessionManager.shared.stopPolling() // Stop waiting for a phone cancel.
        isAlertActive = false                    // Switch UI back to idleView.
        remainingSeconds = 30                    // Reset so the next alert starts at 30.
        if notifyPhone {
            // Tell the phone to dismiss its FallAlertScreen.
            WatchSessionManager.shared.sendCancelAlert()
        }
    }

    // MARK: - Private alert logic

    /// Starts the alert state machine when a fall is confirmed.
    ///
    /// Step-by-step:
    /// 1. Store the fall timestamp (used as countdown origin on both devices).
    /// 2. Show the alert UI immediately.
    /// 3. Compute `remainingSeconds` from the timestamp — if there was network
    ///    delay before this method was called, we start at fewer than 30 s so
    ///    the watch matches the phone countdown exactly.
    /// 4. Cancel any previous countdown task (safety net for rapid re-triggers).
    /// 5. Start polling for a phone-side cancel.
    /// 6. Launch the countdown Task:
    ///    - Wakes every 0.5 s to recompute remainingSeconds from the wall clock.
    ///    - When remaining reaches 0: stops polling and hides the alert.
    ///    - Note: the SMS is sent by the PHONE, not the watch — the watch just
    ///      dismisses its own UI when time runs out.
    private func alertDidFire(timestamp: Int64) {
        fallTimestamp = timestamp
        isAlertActive = true

        // Compute how many full seconds remain.  If the phone sent this event and
        // there was 2 s of Bluetooth latency, we start at 28 s, not 30 s, so both
        // countdowns show the same number.
        remainingSeconds = max(0, 30 - Int((Int64(Date().timeIntervalSince1970 * 1000) - timestamp) / 1000))

        alertExpireTask?.cancel()  // Cancel stale task if alertDidFire is called twice.

        // Start watching for a phone-side cancel.
        WatchSessionManager.shared.startPollingForCancel()

        // Launch the countdown timer as a Swift Concurrency Task.
        // Swift Concurrency (`async/await`) is Apple's modern threading model.
        // A `Task` runs its body on a background thread but never blocks the main
        // UI thread — that's why we use `await MainActor.run { }` for state writes.
        alertExpireTask = Task {
            while !Task.isCancelled {
                // Sleep 0.5 s — half-second updates keep the display smooth
                // (the seconds digit changes at most once per second anyway).
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }

                // Recompute from the original timestamp each iteration to avoid
                // drift — accumulated sleep error would cause the watch countdown
                // to diverge from the phone's over 30 seconds.
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let remaining = max(0, 30 - Int((now - fallTimestamp) / 1000))

                // Write to @Observable properties — must be on main thread.
                await MainActor.run { remainingSeconds = remaining }

                if remaining <= 0 {
                    // Time is up.  The phone handles SMS sending; the watch just
                    // dismisses its alert UI.
                    await MainActor.run {
                        WatchSessionManager.shared.stopPolling()
                        isAlertActive = false  // SwiftUI switches back to idleView.
                    }
                    return  // Exit the loop — task is done.
                }
            }
        }
    }
}
