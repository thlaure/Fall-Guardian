package com.fallguardian

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.OutputStream
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Diagnostic I/O stays off the sensor thread. Bounded queue drops diagnostics,
 * never detection samples, if storage cannot keep up. Losses appear in the export.
 */
object FallDiagnostics {
    const val ENABLED_KEY = "diagnostics_enabled"
    var enabled by mutableStateOf(false)
        private set
    @Volatile private var store: FallDiagnosticStore? = null
    @Volatile private var lastSensorMs = -1L
    @Volatile private var lastDeliveryMs = -1L
    @Volatile private var lastError = "none"
    @Volatile private var sensorConfiguration = "not_registered_in_this_process"
    @Volatile private var thresholds = "not_loaded_in_this_process"
    private var interactiveAtMs = -1L
    private var cachedInteractive = false
    private val droppedSamples = AtomicLong()
    private val acceptedSamples = AtomicLong()
    private val batch = ArrayList<FallDiagnosticSample>(100)
    private val worker = ThreadPoolExecutor(
        1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(8)
    )

    @Synchronized
    fun initialize(context: Context) {
        if (store == null) store = FallDiagnosticStore(java.io.File(context.filesDir, "fall-diagnostics"))
        enabled = context.getSharedPreferences("fall_guardian", Context.MODE_PRIVATE)
            .getBoolean(ENABLED_KEY, false)
    }

    @Synchronized
    fun setEnabled(context: Context, value: Boolean) {
        initialize(context)
        if (!value) flush()
        enabled = value
        context.getSharedPreferences("fall_guardian", Context.MODE_PRIVATE)
            .edit().putBoolean(ENABLED_KEY, value).apply()
        event(if (value) "diagnostics_enabled" else "diagnostics_disabled", "build=${BuildConfig.VERSION_NAME};model=${Build.MODEL};sdk=${Build.VERSION.SDK_INT}")
    }

    @Synchronized
    fun sample(value: FallDiagnosticSample) {
        if (!enabled) return
        lastSensorMs = value.sensorMs
        lastDeliveryMs = value.deliveryMs
        acceptedSamples.incrementAndGet()
        batch.add(value)
        if (batch.size >= 100) flush()
    }

    @Synchronized
    fun flush() {
        if (batch.isEmpty()) return
        val values = batch.toList()
        batch.clear()
        enqueue(values.size) { store?.record(values, System.currentTimeMillis()) }
    }

    fun event(kind: String, details: String) {
        if (kind == "sensor_registration") sensorConfiguration = details
        if (!enabled && kind != "diagnostics_disabled") return
        val wall = System.currentTimeMillis()
        val elapsed = SystemClock.elapsedRealtime()
        enqueue(0) { store?.event(wall, elapsed, kind, details) }
    }

    fun configureThresholds(state: FallDiagnosticSnapshot) {
        thresholds = "low_g=${state.lowThresholdG};impact_g=${state.impactThresholdG};orientation_deg=${state.orientationThresholdDeg};low_ms=${state.lowMinimumMs}"
        event("thresholds_loaded", thresholds)
    }

    fun failure(error: Exception) {
        droppedSamples.incrementAndGet()
        lastError = error.javaClass.simpleName
    }

    fun status(): String = "schema_version=1\nbuild=${BuildConfig.VERSION_NAME}\nenabled=$enabled\naccepted_samples=${acceptedSamples.get()}\ndropped_samples=${droppedSamples.get()}\nlast_sensor_elapsed_ms=$lastSensorMs\nlast_delivery_elapsed_ms=$lastDeliveryMs\nsample_age_ms=${if (lastDeliveryMs < 0) -1 else SystemClock.elapsedRealtime() - lastDeliveryMs}\nio_error=$lastError\nsensor=$sensorConfiguration\nthresholds=$thresholds\nretention_hours=72\nmax_bytes=67108864\n"

    @Synchronized
    fun export(output: OutputStream) {
        flush()
        // Same worker serializes writes and export: ZIP never reads a half-written batch.
        enqueue(0, { output.close() }) {
            output.use { store?.export(it, System.currentTimeMillis(), status()) }
        }
    }

    private fun enqueue(count: Int, rejected: () -> Unit = {}, block: () -> Unit) {
        try {
            worker.execute {
                try { block() } catch (error: Exception) {
                    droppedSamples.addAndGet(count.toLong())
                    lastError = error.javaClass.simpleName
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            droppedSamples.addAndGet(count.toLong())
            lastError = "diagnostic_queue_full"
            rejected()
        }
    }

    @Synchronized
    fun interactive(context: Context): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (interactiveAtMs < 0 || now - interactiveAtMs >= 1_000) {
            cachedInteractive = context.getSystemService(PowerManager::class.java).isInteractive
            interactiveAtMs = now
        }
        return cachedInteractive
    }
}
