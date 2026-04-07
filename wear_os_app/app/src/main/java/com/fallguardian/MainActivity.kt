package com.fallguardian

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.*

/**
 * Entry point of the Wear OS application.
 *
 * --- What is Jetpack Compose? ---
 * Jetpack Compose is Google's modern UI toolkit for Android (and Wear OS).
 * Instead of describing the UI in XML layout files, you write @Composable
 * functions in Kotlin. Each function is a "component" that returns UI — similar
 * to React components or SwiftUI views. When the data they read changes (e.g.
 * WearDataSender.alertActive flips to true), Compose automatically re-runs the
 * affected functions and redraws only the changed parts of the screen.
 *
 * --- Three screen states ---
 * The entire watch UI is controlled by two boolean flags inside WearDataSender:
 *   1. permissionDenied == true  → PermissionDeniedScreen  (BODY_SENSORS not granted)
 *   2. alertActive      == true  → AlertScreen             (fall detected, countdown running)
 *   3. both false               → IdleScreen               (normal monitoring state)
 *
 * --- How this file connects to the others ---
 * • Starts FallDetectionService so sensor monitoring begins immediately.
 * • Registers a MessageClient listener to receive "/cancel_alert" from the phone
 *   while the Activity is foregrounded (belt-and-suspenders alongside
 *   PhoneMessageListenerService which handles the backgrounded case).
 * • Reads WearDataSender state (alertActive, permissionDenied) to decide which
 *   screen to show — no other state is needed.
 */
class MainActivity : ComponentActivity() {

    // --- Belt-and-suspenders cancel listener ---
    // PhoneMessageListenerService handles "/cancel_alert" when the app is
    // backgrounded. However, WearableListenerService is unreliable in the
    // Wear OS emulator for phone→watch messages. This second listener is
    // registered directly on MessageClient and is active while this Activity is
    // alive — providing a reliable path during both emulator testing and real
    // device use when the Activity is in the foreground.
    // It calls the same WearDataSender.cancelAlertFromPhone() so behavior is
    // identical regardless of which listener fires.
    private val cancelAlertListener = MessageClient.OnMessageReceivedListener { messageEvent ->
        if (messageEvent.path == "/cancel_alert") {
            Log.d("MainActivity", "cancelAlertListener: received /cancel_alert")
            WearDataSender.cancelAlertFromPhone()
        }
    }

    // onCreate() is called by the Android OS when the Activity is first created.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register the foreground cancel listener while this Activity is alive.
        Wearable.getMessageClient(this).addListener(cancelAlertListener)

        // Start fall detection immediately — no permission required for the accelerometer.
        startForegroundService(Intent(this, FallDetectionService::class.java))

        // setContent replaces the Activity's view with a Compose UI tree.
        setContent { WearApp() }
    }

    // onDestroy() is called when the Activity is permanently going away.
    // We must unregister the MessageClient listener here to prevent a memory leak
    // (the listener holds a reference to this Activity instance).
    override fun onDestroy() {
        Wearable.getMessageClient(this).removeListener(cancelAlertListener)
        super.onDestroy()
    }
}

/**
 * Root composable — switches between IdleScreen and AlertScreen based on
 * WearDataSender.alertActive state. MaterialTheme provides typography, colours,
 * and shape tokens to all child composables.
 */
@Composable
fun WearApp() {
    val context = LocalContext.current
    val alertActive = WearDataSender.alertActive
    MaterialTheme {
        if (alertActive) AlertScreen(context) else IdleScreen(context)
    }
}

/**
 * Screen shown during an active fall alert (alertActive == true).
 *
 * Displays the 30-second countdown in large text, haptic-vibrates the watch
 * every second (more intensely under 10 s), and flashes red as time runs out.
 * Tapping anywhere on the screen cancels the alert on both watch and phone.
 *
 * --- Why vibrate here instead of in FallDetectionService? ---
 * Haptic feedback is a UI concern — it signals urgency to the user. Keeping it
 * in the composable makes it easy to tie the pattern to the remaining time
 * and to stop it automatically when the screen is dismissed.
 *
 * --- LaunchedEffect ---
 * LaunchedEffect(key) is a Compose side-effect that launches a coroutine scoped
 * to the composable's lifetime. The coroutine re-runs whenever `key` changes.
 * Here, key = `remaining`, so the vibration fires once per countdown second.
 */
@Composable
private fun AlertScreen(context: Context) {
    val remaining = WearDataSender.remainingSeconds  // Read the countdown from shared state.
    val vibrator = context.getSystemService(Vibrator::class.java)

    // Haptic every second — stronger under 10 s to convey increasing urgency.
    LaunchedEffect(remaining) {
        if (remaining in 1..29) {
            val effect = if (remaining <= 10)
                VibrationEffect.createOneShot(150, VibrationEffect.DEFAULT_AMPLITUDE) // Long, full-strength buzz.
            else
                VibrationEffect.createOneShot(40, 80) // Short, moderate buzz.
            vibrator?.vibrate(effect)
        }
    }

    // Flash overlay: under 10 s, a red overlay pulses between transparent and
    // semi-opaque. rememberInfiniteTransition + animateFloat produce the animation.
    // Above 10 s, flashAlpha is always 0 (fully transparent — no flash).
    // Flash overlay pulses between 0 and 0.4 opacity under 10 s
    val flashAlpha by if (remaining <= 10) {
        rememberInfiniteTransition(label = "flash").animateFloat(
            initialValue = 0f,
            targetValue = 0.4f,
            animationSpec = infiniteRepeatable(
                animation = tween(400), repeatMode = RepeatMode.Reverse
            ),
            label = "alpha"
        )
    } else {
        // No animation needed above 10 s — use a static 0 value.
        androidx.compose.runtime.remember {
            androidx.compose.runtime.mutableFloatStateOf(0f)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1A0000))               // Deep red base background.
            .background(Color.Red.copy(alpha = flashAlpha)) // Pulsing red flash overlay on top.
            .clickable { WearDataSender.sendCancelAlert(context) }, // Tap anywhere = cancel.
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // Large countdown number — the focal point of the screen.
            Text(
                text = "$remaining",
                color = Color.White,
                fontSize = 64.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Tap anywhere to cancel",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}

/**
 * Screen shown during normal operation (no alert, permission granted).
 *
 * Displays the app name and a "Monitoring active" status label to reassure
 * the user that fall detection is running in the background.
 *
 * In debug builds (BuildConfig.DEBUG == true), a "Simulate Fall (debug)" button
 * is rendered. Tapping it directly calls WearDataSender.sendFallEvent() with the
 * current timestamp — exactly as FallDetectionService would on a real fall. This
 * lets developers test the full alert flow on a real watch or emulator without
 * having to physically fall. The button is compiled out of release builds entirely.
 */
@Composable
private fun IdleScreen(context: Context) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF001A18)), // Dark teal — calm, non-alarming idle state.
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Circular shield icon badge — a visual indicator of active protection.
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .background(Color(0xFF003F3C), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Shield,
                    contentDescription = null, // Decorative — screen reader can skip it.
                    tint = Color(0xFFE5694A),  // Orange accent colour.
                    modifier = Modifier.size(30.dp)
                )
            }
            Text(
                text = "Fall Guardian",
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Monitoring active",
                color = Color(0xFFD1E0D7), // Muted green-white — calm confirmation.
                fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
            // Debug-only fall simulation button — stripped from release builds at compile time.
            if (BuildConfig.DEBUG) {
                Spacer(modifier = Modifier.height(4.dp))
                Chip(
                    onClick = { simulateFall(context) },
                    label = {
                        Text(
                            text = "Simulate Fall (debug)",
                            fontSize = 11.sp,
                            color = Color(0xFFE5694A)
                        )
                    },
                    colors = ChipDefaults.chipColors(backgroundColor = Color(0xFF001A18)),
                    modifier = Modifier.border(
                        width = 1.dp,
                        color = Color(0xFFE5694A),
                        shape = RoundedCornerShape(50)
                    )
                )
            }
        }
    }
}

/**
 * Triggers a fake fall event with the current wall-clock timestamp.
 * Only reachable from the debug Simulate Fall button in IdleScreen.
 * Exercises the identical code path as a real detected fall:
 * WearDataSender.sendFallEvent() → phone message + local countdown UI.
 */
private fun simulateFall(context: Context) {
    WearDataSender.sendFallEvent(context, System.currentTimeMillis())
}
