package com.fallguardian

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
    }

    /**
     * Called by WearDataListenerService when a fall event arrives from the watch.
     * Forwards it to Flutter via the MethodChannel.
     */
    fun sendFallDetectedToFlutter(timestamp: Long) {
        runOnUiThread {
            channel.invokeMethod("onFallDetected", mapOf("timestamp" to timestamp))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        weakInstance = null
    }
}
