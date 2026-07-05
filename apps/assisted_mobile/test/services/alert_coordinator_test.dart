import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/alert_runtime.dart';

class _FakeFallEventsRepository implements FallEventRecorder {
  final List<FallEvent> savedEvents = [];

  @override
  Future<void> add(FallEvent event) async {
    savedEvents.add(event);
  }
}

class _FakeLocationService implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _FakeLocationServiceWithPosition implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => Position(
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

class _FakeNotificationService implements AlertNotificationGateway {
  int cancelCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }
}

/// Fake backend gateway with enough knobs to deterministically exercise the
/// immediate-registration / fallback / race scenarios in AlertCoordinator:
///   - [shouldFail] makes every submitFallAlert call fail (models "no
///     connectivity at all", both the immediate attempt and the fallback).
///   - [failFirstSubmitOnly] fails exactly the first submitFallAlert call and
///     succeeds afterwards (models "recovers by the time the fallback runs").
///   - [submitCompleter] makes submitFallAlert (when it would otherwise
///     succeed) wait for this completer before resolving, to deterministically
///     hold a "still registering" window open for race tests.
class _FakeBackendGateway implements AlertBackendGateway {
  _FakeBackendGateway({
    this.shouldFail = false,
    this.failFirstSubmitOnly = false,
    this.cancelShouldFail = false,
    this.recordCancelledShouldFail = false,
    this.submitCompleter,
    this.cancelCompleter,
  });

  final bool shouldFail;
  final bool failFirstSubmitOnly;
  final bool cancelShouldFail;
  final bool recordCancelledShouldFail;
  final Completer<void>? submitCompleter;
  final Completer<void>? cancelCompleter;

  String? lastClientAlertId;
  String? lastLocale;
  int? lastTimestamp;
  double? lastLatitude;
  double? lastLongitude;
  int cancelCount = 0;
  int callCount = 0;
  int cancelledRecordCount = 0;
  int attachLocationCount = 0;
  double? lastAttachLatitude;
  double? lastAttachLongitude;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> syncContacts(List<Contact> contacts) async {}

  @override
  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    callCount++;
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;

    if (shouldFail || (failFirstSubmitOnly && callCount == 1)) {
      throw Exception('backend unavailable');
    }

    await submitCompleter?.future;
  }

  @override
  Future<void> recordCancelledFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    cancelledRecordCount++;
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;

    if (recordCancelledShouldFail) {
      throw Exception('backend unavailable');
    }
  }

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {
    cancelCount++;
    await cancelCompleter?.future;

    if (cancelShouldFail) {
      throw Exception('backend unavailable');
    }
  }

  @override
  Future<void> attachLocation({
    required String clientAlertId,
    required double latitude,
    required double longitude,
  }) async {
    attachLocationCount++;
    lastAttachLatitude = latitude;
    lastAttachLongitude = longitude;
  }
}

class _FakeWatchGateway implements WatchCommandGateway {
  int cancelCount = 0;

  @override
  Future<void> sendCancelAlert() async {
    cancelCount++;
  }
}

class _FakeClock implements Clock {
  _FakeClock([DateTime? initialNow]) : _now = initialNow ?? DateTime.now();

  DateTime _now;

  @override
  DateTime now() => _now;

  void setNow(DateTime value) {
    _now = value;
  }
}

class _FakeIdGenerator implements IdGenerator {
  int _next = 0;

  @override
  String newId() => 'id-${_next++}';
}

AlertCoordinator _coordinator({
  FallEventRecorder? eventRecorder,
  AlertLocationProvider? locationProvider,
  AlertNotificationGateway? notificationGateway,
  AlertBackendGateway? backendGateway,
  WatchCommandGateway? watchGateway,
  AlertLocaleResolver? localeResolver,
  Clock? clock,
  IdGenerator? idGenerator,
}) {
  return AlertCoordinator(
    eventRecorder: eventRecorder ?? _FakeFallEventsRepository(),
    locationProvider: locationProvider ?? _FakeLocationService(),
    notificationGateway: notificationGateway ?? _FakeNotificationService(),
    backendGateway: backendGateway ?? _FakeBackendGateway(),
    watchGateway: watchGateway ?? _FakeWatchGateway(),
    localeResolver: localeResolver ?? const DeviceLocaleResolver(),
    clock: clock ?? _FakeClock(),
    idGenerator: idGenerator ?? _FakeIdGenerator(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      null,
    );
  });

  test('startAlert enters countdown phase', () async {
    final coordinator = _coordinator();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    expect(coordinator.currentState?.fallTimestamp, timestamp);
    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(coordinator.currentState?.isSending, isFalse);

    coordinator.dispose();
  });

  test(
      'startAlert registers with the backend immediately, without waiting '
      'for the countdown', () async {
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(backendGateway: backend);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);

    // Registration must not block on GPS — it goes out with no location.
    expect(backend.callCount, 1);
    expect(backend.lastLatitude, isNull);
    expect(backend.lastLongitude, isNull);
    // Still mid-countdown from the UI's perspective; the visual 30s ring is
    // unaffected by backend registration timing.
    expect(coordinator.currentState?.phase, AlertPhase.countdown);

    coordinator.dispose();
  });

  test(
      'startAlert attaches location once it resolves, after registration '
      'already went out', () async {
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      backendGateway: backend,
      locationProvider: _FakeLocationServiceWithPosition(),
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);

    expect(backend.callCount, 1);
    expect(backend.lastLatitude, isNull, reason: 'submit never waits on GPS');
    expect(backend.attachLocationCount, 1);
    expect(backend.lastAttachLatitude, 48.8566);
    expect(backend.lastAttachLongitude, 2.3522);

    coordinator.dispose();
  });

  test(
      'grace window elapsing after successful registration just finalises '
      'the UI locally, without submitting again', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      locationProvider: _FakeLocationServiceWithPosition(),
    );
    final sub = coordinator.stateStream.listen(states.add);

    // fallTimestamp far enough in the past that the local fallback timer
    // fires almost immediately — but since registration succeeds first
    // (see startAlert), the fallback timer must take the fast path.
    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1, reason: 'no second submission needed');
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(repo.savedEvents.single.latitude, 48.8566);
    expect(repo.savedEvents.single.longitude, 2.3522);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'grace window elapsing without a successful registration falls back '
      'to fetching location and submitting one more time', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway(failFirstSubmitOnly: true);
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      locationProvider: _FakeLocationServiceWithPosition(),
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // First call (immediate registration) failed; fallback attempt succeeded.
    expect(backend.callCount, 2);
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'grace window elapsing with no connectivity at all records alertFailed '
      'after trying twice', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway(shouldFail: true);
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 2);
    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertFailed,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('reconcileActiveAlert triggers the fast path after lifecycle pause',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final clock = _FakeClock(DateTime(2026, 4, 19, 12, 0, 0));
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);
    await Future<void>.delayed(Duration.zero);
    expect(backend.callCount, 1, reason: 'registered immediately at t=0');

    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1, reason: 'no second submission needed');
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelFromWatch does not send cancel back to watch', () async {
    final watchCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async {
        watchCalls.add(call);
        return null;
      },
    );

    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);
    await coordinator.cancelFromWatch();

    expect(
      watchCalls.where((call) => call.method == 'sendCancelAlert'),
      isEmpty,
    );
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(coordinator.currentState, isNull);
    expect(notifications.cancelCount, 1);

    coordinator.dispose();
  });

  test('cancelFromWatch emits cancelled phase before dismissal', () async {
    final states = <AlertUiState>[];
    final coordinator = _coordinator();
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromWatch();

    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.cancelled,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'cancelling once registration already succeeded always cancels via '
      'cancelFallAlert, with no local pre-emptive record', () async {
    final repo = _FakeFallEventsRepository();
    final watchGateway = _FakeWatchGateway();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      watchGateway: watchGateway,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);
    expect(backend.callCount, 1, reason: 'registered before cancelling');

    await coordinator.cancelFromPhone();

    expect(watchGateway.cancelCount, 1);
    expect(backend.cancelCount, 1);
    expect(backend.cancelledRecordCount, 0);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(backend.lastClientAlertId, 'id-0');

    coordinator.dispose();
  });

  test(
      'cancelling before registration is known to have succeeded cancels '
      'defensively AND records a cancelled event locally', () async {
    final submitCompleter = Completer<void>();
    final backend = _FakeBackendGateway(submitCompleter: submitCompleter);
    final coordinator = _coordinator(backendGateway: backend);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    // Registration is deliberately still in flight (submitCompleter unresolved).
    await Future<void>.delayed(Duration.zero);
    expect(backend.callCount, 1);

    await coordinator.cancelFromPhone();

    // Defensive cancel (idempotent/404-safe if it never lands) AND the local
    // "cancelled" record, closing the race either way.
    expect(backend.cancelCount, 1);
    expect(backend.cancelledRecordCount, 1);

    submitCompleter.complete();
    coordinator.dispose();
  });

  test('cancelFromPhone waits for the cancel call to finish before resolving',
      () async {
    final backendCompleter = Completer<void>();
    final backend = _FakeBackendGateway(cancelCompleter: backendCompleter);
    final coordinator = _coordinator(backendGateway: backend);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);

    var completed = false;
    final cancelFuture = coordinator.cancelFromPhone().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(backend.cancelCount, 1);
    expect(completed, isFalse);

    backendCompleter.complete();
    await cancelFuture;

    expect(completed, isTrue);

    coordinator.dispose();
  });

  test(
      'cancelling while the grace window has already elapsed prevents a '
      'concurrent reconcileActiveAlert from also escalating', () async {
    final backendCompleter = Completer<void>();
    final backend = _FakeBackendGateway(cancelCompleter: backendCompleter);
    final clock = _FakeClock(DateTime(2026, 6, 16, 9, 45));
    final coordinator = _coordinator(backendGateway: backend, clock: clock);

    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);
    await Future<void>.delayed(Duration.zero);
    final callsBeforeCancel = backend.callCount;

    final cancelFuture = coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();

    expect(backend.callCount, callsBeforeCancel, reason: 'no extra submit');

    backendCompleter.complete();
    await cancelFuture;

    coordinator.dispose();
  });

  test(
      'cancelFromPhone still finishes locally even when the backend cancel '
      'call fails', () async {
    final repo = _FakeFallEventsRepository();
    final backend = _FakeBackendGateway(cancelShouldFail: true);
    final coordinator = _coordinator(eventRecorder: repo, backendGateway: backend);
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);

    await coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    expect(backend.cancelCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(dismissed, isTrue);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'cancelFromPhone still finishes locally even when the pre-registration '
      'cancelled-record call fails', () async {
    final repo = _FakeFallEventsRepository();
    final submitCompleter = Completer<void>();
    final backend = _FakeBackendGateway(
      submitCompleter: submitCompleter,
      recordCancelledShouldFail: true,
    );
    final coordinator = _coordinator(eventRecorder: repo, backendGateway: backend);
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);

    await coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    expect(backend.cancelledRecordCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(dismissed, isTrue);

    submitCompleter.complete();
    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelFromPhone with no active alert clears notifications only',
      () async {
    final notifications = _FakeNotificationService();
    final coordinator = _coordinator(notificationGateway: notifications);
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.cancelFromPhone();
    await Future<void>.delayed(Duration.zero);

    expect(notifications.cancelCount, 1);
    expect(dismissed, isTrue);
    expect(coordinator.currentState, isNull);

    await sub.cancel();
    coordinator.dispose();
  });

  test('the fast-path alertSent outcome dismisses itself after the usual delay',
      () async {
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      notificationGateway: notifications,
      backendGateway: backend,
    );
    var dismissed = false;
    final sub = coordinator.dismissStream.listen((_) => dismissed = true);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(coordinator.currentState?.phase, AlertPhase.alertSent);
    expect(dismissed, isFalse);

    await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 200));

    expect(dismissed, isTrue);
    expect(coordinator.currentState, isNull);

    await sub.cancel();
    coordinator.dispose();
  });

  test(
      'fallback timeout with a real position submits lat/lng and records '
      'them locally on failure', () async {
    final repo = _FakeFallEventsRepository();
    final coordinator = _coordinator(
      locationProvider: _FakeLocationServiceWithPosition(),
      eventRecorder: repo,
      backendGateway: _FakeBackendGateway(shouldFail: true),
    );

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(repo.savedEvents.single.latitude, 48.8566);
    expect(repo.savedEvents.single.longitude, 2.3522);

    coordinator.dispose();
  });
}
