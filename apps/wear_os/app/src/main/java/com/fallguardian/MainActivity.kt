package com.fallguardian

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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

    companion object {
        const val EXTRA_SHOW_FALL_ALERT = "show_fall_alert"
    }

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
            WearDataSender.cancelAlertFromPhone(this@MainActivity, messageEvent.data)
        }
    }

    // onCreate() is called by the Android OS when the Activity is first created.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allows the urgent full-screen notification to reveal the countdown
        // over the lock screen and wake the display without bypassing device
        // authentication for any other content.
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                100
            )
        }

        // Register the foreground cancel listener while this Activity is alive.
        Wearable.getMessageClient(this).addListener(cancelAlertListener)

        // Start fall detection immediately — no permission required for the accelerometer.
        startForegroundService(Intent(this, FallDetectionService::class.java))

        // Re-open an alert that was still counting down when the process died.
        WearDataSender.restore(this)

        // setContent replaces the Activity's view with a Compose UI tree.
        setContent { WearApp() }
        refreshAlertPresentationAccess()
    }

    override fun onResume() {
        super.onResume()
        FallDiagnostics.initialize(this)
        refreshAlertPresentationAccess()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 100) refreshAlertPresentationAccess()
    }

    // onDestroy() is called when the Activity is permanently going away.
    // We must unregister the MessageClient listener here to prevent a memory leak
    // (the listener holds a reference to this Activity instance).
    override fun onDestroy() {
        Wearable.getMessageClient(this).removeListener(cancelAlertListener)
        super.onDestroy()
    }

    private fun refreshAlertPresentationAccess() {
        val manager = getSystemService(NotificationManager::class.java)
        val notificationsGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        val fullScreenGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                manager.canUseFullScreenIntent()

        WearDataSender.updateAlertPresentationIssue(
            alertPresentationIssue(
                Build.VERSION.SDK_INT,
                notificationsGranted,
                fullScreenGranted
            )
        )
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
 * Displays the 30-second countdown in large text and flashes red as time runs
 * out. Cancelling requires a deliberate 1.5-second press-and-hold on the green
 * control (same as watchOS) so a fallen wearer cannot cancel by an accidental
 * brush. Per-second haptics are played by FallDetectionService so they also
 * work with the screen off.
 */
@Composable
private fun AlertScreen(context: Context) {
    val remaining = WearDataSender.remainingSeconds  // Read the countdown from shared state.
    val fontScale = LocalDensity.current.fontScale

    // Flash overlay: under 10 s, a red overlay pulses between transparent and
    // semi-opaque. rememberInfiniteTransition + animateFloat produce the animation.
    // Above 10 s, flashAlpha is always 0 (fully transparent — no flash).
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
        remember { mutableFloatStateOf(0f) }
    }

    // TalkBack announces the countdown through a polite live region; the
    // announced value changes only at milestones (see AlertUiPolicy).
    val announcement = pluralStringResource(
        R.plurals.alert_seconds_remaining,
        AlertUiPolicy.countdownAnnouncementSeconds(remaining),
        AlertUiPolicy.countdownAnnouncementSeconds(remaining)
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1A0000))               // Deep red base background.
            .background(Color.Red.copy(alpha = flashAlpha)), // Pulsing red flash overlay on top.
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
                fontSize = AlertUiPolicy.cappedSp(56f, fontScale).sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = announcement
                }
            )
            Spacer(modifier = Modifier.height(6.dp))
            HoldToCancelButton(
                fontScale = fontScale,
                onConfirmed = { WearDataSender.sendCancelAlert(context) }
            )
        }
    }
}

/**
 * Press-and-hold cancel control.
 *
 * Touch: the green fill grows over 1.5 s while the finger stays down; on
 * completion a haptic tick confirms and the alert is cancelled. Releasing
 * earlier aborts and the fill drains back.
 *
 * Accessibility: screen-reader users get a click action labelled "Hold to
 * cancel". Activating it does not cancel; it opens an explicit confirmation
 * ("Yes, I'm OK" / "No") so the cancel is still a deliberate two-step act.
 */
@Composable
private fun HoldToCancelButton(fontScale: Float, onConfirmed: () -> Unit) {
    val context = LocalContext.current
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var confirming by remember { mutableStateOf(false) }
    var completed by remember { mutableStateOf(false) }
    val holdDescription = stringResource(R.string.alert_hold_to_cancel_description)
    val confirmActionLabel = stringResource(R.string.alert_hold_to_cancel_a11y_action)

    fun complete() {
        if (completed) return
        completed = true
        hapticTick(context)
        onConfirmed()
    }

    if (confirming) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = stringResource(R.string.alert_confirm_cancel_question),
                color = Color.White,
                fontSize = AlertUiPolicy.cappedSp(12f, fontScale).sp,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AlertChoice(
                    text = stringResource(R.string.alert_confirm_cancel_yes),
                    color = Color(0xFF2E7D32),
                    fontScale = fontScale,
                    onClick = ::complete
                )
                AlertChoice(
                    text = stringResource(R.string.alert_confirm_cancel_no),
                    color = Color(0xFF424242),
                    fontScale = fontScale,
                    onClick = { confirming = false }
                )
            }
        }
        return
    }

    Box(
        modifier = Modifier
            .width(150.dp)
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(Color(0xFF1B4D1E))
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        val hold = scope.launch {
                            progress.snapTo(0f)
                            progress.animateTo(
                                1f,
                                tween(AlertUiPolicy.HOLD_TO_CANCEL_MS, easing = LinearEasing)
                            )
                            complete()
                        }
                        tryAwaitRelease()
                        if (!completed) {
                            // Released (or gesture cancelled) before 1.5 s: abort.
                            hold.cancel()
                            scope.launch { progress.animateTo(0f, tween(150)) }
                        }
                    }
                )
            }
            // Replace the merged text with one clear spoken label and a
            // confirmation-gated action for TalkBack / switch access.
            .clearAndSetSemantics {
                contentDescription = holdDescription
                role = Role.Button
                onClick(label = confirmActionLabel) {
                    confirming = true
                    true
                }
            },
        contentAlignment = Alignment.Center
    ) {
        // Progress fill grows left-to-right during the hold.
        Box(
            modifier = Modifier
                .matchParentSize()
                .wrapContentWidth(Alignment.Start)
                .fillMaxWidth(progress.value)
                .background(Color(0xFF43A047))
        )
        Text(
            text = stringResource(R.string.alert_cancel_button),
            color = Color.White,
            fontSize = AlertUiPolicy.cappedSp(11f, fontScale).sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun AlertChoice(text: String, color: Color, fontScale: Float, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .heightIn(min = 44.dp)
            .widthIn(min = 64.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(color)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            color = Color.White,
            fontSize = AlertUiPolicy.cappedSp(11f, fontScale).sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 6.dp)
        )
    }
}

/** Short, strong pulse confirming the hold completed. */
private fun hapticTick(context: Context) {
    context.getSystemService(Vibrator::class.java)
        ?.vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
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
    val presentationIssue = WearDataSender.alertPresentationIssue
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
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
                    tint = Color.White,
                    modifier = Modifier.size(28.dp)
                )
            }
            Text(
                text = stringResource(R.string.app_name),
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Text(
                text = when (presentationIssue) {
                    AlertPresentationIssue.NOTIFICATIONS_DISABLED ->
                        stringResource(R.string.notifications_disabled)
                    AlertPresentationIssue.FULL_SCREEN_DISABLED ->
                        stringResource(R.string.full_screen_disabled)
                    null -> stringResource(R.string.monitoring_active)
                },
                color = if (presentationIssue == null) {
                    Color(0xFFD1E0D7)
                } else {
                    Color(0xFFFFB74D)
                },
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = if (presentationIssue == null) {
                    Modifier
                } else {
                    Modifier.clickable {
                        openAlertPresentationSettings(context, presentationIssue)
                    }
                }
            )
            Text(
                text = stringResource(if (FallDiagnostics.enabled) R.string.diagnostics_on else R.string.diagnostics_off),
                fontSize = 10.sp,
                color = Color(0xFFD1E0D7),
                textAlign = TextAlign.Center,
                modifier = Modifier.clickable {
                    FallDiagnostics.setEnabled(context, !FallDiagnostics.enabled)
                }
            )
            // Debug-only fall simulation button — stripped from release builds at compile time.
            if (BuildConfig.DEBUG) {
                Spacer(modifier = Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .height(34.dp)
                        .width(152.dp)
                        .background(Color(0xFF242424), CircleShape)
                        .clickable { simulateFall(context) },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.simulate_fall_debug),
                        fontSize = 11.sp,
                        color = Color(0xFFE5694A),
                        textAlign = TextAlign.Center
                    )
                }
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

private fun openAlertPresentationSettings(
    context: Context,
    issue: AlertPresentationIssue
) {
    val intent = when (issue) {
        AlertPresentationIssue.NOTIFICATIONS_DISABLED ->
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        AlertPresentationIssue.FULL_SCREEN_DISABLED ->
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:${context.packageName}")
            }
    }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    try {
        context.startActivity(intent)
    } catch (_: Exception) {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }
}
