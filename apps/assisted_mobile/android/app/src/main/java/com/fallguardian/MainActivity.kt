package com.fallguardian

import android.app.NotificationManager
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.util.Log
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "fall_guardian/watch"
        const val SECURE_STORAGE_CHANNEL = "fall_guardian/secure_storage"
        const val PREFS_NAME = "fall_guardian"
        const val PENDING_THRESHOLDS_KEY = "pending_thresholds_json"
        const val PENDING_CANCEL_KEY = "pending_alert_cancelled"

        // WeakReference prevents Activity leak; @Volatile ensures cross-thread visibility.
        @Volatile
        private var weakInstance: java.lang.ref.WeakReference<MainActivity>? = null

        /** Thread-safe accessor — returns null if Activity is destroyed. */
        fun getInstance(): MainActivity? = weakInstance?.get()
    }

    private lateinit var channel: MethodChannel
    private lateinit var secureStorageChannel: MethodChannel
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }
    private val secureStore: AndroidSecureStore by lazy {
        AndroidSecureStore(applicationContext)
    }

    // Tracks the last timestamp forwarded to Flutter so we never push two
    // FallAlertScreens for the same fall event.  This can happen when the app
    // is backgrounded: WearDataListenerService calls sendFallDetectedToFlutter()
    // immediately (to start the cancellation countdown) and also shows a
    // notification; when the user taps the notification onNewIntent fires with
    // the same timestamp — the dedup check here silently drops the duplicate.
    @Volatile private var lastForwardedTimestamp = Long.MIN_VALUE

    /** True when the activity is currently visible to the user. */
    val isInForeground: Boolean
        get() = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        weakInstance = java.lang.ref.WeakReference(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        secureStorageChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_STORAGE_CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendThresholds" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) sendThresholdsToWatch(args)
                    result.success(null)
                }
                "sendCancelAlert" -> {
                    sendCancelAlertToWatch()
                    result.success(null)
                }
                "configureNativeAlertRelay" -> {
                    val baseUrl =
                        (call.arguments as? Map<*, *>)?.get("baseUrl") as? String
                    if (baseUrl == null ||
                        !NativeAlertRelay.configure(applicationContext, baseUrl)
                    ) {
                        result.error(
                            "INVALID_BASE_URL",
                            "Native alert relay requires an allowed backend URL",
                            null
                        )
                    } else {
                        result.success(null)
                    }
                }
                "sendCompanionEnrollment" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Missing enrollment payload", null)
                    } else {
                        sendCompanionEnrollmentToWatch(args, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        secureStorageChannel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            val key = args?.get("key") as? String
            when (call.method) {
                "read" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Missing key", null)
                        return@setMethodCallHandler
                    }
                    result.success(secureStore.read(key))
                }
                "write" -> {
                    val value = args?.get("value") as? String
                    if (key == null || value == null) {
                        result.error("INVALID_ARGS", "Missing key/value", null)
                        return@setMethodCallHandler
                    }
                    secureStore.write(key, value)
                    result.success(null)
                }
                "delete" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Missing key", null)
                        return@setMethodCallHandler
                    }
                    secureStore.delete(key)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        flushPendingCancelToFlutter()
        flushPendingThresholdsToWatch()
        requestFullScreenIntentPermissionIfNeeded()
        // Handle fall event launched via intent (activity was not running)
        if (isTrustedIntent(intent)) {
            forwardIntentFall(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Handle fall event when activity is already running (singleTop)
        if (isTrustedIntent(intent)) {
            forwardIntentFall(intent)
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
     * Called by WearDataListenerService (background) or onNewIntent (notification tap)
     * when a fall event arrives from the watch.
     *
     * The dedup guard prevents a second FallAlertScreen when the app is backgrounded:
     * WearDataListenerService calls this immediately (so the 30-second cancellation
     * countdown starts) and also shows a notification. If the user taps the notification, onNewIntent
     * fires with the same timestamp — without dedup we would push FallAlertScreen twice.
     */
    fun sendFallDetectedToFlutter(timestamp: Long, clientAlertId: String? = null) {
        if (timestamp == lastForwardedTimestamp) return  // duplicate — already in progress
        lastForwardedTimestamp = timestamp
        runOnUiThread {
            Log.d("MainActivity", "sendFallDetectedToFlutter: timestamp=$timestamp")
            // Cancel the native wakeup notification shown by WearDataListenerService
            // when the app was backgrounded or killed — FallAlertScreen takes over.
            getSystemService(NotificationManager::class.java)
                ?.cancel(WearDataListenerService.FALL_WAKEUP_NOTIF_ID)
            channel.invokeMethod(
                "onFallDetected",
                mapOf(
                    "timestamp" to timestamp,
                    "clientAlertId" to clientAlertId
                )
            )
        }
    }

    private fun forwardIntentFall(intent: Intent?) {
        val timestamp = intent?.getLongExtra("fall_timestamp", Long.MIN_VALUE)
            ?.takeIf { it != Long.MIN_VALUE }
            ?: return
        val clientAlertId = intent.getStringExtra("client_alert_id")
        sendFallDetectedToFlutter(timestamp, clientAlertId)
    }

    fun sendCancelAlertToFlutter() {
        prefs.edit().putBoolean(PENDING_CANCEL_KEY, false).apply()
        runOnUiThread {
            Log.d("MainActivity", "sendCancelAlertToFlutter: forwarding cancel to Flutter")
            channel.invokeMethod("onAlertCancelled", null)
        }
    }

    private fun sendCancelAlertToWatch() {
        // Queue backend cancellation before best-effort watch delivery. This
        // remains effective when Flutter is suspended or killed.
        NativeAlertRelay.requestCancel(applicationContext)
        val payload = """{"event":"alert_cancelled"}""".toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                Log.d("MainActivity", "sendCancelAlertToWatch: ${nodes.size} node(s) found")
                nodes.forEach { node ->
                    Log.d("MainActivity", "sendCancelAlertToWatch: sending to ${node.displayName}")
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, "/cancel_alert", payload)
                        .addOnSuccessListener { Log.d("MainActivity", "sendCancelAlertToWatch: sent OK") }
                        .addOnFailureListener { e -> Log.e("MainActivity", "sendCancelAlertToWatch: failed", e) }
                }
                if (nodes.isEmpty()) Log.w("MainActivity", "sendCancelAlertToWatch: no connected nodes")
            }
            .addOnFailureListener { e -> Log.e("MainActivity", "sendCancelAlertToWatch: getNodeClient failed", e) }
    }

    /**
     * Sends a short-lived enrollment token to exactly one connected Wear OS node.
     *
     * Broadcasting an authentication token to every paired watch would let the
     * wrong watch consume it. Zero or multiple nodes therefore produce a
     * recoverable Flutter error instead of an ambiguous success.
     */
    private fun sendCompanionEnrollmentToWatch(
        enrollment: Map<String, Any>,
        result: MethodChannel.Result
    ) {
        val valid = enrollment["type"] == "companionEnrollment" &&
            (enrollment["schemaVersion"] as? Number)?.toInt() == 1 &&
            enrollment["platform"] == "wearos" &&
            (enrollment["enrollmentToken"] as? String)?.length == 64 &&
            (enrollment["expiresAt"] as? String).isNullOrBlank().not()
        if (!valid) {
            result.error("INVALID_ARGS", "Invalid companion enrollment payload", null)
            return
        }

        val payload = org.json.JSONObject(enrollment).toString().toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.size != 1) {
                    result.error(
                        "WATCH_UNAVAILABLE",
                        "Expected one connected Wear OS watch, found ${nodes.size}",
                        null
                    )
                    return@addOnSuccessListener
                }

                Wearable.getMessageClient(this)
                    .sendMessage(nodes.single().id, "/companion_enrollment", payload)
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener {
                        result.error(
                            "WATCH_DELIVERY_FAILED",
                            "Could not send enrollment to Wear OS watch",
                            null
                        )
                    }
            }
            .addOnFailureListener {
                result.error(
                    "WATCH_UNAVAILABLE",
                    "Could not inspect connected Wear OS watches",
                    null
                )
            }
    }

    private fun sendThresholdsToWatch(thresholds: Map<String, Any>) {
        val json = org.json.JSONObject(thresholds)
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        prefs.edit().putString(PENDING_THRESHOLDS_KEY, json.toString()).apply()
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.w("MainActivity", "sendThresholdsToWatch: no connected nodes, keeping pending payload")
                    return@addOnSuccessListener
                }
                var pendingSends = nodes.size
                var failed = false
                nodes.forEach { node ->
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, "/thresholds", payload)
                        .addOnSuccessListener {
                            pendingSends--
                            if (pendingSends == 0 && !failed) {
                                prefs.edit().remove(PENDING_THRESHOLDS_KEY).apply()
                            }
                        }
                        .addOnFailureListener { e ->
                            failed = true
                            Log.e("MainActivity", "Failed to send thresholds to watch", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.w("MainActivity", "No connected nodes for threshold sync", e)
            }
    }

    private fun flushPendingThresholdsToWatch() {
        val raw = prefs.getString(PENDING_THRESHOLDS_KEY, null) ?: return
        val json = try {
            org.json.JSONObject(raw)
        } catch (e: Exception) {
            Log.e("MainActivity", "flushPendingThresholdsToWatch: invalid pending payload", e)
            prefs.edit().remove(PENDING_THRESHOLDS_KEY).apply()
            return
        }
        val thresholds = buildMap<String, Any> {
            if (json.has("thresh_freefall")) put("thresh_freefall", json.getDouble("thresh_freefall"))
            if (json.has("thresh_impact")) put("thresh_impact", json.getDouble("thresh_impact"))
            if (json.has("thresh_tilt")) put("thresh_tilt", json.getDouble("thresh_tilt"))
            if (json.has("thresh_freefall_ms")) put("thresh_freefall_ms", json.getInt("thresh_freefall_ms"))
        }
        if (thresholds.isNotEmpty()) sendThresholdsToWatch(thresholds)
    }

    private fun flushPendingCancelToFlutter() {
        if (!prefs.getBoolean(PENDING_CANCEL_KEY, false)) return
        sendCancelAlertToFlutter()
    }

    /**
     * On Android 14+ (API 34), USE_FULL_SCREEN_INTENT requires an explicit user grant
     * via system settings — declaring it in the manifest is not enough.
     * Without it, fall alerts cannot wake the screen or show over the lock screen.
     * We prompt once (tracked via SharedPreferences) so the user isn't bothered
     * on every launch after they have already granted it.
     */
    private fun requestFullScreenIntentPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.canUseFullScreenIntent()) return
        val alreadyPrompted = prefs.getBoolean("full_screen_intent_prompted", false)
        if (alreadyPrompted) return
        prefs.edit().putBoolean("full_screen_intent_prompted", true).apply()
        startActivity(
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        weakInstance = null
    }
}
