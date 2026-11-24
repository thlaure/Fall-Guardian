package com.fallguardian

import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Replays accelerometer traces through the production FallAlgorithm.
 *
 * Traces live in app/src/test/resources/traces/ in the diagnostics export
 * format (FallDiagnosticSample.HEADER, plain `.csv` or `.csv.gz`). Each must be
 * listed in traces/labels.csv with its expected outcome; see the README
 * section "Replay traces" for how to add real labelled recordings.
 */
class FallTraceReplayTest {
    @get:Rule val temporary = TemporaryFolder()

    private val tracesDir: File by lazy {
        val url = requireNotNull(javaClass.classLoader?.getResource("traces/labels.csv")) {
            "traces/labels.csv missing from test resources"
        }
        File(url.toURI()).parentFile
    }

    @Test fun `every labelled trace replays to its expected outcome`() {
        val labels = TraceLabels.read(File(tracesDir, "labels.csv"))
        assertTrue("expected at least one fall and one non-fall trace",
            labels.values.any { it } && labels.values.any { !it })

        val mismatches = labels.mapNotNull { (file, expectFall) ->
            val result = TraceReplay.replay(File(tracesDir, file))
            if (result.detected == expectFall) null
            else "$file: expected fall=$expectFall, detections=${result.detections}"
        }
        if (mismatches.isNotEmpty()) fail(mismatches.joinToString("\n"))
    }

    @Test fun `every trace file in the directory is labelled`() {
        val labels = TraceLabels.read(File(tracesDir, "labels.csv"))
        val unlabelled = tracesDir.listFiles().orEmpty()
            .map { it.name }
            .filter { TraceReplay.isTrace(it) && it !in labels }
        assertEquals("add these to traces/labels.csv", emptyList<String>(), unlabelled)
    }

    @Test fun `detected fall is reported at the end of post impact stillness`() {
        val result = TraceReplay.replay(File(tracesDir, "synthetic-fall-forward.csv"))
        assertEquals(1, result.detections.size)
        // Impact at ~3.3 s into the trace, 2 s stillness after settling.
        val offset = result.detections.single() - result.firstSensorMs
        assertTrue("detection offset $offset ms", offset in 5_000L..7_500L)
    }

    @Test fun `replays a gzip segment written by the diagnostics exporter`() {
        val source = TraceReplay.readSamples(File(tracesDir, "synthetic-fall-sideways.csv"))
        val directory = temporary.newFolder()
        val store = FallDiagnosticStore(directory)
        val snapshot = FallAlgorithm().diagnosticSnapshot(0)
        // Two batches -> two concatenated gzip members, as on the watch.
        source.chunked(source.size / 2 + 1).forEachIndexed { index, chunk ->
            store.record(chunk.map {
                FallDiagnosticSample(0, it.sensorMs, it.sensorMs, it.ax, it.ay, it.az,
                    false, false, false, snapshot)
            }, 1_000L + index)
        }
        val exported = store.files().single()
        assertTrue(exported.name.endsWith(".csv.gz"))

        assertEquals(source, TraceReplay.readSamples(exported))
        assertTrue(TraceReplay.replay(exported).detected)
    }

    @Test fun `trace without acceleration columns is rejected`() {
        val bad = temporary.newFile("bad.csv").apply {
            writeText("wall_ms,sensor_elapsed_ms\n1,2\n")
        }
        val error = runCatching { TraceReplay.readSamples(bad) }.exceptionOrNull()
        assertTrue(error is IllegalArgumentException)
        assertTrue(error!!.message!!.contains("ax_ms2"))
    }

    @Test fun `samples out of time order are rejected`() {
        val bad = temporary.newFile("unordered.csv").apply {
            writeText("sensor_elapsed_ms,ax_ms2,ay_ms2,az_ms2\n100,0,0,9.81\n60,0,0,9.81\n")
        }
        assertTrue(runCatching { TraceReplay.readSamples(bad) }.exceptionOrNull()
            is IllegalArgumentException)
    }

    @Test fun `cooldown suppresses a second detection within five seconds`() {
        // Same sample timeline replayed twice back-to-back keeps both
        // detections only when they are more than the cooldown apart.
        val samples = TraceReplay.readSamples(File(tracesDir, "synthetic-fall-forward.csv"))
        val span = samples.last().sensorMs - samples.first().sensorMs + 40
        val doubled = samples + samples.map { it.copy(sensorMs = it.sensorMs + span) }
        val result = TraceReplay.replay(doubled)
        assertEquals(2, result.detections.size)
        assertTrue(result.detections[1] - result.detections[0] > TraceReplay.COOLDOWN_MS)
        assertFalse(TraceReplay.replay(emptyList()).detected)
    }
}

data class TraceSample(val sensorMs: Long, val ax: Float, val ay: Float, val az: Float)

data class TraceResult(val firstSensorMs: Long, val detections: List<Long>) {
    val detected: Boolean get() = detections.isNotEmpty()
}

/** Reads diagnostics-format traces and replays them like FallDetectionService. */
object TraceReplay {
    const val COOLDOWN_MS = 5_000L
    private val REQUIRED = listOf("sensor_elapsed_ms", "ax_ms2", "ay_ms2", "az_ms2")

    fun isTrace(name: String) = name.endsWith(".csv") && name != "labels.csv" ||
        name.endsWith(".csv.gz")

    fun readSamples(file: File): List<TraceSample> = open(file).bufferedReader().use { reader ->
        val header = reader.readLine()?.split(',')?.map { it.trim() }
            ?: throw IllegalArgumentException("${file.name}: empty trace")
        val index = REQUIRED.associateWith { column ->
            header.indexOf(column).also {
                require(it >= 0) { "${file.name}: missing column $column" }
            }
        }
        val samples = reader.lineSequence().filter { it.isNotBlank() }.map { line ->
            val fields = line.split(',')
            TraceSample(
                fields[index.getValue("sensor_elapsed_ms")].trim().toLong(),
                fields[index.getValue("ax_ms2")].trim().toFloat(),
                fields[index.getValue("ay_ms2")].trim().toFloat(),
                fields[index.getValue("az_ms2")].trim().toFloat()
            )
        }.toList()
        samples.zipWithNext().forEach { (a, b) ->
            require(b.sensorMs >= a.sensorMs) { "${file.name}: samples out of order at ${b.sensorMs}" }
        }
        samples
    }

    fun replay(file: File): TraceResult = replay(readSamples(file))

    /** Mirrors FallDetectionService.onSensorChanged: default thresholds + cooldown + reset. */
    fun replay(samples: List<TraceSample>): TraceResult {
        val algorithm = FallAlgorithm()
        val detections = mutableListOf<Long>()
        var lastFallMs = 0L
        for (s in samples) {
            val detected = algorithm.processSample(s.ax, s.ay, s.az, s.sensorMs)
            if (detected && s.sensorMs - lastFallMs > COOLDOWN_MS) {
                lastFallMs = s.sensorMs
                algorithm.reset()
                detections += s.sensorMs
            }
        }
        return TraceResult(samples.firstOrNull()?.sensorMs ?: 0L, detections)
    }

    private fun open(file: File): InputStream =
        if (file.name.endsWith(".gz")) GZIPInputStream(file.inputStream()) else file.inputStream()
}

/** `file,expect_fall,description` — description may be quoted and contain commas. */
object TraceLabels {
    fun read(file: File): Map<String, Boolean> = file.readLines()
        .drop(1)
        .filter { it.isNotBlank() }
        .associate { line ->
            val parts = line.split(',', limit = 3)
            require(parts.size >= 2) { "labels.csv: malformed line '$line'" }
            val expect = when (parts[1].trim().lowercase()) {
                "true" -> true
                "false" -> false
                else -> throw IllegalArgumentException("labels.csv: expect_fall must be true/false in '$line'")
            }
            parts[0].trim() to expect
        }
}
