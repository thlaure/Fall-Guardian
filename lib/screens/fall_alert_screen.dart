// dart:async provides Timer (for the countdown) and StreamSubscription
// (for listening to cancel events arriving from the watch).
import 'dart:async';

// Flutter's Material UI toolkit — widgets, animations, navigation, etc.
import 'package:flutter/material.dart';

// geolocator gives us the device's GPS coordinates when the alert fires.
// Position is the data class returned by the location query.
import 'package:geolocator/geolocator.dart';

// Our translated strings — all user-visible text comes from here so the app
// can display in English, French, etc. based on device language.
import '../l10n/app_localizations.dart';

// Data models and repositories
import '../models/fall_event.dart';           // Represents one fall event (id, timestamp, status, coordinates)
import '../repositories/contacts_repository.dart';    // Reads the list of emergency contacts from local storage
import '../repositories/fall_events_repository.dart'; // Persists fall event history to local storage

// Services
import '../services/location_service.dart';           // Wraps the geolocator plugin
import '../services/sms_service.dart';                // Sends SMS messages
import '../services/notification_service.dart';       // Shows / cancels OS push notifications
import '../services/watch_communication_service.dart'; // Sends cancel signal to the watch

// uuid generates universally unique IDs for each FallEvent record so that
// the history list can identify individual events unambiguously.
import 'package:uuid/uuid.dart';

// ─── Why a StatefulWidget? ───────────────────────────────────────────────────
// The screen owns a live countdown (_remaining), a pulsing animation, and a
// StreamSubscription that can dismiss the screen externally. All of these are
// mutable state that must survive widget rebuilds. StatelessWidget cannot hold
// mutable state, so StatefulWidget is the right choice here.

/// Full-screen alert shown when the watch detects a fall.
///
/// The screen displays a 30-second countdown. The user has until zero to tap
/// "Cancel". If the countdown reaches zero, an SMS is sent to every emergency
/// contact. The screen can also be dismissed by a cancel signal arriving from
/// the watch via [cancelStream].
class FallAlertScreen extends StatefulWidget {
  /// The Unix epoch timestamp (milliseconds) at the exact moment the fall was
  /// detected on the watch. Both the watch and the phone derive their remaining
  /// seconds from this shared origin, keeping the two displays in sync even if
  /// the event message was delayed in transit.
  final int fallTimestamp;

  /// A stream that emits a void event when the alert is cancelled from
  /// another device (e.g. the user taps cancel on the watch). The screen
  /// subscribes to this stream and pops itself when an event arrives.
  /// Nullable because the screen can also be used in tests without a stream.
  final Stream<void>? cancelStream;

  const FallAlertScreen({
    super.key,
    required this.fallTimestamp,
    this.cancelStream,
  });

  @override
  State<FallAlertScreen> createState() => _FallAlertScreenState();
}

// TickerProviderStateMixin is required by Flutter's animation system.
// An AnimationController needs a "vsync" source — an object that knows the
// current frame rate — to avoid wasting CPU when the screen is off.
// TickerProviderStateMixin makes this State class itself serve as that source.
class _FallAlertScreenState extends State<FallAlertScreen>
    with TickerProviderStateMixin {
  // The total countdown in seconds. This is the authoritative maximum; the
  // actual remaining time is always computed from the original timestamp.
  static const _countdownSeconds = 30;

  // ── Mutable state ─────────────────────────────────────────────────────────
  int _remaining = _countdownSeconds; // seconds left — drives the progress ring and number
  Timer? _timer;                      // periodic timer that re-computes _remaining
  StreamSubscription<void>? _cancelSub; // subscription to the external cancel stream
  bool _dismissed = false;            // true once cancel/send has started; guards against double-execution
  bool _sending = false;              // true while the SMS-send flow is in progress
  String _statusMessage = '';         // shown beneath the spinner while sending

  // ── Animation ─────────────────────────────────────────────────────────────
  // AnimationController drives the pulse animation on the warning icon.
  // Animation<double> holds the interpolated scale value at each frame.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Order matters: set up animation first, then start the countdown, then
    // subscribe to external cancel events.
    _setupPulse();
    _startCountdown();
    // Listen to the external cancel stream. Every time any event arrives
    // (the value is `void` — we don't care about the payload, only the event
    // itself), call _cancel() to dismiss the screen and stop the countdown.
    _cancelSub = widget.cancelStream?.listen((_) => _cancel());
  }

  // ── Pulse animation setup ─────────────────────────────────────────────────
  void _setupPulse() {
    _pulseController = AnimationController(
      // One full pulse cycle takes 800 ms.
      duration: const Duration(milliseconds: 800),
      // `this` works here because of TickerProviderStateMixin — the State
      // itself acts as the vsync source.
      vsync: this,
      // `..repeat(reverse: true)` chains a method call on the controller
      // immediately after construction. `reverse: true` means the animation
      // goes 0→1→0 instead of restarting abruptly, giving a smooth in-out pulse.
    )..repeat(reverse: true);

    // Tween defines the start and end values; `.animate` binds them to the
    // controller. The icon will scale between 90 % and 110 % of its natural size.
    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(_pulseController);
  }

  // ── Countdown logic ───────────────────────────────────────────────────────
  void _startCountdown() {
    // Poll at 500 ms so the display stays in sync with the watch countdown.
    // Compute remaining from the original fall timestamp so both devices
    // show the same number regardless of message delivery latency.
    //
    // Why compute from the original timestamp instead of decrementing a counter?
    // If we just did `_remaining--` every second, any clock drift or message
    // delay between the watch and the phone would cause the two displays to
    // diverge. By always subtracting from the shared `fallTimestamp`, both
    // devices are guaranteed to show the same number.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      // Guard: if the widget has been removed from the tree (e.g. navigation
      // has already popped this screen), stop the timer and do nothing.
      // Calling setState on an unmounted widget throws an error.
      if (!mounted) return;

      final elapsed =
          DateTime.now().millisecondsSinceEpoch - widget.fallTimestamp;

      // `~/ 1000` is integer division — converts milliseconds to whole seconds.
      // `.clamp(0, _countdownSeconds)` ensures the value never goes negative
      // or above 30 (e.g. if the timestamp is slightly in the future).
      final remaining =
          (_countdownSeconds - elapsed ~/ 1000).clamp(0, _countdownSeconds);

      // setState tells Flutter to rebuild the widget with the new _remaining value.
      setState(() => _remaining = remaining);

      if (_remaining <= 0) {
        // Cancel the timer first to prevent _sendAlert from being called twice
        // if the 500 ms tick fires again before the async send completes.
        timer.cancel();
        _sendAlert();
      }
    });
  }

  // ── Alert send flow (countdown reached zero) ──────────────────────────────
  //
  // Step 1: Get GPS coordinates (best-effort — may be null).
  // Step 2: Build the localised SMS message body.
  // Step 3: Load emergency contacts from SharedPreferences.
  // Step 4: Send the SMS to every contact.
  // Step 5: Persist a FallEvent record to the history log.
  // Step 6: Dismiss the OS notification (it was shown when the app was backgrounded).
  // Step 7: Show a brief confirmation message, then pop the screen.
  Future<void> _sendAlert() async {
    // Double-execution guard: if the user managed to tap Cancel at the exact
    // same moment the timer fired, _dismissed may already be true. Likewise,
    // if _sendAlert is somehow called twice, _sending prevents a second run.
    if (_dismissed || _sending) return;

    // `mounted` check after every `await` is a Flutter best practice. Between
    // any two `await` points, the user could navigate away, causing the widget
    // to be removed from the tree. Using `context` or calling `setState` on an
    // unmounted widget throws a "setState after dispose" error.
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    // Switch the UI to "sending" mode: hide the countdown, show the spinner.
    setState(() {
      _sending = true;
      _statusMessage = l10n.gettingLocation; // "Getting location…"
    });

    // Step 1 — GPS coordinates (async; may take a few seconds or return null
    // if the user denied location permission or GPS is unavailable).
    final Position? position = await LocationService().getCurrentPosition();

    // Mounted + dismissed checks after every await — see note above.
    if (_dismissed || !mounted) return;

    setState(() => _statusMessage = l10n.sendingSms); // "Sending SMS…"

    // Step 2 — Build the localised SMS body here (inside the widget) because
    // AppLocalizations requires a BuildContext, which only exists inside a widget.
    // SmsService is a plain service class with no BuildContext, so we must
    // assemble the message string before handing it off.
    final locationLine = (position != null)
        ? l10n.smsLocationLine(position.latitude, position.longitude)
        : l10n.smsLocationUnavailable;
    final smsBody = l10n.smsMessage(locationLine);

    // Step 3 — Load contacts from SharedPreferences (local device storage).
    final contacts = await ContactsRepository().getAll();

    // Step 4 — Send the SMS. Returns the list of contact names that were
    // successfully notified. An empty list means the send failed or was
    // rate-limited (to prevent accidental SMS floods on a false positive).
    final notified = await SmsService().sendFallAlert(
      contacts: contacts,
      message: smsBody,
    );
    if (_dismissed || !mounted) return;

    // Step 5 — Persist to history so the HomeScreen can show a log of events.
    // smsFailed = we had contacts but none received the SMS.
    final smsFailed = contacts.isNotEmpty && notified.isEmpty;
    final event = FallEvent(
      id: const Uuid().v4(), // universally unique ID
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status:
          smsFailed ? FallEventStatus.alertFailed : FallEventStatus.alertSent,
      latitude: position?.latitude,
      longitude: position?.longitude,
      notifiedContacts: notified,
    );
    await FallEventsRepository().add(event);

    // Step 6 — Dismiss the OS-level heads-up notification that was shown when
    // the app was backgrounded. The alert has now been handled; we no longer
    // want it cluttering the notification shade.
    await NotificationService().cancelAll();
    if (!mounted) return;

    // Step 7 — Show a brief result message, then pop the screen.
    setState(
      () => _statusMessage =
          smsFailed ? l10n.smsFailed : l10n.alertSentCount(notified.length),
    );

    // Hold the result on screen briefly so the user can read it.
    // Show the failure message for 5 s (there is more to read) and the
    // success message for 2 s (a quick confirmation is enough).
    await Future.delayed(Duration(seconds: smsFailed ? 5 : 2));
    if (mounted) Navigator.of(context).pop();
  }

  // ── Cancel flow (user tapped Cancel OR remote cancel from watch) ──────────
  //
  // Steps:
  //   1. Stop the countdown timer.
  //   2. Mark as dismissed so _sendAlert cannot start.
  //   3. Tell the watch to also dismiss its alert (fire-and-forget).
  //   4. Persist a "cancelled" FallEvent to history.
  //   5. Dismiss any lingering OS notification.
  //   6. Pop this screen.
  Future<void> _cancel() async {
    // Step 1 — Immediately stop the periodic timer so no further ticks fire.
    _timer?.cancel();

    // Step 2 — Set the guard flag so _sendAlert (if it somehow fires) will exit.
    // We call setState here so the UI reflects the cancellation (the countdown
    // disappears and the button becomes inactive).
    setState(() => _dismissed = true);

    // Step 3 — Forward the cancel to the watch.
    // `unawaited` explicitly marks that we are not waiting for the result.
    // The cancel signal to the watch is best-effort: if the watch is out of
    // range, the alert will simply time out on the watch side, which is
    // acceptable. We must not block the UI while waiting for a network round-trip.
    unawaited(WatchCommunicationService.sendCancelAlert());

    // Step 4 — Log a "cancelled" event to the history.
    final event = FallEvent(
      id: const Uuid().v4(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status: FallEventStatus.cancelled,
      // No location or notifiedContacts — the alert was cancelled before sending.
    );
    await FallEventsRepository().add(event);

    // Step 5 — Remove any OS notification that was shown when the app was backgrounded.
    await NotificationService().cancelAll();

    // Step 6 — Return to the previous screen (HomeScreen).
    // `mounted` guard because FallEventsRepository().add is async — the widget
    // might have been removed from the tree in the meantime.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Always cancel timers and subscriptions in dispose() to prevent them from
    // firing after the widget is gone, which would cause runtime errors.
    _timer?.cancel();
    _cancelSub?.cancel();
    // AnimationControllers must also be disposed to release the vsync ticker.
    _pulseController.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Progress goes from 1.0 (full, 30 s left) to 0.0 (empty, 0 s left).
    // The CircularProgressIndicator uses this to draw the shrinking arc.
    final progress = _remaining / _countdownSeconds;

    return PopScope(
      // canPop: false disables the system back gesture/button while the alert
      // is active. This prevents the user from accidentally swiping away the
      // screen and missing the countdown. The only way to leave is by tapping
      // "Cancel" (programmatic Navigator.pop) or letting the timer run out.
      canPop: false,
      child: Scaffold(
        // Deep red background — intentionally alarming to grab attention.
        // 0xFF = fully opaque; 0x1A0000 = very dark red.
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          // SafeArea insets the content so it doesn't overlap the status bar
          // (top of screen) or home indicator (bottom of screen on notchless phones).
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Pulsing warning icon ──────────────────────────────────
                // ScaleTransition rebuilds every animation frame with a new
                // scale value derived from _pulseAnimation (0.9 ↔ 1.1).
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Title & body text ─────────────────────────────────────
                Text(
                  l10n.fallAlertTitle, // e.g. "Fall Detected!"
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.fallAlertBody, // e.g. "Tap Cancel if you are OK"
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // ── Conditional body: spinner OR countdown + cancel button ─
                // Once _sendAlert starts (_sending = true), replace the
                // interactive countdown with a progress spinner and status text.
                // The user can no longer cancel at this point — the SMS is already
                // on its way.
                _sending
                    ? Column(
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage, // "Getting location…" or "Sending SMS…"
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // ── Countdown ring ────────────────────────────────
                          // Stack layers widgets on top of each other.
                          // Layer 1 (bottom): the circular progress arc.
                          // Layer 2 (top):    the remaining-seconds number.
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: CircularProgressIndicator(
                                  // `value` between 0.0 and 1.0: the filled fraction.
                                  value: progress,
                                  strokeWidth: 8,
                                  // Faint white background arc so the ring doesn't
                                  // look broken when almost empty.
                                  backgroundColor: Colors.white12,
                                  // Turn the ring bright red in the final 10 seconds
                                  // to signal increasing urgency.
                                  color: _remaining <= 10
                                      ? Colors.redAccent
                                      : const Color(0xFFE5694A), // brand orange
                                ),
                              ),
                              // Large digit centred inside the ring.
                              Text(
                                '$_remaining',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 48),

                          // ── Cancel button ─────────────────────────────────
                          // Green = safe / "I'm OK". Made deliberately large
                          // (60 px tall) so it's easy to tap in a stressful moment.
                          SizedBox(
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _cancel,
                              icon: const Icon(Icons.check_circle, size: 28),
                              label: Text(
                                l10n.cancelAlert, // "I'm OK – Cancel"
                                style: const TextStyle(fontSize: 18),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
