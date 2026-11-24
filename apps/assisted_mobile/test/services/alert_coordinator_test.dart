import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/alert_runtime.dart';
import 'package:fall_guardian/services/backend_api_service.dart';

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
    this.receipt,
    this.repairRequired = false,
    this.laterSubmitsCompleter,
    this.log,
  });

  final List<String>? log;

  /// When set, every submission after the first waits for it (models a slow
  /// fallback submission while the first registration already answered).
  final Completer<void>? laterSubmitsCompleter;

  /// Returned by successful submissions (null = API without deadline data).
  FallAlertReceipt? receipt;

  /// Every submission fails as if the API rejected the device credentials.
  final bool repairRequired;

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
  Future<FallAlertReceipt?> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    callCount++;
    log?.add('submit:$clientAlertId');
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;

    if (repairRequired) {
      throw DeviceRepairRequiredException(statusCode: 401);
    }
    if (shouldFail || (failFirstSubmitOnly && callCount == 1)) {
      throw Exception('backend unavailable');
    }

    if (callCount > 1 && laterSubmitsCompleter != null) {
      await laterSubmitsCompleter!.future;
    } else {
      await submitCompleter?.future;
    }
    return receipt;
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
  String? lastIncidentId;
  int? lastFallTimestamp;

  @override
  Future<void> sendCancelAlert({String? incidentId, int? fallTimestamp}) async {
    cancelCount++;
    lastIncidentId = incidentId;
    lastFallTimestamp = fallTimestamp;
  }
}

class _FakeDurableQueue implements DurableAlertQueue {
  _FakeDurableQueue({this.log, this.shouldFail = false});

  final List<String>? log;
  final bool shouldFail;
  final List<String> enqueuedIds = [];

  @override
  Future<void> enqueue({
    required String clientAlertId,
    required int fallTimestamp,
  }) async {
    log?.add('enqueue:$clientAlertId');
    if (shouldFail) throw Exception('native relay unavailable');
    enqueuedIds.add(clientAlertId);
  }
}

class _FakeClock implements Clock {
  _FakeClock([DateTime? initialNow]) : _now = initialNow ?? DateTime.now();

  DateTime _now;
  Duration _elapsed = Duration.zero;

  @override
  DateTime now() => _now;

  @override
  Duration elapsed() => _elapsed;

  void setNow(DateTime value) {
    _elapsed += value.difference(_now);
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
  DurableAlertQueue? durableQueue,
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
    durableQueue: durableQueue,
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
    final started = await coordinator.startAlert(timestamp);

    expect(started, isTrue);
    expect(coordinator.currentState?.fallTimestamp, timestamp);
    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(coordinator.currentState?.isSending, isFalse);

    coordinator.dispose();
  });

  test('startAlert reuses the native relay idempotency key', () async {
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(backendGateway: backend);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await coordinator.startAlert(
      timestamp,
      clientAlertId: 'wear-os-$timestamp',
    );
    await Future<void>.delayed(Duration.zero);

    expect(backend.lastClientAlertId, 'wear-os-$timestamp');
    coordinator.dispose();
  });

  test('startAlert keeps the original deadline when another detection arrives '
      'before the incident resolves', () async {
    final backend = _FakeBackendGateway();
    final clock = _FakeClock(DateTime(2026, 7, 24, 12));
    final coordinator = _coordinator(backendGateway: backend, clock: clock);
    final originalTimestamp = clock.now().millisecondsSinceEpoch;

    expect(await coordinator.startAlert(originalTimestamp), isTrue);
    await Future<void>.delayed(Duration.zero);
    clock.setNow(clock.now().add(const Duration(seconds: 12)));

    final repeatedTimestamp = clock.now().millisecondsSinceEpoch;
    expect(await coordinator.startAlert(repeatedTimestamp), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.currentState?.fallTimestamp, originalTimestamp);
    expect(coordinator.remainingCountdownSeconds, 18);
    expect(backend.callCount, 1);
    expect(backend.lastTimestamp, originalTimestamp);

    coordinator.dispose();
  });

  test('startAlert registers with the backend immediately, without waiting '
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

  test('startAlert attaches location once it resolves, after registration '
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

  test('grace window elapsing after successful registration just finalises '
      'the UI locally, without submitting again', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final clock = _FakeClock();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      locationProvider: _FakeLocationServiceWithPosition(),
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
    await Future<void>.delayed(Duration.zero);
    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
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

  test('grace window elapsing without a successful registration falls back '
      'to fetching location and submitting one more time', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway(failFirstSubmitOnly: true);
    final clock = _FakeClock();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      locationProvider: _FakeLocationServiceWithPosition(),
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
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

  test('grace window elapsing with no connectivity at all records alertFailed '
      'after trying twice', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway(shouldFail: true);
    final clock = _FakeClock();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
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

  test(
    'reconcileActiveAlert triggers the fast path after lifecycle pause',
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
    },
  );

  test('cancelFromWatch does not send cancel back to watch', () async {
    final watchCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('fall_guardian/watch'), (
          call,
        ) async {
          watchCalls.add(call);
          return null;
        });

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
    await Future<void>.delayed(Duration.zero);

    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.cancelling,
      AlertPhase.cancelled,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelling once registration already succeeded always cancels via '
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

  test('cancelling before registration is known to have succeeded cancels '
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

  test(
    'cancelFromPhone waits for the cancel call to finish before resolving',
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
    },
  );

  test('cancelling while the grace window has already elapsed prevents a '
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
    'cancelFromPhone fails safe when backend cannot confirm cancellation',
    () async {
      final repo = _FakeFallEventsRepository();
      final backend = _FakeBackendGateway(cancelShouldFail: true);
      final coordinator = _coordinator(
        eventRecorder: repo,
        backendGateway: backend,
      );
      var dismissed = false;
      final sub = coordinator.dismissStream.listen((_) => dismissed = true);

      await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
      await Future<void>.delayed(Duration.zero);

      await coordinator.cancelFromPhone();
      await Future<void>.delayed(Duration.zero);

      expect(backend.cancelCount, 1);
      expect(
        repo.savedEvents.single.status,
        FallEventStatus.cancellationPending,
      );
      expect(
        coordinator.currentState?.phase,
        AlertPhase.cancellationUnconfirmed,
      );
      expect(
        coordinator.currentState?.statusMessage,
        contains('may still be alerted'),
      );
      expect(dismissed, isFalse);

      await sub.cancel();
      coordinator.dispose();
    },
  );

  test('cancelFromPhone still finishes locally even when the pre-registration '
      'cancelled-record call fails', () async {
    final repo = _FakeFallEventsRepository();
    final submitCompleter = Completer<void>();
    final backend = _FakeBackendGateway(
      submitCompleter: submitCompleter,
      recordCancelledShouldFail: true,
    );
    final coordinator = _coordinator(
      eventRecorder: repo,
      backendGateway: backend,
    );
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

  test(
    'cancelFromPhone with no active alert clears notifications only',
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
    },
  );

  test(
    'the fast-path alertSent outcome dismisses itself after the usual delay',
    () async {
      final notifications = _FakeNotificationService();
      final backend = _FakeBackendGateway();
      final clock = _FakeClock();
      final coordinator = _coordinator(
        notificationGateway: notifications,
        backendGateway: backend,
        clock: clock,
      );
      var dismissed = false;
      final sub = coordinator.dismissStream.listen((_) => dismissed = true);

      await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
      clock.setNow(clock.now().add(const Duration(seconds: 31)));
      await coordinator.reconcileActiveAlert();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(coordinator.currentState?.phase, AlertPhase.alertSent);
      expect(dismissed, isFalse);

      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 200));

      expect(dismissed, isTrue);
      expect(coordinator.currentState, isNull);

      await sub.cancel();
      coordinator.dispose();
    },
  );

  test('fallback timeout with a real position submits lat/lng and records '
      'them locally on failure', () async {
    final repo = _FakeFallEventsRepository();
    final clock = _FakeClock();
    final coordinator = _coordinator(
      locationProvider: _FakeLocationServiceWithPosition(),
      eventRecorder: repo,
      backendGateway: _FakeBackendGateway(shouldFail: true),
      clock: clock,
    );

    await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(repo.savedEvents.single.latitude, 48.8566);
    expect(repo.savedEvents.single.longitude, 2.3522);

    coordinator.dispose();
  });
  group('durable queue', () {
    test(
      'incident is persisted natively before the first submission',
      () async {
        final log = <String>[];
        final backend = _FakeBackendGateway(log: log);
        final coordinator = _coordinator(
          backendGateway: backend,
          durableQueue: _FakeDurableQueue(log: log),
        );

        await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
        await Future<void>.delayed(Duration.zero);

        expect(log, ['enqueue:id-0', 'submit:id-0']);
        coordinator.dispose();
      },
    );

    test(
      'a native enqueue failure never blocks the in-process submission',
      () async {
        final backend = _FakeBackendGateway();
        final coordinator = _coordinator(
          backendGateway: backend,
          durableQueue: _FakeDurableQueue(shouldFail: true),
        );

        await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
        await Future<void>.delayed(Duration.zero);

        expect(backend.callCount, 1);
        coordinator.dispose();
      },
    );
  });

  group('countdown deadline', () {
    test(
      'before the server answers it runs from fallTimestamp + 30 s',
      () async {
        final clock = _FakeClock(DateTime(2026, 7, 24, 12));
        final submit = Completer<void>();
        final coordinator = _coordinator(
          clock: clock,
          backendGateway: _FakeBackendGateway(submitCompleter: submit),
        );

        // The watch detected the fall 10 s before the phone heard about it.
        await coordinator.startAlert(
          clock.now().millisecondsSinceEpoch - 10000,
        );

        expect(coordinator.remainingCountdownSeconds, 20);
        submit.complete();
        coordinator.dispose();
      },
    );

    test(
      'a watch clock running ahead never extends the window past 30 s',
      () async {
        final clock = _FakeClock(DateTime(2026, 7, 24, 12));
        final submit = Completer<void>();
        final coordinator = _coordinator(
          clock: clock,
          backendGateway: _FakeBackendGateway(submitCompleter: submit),
        );

        await coordinator.startAlert(
          clock.now().millisecondsSinceEpoch + 60000,
        );

        expect(coordinator.remainingCountdownSeconds, 30);
        submit.complete();
        coordinator.dispose();
      },
    );

    test(
      'after the create response the server deadline drives the countdown',
      () async {
        final clock = _FakeClock(DateTime(2026, 7, 24, 12));
        final repo = _FakeFallEventsRepository();
        final backend = _FakeBackendGateway(
          receipt: const FallAlertReceipt(
            remainingGrace: Duration(seconds: 45),
          ),
        );
        final coordinator = _coordinator(
          clock: clock,
          backendGateway: backend,
          eventRecorder: repo,
        );

        await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
        await Future<void>.delayed(Duration.zero);

        // Displayed value is capped at the 30 s window.
        expect(coordinator.remainingCountdownSeconds, 30);

        clock.setNow(clock.now().add(const Duration(seconds: 31)));
        await coordinator.reconcileActiveAlert();
        expect(
          coordinator.currentState?.phase,
          AlertPhase.countdown,
          reason: 'server grace is still open, the user can still cancel',
        );
        expect(coordinator.remainingCountdownSeconds, 14);
        expect(coordinator.isPastDeadline, isFalse);

        clock.setNow(clock.now().add(const Duration(seconds: 15)));
        expect(coordinator.remainingCountdownSeconds, 0);
        expect(coordinator.isPastDeadline, isTrue);
        await coordinator.reconcileActiveAlert();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(coordinator.currentState?.phase, AlertPhase.alertSent);
        expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
        expect(backend.callCount, 1);
        coordinator.dispose();
      },
    );

    test('a shorter server deadline ends the countdown early', () async {
      final clock = _FakeClock(DateTime(2026, 7, 24, 12));
      final coordinator = _coordinator(
        clock: clock,
        backendGateway: _FakeBackendGateway(
          receipt: const FallAlertReceipt(remainingGrace: Duration(seconds: 8)),
        ),
      );

      await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.remainingCountdownSeconds, 8);

      clock.setNow(clock.now().add(const Duration(seconds: 9)));
      expect(
        coordinator.remainingCountdownSeconds,
        0,
        reason: 'never negative',
      );
      expect(coordinator.isPastDeadline, isTrue);
      coordinator.dispose();
    });

    test('a late-delivered fall whose server grace is still open returns to '
        'the countdown after the fallback submission', () async {
      final clock = _FakeClock(DateTime(2026, 7, 24, 12));
      final states = <AlertPhase>[];
      final backend = _FakeBackendGateway(
        failFirstSubmitOnly: true,
        receipt: const FallAlertReceipt(remainingGrace: Duration(seconds: 25)),
      );
      final coordinator = _coordinator(clock: clock, backendGateway: backend);
      final sub = coordinator.stateStream.listen((s) => states.add(s.phase));

      // Detected 60 s ago (e.g. phone was offline): local window is over.
      await coordinator.startAlert(clock.now().millisecondsSinceEpoch - 60000);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(backend.callCount, 2);
      expect(states, [
        AlertPhase.countdown,
        AlertPhase.gettingLocation,
        AlertPhase.sendingAlert,
        AlertPhase.countdown,
      ]);
      expect(coordinator.remainingCountdownSeconds, 25);

      await sub.cancel();
      coordinator.dispose();
    });
  });

  group('re-pairing required', () {
    test('rejected credentials warn during the countdown and end as a '
        'not-notified failure, never as sent', () async {
      final clock = _FakeClock(DateTime(2026, 7, 24, 12));
      final repo = _FakeFallEventsRepository();
      final coordinator = _coordinator(
        clock: clock,
        eventRecorder: repo,
        backendGateway: _FakeBackendGateway(repairRequired: true),
      );

      await coordinator.startAlert(clock.now().millisecondsSinceEpoch);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.repairRequired, isTrue);
      expect(coordinator.currentState?.phase, AlertPhase.countdown);
      expect(coordinator.currentState?.statusMessage, contains('NOT notified'));

      clock.setNow(clock.now().add(const Duration(seconds: 31)));
      await coordinator.reconcileActiveAlert();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(coordinator.currentState?.phase, AlertPhase.alertFailed);
      expect(coordinator.currentState?.statusMessage, contains('NOT notified'));
      expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
      coordinator.dispose();
    });
  });

  group('incident-targeted watch cancel', () {
    test(
      'a cancel for another incident id does not dismiss the active alert',
      () async {
        final repo = _FakeFallEventsRepository();
        final coordinator = _coordinator(eventRecorder: repo);
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        await coordinator.startAlert(timestamp, clientAlertId: 'incident-a');
        await Future<void>.delayed(Duration.zero);
        await coordinator.cancelFromWatch(incidentId: 'incident-b');

        expect(coordinator.currentState?.phase, AlertPhase.countdown);
        expect(repo.savedEvents, isEmpty);

        await coordinator.cancelFromWatch(fallTimestamp: timestamp - 1);
        expect(coordinator.currentState?.phase, AlertPhase.countdown);
        coordinator.dispose();
      },
    );

    test('a cancel naming the active incident cancels it', () async {
      final repo = _FakeFallEventsRepository();
      final coordinator = _coordinator(eventRecorder: repo);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await coordinator.startAlert(
        timestamp,
        clientAlertId: '3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f',
      );
      await Future<void>.delayed(Duration.zero);
      await coordinator.cancelFromWatch(
        incidentId: '3F2B8C1E-9D4A-4C6B-8E2F-1A2B3C4D5E6F',
      );

      expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
      coordinator.dispose();
    });

    test('a cancel naming only the fall timestamp cancels the match', () async {
      final repo = _FakeFallEventsRepository();
      final coordinator = _coordinator(eventRecorder: repo);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await coordinator.startAlert(timestamp);
      await Future<void>.delayed(Duration.zero);
      await coordinator.cancelFromWatch(fallTimestamp: timestamp);

      expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
      coordinator.dispose();
    });

    test('phone cancel tells the watch which incident was cancelled', () async {
      final watch = _FakeWatchGateway();
      final coordinator = _coordinator(watchGateway: watch);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await coordinator.startAlert(timestamp, clientAlertId: 'incident-a');
      await Future<void>.delayed(Duration.zero);
      await coordinator.cancelFromPhone();

      expect(watch.lastIncidentId, 'incident-a');
      expect(watch.lastFallTimestamp, timestamp);
      coordinator.dispose();
    });
  });
  group('cancel before fall and aliases', () {
    test(
      'a targeted watch cancel arriving before its fall cancels it',
      () async {
        final repo = _FakeFallEventsRepository();
        final backend = _FakeBackendGateway();
        final coordinator = _coordinator(
          eventRecorder: repo,
          backendGateway: backend,
        );
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const id = '3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f';

        await coordinator.cancelFromWatch(
          incidentId: id,
          fallTimestamp: timestamp,
        );
        await coordinator.startAlert(timestamp, clientAlertId: id);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
        expect(backend.cancelCount, 1);
        coordinator.dispose();
      },
    );

    test(
      'a cancel tombstone expires and never cancels an unrelated fall',
      () async {
        final clock = _FakeClock(DateTime(2026, 7, 24, 12));
        final repo = _FakeFallEventsRepository();
        final coordinator = _coordinator(clock: clock, eventRecorder: repo);
        final timestamp = clock.now().millisecondsSinceEpoch;

        await coordinator.cancelFromWatch(incidentId: 'incident-a');
        await coordinator.startAlert(timestamp, clientAlertId: 'incident-b');
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.currentState?.phase, AlertPhase.countdown);
        await coordinator.cancelFromPhone();

        // Expired: the cancel names the next fall's timestamp but is 3 min old.
        final later = clock
            .now()
            .add(const Duration(minutes: 3))
            .millisecondsSinceEpoch;
        await coordinator.cancelFromWatch(fallTimestamp: later);
        clock.setNow(clock.now().add(const Duration(minutes: 3)));
        await coordinator.startAlert(later);
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.currentState?.phase, AlertPhase.countdown);
        coordinator.dispose();
      },
    );

    test(
      'an untargeted cancel before any fall never cancels a later fall',
      () async {
        final coordinator = _coordinator();
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        await coordinator.cancelFromWatch();
        await coordinator.startAlert(timestamp);
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.currentState?.phase, AlertPhase.countdown);
        coordinator.dispose();
      },
    );

    test(
      'a cancel naming the watch UUID alias cancels the legacy-id alert',
      () async {
        final repo = _FakeFallEventsRepository();
        final coordinator = _coordinator(eventRecorder: repo);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const uuid = '3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f';

        await coordinator.startAlert(
          timestamp,
          clientAlertId: 'wear-os-$timestamp',
        );
        // Second transport of the same fall brings the watch UUID.
        expect(
          await coordinator.startAlert(
            timestamp,
            clientAlertId: 'wear-os-$timestamp',
            incidentId: uuid,
          ),
          isFalse,
        );
        await Future<void>.delayed(Duration.zero);
        await coordinator.cancelFromWatch(incidentId: uuid);

        expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
        coordinator.dispose();
      },
    );
  });

  test('a delayed fall whose registration answers during the fallback gets the '
      'cancel button back and the fallback stops', () async {
    final clock = _FakeClock(DateTime(2026, 7, 24, 12));
    final submit = Completer<void>();
    final fallbackSubmit = Completer<void>();
    final repo = _FakeFallEventsRepository();
    final phases = <AlertPhase>[];
    final backend = _FakeBackendGateway(
      submitCompleter: submit,
      laterSubmitsCompleter: fallbackSubmit,
      receipt: const FallAlertReceipt(remainingGrace: Duration(seconds: 20)),
    );
    final coordinator = _coordinator(
      clock: clock,
      backendGateway: backend,
      eventRecorder: repo,
    );
    final sub = coordinator.stateStream.listen((s) => phases.add(s.phase));

    // Delivered 60 s late: the local fallback deadline has already passed,
    // so the fallback starts while the first registration is still pending.
    await coordinator.startAlert(clock.now().millisecondsSinceEpoch - 60000);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.currentState?.phase, AlertPhase.sendingAlert);

    // The first registration answers with an open 20 s server window while
    // the redundant fallback submission is still in flight.
    submit.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(coordinator.remainingCountdownSeconds, 20);

    // The superseded fallback finishing later must not override that state.
    fallbackSubmit.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(repo.savedEvents, isEmpty, reason: 'no premature "sent" outcome');
    expect(phases.last, AlertPhase.countdown);

    await sub.cancel();
    coordinator.dispose();
  });
}
