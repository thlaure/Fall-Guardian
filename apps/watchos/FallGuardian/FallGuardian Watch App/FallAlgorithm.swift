import Foundation

/// Multi-phase wrist fall detector tuned for loss-of-balance scenarios.
///
/// A wrist impact alone is intentionally insufficient because knocking a table
/// can exceed the impact threshold. A fall candidate must contain an impact,
/// two seconds of post-impact stillness, and either a qualified low-acceleration
/// phase or a meaningful orientation change relative to the pre-impact wrist
/// orientation.
final class FallAlgorithm {
    var freeFallThresholdG: Double = 0.7
    var impactThresholdG: Double = 2.5
    var tiltThresholdDeg: Double = 50
    var freeFallMinMs: Double = 60

    private var freeFallStartMs: Double = 0
    private var freeFallActive = false
    private var freeFallQualifiedLatch = false
    private var freeFallQualifiedAtMs: Double = 0

    private var impactDetected = false
    private var impactTimeMs: Double = 0
    private var preImpactGravity = Vector3.zero
    private var orientationChangedLatch = false

    private var stillnessStartMs: Double = 0
    private var stillnessActive = false

    private var gravity = Vector3.zero
    private var gravityInitialized = false

    private let alpha = 0.8
    private let candidateWindowMs = 5_000.0
    private let lowAccelerationToImpactMaxMs = 1_500.0
    private let settleDelayMs = 300.0
    private let stillnessMinMs = 2_000.0
    private let stillnessThresholdG = 0.25
    private let nearGravityToleranceG = 0.25

    func reset() {
        freeFallStartMs = 0
        freeFallActive = false
        freeFallQualifiedLatch = false
        freeFallQualifiedAtMs = 0
        impactDetected = false
        impactTimeMs = 0
        preImpactGravity = .zero
        orientationChangedLatch = false
        stillnessStartMs = 0
        stillnessActive = false
        gravity = .zero
        gravityInitialized = false
    }

    /// Processes an accelerometer sample expressed in g-units.
    func processSample(
        ax: Double,
        ay: Double,
        az: Double,
        nowMs: Double
    ) -> Bool {
        let sample = Vector3(x: ax, y: ay, z: az)
        let normG = sample.magnitude

        if !gravityInitialized && normG > 0.8 && normG < 1.2 {
            gravity = sample
            gravityInitialized = true
        }

        // Low acceleration is a pre-impact fall phase. Accepting it after a
        // table knock would join unrelated later wrist movement to that impact.
        if !impactDetected {
            updateFreeFall(normG: normG, nowMs: nowMs)
        }

        if !impactDetected && normG > impactThresholdG {
            freeFallQualifiedLatch =
                freeFallQualifiedLatch &&
                (0...lowAccelerationToImpactMaxMs).contains(
                    nowMs - freeFallQualifiedAtMs
                )
            impactDetected = true
            impactTimeMs = nowMs
            preImpactGravity = gravity
        }

        // Impact spikes are transient linear acceleration, not posture. Do not
        // blend them into the low-pass gravity estimate.
        if normG <= impactThresholdG {
            updateGravity(with: sample)
        }

        guard impactDetected else { return false }
        guard nowMs - impactTimeMs <= candidateWindowMs else {
            clearCandidate()
            return false
        }

        if orientationChangeDeg() >= tiltThresholdDeg {
            orientationChangedLatch = true
        }

        let dynamicG = (sample - gravity).magnitude
        let afterSettleDelay = nowMs - impactTimeMs >= settleDelayMs
        let stillNow =
            afterSettleDelay &&
            dynamicG <= stillnessThresholdG &&
            abs(normG - 1) <= nearGravityToleranceG

        if stillNow {
            if !stillnessActive {
                stillnessActive = true
                stillnessStartMs = nowMs
            }
        } else {
            stillnessActive = false
            stillnessStartMs = 0
        }

        let stillnessQualified =
            stillnessActive && nowMs - stillnessStartMs >= stillnessMinMs
        return stillnessQualified &&
            (freeFallQualifiedLatch || orientationChangedLatch)
    }

    private func updateFreeFall(normG: Double, nowMs: Double) {
        if normG < freeFallThresholdG {
            if !freeFallActive {
                freeFallActive = true
                freeFallStartMs = nowMs
            }
            if nowMs - freeFallStartMs >= freeFallMinMs {
                freeFallQualifiedLatch = true
                freeFallQualifiedAtMs = nowMs
            }
        } else {
            freeFallActive = false
        }
    }

    private func updateGravity(with sample: Vector3) {
        guard gravityInitialized else { return }
        gravity = gravity * alpha + sample * (1 - alpha)
    }

    private func orientationChangeDeg() -> Double {
        let beforeNorm = preImpactGravity.magnitude
        let afterNorm = gravity.magnitude
        guard beforeNorm > 0.01, afterNorm > 0.01 else { return 0 }
        let cosine = min(
            1,
            max(-1, preImpactGravity.dot(gravity) / (beforeNorm * afterNorm))
        )
        return acos(cosine) * 180 / .pi
    }

    private func clearCandidate() {
        impactDetected = false
        impactTimeMs = 0
        preImpactGravity = .zero
        orientationChangedLatch = false
        stillnessActive = false
        stillnessStartMs = 0
        freeFallQualifiedLatch = false
        freeFallQualifiedAtMs = 0
    }
}

private struct Vector3 {
    let x: Double
    let y: Double
    let z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    static func +(left: Vector3, right: Vector3) -> Vector3 {
        Vector3(
            x: left.x + right.x,
            y: left.y + right.y,
            z: left.z + right.z
        )
    }

    static func -(left: Vector3, right: Vector3) -> Vector3 {
        Vector3(
            x: left.x - right.x,
            y: left.y - right.y,
            z: left.z - right.z
        )
    }

    static func *(vector: Vector3, scalar: Double) -> Vector3 {
        Vector3(
            x: vector.x * scalar,
            y: vector.y * scalar,
            z: vector.z * scalar
        )
    }
}
