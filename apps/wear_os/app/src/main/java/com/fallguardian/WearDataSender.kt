package com.fallguardian

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable

/**
 * Central hub for all watch ↔ phone communication and UI state during an alert.
 *
 * --- What is the Wearable MessageClient API? ---
 * Google provides a "Wearable Data Layer" API as part of Google Play Services.
 * It gives paired Wear OS / Android devices a reliable channel to exchange small
 * messages over Bluetooth (or Wi-Fi when Bluetooth is out of range). The
 * MessageClient works node-to-node: you look up the connected phone's node ID,
 * then fire a message at a named "path" (like "/fall_event") that the receiving
 * side listens for. This is why it works across different package names — the
 * routing is by node ID + path, not by app identity.
 *
 * --- Why a Kotlin `object`? ---
 * `object` declares a singleton — there is exactly one instance of WearDataSender
 * for the whole process. That single instance holds the shared UI state
 * (alertActive, remainingSeconds) that both FallDetectionService (background) and
 * MainActivity (UI) read. Using a singleton avoids passing references around and
 * guarantees that state changes from any caller are immediately visible everywhere.
 *
 * --- How this file connects to the others ---
 * - FallDetectionService calls sendFallEvent() when the algorithm fires.
 * - PhoneMessageListenerService calls cancelAlertFromPhone() when the phone
 *   user taps "cancel".
 * - MainActivity's AlertScreen reads alertActive and remainingSeconds to render
 *   the countdown, and calls sendCancelAlert() when the watch user completes the hold.
 *
 * All alert decisions (start, cancel, expiry, restart recovery, Data Layer
 * ordering) live in the pure, unit-tested AlertSession; this object only
 * supplies clocks, runs it on the main thread and executes its effects.
 *
 * Sends fall/cancel messages to the paired phone via the Wearable MessageClient API.
 * MessageClient is node-based and works across different package names.
 */
object WearDataSender {

    /**
     * Owned by FallDetectionService. Keeps alarm presentation (notification,
     * sound, haptics) synchronized with the single alert state machine.
     */
    var onAlertPresentation: ((AlertPresentation) -> Unit)? = null

    // --- Compose-observable UI state ---
    // `mutableStateOf` creates a Compose state holder. Any @Composable function
    // that reads these variables will automatically recompose (re-render) when
    // their value changes — similar to React's useState hook.
    // `private set` means only code inside this object can change the value.
    var alertActive by mutableStateOf(false)
        private set

    // Counts down from 30 to 0 during an active alert. Drives the large number
    // shown on AlertScreen. Updated by tickRunnable.
    var remainingSeconds by mutableStateOf(30)
        private set

    var alertPresentationIssue by mutableStateOf<AlertPresentationIssue?>(null)
        private set

    // Created lazily with the first Context (needs SharedPreferences).
    private var session: AlertSession? = null
    private var appContext: Context? = null

    // --- Countdown timer ---
    // Handler + Looper.getMainLooper() runs on the main (UI) thread. Compose
    // state and AlertSession must only be touched from this thread.
    private val handler = Handler(Looper.getMainLooper())

    // Re-computes the remaining time from the monotonic anchor of the fall
    // (see ActiveAlert): no drift, and a wall-clock change cannot end it.
    private val tickRunnable = object : Runnable {
        override fun run() {
            val context = appContext ?: return
            val current = session ?: return
            val now = clock(context)
            val effects = current.onTick(now)
            remainingSeconds = current.remainingSeconds(now)
            if (effects.isEmpty() && current.active != null) {
                handler.postDelayed(this, 500L)
            } else {
                // Countdown expired without cancellation — time is up.
                // Backend escalation continues independently on the phone.
                execute(context, effects)
            }
        }
    }

    /**
     * Restores a persisted alert after process death (called by
     * FallDetectionService and MainActivity on start) and re-sends its fall
     * with the same incident id. If already active in memory, only
     * re-announces it so a newly attached presenter shows notification/sound.
     */
    fun restore(context: Context) = run(context, "restore") { session, now -> session.restore(now) }

    /**
     * Called by FallDetectionService when a fall is confirmed.
     *
     * @param timestamp  Wall-clock time in ms (System.currentTimeMillis()) when
     *                   the fall was detected; sent to the phone unchanged.
     */
    fun sendFallEvent(context: Context, timestamp: Long) =
        run(context, "fall") { session, now -> session.onFallDetected(timestamp, now) }

    /** Called when the watch user completes the 1.5-second hold on AlertScreen. */
    fun sendCancelAlert(context: Context) =
        run(context, "watch cancel") { session, now -> session.onWatchCancel(now) }

    /**
     * Called by PhoneMessageListenerService (or MainActivity's listener) when
     * the phone sends "/cancel_alert". Never echoes back to the phone.
     */
    fun cancelAlertFromPhone(context: Context, payload: ByteArray?) {
        val cancel = AlertContract.parsePhoneCancel(payload)
        run(context, "phone cancel identified=${cancel.incidentId != null}") { session, _ ->
            session.onPhoneCancel(cancel)
        }
    }

    fun updateAlertPresentationIssue(issue: AlertPresentationIssue?) {
        handler.post { alertPresentationIssue = issue }
    }

    // handler.post() ensures every transition runs on the main thread, even
    // when called from a Wearable listener or sensor callback.
    private fun run(
        context: Context,
        label: String,
        transition: (AlertSession, ClockReading) -> List<AlertEffect>
    ) {
        val applicationContext = context.applicationContext
        handler.post {
            appContext = applicationContext
            val current = session(applicationContext)
            val effects = transition(current, clock(applicationContext))
            Log.d("WearDataSender", "$label: effects=${effects.size} active=${current.active != null}")
            execute(applicationContext, effects)
        }
    }

    private fun execute(context: Context, effects: List<AlertEffect>) {
        for (effect in effects) {
            when (effect) {
                is AlertEffect.SendMessage -> sendToPhone(context, effect.path, effect.payload, effect.path)
                is AlertEffect.PutDataItem -> queueForPhone(context, effect.path, effect.fields, effect.path)
                is AlertEffect.DeleteDataItem -> deleteQueued(context, effect.path)
                is AlertEffect.Present -> present(context, effect.presentation)
            }
        }
    }

    private fun present(context: Context, presentation: AlertPresentation) {
        val current = session(context)
        handler.removeCallbacks(tickRunnable)
        if (presentation == AlertPresentation.SHOW) {
            alertActive = true        // Tell Compose to switch to AlertScreen.
            remainingSeconds = current.remainingSeconds(clock(context))
            onAlertPresentation?.invoke(presentation)
            handler.post(tickRunnable)
        } else {
            alertActive = false       // Return to IdleScreen.
            remainingSeconds = 30     // Reset for the next alert.
            onAlertPresentation?.invoke(presentation)
        }
    }

    private fun session(context: Context): AlertSession =
        session ?: AlertSession(
            ActiveAlertStore(
                SharedPreferencesAlertStorage(
                    context.getSharedPreferences("fall_guardian_alert", Context.MODE_PRIVATE)
                )
            )
        ).also { session = it }

    private fun clock(context: Context) = ClockReading(
        wallMs = System.currentTimeMillis(),
        elapsedMs = SystemClock.elapsedRealtime(),
        bootCount = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
            .takeIf { it >= 0 }
    )

    /**
     * Low-level helper that sends a Wearable message to all connected phone nodes.
     *
     * --- NodeClient and MessageClient ---
     * The Wearable Data Layer has two relevant clients:
     *   • NodeClient  — lists the Bluetooth-paired devices ("nodes"). A node is
     *                   any device running Google Play Services with a paired Wear
     *                   OS watch. In practice there is usually exactly one node
     *                   (the user's phone).
     *   • MessageClient — sends a fire-and-forget message to a specific node ID
     *                     at a named path. Messages are delivered reliably over
     *                     the Bluetooth link (or Wi-Fi Direct if BT is unavailable).
     *
     * --- Asynchronous callbacks ---
     * Both getNodeClient and sendMessage are asynchronous operations — they return
     * a Task<T> (Google's async primitive). addOnSuccessListener and
     * addOnFailureListener register callbacks that run when the operation completes.
     * This avoids blocking the calling thread (which could be the UI thread).
     *
     * @param context  Android context for Play Services.
     * @param path     Message path (e.g. "/fall_event", "/cancel_alert").
     * @param payload  Raw bytes to send (see AlertContract; well under 1 KB).
     * @param label    Human-readable name used in log messages for debugging.
     */
    private fun sendToPhone(context: Context, path: String, payload: ByteArray, label: String) {
        // Step A: discover which phone nodes are currently reachable.
        Wearable.getNodeClient(context).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    // Phone is out of range or Bluetooth is off. The message is
                    // lost — there is no queuing in MessageClient (use DataClient
                    // for guaranteed delivery). Log a warning for debugging.
                    Log.w("WearDataSender", "No connected nodes found")
                    return@addOnSuccessListener
                }
                // Step B: send the message to every connected node. Normally there
                // is only one (the paired phone), but the API supports multi-node
                // setups, so we iterate to be correct.
                nodes.forEach { node ->
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, path, payload)
                        .addOnSuccessListener { Log.d("WearDataSender", "Sent $label to ${node.displayName}") }
                        .addOnFailureListener { e -> Log.e("WearDataSender", "Failed to send $label", e) }
                }
            }
            .addOnFailureListener { e -> Log.e("WearDataSender", "Failed to get connected nodes", e) }
    }

    private fun queueForPhone(
        context: Context,
        path: String,
        fields: Map<String, Any>,
        label: String
    ) {
        // DataClient keeps one item per path: a newer incident overwrites the
        // older one instead of accumulating. `updatedAt` makes every write a
        // distinct change so the phone is notified even for the same path.
        val request = PutDataMapRequest.create(path).apply {
            fields.forEach { (key, value) ->
                when (value) {
                    is Long -> dataMap.putLong(key, value)
                    is String -> dataMap.putString(key, value)
                    else -> error("Unsupported Data Layer field type for $key")
                }
            }
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context)
            .putDataItem(request)
            .addOnSuccessListener { Log.d("WearDataSender", "Queued $label for phone") }
            .addOnFailureListener { e -> Log.e("WearDataSender", "Failed to queue $label", e) }
    }

    /** Deletes this watch's queued item at [path] (no host = every node's copy we own). */
    private fun deleteQueued(context: Context, path: String) {
        val uri = Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(path).build()
        Wearable.getDataClient(context)
            .deleteDataItems(uri, DataClient.FILTER_LITERAL)
            .addOnFailureListener { e -> Log.w("WearDataSender", "Failed to delete $path item", e) }
    }
}

/** SharedPreferences adapter for ActiveAlertStore. commit() because this is safety state. */
private class SharedPreferencesAlertStorage(
    private val prefs: android.content.SharedPreferences
) : AlertStateStorage {
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun getLong(key: String): Long? = if (prefs.contains(key)) prefs.getLong(key, 0L) else null
    override fun write(values: Map<String, Any>?) {
        val editor = prefs.edit().clear()
        values?.forEach { (key, value) ->
            when (value) {
                is Long -> editor.putLong(key, value)
                is String -> editor.putString(key, value)
            }
        }
        editor.commit()
    }
}
