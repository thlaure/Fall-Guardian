package com.fallguardian

import android.content.Intent
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

/**
 * Listens for DataItems sent by the Wear OS app via the Wearable Data Layer.
 * On fall_event path: wakes phone app and forwards event to Flutter.
 */
class WearDataListenerService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.forEach { event ->
            if (event.type == DataEvent.TYPE_CHANGED) {
                val item = event.dataItem
                if (item.uri.path == "/fall_event") {
                    val dataMap = DataMapItem.fromDataItem(item).dataMap
                    val timestamp = dataMap.getLong("timestamp", System.currentTimeMillis())
                    handleFallDetected(timestamp)
                }
            }
        }
    }

    private fun handleFallDetected(timestamp: Long) {
        // Snapshot the WeakReference result once to avoid TOCTOU between null-check and use.
        val activity = MainActivity.getInstance()
        if (activity != null) {
            // App is in foreground — forward directly
            activity.sendFallDetectedToFlutter(timestamp)
        } else {
            // App is in background — launch it with the event in the intent
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("fall_timestamp", timestamp)
            }
            startActivity(intent)
        }
    }
}
