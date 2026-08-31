package com.fallguardian

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class FallAlgorithmTest {
    private lateinit var algorithm: FallAlgorithm

    @Before
    fun setUp() {
        algorithm = FallAlgorithm()
    }

    @Test
    fun `table impact without orientation change does not trigger`() {
        baseline(algorithm)

        assertFalse(algorithm.processSample(0f, 0f, 45f, 500L))
        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 510L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `orientation change without post-impact stillness does not trigger`() {
        baseline(algorithm)
        algorithm.processSample(0f, 0f, 46f, 500L)

        var triggered = false
        var time = 510L
        while (time < 4_800L) {
            val x = if ((time / 100) % 2L == 0L) 9.81f else -9.81f
            triggered = algorithm.processSample(x, 0f, 0f, time) || triggered
            time += 20L
        }

        assertFalse(triggered)
    }

    @Test
    fun `loss of balance impact orientation change and stillness triggers`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 160L, 20L)
        assertFalse(algorithm.processSample(0f, 0f, 45f, 680L))

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 700L,
            durationMs = 4_000L
        )

        assertTrue(triggered)
    }

    @Test
    fun `quick couch sit with impact rotation and rest does not trigger`() {
        baseline(algorithm)
        assertFalse(algorithm.processSample(0f, 0f, 45f, 500L))

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 4_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `hand dropped onto knee without orientation change does not trigger`() {
        baseline(algorithm)
        samples(
            algorithm,
            0f,
            0f,
            0f,
            startMs = 500L,
            durationMs = 160L,
            stepMs = 20L
        )
        assertFalse(algorithm.processSample(0f, 0f, 45f, 680L))

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 700L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `rapid arm raise with large acceleration and rotation does not trigger`() {
        baseline(algorithm)
        assertFalse(algorithm.processSample(0f, 0f, 50f, 500L))

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 4_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `short low acceleration does not bypass orientation requirement`() {
        baseline(algorithm)
        samples(
            algorithm,
            0f,
            0f,
            0f,
            startMs = 500L,
            durationMs = 40L,
            stepMs = 20L
        )
        algorithm.processSample(0f, 0f, 45f, 560L)

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 580L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `three g wrist impact followed by rest does not trigger conservative defaults`() {
        baseline(algorithm)

        assertFalse(algorithm.processSample(0f, 0f, 29.43f, 500L))
        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `eighty millisecond low acceleration does not qualify conservative defaults`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 80L, 20L)
        algorithm.processSample(0f, 0f, 45f, 600L)

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 620L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `stale low acceleration does not combine with a later impact`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 160L, 20L)
        samples(algorithm, 0f, 0f, 9.81f, 680L, 2_000L)
        algorithm.processSample(0f, 0f, 45f, 2_700L)

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 2_720L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `low acceleration after impact does not qualify the candidate`() {
        baseline(algorithm)
        algorithm.processSample(0f, 0f, 45f, 500L)
        samples(algorithm, 0f, 0f, 0f, 520L, 160L, 20L)

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 700L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `orientation threshold changes detection behavior`() {
        val strict = FallAlgorithm(tiltThresholdDeg = 100f)
        baseline(strict)
        samples(strict, 0f, 0f, 0f, 500L, 160L, 20L)
        strict.processSample(0f, 0f, 45f, 680L)

        val triggered = samples(
            strict,
            9.81f,
            0f,
            0f,
            startMs = 700L,
            durationMs = 4_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `candidate expires before late stillness`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 160L, 20L)
        algorithm.processSample(0f, 0f, 45f, 680L)
        samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 700L,
            durationMs = 1_000L
        )

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 5_800L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `reset clears a qualified fall candidate`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 160L, 20L)
        algorithm.processSample(0f, 0f, 45f, 680L)

        algorithm.reset()
        baseline(algorithm, startMs = 1_000L)
        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 1_500L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    private fun baseline(
        target: FallAlgorithm,
        startMs: Long = 0L
    ) {
        samples(target, 0f, 0f, 9.81f, startMs, 500L)
    }

    private fun samples(
        target: FallAlgorithm,
        ax: Float,
        ay: Float,
        az: Float,
        startMs: Long,
        durationMs: Long,
        stepMs: Long = 20L
    ): Boolean {
        var triggered = false
        var time = startMs
        while (time <= startMs + durationMs) {
            triggered = target.processSample(ax, ay, az, time) || triggered
            time += stepMs
        }
        return triggered
    }
}
