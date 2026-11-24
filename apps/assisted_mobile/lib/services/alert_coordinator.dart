import 'dart:async';
import 'dart:developer' as developer;

import 'package:geolocator/geolocator.dart';

import '../models/fall_event.dart';
import 'alert_ports.dart';
import 'alert_runtime.dart';
import 'backend_api_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import '../repositories/fall_events_repository.dart';

enum AlertPhase {
  countdown,
  gettingLocation,
  sendingAlert,
  alertSent,
  alertFailed,
  timedOutNoSms,
  cancelling,
  cancelled,
  cancellationUnconfirmed,
}

class AlertUiState {
  final int fallTimestamp;
  final AlertPhase phase;
  final String? statusMessage;

  const AlertUiState({
    required this.fallTimestamp,
    required this.phase,
    this.statusMessage,
  });

  bool get isSending =>
      phase == AlertPhase.gettingLocation ||
      phase == AlertPhase.sendingAlert ||
      phase == AlertPhase.alertSent ||
      phase == AlertPhase.alertFailed ||
      phase == AlertPhase.timedOutNoSms ||
      phase == AlertPhase.cancelling ||
      phase == AlertPhase.cancellationUnconfirmed;
}

class AlertCoordinator {
  /// The alert workflow is intentionally written in terms of ports instead of
  /// concrete repositories/plugins. That keeps this class focused on
  /// "what should happen next?" rather than "how do we talk to storage/push?".
  AlertCoordinator({
    required this._eventRecorder,
    required this._locationProvider,
    required this._notificationGateway,
    required this._backendGateway,
    required this._watchGateway,
    required this._localeResolver,
    required this._clock,
    required this._idGenerator,
    DurableAlertQueue? durableQueue,
  }) : _durableQueue = durableQueue ?? const _NoDurableAlertQueue();

  factory AlertCoordinator.live() {
    return AlertCoordinator(
      eventRecorder: FallEventsRepository(),
      locationProvider: LocationService(),
      notificationGateway: NotificationService(),
      backendGateway: BackendApiService(),
      watchGateway: const MethodChannelWatchGateway(),
      localeResolver: const DeviceLocaleResolver(),
      clock: SystemClock(),
      idGenerator: const UuidGenerator(),
      durableQueue: const MethodChannelDurableAlertQueue(),
    );
  }

  static const _countdownSeconds = 30;
  static const _graceWindow = Duration(seconds: _countdownSeconds);

  final FallEventRecorder _eventRecorder;
  final AlertLocationProvider _locationProvider;
  final AlertNotificationGateway _notificationGateway;
  final AlertBackendGateway _backendGateway;
  final WatchCommandGateway _watchGateway;
  final AlertLocaleResolver _localeResolver;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final DurableAlertQueue _durableQueue;

  final _stateController = StreamController<AlertUiState>.broadcast();
  final _dismissController = StreamController<void>.broadcast();

  Timer? _timeoutTimer;
  Timer? _dismissTimer;
  AlertUiState? _currentState;
  int? _activeTimestamp;
  String? _activeClientAlertId;

  // Monotonic-clock instant (see [Clock.elapsed]) at which the cancellation
  // window closes. Until the backend answers it is derived from the fall
  // timestamp (fallTimestamp + 30 s); once the API accepted the alert it is
  // replaced by the server-owned cancelDeadlineAt, which is what actually
  // gates caregiver dispatch.
  Duration? _deadline;

  // Set when the backend rejected this phone's credentials: caregivers can
  // NOT be notified until the user re-pairs. Never hidden behind "sent".
  bool _repairRequired = false;

  // True once the immediate registration below has landed on the backend —
  // from that point the backend owns the cancel/grace window and will
  // dispatch the caregiver push itself, so this phone no longer needs to
  // stay alive for the rest of the countdown.
  bool _registeredWithBackend = false;

  // Best-effort GPS fix attached to the backend alert once it resolves.
  // Reused for the local FallEvent record too, purely for display purposes.
  Position? _lastKnownPosition;

  Stream<AlertUiState> get stateStream => _stateController.stream;
  Stream<void> get dismissStream => _dismissController.stream;
  AlertUiState? get currentState => _currentState;

  Future<bool> startAlert(int timestamp, {String? clientAlertId}) async {
    // One unresolved incident owns one fixed grace-window deadline. Sensor
    // re-triggers and duplicate watch transports must not replace it, restart
    // its timer, or create another backend alert.
    if (_activeTimestamp != null) return false;

    _cancelTimers();
    _activeTimestamp = timestamp;
    _activeClientAlertId = switch (clientAlertId?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => _idGenerator.newId(),
    };
    _registeredWithBackend = false;
    _repairRequired = false;
    _lastKnownPosition = null;
    _transition(timestamp, AlertPhase.countdown);

    // Fallback deadline until the server answers: the window opened when the
    // fall was detected, not when this phone heard about it.
    _setDeadline(timestamp, _clock.elapsed() + _fallbackRemaining(timestamp));

    unawaited(_persistThenRegister(timestamp, _activeClientAlertId!));
    return true;
  }

  Duration _fallbackRemaining(int timestamp) {
    final ageMs = _clock.now().millisecondsSinceEpoch - timestamp;
    // A timestamp from the future (watch clock ahead) never extends the
    // window beyond 30 s; a very old one never yields negative time.
    final clampedAgeMs = ageMs.clamp(0, _graceWindow.inMilliseconds);
    return _graceWindow - Duration(milliseconds: clampedAgeMs);
  }

  /// (Re)arms the local timer for [deadline]. When it fires either the
  /// backend already owns escalation (UI just finalises) or the fallback
  /// submission runs.
  void _setDeadline(int timestamp, Duration deadline) {
    _deadline = deadline;
    _timeoutTimer?.cancel();
    final delay = deadline - _clock.elapsed();
    _timeoutTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_handleGraceWindowElapsed(timestamp)),
    );
  }

  void _applyReceipt(int timestamp, FallAlertReceipt? receipt) {
    if (receipt == null || !_isCurrentAlert(timestamp)) return;
    // The receipt's remaining time is measured on the server clock and
    // anchored here on the monotonic clock, so clock skew cannot shift it.
    _setDeadline(timestamp, _clock.elapsed() + receipt.remainingGrace);
  }

  Future<void> _persistThenRegister(int timestamp, String clientAlertId) async {
    // Persist before any network attempt so the native relay (JobScheduler /
    // BGTaskScheduler) keeps retrying even if this process dies right now.
    try {
      await _durableQueue.enqueue(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Durable alert enqueue failed; relying on in-process submission',
        name: 'AlertCoordinator',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!_isCurrentAlert(timestamp)) return;
    await _registerWithBackend(timestamp, clientAlertId);
  }

  Future<void> _registerWithBackend(int timestamp, String clientAlertId) async {
    final FallAlertReceipt? receipt;
    try {
      receipt = await _backendGateway.submitFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: _localeResolver.languageCode(),
        latitude: null,
        longitude: null,
      );
    } on DeviceRepairRequiredException {
      _flagRepairRequired(timestamp);
      return;
    } catch (_) {
      // Stay unregistered — the fallback timer will retry at grace-window
      // end, exactly like before this immediate-registration existed.
      return;
    }

    if (!_isCurrentAlert(timestamp)) return;
    _registeredWithBackend = true;
    _applyReceipt(timestamp, receipt);
    unawaited(_attachLocationWhenAvailable(timestamp, clientAlertId));
  }

  /// Keeps the countdown (the user may still cancel) but tells them right
  /// away that caregivers will not be reached until the phone is re-paired.
  void _flagRepairRequired(int timestamp) {
    if (!_isCurrentAlert(timestamp)) return;
    _repairRequired = true;
    if (_currentState?.phase == AlertPhase.countdown) {
      _transition(
        timestamp,
        AlertPhase.countdown,
        statusMessage: _localeResolver.resolve().alertRepairRequired,
      );
    }
  }

  Future<void> _attachLocationWhenAvailable(
    int timestamp,
    String clientAlertId,
  ) async {
    final position = await _locationProvider.getCurrentPosition();
    if (position == null || !_isCurrentAlert(timestamp)) return;

    _lastKnownPosition = position;
    try {
      await _backendGateway.attachLocation(
        clientAlertId: clientAlertId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Best-effort enhancement data only — the alert itself is already
      // registered regardless of whether this call succeeds.
    }
  }

  /// Reconciles the active alert after lifecycle interruptions such as the app
  /// being backgrounded long enough for Dart timers to pause.
  Future<void> reconcileActiveAlert() async {
    final timestamp = _activeTimestamp;
    if (timestamp == null) return;
    if (_currentState?.phase != AlertPhase.countdown) return;

    final deadline = _deadline;
    if (deadline == null || _clock.elapsed() < deadline) return;

    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _handleGraceWindowElapsed(timestamp);
  }

  Future<void> cancelFromPhone() => _cancel(notifyWatch: true);

  /// A watch cancel may name its incident ([incidentId] and/or
  /// [fallTimestamp]). Then only a matching active alert is cancelled; a
  /// cancel for another (older) incident must never dismiss this one. Without
  /// a target (legacy watches) the active alert is cancelled.
  Future<void> cancelFromWatch({String? incidentId, int? fallTimestamp}) {
    final targeted =
        (incidentId?.trim().isNotEmpty ?? false) || fallTimestamp != null;
    if (targeted &&
        _activeTimestamp != null &&
        !_matchesActive(incidentId, fallTimestamp)) {
      developer.log(
        'Ignoring watch cancel for a different incident',
        name: 'AlertCoordinator',
      );
      return Future<void>.value();
    }
    return _cancel(notifyWatch: false);
  }

  bool _matchesActive(String? incidentId, int? fallTimestamp) {
    final id = incidentId?.trim().toLowerCase();
    final activeId = _activeClientAlertId?.toLowerCase();
    if (id != null && id.isNotEmpty && id == activeId) return true;
    return fallTimestamp != null && fallTimestamp == _activeTimestamp;
  }

  Future<void> _cancel({required bool notifyWatch}) async {
    final timestamp = _activeTimestamp;
    _cancelTimers();

    if (timestamp == null) {
      await _notificationGateway.cancelAll();
      _dismissController.add(null);
      return;
    }

    final clientAlertId = _activeClientAlertId;
    if (notifyWatch) {
      unawaited(
        _watchGateway.sendCancelAlert(
          incidentId: clientAlertId,
          fallTimestamp: timestamp,
        ),
      );
    }

    final wasRegistered = _registeredWithBackend;
    final l10n = _localeResolver.resolve();
    _transition(
      timestamp,
      AlertPhase.cancelling,
      statusMessage: l10n.confirmingCancellation,
    );

    var cancellationConfirmed = false;
    if (clientAlertId != null) {
      // Always attempt the real cancel — it's idempotent/404-safe if the
      // alert never actually landed server-side. When this phone doesn't
      // yet know registration succeeded, also record a cancelled event so
      // there's still a backend record if it truly never got through.
      cancellationConfirmed = await _cancelRegisteredFallAlert(
        clientAlertId: clientAlertId,
      );
      if (!wasRegistered) {
        cancellationConfirmed =
            await _recordCancelledFallAlert(
              clientAlertId: clientAlertId,
              timestamp: timestamp,
            ) ||
            cancellationConfirmed;
      }
    }

    if (!cancellationConfirmed) {
      await _finishWithOutcome(
        timestamp,
        _AlertOutcome(
          event: FallEvent(
            id: _idGenerator.newId(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ),
            status: FallEventStatus.cancellationPending,
          ),
          phase: AlertPhase.cancellationUnconfirmed,
          message: l10n.cancellationUnconfirmed,
          dismissDelay: const Duration(seconds: 5),
        ),
      );
      return;
    }

    final event = FallEvent(
      id: _idGenerator.newId(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      status: FallEventStatus.cancelled,
    );
    await _eventRecorder.add(event);
    await _notificationGateway.cancelAll();
    if (!_isCurrentAlert(timestamp)) return;
    _transition(timestamp, AlertPhase.cancelled);
    _clearActiveAlert();
    _dismissController.add(null);
  }

  Future<bool> _cancelRegisteredFallAlert({
    required String clientAlertId,
  }) async {
    try {
      await _backendGateway.cancelFallAlert(clientAlertId: clientAlertId);
      return true;
    } catch (error, stackTrace) {
      // Never claim a safety-critical cancellation succeeded unless backend
      // confirmed it. The caller keeps the alert on the safe escalation path.
      developer.log(
        'cancelFallAlert failed for $clientAlertId',
        name: 'AlertCoordinator',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> _recordCancelledFallAlert({
    required String clientAlertId,
    required int timestamp,
  }) async {
    try {
      await _backendGateway.recordCancelledFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: _localeResolver.languageCode(),
        latitude: null,
        longitude: null,
      );
      return true;
    } catch (error, stackTrace) {
      // Same fail-safe rule as the direct cancel path: an unconfirmed
      // cancellation is treated as potentially dispatched.
      developer.log(
        'recordCancelledFallAlert failed for $clientAlertId',
        name: 'AlertCoordinator',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Called once the 30s grace window elapses, either by the local fallback
  /// timer or by [reconcileActiveAlert] catching up after a backgrounding.
  Future<void> _handleGraceWindowElapsed(int timestamp) async {
    if (!_isCurrentAlert(timestamp) ||
        _currentState?.phase != AlertPhase.countdown) {
      return;
    }

    if (_registeredWithBackend) {
      // Already registered immediately at t=0 (see startAlert) — the
      // backend owns escalation from here. This is just the local "we're
      // done" UI transition; no second submission needed.
      await _finishRegisteredAlert(timestamp);
      return;
    }

    // Fallback: the immediate registration never landed (e.g. no network at
    // all when the fall was detected). Do exactly what the fully
    // client-owned flow used to do — fetch location and try one last time.
    final l10n = _localeResolver.resolve();
    final clientAlertId = _activeClientAlertId;
    _transition(
      timestamp,
      AlertPhase.gettingLocation,
      statusMessage: l10n.gettingLocation,
    );

    final Position? position = await _locationProvider.getCurrentPosition();
    if (!_isCurrentAlert(timestamp)) return;

    _transition(
      timestamp,
      AlertPhase.sendingAlert,
      statusMessage: l10n.sendingAlert,
    );

    final outcome = await _backendEscalationOutcome(
      clientAlertId: clientAlertId,
      timestamp: timestamp,
      position: position,
      locale: _localeResolver.languageCode(),
      alertFailedMessage: l10n.alertSubmissionFailed,
      alertSubmittedMessage: l10n.alertSubmitted,
      repairRequiredMessage: l10n.alertRepairRequired,
    );
    if (outcome == null || !_isCurrentAlert(timestamp)) return;

    final remaining = outcome.serverRemainingGrace;
    if (remaining != null && remaining > Duration.zero) {
      // The alert reached the server late (e.g. the phone was offline), so
      // the server grace period is still open: the user can still cancel.
      _transition(timestamp, AlertPhase.countdown);
      _setDeadline(timestamp, _clock.elapsed() + remaining);
      return;
    }

    await _finishWithOutcome(timestamp, outcome);
  }

  Future<void> _finishRegisteredAlert(int timestamp) async {
    final l10n = _localeResolver.resolve();

    await _finishWithOutcome(
      timestamp,
      _AlertOutcome(
        event: FallEvent(
          id: _idGenerator.newId(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
          status: FallEventStatus.alertSent,
          latitude: _lastKnownPosition?.latitude,
          longitude: _lastKnownPosition?.longitude,
        ),
        phase: AlertPhase.alertSent,
        message: l10n.alertSubmitted,
        dismissDelay: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _finishWithOutcome(int timestamp, _AlertOutcome outcome) async {
    await _eventRecorder.add(outcome.event);
    await _notificationGateway.cancelAll();
    if (!_isCurrentAlert(timestamp)) return;

    _transition(timestamp, outcome.phase, statusMessage: outcome.message);

    _dismissTimer = Timer(outcome.dismissDelay, () {
      if (!_isCurrentAlert(timestamp)) return;
      _clearActiveAlert();
      _dismissController.add(null);
    });
  }

  void _clearActiveAlert() {
    _activeTimestamp = null;
    _deadline = null;
    _activeClientAlertId = null;
    _registeredWithBackend = false;
    _repairRequired = false;
    _lastKnownPosition = null;
    _currentState = null;
  }

  Future<_AlertOutcome?> _backendEscalationOutcome({
    required String? clientAlertId,
    required int timestamp,
    required Position? position,
    required String locale,
    required String alertFailedMessage,
    required String alertSubmittedMessage,
    required String repairRequiredMessage,
  }) async {
    if (clientAlertId == null) {
      return null;
    }

    final FallAlertReceipt? receipt;
    try {
      receipt = await _backendGateway.submitFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: locale,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
    } catch (error) {
      if (!_isCurrentAlert(timestamp)) return null;
      final repairRequired =
          error is DeviceRepairRequiredException || _repairRequired;

      return _AlertOutcome(
        event: FallEvent(
          id: _idGenerator.newId(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
          status: FallEventStatus.alertFailed,
          latitude: position?.latitude,
          longitude: position?.longitude,
        ),
        phase: AlertPhase.alertFailed,
        message: repairRequired ? repairRequiredMessage : alertFailedMessage,
        // Leave the "caregivers were NOT notified" explanation up longer.
        dismissDelay: Duration(seconds: repairRequired ? 15 : 5),
      );
    }

    if (!_isCurrentAlert(timestamp)) return null;
    _registeredWithBackend = true;
    _repairRequired = false;

    return _AlertOutcome(
      event: FallEvent(
        id: _idGenerator.newId(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        status: FallEventStatus.alertSent,
        latitude: position?.latitude,
        longitude: position?.longitude,
      ),
      phase: AlertPhase.alertSent,
      message: alertSubmittedMessage,
      dismissDelay: const Duration(seconds: 2),
      serverRemainingGrace: receipt?.remainingGrace,
    );
  }

  void _cancelTimers() {
    _timeoutTimer?.cancel();
    _dismissTimer?.cancel();
  }

  bool _isCurrentAlert(int timestamp) => _activeTimestamp == timestamp;

  /// Whole seconds left in the cancellation window, never negative.
  int get remainingCountdownSeconds {
    final deadline = _deadline;
    if (deadline == null) return 0;

    final remainingMs = (deadline - _clock.elapsed()).inMilliseconds;
    if (remainingMs <= 0) return 0;
    return ((remainingMs + 999) ~/ 1000).clamp(0, _countdownSeconds);
  }

  /// True while the countdown UI is still up but the cancellation window has
  /// closed — caregivers are being notified (or about to be).
  bool get isPastDeadline {
    final deadline = _deadline;
    return deadline != null &&
        _currentState?.phase == AlertPhase.countdown &&
        _clock.elapsed() >= deadline;
  }

  /// True when the backend rejected this phone's credentials during the
  /// active alert: caregivers cannot be reached until it is re-paired.
  bool get repairRequired => _repairRequired;

  void _transition(int timestamp, AlertPhase phase, {String? statusMessage}) {
    _emit(
      AlertUiState(
        fallTimestamp: timestamp,
        phase: phase,
        statusMessage: statusMessage,
      ),
    );
  }

  void _emit(AlertUiState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() {
    _timeoutTimer?.cancel();
    _dismissTimer?.cancel();
    _stateController.close();
    _dismissController.close();
  }
}

class _AlertOutcome {
  const _AlertOutcome({
    required this.event,
    required this.phase,
    required this.message,
    required this.dismissDelay,
    this.serverRemainingGrace,
  });

  final FallEvent event;
  final AlertPhase phase;
  final String message;
  final Duration dismissDelay;
  final Duration? serverRemainingGrace;
}

class _NoDurableAlertQueue implements DurableAlertQueue {
  const _NoDurableAlertQueue();

  @override
  Future<void> enqueue({
    required String clientAlertId,
    required int fallTimestamp,
  }) async {}
}
