// ContentView.swift
// Fall Guardian — watchOS
//
// This file is the entire watchOS user interface.  Apple Watch apps can only
// display one "scene" at a time (there are no navigation stacks or tabs in
// typical watch apps), so this single file renders both possible states:
//
//   IDLE      — shield icon + "Monitoring active" text (normal state)
//   ALERT     — countdown, then "Notifying your caregivers…" (fall detected);
//               the 1.5 s hold-to-cancel stays available in both phases
//
// Architecture pattern used here: MVVM (Model-View-ViewModel)
//   - `ContentView`      is the VIEW      — pure SwiftUI, no business logic.
//   - `ContentViewModel` is the VIEWMODEL — holds state and coordinates actions.
//   - WatchAlertState (pure, unit tested) holds the alert state machine;
//     SystemFallDetectionService / WatchSessionManager are the platform layer.
//
// How data flows end-to-end when a fall happens:
//   1. CMFallDetectionManager wakes the app with Apple's system event
//   2. SystemFallDetectionService validates and deduplicates the event
//   3. ContentViewModel.alertDidFire(_:) starts WatchAlertState
//   4. SwiftUI re-renders ContentView, showing alertView
//   5. WatchSessionManager.sendFallEvent() notifies the iPhone
//
// How data flows when the alert is cancelled:
//   Watch side:   deliberate 1.5 s hold → viewModel.cancelAlert()
//   Phone side:   WatchSessionManager.onAlertCancelled → viewModel.cancelAlert(notifyPhone: false)

import SwiftUI      // Apple's declarative UI framework for all Apple platforms.
                    // Views are Swift structs that describe WHAT to show; SwiftUI
                    // decides HOW and WHEN to redraw them.
import Observation  // Provides the @Observable macro used on ContentViewModel.
                    // Replaces the older @ObservedObject/@Published pattern on iOS 17+.
import WatchKit     // WKInterfaceDevice.current().play() — haptic feedback API.
import CoreMotion
import Accessibility  // AccessibilityNotification.Announcement for VoiceOver.

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
        Group {
            if let phase = viewModel.alertPhase {
                alertView(phase: phase)  // Fall in progress.
            } else if viewModel.isShowingLateCancelNotice {
                lateCancelNoticeView     // Cancel sent after the deadline.
            } else {
                idleView                 // Shield icon — monitoring quietly.
            }
        }
        // Called once when the view first appears on screen.
        // We start the services here rather than in init() because watchOS may
        // keep the view object alive in memory while suspending the app;
        // onAppear fires reliably when the face is actually visible.
        .onAppear {
            viewModel.startIfNeeded()
        }
    }

    // MARK: - Alert view (fall detected)

    /// Full-screen red layout shown while an alert is active.
    ///
    /// Fonts use Dynamic Type text styles so they follow the wearer's text-size
    /// setting; `minimumScaleFactor` keeps the largest sizes on screen.
    private func alertView(phase: WatchAlertPhase) -> some View {
        ZStack {
            Color(red: 0.1, green: 0, blue: 0).ignoresSafeArea()

            if isUrgent(phase) {
                Color.red.opacity(0.3).ignoresSafeArea()
            }

            VStack(spacing: 6) {
                switch phase {
                case .countdown(let seconds):
                    Text(verbatim: "\(seconds)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .accessibilityLabel(Text("\(seconds) seconds before your caregivers are notified"))
                        .accessibilityAddTraits(.updatesFrequently)
                case .notifyingCaregivers:
                    Text("Notifying your caregivers…")
                        .font(.headline)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Text("I'm OK\nHold to cancel")
                    .font(.footnote.weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.green.opacity(0.85))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onLongPressGesture(
                        minimumDuration: 1.5,
                        maximumDistance: 30
                    ) {
                        viewModel.cancelAlert()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("I'm OK. Cancel alert"))
                    .accessibilityHint(Text("Touch and hold for one and a half seconds"))
                    .accessibilityAddTraits(.isButton)
                    // No accessibilityAction on purpose: a single VoiceOver
                    // double-tap must not cancel a safety alert. VoiceOver users
                    // double-tap and hold, which passes the long press through.
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(.red.opacity(0.1), for: .navigation)
    }

    private func isUrgent(_ phase: WatchAlertPhase) -> Bool {
        if case .countdown(let seconds) = phase { return seconds <= 10 }
        return true
    }

    // MARK: - Late cancel notice

    /// Shown after the wearer cancels once the grace window is over. The cancel
    /// is still sent to the phone, but the API may already have alerted
    /// caregivers, and it does not tell them the person is OK — so the screen
    /// must not look like a successful, silent cancel.
    private var lateCancelNoticeView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Caregivers may already have been notified")
                .font(.headline)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Button("OK") {
                viewModel.dismissLateCancelNotice()
            }
        }
        .padding(.horizontal, 4)
        .containerBackground(.orange.opacity(0.15), for: .navigation)
    }

    // MARK: - Idle view (no active alert, monitoring silently)

    /// Compact status view shown when no fall is in progress.
    private var idleView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.247, blue: 0.235))  // Dark teal
                    .frame(width: 52, height: 52)
                Image(systemName: "shield.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            Text(verbatim: "Fall Guardian")
                .font(.headline)
                .foregroundStyle(.white)

            Text(viewModel.monitoringStatusText)
                .font(.caption)
                .foregroundStyle(Color(red: 0.820, green: 0.878, blue: 0.843))  // Light mint
                .multilineTextAlignment(.center)

            // Test builds only — stripped from App Store / release builds.
            #if DEBUG || TESTING
            Button("Test Apple relay (debug)") {
                viewModel.simulateAppleSystemFall()
            }
            .font(.footnote)
            .foregroundStyle(Color(red: 0.898, green: 0.412, blue: 0.290))
            #endif
        }
        .containerBackground(.black, for: .navigation)
    }
}

// MARK: - ContentViewModel (the business logic layer)

/// Thin coordinator between the UI, the pure `WatchAlertState` machine, and
/// the platform services. Decisions (phase, haptics, announcements, cancel
/// matching) live in tested pure types; this class only wires side effects.
///
/// Threading note: properties are read by SwiftUI on the main thread; every
/// write happens on the main thread.
@Observable
class ContentViewModel {

    // MARK: - Published state (read by ContentView)

    /// nil = idle; otherwise what the alert screen shows.
    var alertPhase: WatchAlertPhase?

    var isAlertActive: Bool { alertState.isActive }

    /// True after a cancel that came too late to stop escalation.
    var isShowingLateCancelNotice = false

    /// Makes the important difference between system background monitoring and
    /// an inactive watch visible to the wearer.
    var monitoringStatusText: String = String(localized: "Checking permission…")

    // MARK: - Private state

    private var alertState = WatchAlertState()

    /// The background task that drives the alert screen.
    private var alertTickTask: Task<Void, Never>?

    deinit {
        alertTickTask?.cancel()
    }

    // MARK: - Lifecycle

    func startIfNeeded() {
        let systemDetection = SystemFallDetectionService.shared
        systemDetection.onFallDetected = { [weak self] incident in
            DispatchQueue.main.async {
                self?.alertDidFire(incident, presentedAt: WatchAlertNotificationService.nowMilliseconds())
            }
        }
        systemDetection.onAuthorizationChanged = { [weak self] status in
            DispatchQueue.main.async { self?.applyDetectionMode(for: status) }
        }
        systemDetection.requestAuthorizationIfNeeded()
        applyDetectionMode(for: systemDetection.authorizationStatus)

        // Wire the cancel callback from the phone.
        // `notifyPhone: false` prevents the ping-pong loop: the phone already
        // knows it cancelled — we only need to update the watch UI.
        WatchSessionManager.shared.onAlertCancelled = { [weak self] in
            self?.cancelAlert(notifyPhone: false)
        }

        let notificationService = WatchAlertNotificationService.shared
        notificationService.requestAuthorizationIfNeeded()

        // If watchOS launched the app because the wearer tapped a fall
        // notification (or its "Open to cancel" action), restore the incident.
        if let active = notificationService.activeAlert() {
            alertDidFire(active.incident, presentedAt: active.presentedAt)
        }

        #if DEBUG && targetEnvironment(simulator)
        startDebugTriggerPolling()
        #endif
    }

    // MARK: - Debug / simulator test helpers

    #if DEBUG && targetEnvironment(simulator)
    /// Polls /tmp flag files written by `scripts/test_ios_watchos.sh` so the E2E
    /// script can simulate a fall or a cancel without UI interaction.
    ///   /tmp/com.fallguardian.debugSimulateFall  → simulateFall()
    ///   /tmp/com.fallguardian.debugCancelWatch   → cancelAlert()
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

    /// Fires a local fall and relays it, exercising watch + phone end-to-end.
    func simulateFall() {
        guard !isAlertActive else { return }
        let now = WatchAlertNotificationService.nowMilliseconds()
        let incident = WatchIncident.make(timestamp: now)
        WatchAlertNotificationService.shared.presentFallAlert(incident)
        alertDidFire(incident, presentedAt: now)
        WatchSessionManager.shared.sendFallEvent(incident)
    }
    #endif

    // MARK: - Actions

    /// Tests the same relay used by CMFallDetectionManager. It deliberately does
    /// not claim to emulate Apple's proprietary fall-detection sensor model.
    func simulateAppleSystemFall() {
        guard !isAlertActive else { return }
        #if DEBUG || TESTING
        SystemFallDetectionService.shared.simulateFallForTesting()
        #endif
    }

    /// Cancels the active alert and optionally notifies the phone.
    ///
    /// - Parameter notifyPhone: `false` when the cancel originated from the phone
    ///   (avoids a cancel ping-pong loop).
    func cancelAlert(notifyPhone: Bool = true) {
        let outcome = alertState.cancelOutcome(now: WatchAlertNotificationService.nowMilliseconds())
        let cancelled = finishAlert()
        guard notifyPhone else { return }

        // Always relay the cancel, naming the incident, even when late.
        WatchSessionManager.shared.sendCancelAlert(for: cancelled)

        if outcome == .afterDeadline {
            // Honest feedback: escalation may already have happened.
            WKInterfaceDevice.current().play(.failure)
            isShowingLateCancelNotice = true
            AccessibilityNotification.Announcement(
                String(localized: "Caregivers may already have been notified")
            ).post()
        } else {
            WKInterfaceDevice.current().play(.success)
        }
    }

    func dismissLateCancelNotice() {
        isShowingLateCancelNotice = false
    }

    // MARK: - Private alert logic

    /// Starts the alert screen for an incident.
    ///
    /// The countdown is computed from the fall timestamp (shared with phone and
    /// API). Apple can deliver its event after its own check-in, so the grace
    /// window may already be over: the screen then shows "Notifying your
    /// caregivers…" with cancel still available, never a 0 countdown. Escalation
    /// timing is unchanged — the API owns the deadline.
    private func alertDidFire(_ incident: WatchIncident, presentedAt: Int64) {
        let now = WatchAlertNotificationService.nowMilliseconds()
        guard alertState.start(incident, presentedAt: presentedAt, now: now) else { return }
        isShowingLateCancelNotice = false

        // Watch for a phone-side cancellation of this exact incident.
        WatchSessionManager.shared.startPollingForCancel(incident: incident)
        update(now: now)

        alertTickTask?.cancel()
        alertTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                let keepRunning = await MainActor.run { () -> Bool in
                    guard let self else { return false }
                    return self.update(now: WatchAlertNotificationService.nowMilliseconds())
                }
                if !keepRunning { return }
            }
        }
    }

    /// Recomputes the phase from the wall clock (no drift), plays haptics and
    /// VoiceOver announcements on changes. Returns false once the alert ended.
    ///
    /// Haptics play from this tick (not from the view), so they keep running
    /// while the app process is active even if the view is not redrawn.
    /// watchOS does not let a suspended third-party app play haptics; the
    /// time-sensitive notification covers the closed-app case.
    @discardableResult
    private func update(now: Int64) -> Bool {
        let previous = alertPhase
        guard let phase = alertState.phase(now: now) else {
            // Display window over. Backend escalation continues independently.
            finishAlert()
            return false
        }
        alertPhase = phase

        switch WatchAlertState.hapticCue(from: previous, to: phase) {
        case .tick: WKInterfaceDevice.current().play(.click)
        case .urgent: WKInterfaceDevice.current().play(.notification)
        case nil: break
        }

        if WatchAlertState.shouldAnnounce(phase, previous: previous) {
            AccessibilityNotification.Announcement(announcement(for: phase)).post()
        }
        return true
    }

    private func announcement(for phase: WatchAlertPhase) -> String {
        switch phase {
        case .countdown(let seconds):
            return String(localized: "\(seconds) seconds before your caregivers are notified")
        case .notifyingCaregivers:
            return String(localized: "Notifying your caregivers…")
        }
    }

    @discardableResult
    private func finishAlert() -> WatchIncident? {
        alertTickTask?.cancel()
        alertTickTask = nil
        WatchSessionManager.shared.stopPolling()
        let finished = alertState.finish()
        alertPhase = nil
        WatchAlertNotificationService.shared.clearAlert()
        applyDetectionMode(for: SystemFallDetectionService.shared.authorizationStatus)
        return finished
    }

    /// Apple detection is the only production source because it can wake the
    /// app in the background. If it is unavailable or denied, say so instead of
    /// implying background protection.
    private func applyDetectionMode(for status: CMAuthorizationStatus) {
        switch status {
        case .authorized:
            monitoringStatusText = String(localized: "Apple background fall detection active")
        case .notDetermined:
            monitoringStatusText = String(localized: "Allow Apple fall detection for background alerts")
        default:
            monitoringStatusText = String(localized: "Apple fall detection unavailable — monitoring inactive")
        }
    }
}
