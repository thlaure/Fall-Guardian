import XCTest
@testable import FallGuardian_Watch_App

final class FallAlgorithmTests: XCTestCase {
    private var algorithm: FallAlgorithm!

    override func setUp() {
        super.setUp()
        algorithm = FallAlgorithm()
    }

    func testTableImpactWithoutOrientationChangeDoesNotTrigger() {
        baseline(algorithm)
        XCTAssertFalse(
            algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 500)
        )

        XCTAssertFalse(
            samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 520,
                durationMs: 3_000
            )
        )
    }

    func testLossOfBalanceImpactOrientationChangeAndStillnessTriggers() {
        baseline(algorithm)
        _ = samples(algorithm, x: 0, y: 0, z: 0, startMs: 500, durationMs: 160)
        XCTAssertFalse(algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 680))

        XCTAssertTrue(
            samples(
                algorithm,
                x: 1,
                y: 0,
                z: 0,
                startMs: 700,
                durationMs: 4_000
            )
        )
    }

    func testOrientationChangeWithoutStillnessDoesNotTrigger() {
        baseline(algorithm)
        _ = samples(algorithm, x: 0, y: 0, z: 0, startMs: 500, durationMs: 160)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 680)

        var triggered = false
        var time = 520.0
        while time < 4_800 {
            let x = Int(time / 100).isMultiple(of: 2) ? 1.0 : -1.0
            triggered =
                algorithm.processSample(ax: x, ay: 0, az: 0, nowMs: time) ||
                triggered
            time += 20
        }

        XCTAssertFalse(triggered)
    }

    func testHandDroppedOntoKneeWithoutOrientationDoesNotTrigger() {
        baseline(algorithm)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 500,
            durationMs: 160
        )
        XCTAssertFalse(algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 680))

        XCTAssertFalse(
            samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 700,
                durationMs: 3_500
            )
        )
    }

    func testRapidArmRaiseDoesNotTrigger() {
        baseline(algorithm)
        XCTAssertFalse(algorithm.processSample(ax: 0, ay: 0, az: 5, nowMs: 500))
        XCTAssertFalse(
            samples(algorithm, x: 1, y: 0, z: 0, startMs: 520, durationMs: 4_000)
        )
    }

    func testRaisedOrientationThresholdSuppressesRotationPath() {
        algorithm.tiltThresholdDeg = 100
        baseline(algorithm)
        _ = samples(algorithm, x: 0, y: 0, z: 0, startMs: 500, durationMs: 160)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 680)

        XCTAssertFalse(
            samples(
                algorithm,
                x: 1,
                y: 0,
                z: 0,
                startMs: 700,
                durationMs: 4_000
            )
        )
    }

    func testResetClearsCandidate() {
        baseline(algorithm)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 500,
            durationMs: 160
        )
        _ = algorithm.processSample(ax: 0, ay: 0, az: 4.5, nowMs: 680)

        algorithm.reset()
        baseline(algorithm, startMs: 1_000)
        XCTAssertFalse(
            samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 1_500,
                durationMs: 3_000
            )
        )
    }

    private func baseline(
        _ target: FallAlgorithm,
        startMs: Double = 0
    ) {
        _ = samples(
            target,
            x: 0,
            y: 0,
            z: 1,
            startMs: startMs,
            durationMs: 500
        )
    }

    private func samples(
        _ target: FallAlgorithm,
        x: Double,
        y: Double,
        z: Double,
        startMs: Double,
        durationMs: Double,
        stepMs: Double = 20
    ) -> Bool {
        var triggered = false
        var time = startMs
        while time <= startMs + durationMs {
            triggered =
                target.processSample(ax: x, ay: y, az: z, nowMs: time) ||
                triggered
            time += stepMs
        }
        return triggered
    }
}
