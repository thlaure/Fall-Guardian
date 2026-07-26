package com.fallguardian

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Debug-only automation hooks used by the Android/Wear end-to-end script.
 *
 * The receiver is always compiled, but it is a no-op outside debug builds.
 * Keeping the hooks behind BuildConfig.DEBUG lets adb drive stable test actions
 * without exposing production-only control surfaces.
 */
class DebugAutomationReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_SIMULATE_FALL = "com.fallguardian.debug.SIMULATE_FALL"
        const val ACTION_CANCEL_ALERT = "com.fallguardian.debug.CANCEL_ALERT"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return

        when (intent.action) {
            ACTION_SIMULATE_FALL -> {
                Log.d("DebugAutomation", "simulate fall broadcast received")
                // Physical debug flows launch the app once before backgrounding
                // it, so the persistent detection service is already running.
                // Starting a foreground service from this background receiver is
                // forbidden on modern Wear OS and would crash the test hook.
                WearDataSender.sendFallEvent(context.applicationContext, System.currentTimeMillis())
            }

            ACTION_CANCEL_ALERT -> {
                Log.d("DebugAutomation", "cancel alert broadcast received")
                WearDataSender.sendCancelAlert(context.applicationContext)
            }
        }
    }
}
