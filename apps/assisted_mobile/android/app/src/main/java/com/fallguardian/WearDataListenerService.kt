package com.fallguardian

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

/**
 * Listens for messages sent by the Wear OS app via the Wearable MessageClient API.
 *
 * On /fall_event:
 *   • App in foreground  → invoke Flutter channel directly (FallAlertScreen appears immediately).
 *   • App in background  → show full-screen intent notification (wakes lock screen) AND start
 *                          the Flutter countdown immediately so the 30-second cancellation
 *                          window runs even if the user never taps the notification.
 *   • App killed         → show full-screen intent notification; MainActivity reads the
 *                          fall_timestamp intent extra on launch and starts FallAlertScreen.
 *
 * startActivity() from a background service is blocked on Android 10+, so the full-screen
 * intent notification is the correct mechanism for all non-foreground cases.
 */
class WearDataListenerService : WearableListenerService() {

    companion object {
        // Notification ID for the native wakeup notification. Must differ from
        // flutter_local_notifications' ID (1) to avoid cancelling each other.
        const val FALL_WAKEUP_NOTIF_ID = 2
        // Same channel ID as flutter_local_notifications so the user sees one
        // "Fall Alerts" entry in system notification settings.
        private const val CHANNEL_ID = "fall_guardian_alerts"
        private const val DATA_EVENT_TTL_MS = 2 * 60 * 1000L
        private const val DISPLAYED_NOTIFICATION_KEY = "displayed_fall_notification"
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.forEach { event ->
            if (event.type != DataEvent.TYPE_CHANGED) return@forEach
            if (!isTrustedDataItem(event)) {
                deleteDataItem(event)
                return@forEach
            }

            when (event.dataItem.uri.path) {
                "/fall_event" -> {
                    val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                    val timestamp = dataMap.getLong("timestamp", System.currentTimeMillis())
                    val updatedAt = dataMap.getLong("updatedAt", timestamp)
                    if (isStaleDataEvent(updatedAt)) {
                        deleteDataItem(event)
                        return@forEach
                    }
                    // Optional watch-generated incident UUID (newer watches).
                    handleFallDetected(timestamp, dataMap.getString("incidentId"))
                }
                "/cancel_alert" -> {
                    // Optional incident targeting: newer watches send the
                    // incidentId and fallTimestamp of the incident to cancel.
                    // Note "timestamp" on this item is the cancel time, not
                    // the fall time, so it is deliberately not used here.
                    val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                    val fallTimestamp = if (dataMap.containsKey("fallTimestamp")) {
                        dataMap.getLong("fallTimestamp")
                    } else {
                        null
                    }
                    handleCancelAlert(dataMap.getString("incidentId"), fallTimestamp)
                }
            }
            deleteDataItem(event)
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            "/cancel_alert" -> {
                val target = WatchPayloads.parseCancel(messageEvent.data)
                handleCancelAlert(target.incidentId, target.fallTimestamp)
                return
            }
            "/fall_event" -> Unit
            else -> return
        }
        // Validate that the sender is an actually connected Wearable node.
        val connectedNodes = try {
            Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        } catch (_: Exception) {
            return
        }
        if (connectedNodes.none { it.id == messageEvent.sourceNodeId }) return
        val fall = WatchPayloads.parseFall(messageEvent.data) ?: return
        handleFallDetected(fall.timestamp, fall.incidentId)
    }

    private fun isTrustedDataItem(event: DataEvent): Boolean {
        val sourceNodeId = event.dataItem.uri.host ?: return false
        val connectedNodes = try {
            Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        } catch (_: Exception) {
            return false
        }

        return connectedNodes.any { it.id == sourceNodeId }
    }

    private fun isStaleDataEvent(updatedAt: Long): Boolean {
        return System.currentTimeMillis() - updatedAt > DATA_EVENT_TTL_MS
    }

    private fun deleteDataItem(event: DataEvent) {
        Wearable.getDataClient(this).deleteDataItems(event.dataItem.uri)
    }

    private fun handleFallDetected(timestamp: Long, incidentId: String?) {
        // Watch UUID, forwarded to Flutter as an alias when the incident is
        // already known under another id (e.g. legacy transport first).
        val watchIncidentId = NativeAlertRelayPolicy.normalizedIncidentId(incidentId)
        // Persist and schedule backend registration before touching UI. The
        // JobService survives a missing Flutter engine, process death and
        // temporary network loss. Dart receives the same idempotency key when
        // it is available, so native and Flutter retries create one incident.
        val clientAlertId = NativeAlertRelay.enqueueFall(
            applicationContext,
            timestamp,
            incidentId
        )
        val activity = MainActivity.getInstance()
        if (activity != null && activity.isInForeground) {
            // App is visible — invoke the Flutter channel directly.
            // No notification needed: Flutter will push FallAlertScreen immediately.
            activity.sendFallDetectedToFlutter(timestamp, clientAlertId, watchIncidentId)
            return
        }

        // App is in the background or fully killed.
        //
        // On Android 10+ startActivity() from a background service is blocked, so we
        // cannot force the app to the foreground directly. Instead we use a full-screen
        // intent notification which:
        //   • On a locked/sleeping screen → shows as a full-screen activity (like an
        //     incoming call), turning the screen on via MainActivity's showWhenLocked /
        //     turnScreenOn attributes.
        //   • On an unlocked screen → shows as a heads-up banner the user can tap.
        //
        // If the activity is alive but backgrounded we also call sendFallDetectedToFlutter
        // immediately so the 30-second cancellation countdown starts even if the user never
        // taps the notification. A dedup guard in MainActivity prevents a double FallAlertScreen
        // if the user later taps the notification (which fires onNewIntent with the same
        // timestamp).
        showFallNotification(timestamp, clientAlertId, watchIncidentId)
        activity?.sendFallDetectedToFlutter(timestamp, clientAlertId, watchIncidentId)
    }

    private fun showFallNotification(
        timestamp: Long,
        clientAlertId: String,
        watchIncidentId: String?
    ) {
        // Remember which incident the notification shows, so a delayed cancel
        // for another incident cannot remove it.
        getSharedPreferences(MainActivity.PREFS_NAME, MODE_PRIVATE).edit()
            .putString(
                DISPLAYED_NOTIFICATION_KEY,
                FallNotificationPolicy.encode(
                    DisplayedFallNotification(clientAlertId, watchIncidentId, timestamp)
                )
            )
            .apply()
        val nm = getSystemService(NotificationManager::class.java)

        // Create the channel if it doesn't exist yet (idempotent — no-op if
        // flutter_local_notifications already created it with the same ID).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Fall Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "Urgent fall detection alerts" }
            )
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            `package` = packageName
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("fall_timestamp", timestamp)
            putExtra("client_alert_id", clientAlertId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ Fall Detected")
            .setContentText("Open to cancel — caregivers are notified in 30 seconds")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(pendingIntent)  // tap anywhere on the banner opens the app
            // Keep the notification visible until MainActivity cancels it.
            .setOngoing(true)

        // setFullScreenIntent makes Android show the alert as a full-screen activity
        // on the lock/sleeping screen (turning the display on via MainActivity's
        // showWhenLocked + turnScreenOn attributes).
        // On Android 14+ USE_FULL_SCREEN_INTENT is a runtime-grantable permission;
        // we check canUseFullScreenIntent() before setting it to avoid a no-op on
        // devices where the user has not granted it.
        if (Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()) {
            builder.setFullScreenIntent(pendingIntent, true)
        }

        nm.notify(FALL_WAKEUP_NOTIF_ID, builder.build())
    }

    private fun handleCancelAlert(rawIncidentId: String?, fallTimestamp: Long?) {
        val incidentId = NativeAlertRelayPolicy.normalizedIncidentId(rawIncidentId)
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, MODE_PRIVATE)
        val displayed = FallNotificationPolicy.decode(
            prefs.getString(DISPLAYED_NOTIFICATION_KEY, null)
        )
        if (FallNotificationPolicy.shouldDismiss(displayed, incidentId, fallTimestamp)) {
            getSystemService(NotificationManager::class.java)
                ?.cancel(FALL_WAKEUP_NOTIF_ID)
            prefs.edit().remove(DISPLAYED_NOTIFICATION_KEY).apply()
        }

        MainActivity.storePendingCancel(applicationContext, incidentId, fallTimestamp)
        NativeAlertRelay.requestCancel(applicationContext, incidentId, fallTimestamp)

        MainActivity.getInstance()?.deliverPendingCancelsToFlutter()
    }
}
