package com.fallguardian.wear

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

/**
 * Sends fall event data to the paired phone via the Wearable Data Layer API.
 */
object WearDataSender {

    fun sendFallEvent(context: Context, timestamp: Long) {
        val request = PutDataMapRequest.create("/fall_event").apply {
            dataMap.putLong("timestamp", timestamp)
            // Force Data Layer to treat as new event even if same timestamp
            dataMap.putLong("sent_at", System.currentTimeMillis())
        }
        val putRequest = request.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context)
            .putDataItem(putRequest)
            .addOnSuccessListener { /* event sent */ }
            .addOnFailureListener { /* log if needed */ }
    }
}
