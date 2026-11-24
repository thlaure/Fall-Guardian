package com.fallguardian

import android.content.Context
import android.os.Handler
import android.os.Looper
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
 * Sends fall/cancel messages to the paired phone via the Wearable MessageClient API.
 * MessageClient is node-based and works across different package names.
 */
object WearDataSender {

    /**
     * Owned by FallDetectionService. The callback keeps alarm presentation
     * synchronized with the single alert state machine: true starts the urgent
     * notification and sound, false stops both on every cancellation path.
     */
    var onAlertStateChanged: ((Boolean) -> Unit)? = null

    // --- Compose-observable UI state ---
    // `mutableStateOf` creates a Compose state holder. Any @Composable function
    // that reads these variables will automatically recompose (re-render) when
    // their value changes — similar to React's useState hook.
    // `by` is Kotlin's property delegation syntax; it unwraps the state object
    // so we can read/write alertActive directly instead of alertActive.value.
    // `private set` means only code inside this object can change the value;
    // external callers can only read it.
    var alertActive by mutableStateOf(false)
        private set

    // Counts down from 30 to 0 during an active alert. Drives the large number
    // shown on AlertScreen. Updated by tickRunnable every second.
    var remainingSeconds by mutableStateOf(30)
        private set

    var alertPresentationIssue by mutableStateOf<AlertPresentationIssue?>(null)
        private set

    // The incident currently counting down (null when idle). It is also
    // persisted through activeAlertStore so a process restart within the
    // 30-second window restores the alert screen and notification.
    private var activeAlert: ActiveAlert? = null
    private var activeAlertStore: ActiveAlertStore? = null

    // --- Countdown timer ---
    // Handler + Looper.getMainLooper() creates a timer that runs on the main
    // (UI) thread. Composable state must only be written from the main thread,
    // so this is the correct choice over a background Thread or coroutine here.
    private val handler = Handler(Looper.getMainLooper())

    // tickRunnable re-computes the remaining time from the original fall timestamp.
    // This avoids drift and keeps the watch aligned with the phone countdown even
    // if there was a delivery delay before either screen became visible.
    // Using `object : Runnable` creates an anonymous class implementing Runnable
    // so the Runnable can reference itself via `this` to reschedule.
    private val tickRunnable = object : Runnable {
        override fun run() {
            val alert = activeAlert ?: return
            val remaining = alertRemainingSeconds(
                alert.fallTimestampMs,
                System.currentTimeMillis()
            )
            remainingSeconds = remaining

            if (remaining > 0) {
                handler.postDelayed(this, 500L)
            } else {
                // Countdown expired without cancellation — time is up.
                // Backend escalation and caregiver notification continue
                // independently on the phone after the local grace period.
                endAlert()
            }
        }
    }

    /**
     * Restores a persisted alert after process death (called by
     * FallDetectionService and MainActivity on start). If the alert is already
     * active in memory, re-announces it so a newly attached
     * onAlertStateChanged owner (the service) shows notification and sound.
     */
    fun restore(context: Context) {
        val applicationContext = context.applicationContext
        handler.post {
            val store = store(applicationContext)
            if (activeAlert != null) {
                onAlertStateChanged?.invoke(true)
                return@post
            }
            val restored = store.restore(System.currentTimeMillis()) ?: return@post
            Log.i("WearDataSender", "Restoring active alert after process restart")
            startAlert(restored)
        }
    }

    /**
     * Called by FallDetectionService when a fall is confirmed.
     *
     * Step 1 — Create a new incident (random lowercase UUID) for this fall.
     * Step 2 — Send "/fall_event" to connected phones (fast path) and queue a
     *           "/fall_event" data item (durable path for a disconnected phone).
     *           See AlertContract for the exact, backward-compatible payload.
     * Step 3 — Persist the incident and start the local 30-second countdown.
     *
     * @param context  Android context needed to reach Wearable APIs.
     * @param timestamp  Wall-clock time in ms (System.currentTimeMillis()) when
     *                   the fall was detected. Both watch and phone use this same
     *                   origin to keep their countdowns in sync.
     */
    fun sendFallEvent(context: Context, timestamp: Long) {
        val applicationContext = context.applicationContext
        handler.post {
            // One incident owns one countdown. Repeated sensor signatures must
            // not restart the 30-second grace period or replay the alarm.
            val now = System.currentTimeMillis()
            if (!shouldStartAlert(alertActive, timestamp, now)) return@post

            val alert = ActiveAlert(AlertContract.newIncidentId(), timestamp)
            store(applicationContext).save(alert)

            sendToPhone(
                applicationContext,
                AlertContract.FALL_PATH,
                AlertContract.fallMessagePayload(alert),
                "fall event"
            )
            // A previous incident's undelivered cancel must never reach the
            // phone after this new fall: an older phone build would accept it
            // and close the new alert. Dropping it can at worst escalate the
            // previous incident, which is the safe failure direction.
            deleteQueued(applicationContext, AlertContract.CANCEL_PATH)
            queueForPhone(
                applicationContext,
                AlertContract.FALL_PATH,
                AlertContract.fallDataFields(alert, now),
                "fall event"
            )
            startAlert(alert)
        }
    }

    /**
     * Called when the watch user completes the 1.5-second hold on AlertScreen.
     *
     * Stops the local countdown, dismisses AlertScreen, and sends "/cancel_alert"
     * with the incident id and original fall timestamp to the phone so it
     * closes exactly this incident. The reverse path (phone → watch) is
     * handled by cancelAlertFromPhone().
     *
     * @param context  Android context needed to reach Wearable APIs.
     */
    fun sendCancelAlert(context: Context) {
        val applicationContext = context.applicationContext
        handler.post {
            val alert = activeAlert ?: return@post
            store(applicationContext)
            endAlert()
            val now = System.currentTimeMillis()
            sendToPhone(
                applicationContext,
                AlertContract.CANCEL_PATH,
                AlertContract.cancelMessagePayload(alert),
                "cancel alert"
            )
            // The cancelled fall must not be replayed to a phone that
            // reconnects later; deleting it also guarantees this cancel can
            // never be delivered after (and be overtaken by) its own fall.
            deleteQueued(applicationContext, AlertContract.FALL_PATH)
            queueForPhone(
                applicationContext,
                AlertContract.CANCEL_PATH,
                AlertContract.cancelDataFields(alert, now),
                "cancel alert"
            )
        }
    }

    fun updateAlertPresentationIssue(issue: AlertPresentationIssue?) {
        handler.post { alertPresentationIssue = issue }
    }

    /**
     * Called by PhoneMessageListenerService (or MainActivity's cancelAlertListener)
     * when the phone sends "/cancel_alert" to the watch.
     *
     * A cancel that names an incident closes only that incident; a legacy
     * cancel without identifiers closes whichever alert is active. See
     * AlertContract.shouldAcceptPhoneCancel.
     *
     * We do NOT call sendToPhone() here — that would echo the cancel back to the
     * phone, causing an infinite ping-pong loop. We only update local state.
     *
     * handler.post() ensures the state write happens on the main thread, even
     * though PhoneMessageListenerService may call this from a background thread.
     */
    fun cancelAlertFromPhone(context: Context, payload: ByteArray?) {
        val applicationContext = context.applicationContext
        val cancel = AlertContract.parsePhoneCancel(payload)
        handler.post {
            store(applicationContext)
            val accepted = AlertContract.shouldAcceptPhoneCancel(activeAlert, cancel)
            Log.d(
                "WearDataSender",
                "cancelAlertFromPhone: active=${activeAlert != null} " +
                    "identified=${cancel.incidentId != null} accepted=$accepted"
            )
            if (accepted) endAlert()
        }
    }

    private fun startAlert(alert: ActiveAlert) {
        handler.removeCallbacks(tickRunnable)
        activeAlert = alert
        alertActive = true        // Tell Compose to switch to AlertScreen.
        remainingSeconds = alertRemainingSeconds(alert.fallTimestampMs, System.currentTimeMillis())
        onAlertStateChanged?.invoke(true)
        handler.post(tickRunnable)
    }

    private fun endAlert() {
        handler.removeCallbacks(tickRunnable)  // Stop the countdown timer.
        activeAlert = null
        activeAlertStore?.clear()
        alertActive = false                    // Return to IdleScreen.
        remainingSeconds = 30                  // Reset for the next alert.
        onAlertStateChanged?.invoke(false)     // Stop sound and urgent notification.
    }

    private fun store(context: Context): ActiveAlertStore =
        activeAlertStore ?: ActiveAlertStore(
            SharedPreferencesAlertStorage(
                context.getSharedPreferences("fall_guardian_alert", Context.MODE_PRIVATE)
            )
        ).also { activeAlertStore = it }

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
