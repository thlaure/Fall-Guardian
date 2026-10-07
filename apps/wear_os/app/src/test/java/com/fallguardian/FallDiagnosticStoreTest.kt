package com.fallguardian

import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.GZIPInputStream
import java.util.zip.ZipInputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FallDiagnosticStoreTest {
    @get:Rule val temporary = TemporaryFolder()

    private fun sample(time: Long = 1_000) = FallDiagnosticSample(
        100_000 + time, time, time + 500, 0f, 0f, 9.81f, false, false, false,
        FallDiagnosticSnapshot(0.35f, 4.2f, 80f, 160, false, false, false, 0f, 0, 0, false)
    )

    @Test fun `all samples persist without an impact and gzip batches concatenate`() {
        val directory = temporary.newFolder()
        val store = FallDiagnosticStore(directory)
        store.record(listOf(sample()), 100_000)
        store.record(listOf(sample(1_040)), 100_040)
        val lines = GZIPInputStream(store.files().single().inputStream()).bufferedReader().readLines()
        assertEquals(3, lines.size)
        assertEquals(FallDiagnosticSample.HEADER, lines[0])
        assertTrue(lines[1].startsWith("101000,1000,1500,0.0,0.0,9.81,false,false,false"))
        assertTrue(lines[2].startsWith("101040,1040,1540"))
    }

    @Test fun `rotation and process restart preserve completed batches`() {
        val directory = temporary.newFolder()
        val first = FallDiagnosticStore(directory)
        first.record(listOf(sample()), 100_000)
        first.record(listOf(sample()), 400_000)
        FallDiagnosticStore(directory).record(listOf(sample()), 400_000)
        assertEquals(3, first.files().size)
        first.files().forEach {
            assertEquals(2, GZIPInputStream(it.inputStream()).bufferedReader().readLines().size)
        }
    }

    @Test fun `retention and byte limits remove oldest diagnostics`() {
        val directory = temporary.newFolder()
        val store = FallDiagnosticStore(directory, maxBytes = 10_000, retentionMs = 100)
        store.record(listOf(sample()), 100_000)
        store.prune(100_101)
        assertTrue(store.files().isEmpty())
        store.record(listOf(sample()), 100_200)
        FallDiagnosticStore(directory, maxBytes = 1).prune(100_200)
        assertTrue(store.files().isEmpty())
    }

    @Test fun `export includes samples and status but excludes unrelated files`() {
        val directory = temporary.newFolder()
        val store = FallDiagnosticStore(directory)
        store.record(listOf(sample()), 100_000)
        store.event(100_000, 1_000, "heartbeat", "screen=false,context=\"test\"")
        File(directory, "credentials.xml").writeText("must not export")
        val output = ByteArrayOutputStream()
        store.export(output, 100_000, "enabled=true")
        val names = mutableListOf<String>()
        ZipInputStream(output.toByteArray().inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                names.add(entry.name)
                val bytes = zip.readBytes()
                if (entry.name == "status.txt") assertEquals("enabled=true", bytes.toString(Charsets.UTF_8))
                assertFalse(bytes.toString(Charsets.UTF_8).contains("must not export"))
            }
        }
        assertEquals(3, names.size)
        assertFalse(names.contains("credentials.xml"))
        assertTrue(store.files().first { it.extension == "csv" }.readText().contains("\"\"test\"\""))
    }

    @Test fun `diagnostic observation does not change algorithm decisions`() {
        val observed = FallAlgorithm()
        val original = FallAlgorithm()
        for (time in 0L..5_000L step 40) {
            val z = when {
                time < 500 -> 9.81f
                time < 700 -> 0f
                time == 720L -> 45f
                else -> 0f
            }
            val x = if (time > 720) 9.81f else 0f
            assertEquals(original.processSample(x, 0f, z, time), observed.processSample(x, 0f, z, time))
            val snapshot = observed.diagnosticSnapshot(time)
            assertEquals(4.2f, snapshot.impactThresholdG, 0.001f)
        }
    }

    @Test fun `snapshot explains unqualified impact and candidate expiration`() {
        val algorithm = FallAlgorithm()
        algorithm.processSample(0f, 0f, 9.81f, 0)
        algorithm.processSample(0f, 0f, 45f, 500)
        val impact = algorithm.diagnosticSnapshot(500)
        assertTrue(impact.impactSeen)
        assertFalse(impact.lowQualified)
        algorithm.processSample(0f, 0f, 9.81f, 5_501)
        assertTrue(algorithm.diagnosticSnapshot(5_501).candidateExpired)
        assertFalse(algorithm.diagnosticSnapshot(5_501).impactSeen)
    }
}
