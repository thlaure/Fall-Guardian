package com.fallguardian

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Characterization of the current detector on recorded CSV traces.
 * Expectations describe today's behavior, including known misses.
 * They are not clinical sensitivity figures.
 */
class FallReplayTest {
    @Test
    fun `bundled corpus matches the current detector episode by episode`() {
        val labeled = loadBundled()
        val outcomes = labeled.map { FallReplay.replay(it.trace) }

        labeled.zip(outcomes).forEach { (row, outcome) ->
            assertEquals(row.trace.id, row.expectDetected, outcome.detected)
        }

        val qualified = outcomes.single { it.id == "qualified_low_phase_25hz" }
        assertEquals(2_320L, qualified.latencyFromImpactMs)
        assertEquals(1, qualified.episodes)

        val shortLowPhase = outcomes.single { it.id == "four_samples_low_phase_25hz" }
        assertNotNull(shortLowPhase.impactAtMs)
        assertFalse(shortLowPhase.detected)

        val threeG = outcomes.single { it.id == "three_g_impact_25hz" }
        assertNull(threeG.impactAtMs)
        assertFalse(threeG.detected)

        val metrics = FallReplay.evaluate(labeled.map { it.trace })
        assertEquals(4, metrics.falls)
        assertEquals(3, metrics.adls)
        assertEquals(1, metrics.truePositives)
        assertEquals(3, metrics.falseNegatives)
        assertEquals(2, metrics.trueNegatives)
        assertEquals(1, metrics.falsePositiveEpisodes)
        assertEquals(0.25, metrics.sensitivity!!, 1.0e-9)
        assertEquals(2.0 / 3.0, metrics.specificity!!, 1.0e-9)
        assertEquals(
            metrics.falsePositiveEpisodes * 86_400_000.0 / metrics.adlDurationMs,
            metrics.falseAlarmsPerDay!!,
            1.0e-6,
        )
    }

    @Test
    fun `halving a 50 hertz stream can miss either the low phase or the impact`() {
        val native = narrowImpactTrace()
        assertTrue(FallReplay.replay(native).detected)

        val even = native.copy(samples = FallReplay.decimate(native.samples, factor = 2, phase = 0))
        val odd = native.copy(samples = FallReplay.decimate(native.samples, factor = 2, phase = 1))
        val peaked = native.copy(samples = FallReplay.bucketPeak(native.samples, factor = 2))

        assertTrue(even.samples.any { it.az == 60f })
        assertFalse(FallReplay.replay(even).detected)
        assertFalse(odd.samples.any { it.az == 60f })
        assertFalse(FallReplay.replay(odd).detected)
        assertTrue(peaked.samples.any { it.az == 60f })
        assertFalse(FallReplay.replay(peaked).detected)
    }

    @Test
    fun `external replay directory prints metrics and does not gate this test`() {
        val directory = System.getProperty("fall.replay.dir") ?: return
        val metrics = FallReplay.evaluate(
            FallReplay.loadManifest(File(directory, "manifest.csv")).map { it.trace },
        )
        println(
            "external-replay sensitivity=${metrics.sensitivity} " +
                "specificity=${metrics.specificity} " +
                "falseAlarmsPerDay=${metrics.falseAlarmsPerDay} " +
                "falls=${metrics.falls} adls=${metrics.adls}",
        )
    }

    private fun loadBundled(): List<LabeledTrace> {
        val loader = requireNotNull(javaClass.classLoader) { "unit test class loader is missing" }
        val resource = requireNotNull(loader.getResource("fall-replay/manifest.csv")) {
            "bundled fall-replay manifest is missing"
        }
        return FallReplay.loadManifest(File(resource.toURI()))
    }

    private fun narrowImpactTrace(): ReplayTrace {
        val samples = ArrayList<ReplaySample>()
        fun hold(from: Long, to: Long, step: Long, ax: Float, ay: Float, az: Float) {
            var time = from
            while (time <= to) {
                samples += ReplaySample(time, ax, ay, az)
                time += step
            }
        }
        hold(0L, 480L, 20L, 0f, 0f, 9.81f)
        hold(500L, 660L, 20L, 0f, 0f, 0f)
        samples += ReplaySample(680L, 0f, 0f, 60f)
        samples += ReplaySample(700L, 0f, 0f, 15f)
        hold(720L, 4_720L, 20L, 9.81f, 0f, 0f)
        return ReplayTrace("narrow-impact-50hz", ReplayLabel.FALL, samples)
    }
}
