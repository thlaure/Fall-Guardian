package com.fallguardian

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "fall_guardian/watch"

        // WeakReference prevents Activity leak; @Volatile ensures cross-thread visibility.
        @Volatile
        private var weakInstance: java.lang.ref.WeakReference<MainActivity>? = null

        /** Thread-safe accessor — returns null if Activity is destroyed. */
        fun getInstance(): MainActivity? = weakInstance?.get()
    }

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        weakInstance = java.lang.ref.WeakReference(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        // Handle fall event launched via intent (activity was not running)
        if (isTrustedIntent(intent)) {
            intent?.getLongExtra("fall_timestamp", Long.MIN_VALUE)
                ?.takeIf { it != Long.MIN_VALUE }
                ?.let { sendFallDetectedToFlutter(it) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Handle fall event when activity is already running (singleTop)
        if (isTrustedIntent(intent)) {
            intent.getLongExtra("fall_timestamp", Long.MIN_VALUE)
                .takeIf { it != Long.MIN_VALUE }
                ?.let { sendFallDetectedToFlutter(it) }
        }
    }

    /**
     * Returns true only when the intent originates from this same package.
     * WearDataListenerService sends internal intents, so same-package intents must pass.
     * External apps crafting a fall_timestamp intent are rejected.
     */
    private fun isTrustedIntent(intent: Intent?): Boolean {
        if (intent == null) return true
        if (intent.hasExtra("fall_timestamp").not()) return true
        return intent.`package` == packageName || callingActivity?.packageName == packageName
    }

    /**
     * Called by WearDataListenerService (background) or onDataChanged (foreground)
     * when a fall event arrives from the watch.
     */
    fun sendFallDetectedToFlutter(timestamp: Long) {
        runOnUiThread {
            channel.invokeMethod("onFallDetected", mapOf("timestamp" to timestamp))
        }
    }

    fun sendCancelAlertToFlutter() {
        runOnUiThread {
            channel.invokeMethod("onAlertCancelled", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        weakInstance = null
    }
}
