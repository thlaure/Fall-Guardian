// FallAlgorithm.swift
// Fall Guardian — watchOS
//
// This file contains the pure math that decides whether a fall has occurred.
// It has NO knowledge of sensors, network, or UI — it only receives numbers
// and returns true/false.  That separation makes it easy to unit-test and to
// share the same logic between platforms (the Kotlin Wear OS version uses
// identical thresholds and state machine).
//
// How it fits in the system:
//   CMMotionManager (hardware accelerometer)
//       ↓  raw x/y/z values 50 times per second
//   FallDetectionManager.process(data:)
//       ↓  calls processSample() on every tick
//   FallAlgorithm.processSample()   ← YOU ARE HERE
//       ↓  returns true when fall is confirmed
//   FallDetectionManager  fires onFallDetected callback
//       ↓
//   ContentViewModel.alertDidFire()  →  UI + WatchSessionManager

import Foundation  // Basic Swift utilities (Date, etc.) — no UI dependencies here.
import CoreMotion  // Apple's motion framework; CMAccelerometerData lives here.
                   // We import it for documentation purposes even though this
                   // class only receives plain Doubles, not CMAccelerometerData directly.

/// Pure fall-detection algorithm — a Swift port of the Kotlin Wear OS version.
///
/// ## What is the PSP algorithm?
/// PSP stands for the three phases it checks in sequence:
///   - **P**hase 1 — Free-fall  : the watch becomes nearly weightless
///   - **P**hase 2 — Impact     : a sudden hard jolt follows the free-fall
///   - **P**hase 3 — (P)osture/Tilt : body orientation change after landing
///                                    (tracked here but not part of the trigger)
///
/// A real human fall typically produces this exact signature:
///   1. The person's arm swings freely → accelerometer magnitude drops near 0 g.
///   2. The body hits the ground        → magnitude spikes well above 1 g.
/// Requiring both phases in order eliminates most false positives (sitting down,
/// arm gestures, phone vibrations, etc.).
///
/// ## Units: g-forces vs m/s²
/// Apple's CMMotionManager reports acceleration in **g** (1 g ≈ 9.81 m/s²).
/// When the watch is lying still on a table the magnitude is exactly 1 g
/// (gravity alone).  During free-fall it approaches 0 g.  During a hard impact
/// it can reach 3–6 g.  All thresholds in this class use g as the unit.
class FallAlgorithm {

    // MARK: - Configurable thresholds
    //
    // These four values are the knobs that control sensitivity.  They are NOT
    // hard-coded — FallDetectionManager reads them from UserDefaults (the watch's
    // local key-value store) so the phone app can push updates via WatchSessionManager.
    // The keys that must match across all platforms are documented in CLAUDE.md.

    /// Acceleration magnitude (in g) below which the watch is considered to be in
    /// free-fall.  Earth's gravity alone gives 1 g; during a true free-fall the
    /// accelerometer approaches 0 g.  0.5 g is a conservative threshold that
    /// avoids triggering on slow arm movements while still catching real falls.
    var freeFallThresholdG: Double = 0.5

    /// Acceleration magnitude (in g) that must be exceeded for an impact to be
    /// registered.  Normal walking peaks around 1.5–2 g; a body hitting the floor
    /// typically produces 3–6 g.  2.5 g sits between those ranges.
    var impactThresholdG: Double = 2.5

    /// Tilt angle (degrees from vertical) tracked after landing.  Kept for future
    /// use and logging but not currently part of the trigger condition.
    var tiltThresholdDeg: Double = 45.0

    /// Minimum number of milliseconds the acceleration must stay below
    /// `freeFallThresholdG` to be counted as genuine free-fall.  Short spikes
    /// (e.g. a sudden wrist flick) last only 10–30 ms; real falls typically last
    /// 80–200 ms.  This filter prevents wrist movements from triggering the alarm.
    var freeFallMinMs: Double = 80.0

    // MARK: - Internal state
    //
    // These variables track what phase the algorithm is currently in.
    // They are all reset between falls so each detection starts fresh.

    /// The millisecond timestamp at which the current free-fall window started.
    /// Used to measure how long the watch has been in free-fall.
    private var freeFallStartMs: Double = 0

    /// True while the magnitude is currently below `freeFallThresholdG`.
    /// Becomes false the moment the magnitude climbs back above the threshold.
    private var freeFallActive = false

    /// A "latch" flag that stays true once a qualifying free-fall has been seen.
    /// This is important because free-fall ends before impact — the watch is no
    /// longer in free-fall when it hits the ground.  Without a latch we would
    /// never see both phases simultaneously.  Only `reset()` clears this.
    private var freeFallQualifiedLatch = false

    /// True once a magnitude spike above `impactThresholdG` has been seen.
    private var impactDetected = false

    /// Millisecond timestamp of the most recent impact spike.
    /// Used together with `impactDetected` to enforce a 2-second impact window
    /// (impacts older than 2 s are ignored to avoid late false triggers).
    private var impactTimeMs: Double = 0

    // MARK: - Low-pass filter state
    //
    // A raw accelerometer signal contains both gravity (a constant downward pull)
    // and the device's own acceleration (wrist movements, impacts).  Separating
    // them lets us compute tilt even while the user is moving.
    //
    // A low-pass filter keeps the slow-changing gravity component by blending the
    // current raw value with the previous filtered value:
    //   gravity_new = alpha * gravity_old + (1 - alpha) * raw
    // A high alpha (0.8) means "trust the old value a lot" → the filtered signal
    // changes slowly → it tracks gravity but ignores fast movements.

    private var gravityX: Double = 0  // Filtered gravity component along X axis (g)
    private var gravityY: Double = 0  // Filtered gravity component along Y axis (g)
    private var gravityZ: Double = 0  // Filtered gravity component along Z axis (g)

    /// Blending coefficient for the gravity low-pass filter.
    /// 0.8 = 80% old estimate + 20% new measurement.
    private let alpha: Double = 0.8

    // MARK: - Public API

    /// Resets all internal state so the next `processSample` call starts a brand-new
    /// detection cycle.  Called by FallDetectionManager after a fall is confirmed
    /// and after `stop()` to avoid carrying stale state into the next session.
    func reset() {
        freeFallActive = false
        freeFallStartMs = 0
        freeFallQualifiedLatch = false
        impactDetected = false
        impactTimeMs = 0
        gravityX = 0; gravityY = 0; gravityZ = 0
    }

    /// Analyzes one accelerometer sample and returns whether a fall was just detected.
    ///
    /// This method is called 50 times per second by `FallDetectionManager`.
    /// Each call runs through the three PSP phases in order and returns `true`
    /// only when both phase-1 latch and active phase-2 are simultaneously satisfied.
    ///
    /// - Parameters:
    ///   - ax: Raw X-axis acceleration from the accelerometer, in g-units.
    ///         Positive X points roughly toward the top of the watch face.
    ///   - ay: Raw Y-axis acceleration, in g-units.
    ///   - az: Raw Z-axis acceleration, in g-units.
    ///         Positive Z points away from the wearer's wrist.
    ///   - nowMs: Current wall-clock time in milliseconds since Unix epoch (1 Jan 1970).
    ///            Passed in rather than read internally so tests can feed fake timestamps.
    /// - Returns: `true` the first time both free-fall and impact conditions are met.
    ///            `false` on every other call.
    func processSample(ax: Double, ay: Double, az: Double, nowMs: Double) -> Bool {

        // --- Step 0: Update the gravity low-pass filter ---
        // Each component is blended independently.  After a few seconds of still
        // wear the gravity vector converges and tracks the orientation of the watch.
        gravityX = alpha * gravityX + (1 - alpha) * ax
        gravityY = alpha * gravityY + (1 - alpha) * ay
        gravityZ = alpha * gravityZ + (1 - alpha) * az

        // --- Compute the scalar magnitude of the raw acceleration vector ---
        // norm(x,y,z) = √(x²+y²+z²)
        // This collapses the three-axis measurement into a single "how much force?"
        // number in g.  When the watch is still: ~1 g.  Free-fall: ~0 g.  Impact: 3–6 g.
        // Using magnitude (instead of any single axis) makes the algorithm
        // orientation-independent — it works regardless of how the user wears the watch.
        //
        // CMMotionManager already delivers values in g, so no conversion is needed.
        let normG = norm(ax, ay, az)

        // --- Phase 1: Free-fall detection ---
        // We need to see the magnitude stay below the threshold for at least
        // `freeFallMinMs` milliseconds continuously.  A single low sample could
        // be noise; a sustained dip is real free-fall.
        if normG < freeFallThresholdG {
            // Magnitude is in the free-fall zone.
            if !freeFallActive {
                // First sample in this free-fall window — record the start time.
                freeFallActive = true
                freeFallStartMs = nowMs
            }
            // If freeFallActive was already true, we just keep accumulating time.
        } else {
            // Magnitude climbed back above threshold — free-fall ended.
            freeFallActive = false
            // Note: we do NOT reset freeFallStartMs here because the latch below
            // has already recorded a qualified event if one occurred.
        }

        // `freeFallQualified` is true only while in the free-fall zone AND the
        // duration has exceeded the minimum millisecond requirement.
        let freeFallQualified = freeFallActive && (nowMs - freeFallStartMs >= freeFallMinMs)

        // The latch turns on as soon as free-fall qualifies and stays on until
        // reset() is called.  This lets us match a free-fall that ended 500 ms
        // ago with an impact happening right now — a realistic fall timeline.
        if freeFallQualified { freeFallQualifiedLatch = true }

        // --- Phase 2: Impact detection ---
        // Record the timestamp whenever a spike above the threshold occurs.
        if normG > impactThresholdG {
            impactDetected = true
            impactTimeMs = nowMs  // Refresh the window start on every spike sample.
        }

        // The impact is considered "active" only within 2 seconds of the spike.
        // After 2 s we stop waiting — if a free-fall latch exists but no recent
        // impact followed it was probably a slow controlled descent, not a fall.
        let impactActive = impactDetected && (nowMs - impactTimeMs < 2000)

        // --- Phase 3: Tilt tracking (informational only) ---
        // Tilt angle is computed from the filtered gravity vector.  It tells us
        // how far the watch has tilted from its normal upright position.
        // Currently tracked but NOT part of the trigger decision.  The underscore
        // assignment suppresses the Swift "result unused" compiler warning.
        _ = tiltAngleDeg()

        // --- Final trigger ---
        // A fall is confirmed when BOTH conditions hold at the same time:
        //   • The free-fall latch fired earlier (phase 1 was qualified)
        //   • An impact spike happened recently (phase 2 is still active)
        // Returning true here causes FallDetectionManager to fire the alarm.
        return freeFallQualifiedLatch && impactActive
    }

    // MARK: - Private helpers

    /// Computes the tilt angle (in degrees) between the filtered gravity vector
    /// and the vertical axis (Z axis, perpendicular to the wrist).
    ///
    /// A tilt of 0° means the watch face is horizontal (wearer lying flat on back).
    /// A tilt of 90° means the watch face is vertical (normal wearing position).
    /// Values near 90° after a fall suggest the person is lying on their side.
    ///
    /// The formula is the arc-cosine of the Z component divided by the total
    /// magnitude, then converted from radians to degrees.
    /// `max(-1, min(1, ...))` clamps the input to the valid arc-cosine domain
    /// [-1, 1] to prevent a NaN result from floating-point rounding errors.
    private func tiltAngleDeg() -> Double {
        let gNorm = norm(gravityX, gravityY, gravityZ)
        guard gNorm > 0.01 else { return 0 }  // Avoid dividing by near-zero during initialisation.
        let cosAngle = max(-1, min(1, gravityZ / gNorm))
        return (acos(cosAngle) * 180) / .pi
    }

    /// Returns the Euclidean magnitude (length) of a 3D vector.
    /// Example: norm(0, 0, 1) = 1.0  (watch lying flat, gravity pointing straight down)
    ///          norm(0, 0, 0) = 0.0  (theoretical pure free-fall)
    private func norm(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
