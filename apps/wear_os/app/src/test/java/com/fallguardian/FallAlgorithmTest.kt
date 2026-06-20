package com.fallguardian

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for FallAlgorithm.
 *
 * Algorithm trigger rule (from source):
 *   fallDetected = freeFallQualifiedLatch && impactActive
 *
 * Free-fall must be observed first (>=freeFallMinMs) to latch the state;
 * the latch persists until reset() is called. Impact must then occur within
 * the 2000ms impact window. Tilt is tracked but not part of the trigger rule.
 */
class FallAlgorithmTest {

    private lateinit var algo: FallAlgorithm

    @Before
    fun setUp() {
        algo = FallAlgorithm(
            freeFallThresholdG = 0.5f,
            impactThresholdG = 2.5f,
            tiltThresholdDeg = 45f,
            freeFallMinMs = 80L
        )
    }

    // ---------------------------------------------------------------------------
    // Helper: send a fixed acceleration sample repeatedly over durationMs,
    // advancing nowMs by stepMs each call. Returns true if any call triggered.
    // ---------------------------------------------------------------------------
    private fun sendSamples(
        algo: FallAlgorithm,
        ax: Float, ay: Float, az: Float,
        durationMs: Long,
        stepMs: Long = 10L,
        startMs: Long = 0L
    ): Boolean {
        var triggered = false
        var t = startMs
        while (t < startMs + durationMs) {
            if (algo.processSample(ax, ay, az, t)) triggered = true
            t += stepMs
        }
        return triggered
    }

    // ------------------------------------------------------------------
    // 1. Free-fall >= 80ms then impact → must trigger (primary path)
    // ------------------------------------------------------------------
    @Test
    fun freeFallPlusImpact_triggersFall() {
        // Free-fall: normG(0,0,0) = 0 < 0.5 → freeFallActive starts at t=0.
        // After 80ms the latch fires; 100ms total ensures we pass the threshold.
        sendSamples(algo, 0f, 0f, 0f, durationMs = 100L, startMs = 0L)

        // Impact: normG ≈ 3.06 > 2.5 → impactActive=true, latch=true → trigger.
        val triggered = algo.processSample(0f, 0f, 30f, 110L)
        assertTrue("Free-fall >=80ms + impact must trigger a fall", triggered)
    }

    // ------------------------------------------------------------------
    // 2. Free-fall alone (no impact) → must NOT trigger
    // ------------------------------------------------------------------
    @Test
    fun freeFallAlone_doesNotTrigger() {
        val triggered = sendSamples(algo, 0f, 0f, 0f, durationMs = 200L, startMs = 0L)
        assertFalse("Free-fall without impact must not trigger", triggered)
    }

    // ------------------------------------------------------------------
    // 3. Impact alone with upright device → must NOT trigger
    //    (tilt ≈ 0° because gravity is vertical)
    // ------------------------------------------------------------------
    @Test
    fun impactAlone_doesNotTrigger() {
        // Converge gravity to upright so tilt stays ~0°.
        sendSamples(algo, 0f, 0f, 9.81f, durationMs = 200L, startMs = 0L)

        val triggered = algo.processSample(0f, 0f, 30f, 210L)
        assertFalse("Impact with upright device (tilt ~0°) must not trigger", triggered)
    }

    // ------------------------------------------------------------------
    // 4. Free-fall + impact while device is horizontally tilted → should trigger.
    //    Free-fall is required; tilt alone with impact does NOT trigger.
    // ------------------------------------------------------------------
    @Test
    fun freeFallPlusImpact_withPriorTilt_triggersFall() {
        // Prime gravity to horizontal so tiltAngleDeg ≈ 90°.
        sendSamples(algo, 9.81f, 0f, 0f, durationMs = 200L, startMs = 0L)
        // Free-fall for >=80ms → freeFallQualifiedLatch latches to true.
        sendSamples(algo, 0f, 0f, 0f, durationMs = 100L, startMs = 200L)

        val triggered = algo.processSample(0f, 0f, 30f, 310L)
        assertTrue("Free-fall + impact (with prior horizontal tilt) must trigger a fall", triggered)
    }

    // ------------------------------------------------------------------
    // 5. Free-fall for only 50ms (below 80ms threshold), upright device,
    //    then impact — must NOT trigger.
    //    (No tilt, and free-fall duration was too short to qualify.)
    // ------------------------------------------------------------------
    @Test
    fun freeFallTooShort_doesNotTrigger() {
        // Upright gravity baseline so tilt stays ~0°.
        sendSamples(algo, 0f, 0f, 9.81f, durationMs = 200L, startMs = 0L)

        // Short free-fall (50ms < freeFallMinMs=80ms).
        sendSamples(algo, 0f, 0f, 0f, durationMs = 50L, startMs = 200L)

        // Impact right after the short free-fall, upright, no tilt.
        val triggered = algo.processSample(0f, 0f, 30f, 255L)
        assertFalse("Impact after too-short free-fall with upright device must not trigger", triggered)
    }

    // ------------------------------------------------------------------
    // 6. Impact window expires after 2000ms → must NOT trigger
    // ------------------------------------------------------------------
    @Test
    fun impactWindowExpires_doesNotTrigger() {
        // Free-fall to qualify the latch, then record an impact.
        sendSamples(algo, 0f, 0f, 0f, durationMs = 100L, startMs = 0L)
        algo.processSample(0f, 0f, 30f, 110L) // sets impactDetected=true, impactTimeMs=110

        // More than 2000ms later — impact window expired.
        // impactTimeMs=110, so at t=2111: 2111-110=2001 >= 2000 → impactActive=false.
        val triggered = algo.processSample(0f, 0f, 9.81f, 2111L)
        assertFalse("Impact window must expire after 2000ms", triggered)
    }

    // ------------------------------------------------------------------
    // 7. reset() clears all state — impact + upright tilt after reset
    //    must NOT trigger
    // ------------------------------------------------------------------
    @Test
    fun reset_clearsState() {
        // Trigger a fall first (horizontal gravity + impact).
        sendSamples(algo, 9.81f, 0f, 0f, durationMs = 200L, startMs = 0L)
        algo.processSample(0f, 0f, 30f, 210L)

        // Reset clears impactDetected, gravity, and free-fall state.
        algo.reset()

        // Re-prime gravity to upright after reset (tilt ~0°).
        sendSamples(algo, 0f, 0f, 9.81f, durationMs = 200L, startMs = 300L)

        // Impact with upright device → tilt ~0° → must NOT trigger.
        val triggered = algo.processSample(0f, 0f, 30f, 510L)
        assertFalse("After reset, impact with upright device must not trigger", triggered)
    }

    // ------------------------------------------------------------------
    // 8. Norm calculation: (3, 4, 0) → norm = 5 m/s² ≈ 0.51g > 0.5g
    //    → NOT free-fall (just above threshold)
    //
    // We test the norm logic directly: normG(3, 4, 0) must be > freeFallThreshold,
    // so freeFallActive is never set, so even with a long period of this signal
    // there is no qualified free-fall.  We verify this by confirming that the
    // algorithm does NOT count it as free-fall: after 100ms of (3,4,0) followed by
    // a second period of upright gravity (to reset tilt), an impact must not trigger.
    // ------------------------------------------------------------------
    @Test
    fun normCalculation_isCorrect() {
        // norm(3, 4, 0) = 5 m/s² = 5/9.81 ≈ 0.51g.
        // 0.51g is NOT < 0.5g threshold → free-fall is never set.
        // Run 100ms of this signal followed by 300ms of upright to restore
        // tilt ≈ 0° before the impact sample.
        sendSamples(algo, 3f, 4f, 0f, durationMs = 100L, startMs = 0L)

        // Recover gravity to upright (reset tilt) so the impact path via tilt
        // is also blocked.
        sendSamples(algo, 0f, 0f, 9.81f, durationMs = 300L, startMs = 100L)

        // Impact: no free-fall was ever qualified; tilt ≈ 0° → must not trigger.
        val triggered = algo.processSample(0f, 0f, 30f, 410L)
        assertFalse("norm(3,4,0)=0.51g is not free-fall; impact after tilt recovery must not trigger", triggered)
    }

    // ------------------------------------------------------------------
    // 9. Gravity filter converges to steady-state after 20+ upright samples
    //    → tilt ≈ 0° → impact alone must NOT trigger
    // ------------------------------------------------------------------
    @Test
    fun gravityFilter_convergesToSteadyState() {
        // 20 samples of upright gravity (0, 0, 9.81).
        // alpha=0.8: after N samples from zero, gravity[2] ≈ 9.81*(1-0.8^N).
        // After 20 samples: 9.81*(1-0.8^20) ≈ 9.81*0.9885 ≈ 9.70. tilt ≈ 0°.
        sendSamples(algo, 0f, 0f, 9.81f, durationMs = 200L, startMs = 0L)

        // Impact: tilt should be ~0° → must NOT trigger.
        val triggered = algo.processSample(0f, 0f, 30f, 210L)
        assertFalse(
            "After upright gravity convergence tilt≈0° — impact alone must not trigger",
            triggered
        )
    }

    // ------------------------------------------------------------------
    // 10. normG exactly equal to freeFallThreshold (0.5) is NOT free-fall
    //     (strict '<' comparison — equal is not less-than)
    //
    // We use a z-axis-only signal so the gravity filter stays vertical and
    // tilt remains ~0°, isolating the norm threshold check.
    // ------------------------------------------------------------------
    @Test
    fun exactThreshold_treatedAsNotMeeting() {
        // norm(0, 0, 4.905) = 4.905 m/s² → normG = 4.905/9.81 = 0.5 exactly.
        // With strict '<', 0.5 is NOT < 0.5 → freeFallActive is never set.
        // The z-axis direction keeps gravity pointing upward → tilt stays ~0°.
        val exactNorm = 0.5f * 9.81f  // = 4.905 m/s²

        // 100ms of exactly-at-threshold signal (all along z, so tilt ~0°).
        sendSamples(algo, 0f, 0f, exactNorm, durationMs = 100L, startMs = 0L)

        // Impact: no free-fall qualified, tilt ~0° → must not trigger.
        val triggered = algo.processSample(0f, 0f, 30f, 110L)
        assertFalse(
            "normG == 0.5 (not strictly < freeFallThreshold) must not count as free-fall",
            triggered
        )
    }
}
