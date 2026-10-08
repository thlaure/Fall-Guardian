package com.fallguardian

import java.io.File
import java.io.OutputStream
import java.util.zip.GZIPOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

data class FallDiagnosticSnapshot(
    val lowThresholdG: Float,
    val impactThresholdG: Float,
    val orientationThresholdDeg: Float,
    val lowMinimumMs: Long,
    val impactSeen: Boolean,
    val lowQualified: Boolean,
    val orientationQualified: Boolean,
    val orientationDeg: Float,
    val stillnessMs: Long,
    val candidateAgeMs: Long,
    val candidateExpired: Boolean
)

/** Times include original sensor time AND delivery time, so batching/sleep is visible. */
data class FallDiagnosticSample(
    val wallMs: Long,
    val sensorMs: Long,
    val deliveryMs: Long,
    val ax: Float,
    val ay: Float,
    val az: Float,
    val interactive: Boolean,
    val detected: Boolean,
    val alertDispatched: Boolean,
    val state: FallDiagnosticSnapshot
) {
    fun csv(): String = listOf(
        wallMs, sensorMs, deliveryMs, ax, ay, az, interactive, detected,
        alertDispatched, state.lowThresholdG, state.impactThresholdG,
        state.orientationThresholdDeg, state.lowMinimumMs, state.impactSeen,
        state.lowQualified, state.orientationQualified, state.orientationDeg,
        state.stillnessMs, state.candidateAgeMs, state.candidateExpired
    ).joinToString(",")

    companion object {
        const val HEADER = "wall_ms,sensor_elapsed_ms,delivery_elapsed_ms,ax_ms2,ay_ms2,az_ms2,interactive,detected,alert_dispatched,low_threshold_g,impact_threshold_g,orientation_threshold_deg,low_minimum_ms,impact_seen,low_qualified,orientation_qualified,orientation_deg,stillness_ms,candidate_age_ms,candidate_expired"
    }
}

/** Single-worker storage: all delivered samples, including events rejected by the detector.
 * Gzip members are closed every batch; completed batches survive process death.
 * No credentials, location or phone data belong in this directory.
 */
class FallDiagnosticStore(
    private val directory: File,
    private val maxBytes: Long = 64L * 1024 * 1024,
    private val retentionMs: Long = 72L * 60 * 60 * 1000,
    private val sessionId: String = java.util.UUID.randomUUID().toString()
) {
    private var segmentStartedMs: Long? = null
    private var segment: File? = null

    init { require(maxBytes > 0 && retentionMs > 0) }

    fun record(samples: List<FallDiagnosticSample>, nowMs: Long) {
        if (samples.isEmpty()) return
        directory.mkdirs()
        val started = segmentStartedMs
        if (started == null || nowMs < started || nowMs - started >= 300_000) {
            segmentStartedMs = nowMs
            segment = File(directory, "samples-$nowMs-$sessionId.csv.gz")
        }
        val target = requireNotNull(segment)
        val newFile = !target.exists()
        GZIPOutputStream(target.outputStreamAppend()).bufferedWriter(Charsets.UTF_8).use { writer ->
            if (newFile) { writer.write(FallDiagnosticSample.HEADER); writer.newLine() }
            for (sample in samples) { writer.write(sample.csv()); writer.newLine() }
        }
        target.setLastModified(nowMs)
        prune(nowMs)
    }

    fun event(wallMs: Long, elapsedMs: Long, kind: String, details: String) {
        directory.mkdirs()
        val target = File(directory, "events-${wallMs / 300_000}-$sessionId.csv")
        val newFile = !target.exists()
        target.appendText(
            (if (newFile) "wall_ms,elapsed_ms,event,details\n" else "") +
                "$wallMs,$elapsedMs,${csvField(kind)},${csvField(details)}\n"
        )
        target.setLastModified(wallMs)
        prune(wallMs)
    }

    fun export(output: OutputStream, nowMs: Long, status: String) {
        prune(nowMs)
        ZipOutputStream(output).use { zip ->
            zip.putNextEntry(ZipEntry("status.txt"))
            zip.write(status.toByteArray(Charsets.UTF_8))
            zip.closeEntry()
            for (file in files()) {
                zip.putNextEntry(ZipEntry(file.name))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    fun files(): List<File> = directory.listFiles()?.filter {
        it.isFile && !java.nio.file.Files.isSymbolicLink(it.toPath()) &&
            (it.name.startsWith("samples-") && it.name.endsWith(".csv.gz") ||
                it.name.startsWith("events-") && it.name.endsWith(".csv"))
    }?.sortedBy { it.lastModified() } ?: emptyList()

    fun prune(nowMs: Long) {
        val remaining = files().filter { file ->
            if (nowMs - file.lastModified() > retentionMs) { file.delete(); false } else true
        }
        var bytes = remaining.sumOf { it.length() }
        for (file in remaining) {
            if (bytes <= maxBytes) break
            val size = file.length()
            if (file.delete()) bytes -= size
        }
    }

    private fun File.outputStreamAppend() = java.io.FileOutputStream(this, true)
    private fun csvField(value: String) = "\"${value.replace("\"", "\"\"")}\""
}
