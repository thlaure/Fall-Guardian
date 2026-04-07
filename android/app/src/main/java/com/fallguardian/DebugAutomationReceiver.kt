package com.fallguardian

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.util.Log
import com.google.android.gms.wearable.Wearable

/**
 * Debug-only adb hooks for Android/Wear end-to-end automation.
 *
 * The Android E2E script uses this receiver to send the same "/cancel_alert"
 * message that the phone app would send after the user cancels on the phone.
 */
class DebugAutomationReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_CANCEL_ALERT_TO_WATCH = "com.fallguardian.debug.CANCEL_ALERT_TO_WATCH"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val isDebuggable =
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) return
        if (intent.action != ACTION_CANCEL_ALERT_TO_WATCH) return

        Log.d("DebugAutomation", "cancel-to-watch broadcast received")
        val payload = """{"event":"alert_cancelled"}""".toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(context).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.w("DebugAutomation", "cancel-to-watch: no connected nodes")
                    return@addOnSuccessListener
                }
                nodes.forEach { node ->
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, "/cancel_alert", payload)
                        .addOnSuccessListener {
                            Log.d("DebugAutomation", "cancel-to-watch: sent to ${node.displayName}")
                        }
                        .addOnFailureListener { e ->
                            Log.e("DebugAutomation", "cancel-to-watch: failed", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.e("DebugAutomation", "cancel-to-watch: node lookup failed", e)
            }
    }
}
