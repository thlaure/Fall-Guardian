package com.fallguardian

import kotlin.math.acos
import kotlin.math.sqrt

/**
 * Multi-phase wrist fall detector tuned for loss-of-balance scenarios.
 *
 * A wrist impact is not enough: knocking a table can easily exceed 2.5 g.
 * Detection therefore waits for a stable post-impact posture and requires:
 *
 *   (qualified low-acceleration phase OR meaningful orientation change)
 *       AND impact
 *       AND two seconds of post-impact stillness.
 *
 * Orientation is measured relative to the wrist orientation immediately
 * before impact, not relative to an arbitrary device axis. This removes the
 * old false-positive path where a normally worn watch was already beyond the
 * absolute 45° "tilt" threshold before anything happened.
 */
class FallAlgorithm(
    var freeFallThresholdG: Float = 0.7f,
    var impactThresholdG: Float = 2.5f,
    var tiltThresholdDeg: Float = 50f,
    var freeFallMinMs: Long = 60L
) {
    private var freeFallStartMs: Long = 0L
    private var freeFallActive = false
    private var freeFallQualifiedLatch = false
    private var freeFallQualifiedAtMs: Long = 0L

    private var impactDetected = false
    private var impactTimeMs: Long = 0L
    private val preImpactGravity = FloatArray(3)
    private var orientationChangedLatch = false

    private var stillnessStartMs: Long = 0L
    private var stillnessActive = false

    private val gravity = FloatArray(3)
    private var gravityInitialized = false

    private val alpha = 0.8f
    private val candidateWindowMs = 5_000L
    private val lowAccelerationToImpactMaxMs = 1_500L
    private val settleDelayMs = 300L
    private val stillnessMinMs = 2_000L
    private val stillnessThresholdG = 0.25f
    private val nearGravityToleranceG = 0.25f

    fun reset() {
        freeFallStartMs = 0L
        freeFallActive = false
        freeFallQualifiedLatch = false
        freeFallQualifiedAtMs = 0L
        impactDetected = false
        impactTimeMs = 0L
        preImpactGravity.fill(0f)
        orientationChangedLatch = false
        stillnessStartMs = 0L
        stillnessActive = false
        gravity.fill(0f)
        gravityInitialized = false
    }

    /**
     * @param ax/ay/az raw accelerometer values in m/s².
     * @param nowMs monotonic elapsed time in milliseconds.
     */
    fun processSample(ax: Float, ay: Float, az: Float, nowMs: Long): Boolean {
        val normG = norm(ax, ay, az) / EARTH_GRAVITY

        if (!gravityInitialized && normG > 0.8f && normG < 1.2f) {
            gravity[0] = ax
            gravity[1] = ay
            gravity[2] = az
            gravityInitialized = true
        }

        // Low acceleration is a pre-impact fall phase. Accepting it after a
        // table knock would turn unrelated later wrist movement into a fall.
        if (!impactDetected) {
            updateFreeFall(normG, nowMs)
        }

        if (!impactDetected && normG > impactThresholdG) {
            freeFallQualifiedLatch =
                freeFallQualifiedLatch &&
                    nowMs - freeFallQualifiedAtMs in
                    0..lowAccelerationToImpactMaxMs
            impactDetected = true
            impactTimeMs = nowMs
            preImpactGravity[0] = gravity[0]
            preImpactGravity[1] = gravity[1]
            preImpactGravity[2] = gravity[2]
        }

        // Do not blend impact spikes into the gravity estimate. They are
        // transient linear acceleration, not a posture change.
        if (normG <= impactThresholdG) {
            updateGravity(ax, ay, az)
        }

        if (!impactDetected) return false
        if (nowMs - impactTimeMs > candidateWindowMs) {
            clearCandidate()
            return false
        }

        if (orientationChangeDeg() >= tiltThresholdDeg) {
            orientationChangedLatch = true
        }

        val dynamicG = norm(
            ax - gravity[0],
            ay - gravity[1],
            az - gravity[2]
        ) / EARTH_GRAVITY
        val afterSettleDelay = nowMs - impactTimeMs >= settleDelayMs
        val stillNow =
            afterSettleDelay &&
                dynamicG <= stillnessThresholdG &&
                kotlin.math.abs(normG - 1f) <= nearGravityToleranceG

        if (stillNow) {
            if (!stillnessActive) {
                stillnessActive = true
                stillnessStartMs = nowMs
            }
        } else {
            stillnessActive = false
            stillnessStartMs = 0L
        }

        val stillnessQualified =
            stillnessActive && nowMs - stillnessStartMs >= stillnessMinMs
        return stillnessQualified &&
            (freeFallQualifiedLatch || orientationChangedLatch)
    }

    private fun updateFreeFall(normG: Float, nowMs: Long) {
        if (normG < freeFallThresholdG) {
            if (!freeFallActive) {
                freeFallActive = true
                freeFallStartMs = nowMs
            }
            if (nowMs - freeFallStartMs >= freeFallMinMs) {
                freeFallQualifiedLatch = true
                freeFallQualifiedAtMs = nowMs
            }
        } else {
            freeFallActive = false
        }
    }

    private fun updateGravity(ax: Float, ay: Float, az: Float) {
        if (!gravityInitialized) return
        gravity[0] = alpha * gravity[0] + (1 - alpha) * ax
        gravity[1] = alpha * gravity[1] + (1 - alpha) * ay
        gravity[2] = alpha * gravity[2] + (1 - alpha) * az
    }

    private fun orientationChangeDeg(): Float {
        val beforeNorm = norm(
            preImpactGravity[0],
            preImpactGravity[1],
            preImpactGravity[2]
        )
        val afterNorm = norm(gravity[0], gravity[1], gravity[2])
        if (beforeNorm < 0.01f || afterNorm < 0.01f) return 0f
        val dot =
            preImpactGravity[0] * gravity[0] +
                preImpactGravity[1] * gravity[1] +
                preImpactGravity[2] * gravity[2]
        val cosine = (dot / (beforeNorm * afterNorm)).coerceIn(-1f, 1f)
        return Math.toDegrees(acos(cosine.toDouble())).toFloat()
    }

    private fun clearCandidate() {
        impactDetected = false
        impactTimeMs = 0L
        preImpactGravity.fill(0f)
        orientationChangedLatch = false
        stillnessActive = false
        stillnessStartMs = 0L
        freeFallQualifiedLatch = false
        freeFallQualifiedAtMs = 0L
    }

    private fun norm(x: Float, y: Float, z: Float): Float =
        sqrt((x * x + y * y + z * z).toDouble()).toFloat()

    private companion object {
        const val EARTH_GRAVITY = 9.81f
    }
}
