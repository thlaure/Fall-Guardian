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
  /// "what should happen next?" rather than "how do we talk to storage/SMS?".
  AlertCoordinator({
    required FallEventRecorder eventRecorder,
    required AlertLocationProvider locationProvider,
    required AlertNotificationGateway notificationGateway,
    required AlertBackendGateway backendGateway,
    required WatchCommandGateway watchGateway,
    required AlertLocaleResolver localeResolver,
    required Clock clock,
    required IdGenerator idGenerator,
  })  : _eventRecorder = eventRecorder,
        _locationProvider = locationProvider,
        _notificationGateway = notificationGateway,
        _backendGateway = backendGateway,
        _watchGateway = watchGateway,
        _localeResolver = localeResolver,
        _clock = clock,
        _idGenerator = idGenerator;

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
    );
  }

  static const _countdownSeconds = 30;

  final FallEventRecorder _eventRecorder;
  final AlertLocationProvider _locationProvider;
  final AlertNotificationGateway _notificationGateway;
  final AlertBackendGateway _backendGateway;
  final WatchCommandGateway _watchGateway;
  final AlertLocaleResolver _localeResolver;
  final Clock _clock;
  final IdGenerator _idGenerator;

  final _stateController = StreamController<AlertUiState>.broadcast();
  final _dismissController = StreamController<void>.broadcast();

  Timer? _timeoutTimer;
  Timer? _dismissTimer;
  AlertUiState? _currentState;
  int? _activeTimestamp;
  Duration? _countdownStartedAt;
  String? _activeClientAlertId;

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

  Future<void> startAlert(int timestamp) async {
    if (_activeTimestamp == timestamp) return;

    _cancelTimers();
    _activeTimestamp = timestamp;
    _countdownStartedAt = _clock.elapsed();
    _activeClientAlertId = _idGenerator.newId();
    _registeredWithBackend = false;
    _lastKnownPosition = null;
    _transition(timestamp, AlertPhase.countdown);

    final remainingMs = _countdownSeconds * 1000;

    // Fallback only: if the immediate registration below never lands (e.g.
    // no network at all right now), fall back to the legacy local-timeout
    // escalation once the grace window elapses.
    _timeoutTimer = Timer(
      Duration(milliseconds: remainingMs),
      () => unawaited(_handleGraceWindowElapsed(timestamp)),
    );

    // Register with the backend immediately — from here it owns the
    // cancel/grace window, so escalation still fires even if this phone
    // gets locked before the local timer above would have elapsed.
    unawaited(_registerWithBackend(timestamp, _activeClientAlertId!));
  }

  Future<void> _registerWithBackend(int timestamp, String clientAlertId) async {
    try {
      await _backendGateway.submitFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: _localeResolver.languageCode(),
        latitude: null,
        longitude: null,
      );
    } catch (_) {
      // Stay unregistered — the fallback timer will retry at grace-window
      // end, exactly like before this immediate-registration existed.
      return;
    }

    if (!_isCurrentAlert(timestamp)) return;
    _registeredWithBackend = true;
    unawaited(_attachLocationWhenAvailable(timestamp, clientAlertId));
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

    final startedAt = _countdownStartedAt;
    if (startedAt == null) return;
    final elapsedMs = (_clock.elapsed() - startedAt).inMilliseconds;
    if (elapsedMs < _countdownSeconds * 1000) return;

    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _handleGraceWindowElapsed(timestamp);
  }

  Future<void> cancelFromPhone() => _cancel(notifyWatch: true);

  Future<void> cancelFromWatch() => _cancel(notifyWatch: false);

  Future<void> _cancel({required bool notifyWatch}) async {
    final timestamp = _activeTimestamp;
    _cancelTimers();

    if (timestamp == null) {
      await _notificationGateway.cancelAll();
      _dismissController.add(null);
      return;
    }

    if (notifyWatch) {
      unawaited(_watchGateway.sendCancelAlert());
    }

    final clientAlertId = _activeClientAlertId;
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
      cancellationConfirmed =
          await _cancelRegisteredFallAlert(clientAlertId: clientAlertId);
      if (!wasRegistered) {
        cancellationConfirmed = await _recordCancelledFallAlert(
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
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
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
    _activeTimestamp = null;
    _countdownStartedAt = null;
    _activeClientAlertId = null;
    _registeredWithBackend = false;
    _lastKnownPosition = null;
    _currentState = null;
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
      alertFailedMessage: l10n.smsFailed,
      alertSubmittedMessage: l10n.alertSubmitted,
    );
    if (outcome == null || !_isCurrentAlert(timestamp)) return;

    await _finishWithOutcome(timestamp, outcome);
  }

  Future<void> _finishRegisteredAlert(int timestamp) async {
    final l10n = _localeResolver.resolve();

    await _finishWithOutcome(
      timestamp,
      _AlertOutcome(
        event: FallEvent(
          id: _idGenerator.newId(),
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
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
      _activeTimestamp = null;
      _countdownStartedAt = null;
      _activeClientAlertId = null;
      _registeredWithBackend = false;
      _lastKnownPosition = null;
      _currentState = null;
      _dismissController.add(null);
    });
  }

  Future<_AlertOutcome?> _backendEscalationOutcome({
    required String? clientAlertId,
    required int timestamp,
    required Position? position,
    required String locale,
    required String alertFailedMessage,
    required String alertSubmittedMessage,
  }) async {
    if (clientAlertId == null) {
      return null;
    }

    try {
      await _backendGateway.submitFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: locale,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
    } catch (_) {
      if (!_isCurrentAlert(timestamp)) return null;

      return _AlertOutcome(
        event: FallEvent(
          id: _idGenerator.newId(),
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
          status: FallEventStatus.alertFailed,
          latitude: position?.latitude,
          longitude: position?.longitude,
        ),
        phase: AlertPhase.alertFailed,
        message: alertFailedMessage,
        dismissDelay: const Duration(seconds: 5),
      );
    }

    if (!_isCurrentAlert(timestamp)) return null;
    _registeredWithBackend = true;

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
    );
  }

  void _cancelTimers() {
    _timeoutTimer?.cancel();
    _dismissTimer?.cancel();
  }

  bool _isCurrentAlert(int timestamp) => _activeTimestamp == timestamp;

  int get remainingCountdownSeconds {
    final startedAt = _countdownStartedAt;
    if (startedAt == null) return 0;

    final elapsedSeconds = (_clock.elapsed() - startedAt).inSeconds;
    return (_countdownSeconds - elapsedSeconds).clamp(0, _countdownSeconds);
  }

  void _transition(
    int timestamp,
    AlertPhase phase, {
    String? statusMessage,
  }) {
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
  });

  final FallEvent event;
  final AlertPhase phase;
  final String message;
  final Duration dismissDelay;
}
