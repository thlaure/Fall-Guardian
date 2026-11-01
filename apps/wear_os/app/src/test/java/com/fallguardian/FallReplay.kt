package com.fallguardian

import java.io.File
import kotlin.math.sqrt

/**
 * Replays timestamped accelerometer traces through [FallAlgorithm].
 *
 * This harness does not change detection. It counts the same dispatch
 * episodes as [FallDetectionService]: a positive sample is one episode,
 * then the algorithm is reset and further positives are suppressed for
 * the service cooldown.
 *
 * Input CSV columns are `t_ms,ax_mps2,ay_mps2,az_mps2` in milliseconds and
 * m/s², which is the unit [FallAlgorithm.processSample] already consumes.
 * A manifest CSV (`id,label,file,expect_detected`) groups traces into
 * `fall` and `adl` so sensitivity, specificity and false alarms per day
 * are computed from files rather than from hand-built vectors.
 */
internal object FallReplay {
    const val DISPATCH_COOLDOWN_MS = 5_000L
    private const val EARTH_GRAVITY = 9.81f

    fun loadManifest(manifest: File): List<LabeledTrace> {
        val directory = manifest.parentFile ?: error("manifest has no directory: $manifest")
        return parseManifest(manifest.readText(), directory)
    }

    fun parseManifest(text: String, directory: File): List<LabeledTrace> {
        val rows = csvRows(text)
        require(rows.isNotEmpty()) { "manifest is empty" }
        require(rows.first() == listOf("id", "label", "file", "expect_detected")) {
            "unexpected manifest header: ${rows.first()}"
        }
        return rows.drop(1).map { columns ->
            require(columns.size == 4) { "manifest row must have 4 columns: $columns" }
            val label = when (columns[1]) {
                "fall" -> ReplayLabel.FALL
                "adl" -> ReplayLabel.ADL
                else -> error("label must be fall or adl: ${columns[1]}")
            }
            val expectDetected = when (columns[3]) {
                "true" -> true
                "false" -> false
                else -> error("expect_detected must be true or false: ${columns[3]}")
            }
            LabeledTrace(
                trace = parseTrace(columns[0], label, File(directory, columns[2]).readText()),
                expectDetected = expectDetected,
            )
        }
    }

    fun parseTrace(id: String, label: ReplayLabel, csv: String): ReplayTrace {
        val rows = csvRows(csv)
        require(rows.isNotEmpty()) { "$id is empty" }
        require(rows.first() == listOf("t_ms", "ax_mps2", "ay_mps2", "az_mps2")) {
            "$id has unexpected header: ${rows.first()}"
        }
        var previous = Long.MIN_VALUE
        val samples = rows.drop(1).map { columns ->
            require(columns.size == 4) { "$id row must have 4 columns: $columns" }
            val time = columns[0].toLong()
            require(time > previous) { "$id timestamps must be strictly increasing: $time" }
            previous = time
            ReplaySample(time, columns[1].toFloat(), columns[2].toFloat(), columns[3].toFloat())
        }
        require(samples.isNotEmpty()) { "$id has no samples" }
        return ReplayTrace(id, label, samples)
    }

    fun replay(
        trace: ReplayTrace,
        algorithm: FallAlgorithm = FallAlgorithm(),
        cooldownMs: Long = DISPATCH_COOLDOWN_MS,
    ): ReplayOutcome {
        algorithm.reset()
        var episodes = 0
        var detectedAt: Long? = null
        var impactAt: Long? = null
        var lastDispatchAt = Long.MIN_VALUE / 4
        for (sample in trace.samples) {
            val normG = sample.norm() / EARTH_GRAVITY
            if (impactAt == null && normG > algorithm.impactThresholdG) {
                impactAt = sample.tMs
            }
            val detected = algorithm.processSample(sample.ax, sample.ay, sample.az, sample.tMs)
            if (detected && sample.tMs - lastDispatchAt > cooldownMs) {
                episodes += 1
                lastDispatchAt = sample.tMs
                if (detectedAt == null) detectedAt = sample.tMs
                algorithm.reset()
            }
        }
        return ReplayOutcome(trace.id, trace.label, episodes, detectedAt, impactAt)
    }

    fun evaluate(traces: List<ReplayTrace>, algorithm: FallAlgorithm = FallAlgorithm()): ReplayMetrics {
        val outcomes = traces.map { replay(it, algorithm) }
        val falls = outcomes.filter { it.label == ReplayLabel.FALL }
        val adls = outcomes.filter { it.label == ReplayLabel.ADL }
        val truePositives = falls.count { it.episodes > 0 }
        val falsePositives = adls.sumOf { it.episodes }
        val adlDurationMs = traces
            .filter { it.label == ReplayLabel.ADL }
            .sumOf { it.durationMs }
        return ReplayMetrics(
            falls = falls.size,
            adls = adls.size,
            truePositives = truePositives,
            falseNegatives = falls.size - truePositives,
            trueNegatives = adls.count { it.episodes == 0 },
            falsePositiveEpisodes = falsePositives,
            adlDurationMs = adlDurationMs,
        )
    }

    /**
     * Keeps one sample out of [factor], starting at [phase].
     * Timestamps of the kept samples are unchanged, so the algorithm sees
     * the coarser spacing a slower sensor stream would have delivered.
     */
    fun decimate(samples: List<ReplaySample>, factor: Int, phase: Int): List<ReplaySample> {
        require(factor > 1) { "factor must be greater than 1" }
        require(phase in 0 until factor) { "phase must be in 0 until factor" }
        return samples.filterIndexed { index, _ -> index % factor == phase }
    }

    /** Keeps the largest acceleration vector in each block of [factor] samples. */
    fun bucketPeak(samples: List<ReplaySample>, factor: Int): List<ReplaySample> {
        require(factor > 1) { "factor must be greater than 1" }
        return samples.chunked(factor).map { chunk -> chunk.maxBy { it.norm() } }
    }

    private fun csvRows(text: String): List<List<String>> =
        text.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { line -> line.split(",").map { it.trim() } }
            .toList()
}

internal enum class ReplayLabel { FALL, ADL }

internal data class ReplaySample(
    val tMs: Long,
    val ax: Float,
    val ay: Float,
    val az: Float,
) {
    fun norm(): Float = sqrt(ax * ax + ay * ay + az * az)
}

internal data class ReplayTrace(
    val id: String,
    val label: ReplayLabel,
    val samples: List<ReplaySample>,
) {
    val durationMs: Long get() = samples.last().tMs - samples.first().tMs
}

internal data class LabeledTrace(
    val trace: ReplayTrace,
    val expectDetected: Boolean,
)

internal data class ReplayOutcome(
    val id: String,
    val label: ReplayLabel,
    val episodes: Int,
    val detectedAtMs: Long?,
    val impactAtMs: Long?,
) {
    val detected: Boolean get() = episodes > 0
    val latencyFromImpactMs: Long?
        get() = if (detectedAtMs != null && impactAtMs != null) detectedAtMs - impactAtMs else null
}

internal data class ReplayMetrics(
    val falls: Int,
    val adls: Int,
    val truePositives: Int,
    val falseNegatives: Int,
    val trueNegatives: Int,
    val falsePositiveEpisodes: Int,
    val adlDurationMs: Long,
) {
    val sensitivity: Double? get() = ratio(truePositives, falls)
    val specificity: Double? get() = ratio(trueNegatives, adls)
    val falseAlarmsPerDay: Double?
        get() = if (adlDurationMs <= 0L) null else falsePositiveEpisodes * 86_400_000.0 / adlDurationMs

    private fun ratio(numerator: Int, denominator: Int): Double? =
        if (denominator == 0) null else numerator.toDouble() / denominator
}
