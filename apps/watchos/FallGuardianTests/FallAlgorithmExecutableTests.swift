import Foundation

@main
struct FallAlgorithmExecutableTests {
    private static var failures = 0

    static func main() {
        tableImpactDoesNotTrigger()
        lossOfBalanceTriggers()
        movementAfterImpactDoesNotTrigger()
        qualifiedLowAccelerationTriggers()
        staleLowAccelerationDoesNotTrigger()
        postImpactLowAccelerationDoesNotTrigger()
        strictOrientationThresholdSuppressesRotation()
        resetClearsCandidate()

        guard failures == 0 else {
            fputs("\(failures) FallAlgorithm test(s) failed\n", stderr)
            exit(1)
        }
        print("FallAlgorithm tests passed")
    }

    private static func tableImpactDoesNotTrigger() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        expect(
            !algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 500),
            "table impact is not an immediate fall"
        )
        expect(
            !samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 520,
                durationMs: 3_000
            ),
            "table impact without orientation change stays rejected"
        )
    }

    private static func lossOfBalanceTriggers() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 500)
        expect(
            samples(
                algorithm,
                x: 1,
                y: 0,
                z: 0,
                startMs: 520,
                durationMs: 4_000
            ),
            "impact, orientation change and stillness trigger"
        )
    }

    private static func movementAfterImpactDoesNotTrigger() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 500)

        var triggered = false
        var time = 520.0
        while time < 4_800 {
            let x = Int(time / 100).isMultiple(of: 2) ? 1.0 : -1.0
            triggered =
                algorithm.processSample(ax: x, ay: 0, az: 0, nowMs: time) ||
                triggered
            time += 20
        }
        expect(!triggered, "continued motion after impact stays rejected")
    }

    private static func qualifiedLowAccelerationTriggers() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 500,
            durationMs: 100
        )
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 620)
        expect(
            samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 640,
                durationMs: 3_500
            ),
            "low acceleration, impact and stillness trigger"
        )
    }

    private static func strictOrientationThresholdSuppressesRotation() {
        let algorithm = FallAlgorithm()
        algorithm.tiltThresholdDeg = 100
        baseline(algorithm)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 500)
        expect(
            !samples(
                algorithm,
                x: 1,
                y: 0,
                z: 0,
                startMs: 520,
                durationMs: 4_000
            ),
            "orientation threshold changes rotation-path behavior"
        )
    }

    private static func staleLowAccelerationDoesNotTrigger() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 500,
            durationMs: 100
        )
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 1,
            startMs: 620,
            durationMs: 2_000
        )
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 2_640)
        expect(
            !samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 2_660,
                durationMs: 3_000
            ),
            "stale low acceleration cannot combine with a later impact"
        )
    }

    private static func postImpactLowAccelerationDoesNotTrigger() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 500)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 520,
            durationMs: 100
        )
        expect(
            !samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 640,
                durationMs: 3_500
            ),
            "post-impact low acceleration cannot qualify a fall"
        )
    }

    private static func resetClearsCandidate() {
        let algorithm = FallAlgorithm()
        baseline(algorithm)
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 0,
            startMs: 500,
            durationMs: 100
        )
        _ = algorithm.processSample(ax: 0, ay: 0, az: 3.1, nowMs: 620)
        algorithm.reset()
        baseline(algorithm, startMs: 1_000)
        expect(
            !samples(
                algorithm,
                x: 0,
                y: 0,
                z: 1,
                startMs: 1_500,
                durationMs: 3_000
            ),
            "reset clears candidate phases"
        )
    }

    private static func baseline(
        _ algorithm: FallAlgorithm,
        startMs: Double = 0
    ) {
        _ = samples(
            algorithm,
            x: 0,
            y: 0,
            z: 1,
            startMs: startMs,
            durationMs: 500
        )
    }

    private static func samples(
        _ algorithm: FallAlgorithm,
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
                algorithm.processSample(ax: x, ay: y, az: z, nowMs: time) ||
                triggered
            time += stepMs
        }
        return triggered
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }
}
