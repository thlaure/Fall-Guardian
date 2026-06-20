import XCTest

// Note: to run these tests, add a "Unit Testing Bundle" target in Xcode:
// File → New → Target → Unit Testing Bundle, set the host app to
// "FallGuardian Watch App", then add FallAlgorithm.swift to that target.

final class FallAlgorithmTests: XCTestCase {

    private var algorithm: FallAlgorithm!

    override func setUp() {
        super.setUp()
        algorithm = FallAlgorithm()
    }

    override func tearDown() {
        algorithm = nil
        super.tearDown()
    }

    // MARK: - No false positive at rest

    func testNoFallAtRest() {
        var triggered = false
        for i in 0..<200 {
            let t = Double(i) * 20 // 50 Hz → 20 ms steps
            triggered = algorithm.processSample(ax: 0, ay: 0, az: 1.0, nowMs: t) || triggered
        }
        XCTAssertFalse(triggered, "Should not detect a fall at rest")
    }

    // MARK: - Free-fall alone does not trigger

    func testFreeFallAloneDoesNotTrigger() {
        var triggered = false
        for i in 0..<10 {
            let t = Double(i) * 20
            triggered = algorithm.processSample(ax: 0.1, ay: 0.1, az: 0.1, nowMs: t) || triggered
        }
        XCTAssertFalse(triggered, "Free-fall alone should not trigger")
    }

    // MARK: - Impact alone does not trigger

    func testImpactAloneDoesNotTrigger() {
        var triggered = false
        for i in 0..<5 {
            let t = Double(i) * 20
            triggered = algorithm.processSample(ax: 3.0, ay: 3.0, az: 3.0, nowMs: t) || triggered
        }
        XCTAssertFalse(triggered, "Impact without prior free-fall should not trigger")
    }

    // MARK: - Full fall sequence triggers detection

    func testFallSequenceTriggers() {
        var triggered = false
        var t = 0.0

        // Phase 1: free-fall for 100 ms (5 samples at 20 ms each)
        for _ in 0..<5 {
            triggered = algorithm.processSample(ax: 0.1, ay: 0.1, az: 0.1, nowMs: t) || triggered
            t += 20
        }

        // Phase 2: impact
        triggered = algorithm.processSample(ax: 3.0, ay: 3.0, az: 3.0, nowMs: t) || triggered

        XCTAssertTrue(triggered, "Fall sequence (free-fall then impact) should trigger detection")
    }

    // MARK: - reset() clears latch

    func testResetClearsFreeFallLatch() {
        var t = 0.0
        // Qualify free-fall latch
        for _ in 0..<5 {
            _ = algorithm.processSample(ax: 0.1, ay: 0.1, az: 0.1, nowMs: t)
            t += 20
        }
        algorithm.reset()
        // After reset, impact alone must not trigger
        let triggered = algorithm.processSample(ax: 3.0, ay: 3.0, az: 3.0, nowMs: t)
        XCTAssertFalse(triggered, "Impact after reset() should not trigger without new free-fall")
    }

    // MARK: - Impact window expires

    func testImpactWindowExpires() {
        var t = 0.0
        // Free-fall for 100 ms
        for _ in 0..<5 {
            _ = algorithm.processSample(ax: 0.1, ay: 0.1, az: 0.1, nowMs: t)
            t += 20
        }
        // Impact at t = 100
        _ = algorithm.processSample(ax: 3.0, ay: 3.0, az: 3.0, nowMs: t)
        t += 2500 // advance 2.5 s past the 2 s impact window

        let triggered = algorithm.processSample(ax: 1.0, ay: 0, az: 0, nowMs: t)
        XCTAssertFalse(triggered, "Should not trigger when impact window has expired")
    }

    // MARK: - Short free-fall below minimum duration does not latch

    func testShortFreeFallDoesNotLatch() {
        var t = 0.0
        // Free-fall for only 40 ms (< default 80 ms minimum)
        for _ in 0..<2 {
            _ = algorithm.processSample(ax: 0.1, ay: 0.1, az: 0.1, nowMs: t)
            t += 20
        }
        // Impact immediately after
        let triggered = algorithm.processSample(ax: 3.0, ay: 3.0, az: 3.0, nowMs: t)
        XCTAssertFalse(triggered, "Free-fall shorter than freeFallMinMs should not latch")
    }
}
