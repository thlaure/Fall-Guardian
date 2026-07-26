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

        assertFalse(algorithm.processSample(0f, 0f, 30f, 500L))
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
        algorithm.processSample(0f, 0f, 30f, 500L)

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
        assertFalse(algorithm.processSample(0f, 0f, 30f, 500L))

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 4_000L
        )

        assertTrue(triggered)
    }

    @Test
    fun `qualified low acceleration impact and stillness triggers without rotation`() {
        baseline(algorithm)
        samples(
            algorithm,
            0f,
            0f,
            0f,
            startMs = 500L,
            durationMs = 100L,
            stepMs = 20L
        )
        assertFalse(algorithm.processSample(0f, 0f, 30f, 620L))

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 640L,
            durationMs = 3_500L
        )

        assertTrue(triggered)
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
        algorithm.processSample(0f, 0f, 30f, 560L)

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 580L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `stale low acceleration does not combine with a later impact`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 100L, 20L)
        samples(algorithm, 0f, 0f, 9.81f, 620L, 2_000L)
        algorithm.processSample(0f, 0f, 30f, 2_640L)

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 2_660L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `low acceleration after impact does not qualify the candidate`() {
        baseline(algorithm)
        algorithm.processSample(0f, 0f, 30f, 500L)
        samples(algorithm, 0f, 0f, 0f, 520L, 100L, 20L)

        val triggered = samples(
            algorithm,
            0f,
            0f,
            9.81f,
            startMs = 640L,
            durationMs = 3_500L
        )

        assertFalse(triggered)
    }

    @Test
    fun `orientation threshold changes detection behavior`() {
        val strict = FallAlgorithm(tiltThresholdDeg = 100f)
        baseline(strict)
        strict.processSample(0f, 0f, 30f, 500L)

        val triggered = samples(
            strict,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 4_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `candidate expires before late stillness`() {
        baseline(algorithm)
        algorithm.processSample(0f, 0f, 30f, 500L)
        samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 520L,
            durationMs = 1_000L
        )

        val triggered = samples(
            algorithm,
            9.81f,
            0f,
            0f,
            startMs = 5_600L,
            durationMs = 3_000L
        )

        assertFalse(triggered)
    }

    @Test
    fun `reset clears a qualified fall candidate`() {
        baseline(algorithm)
        samples(algorithm, 0f, 0f, 0f, 500L, 100L, 20L)
        algorithm.processSample(0f, 0f, 30f, 620L)

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
