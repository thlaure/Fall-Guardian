package com.fallguardian

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the cancellation action exposed directly on the urgent watch
 * notification. This gives a fallen wearer a second large system-provided
 * target when Android cannot open the app full-screen.
 */
class AlertActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_CANCEL_FALL_ALERT) {
            WearDataSender.sendCancelAlert(context.applicationContext)
        }
    }

    companion object {
        const val ACTION_CANCEL_FALL_ALERT =
            "com.fallguardian.action.CANCEL_FALL_ALERT"
    }
}
